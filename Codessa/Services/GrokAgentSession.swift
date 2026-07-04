import Foundation

/// A persistent `grok agent stdio` ACP (Agent Client Protocol) client.
///
/// The old path spawned a fresh `grok -p` per message, and every spawn re-booted
/// all MCP servers (~30s of dead air before the first token). Agent mode keeps
/// ONE long-lived process: MCP initialises once at startup and stays warm, so
/// the 2nd prompt onward streams instantly.
///
/// Protocol (JSON-RPC 2.0, newline-delimited over stdin/stdout), verified live:
///   initialize                       → once per process
///   session/new {cwd, mcpServers:[]} → result.sessionId
///   session/load {sessionId, cwd}    → resume an on-disk session
///   session/set_model {sessionId, modelId} → switch model without re-spawning
///   session/prompt {sessionId, prompt:[{type:text,text}]} → result.stopReason
/// Streamed back as `session/update` notifications whose `update.sessionUpdate`
/// is `agent_thought_chunk` / `agent_message_chunk` (text in `update.content.text`).
///
/// Spawned with `--always-approve` so tool calls don't block on a permission
/// round-trip — read-only "Plan mode" and `--check` still route through the
/// one-shot path in `GrokCLIService`, which honours `--permission-mode`.
nonisolated final class GrokAgentSession: @unchecked Sendable {
    static let shared = GrokAgentSession()

    private let grokPath: String
    private let singletonPath: String
    private let lock = NSLock()
    private let startCondition = NSCondition()
    private var startInProgress = false

    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var initialized = false

    private var nextId = 1
    private var responders: [Int: (Result<[String: Any], Error>) -> Void] = [:]

    /// Session currently loaded in the warm process, and the model set on it.
    private var currentSessionId: String?
    private var currentModel: String?

    /// Routing for the in-flight prompt's streamed chunks.
    private var promptOnEvent: (@Sendable (GrokStreamEvent) -> Void)?
    private var promptSessionId: String?
    /// JSON-RPC id of the in-flight `session/prompt`, so the inactivity
    /// watchdog can fail exactly that request if the turn stalls.
    private var promptRequestId: Int?

    /// Inactivity watchdog for the in-flight turn. The warm session has no
    /// per-request timeout, so a mid-turn stall (a hung tool/MCP, or an agent
    /// callback we can't satisfy) would otherwise leave the UI spinning
    /// forever. Every streamed chunk / agent callback reschedules it.
    private var watchdog: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "grok.agent.watchdog")

    /// Rolling tail of the agent process's stderr. The `grok agent` process
    /// writes crash traces / auth failures / rate-limit notices here; capturing
    /// the last few KB lets us surface the *actual* reason when the process dies,
    /// instead of a generic "the process exited" banner.
    private var stderrTail = ""
    private static let stderrTailLimit = 4000

    private static let newline = UInt8(ascii: "\n")

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.grok/bin/grok",
            "/usr/local/bin/grok",
            "/opt/homebrew/bin/grok",
        ]
        grokPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
        singletonPath = "\(home)/.local/bin/mcp-singleton"
    }

    // MARK: - Public

    /// Stream a prompt through the warm session, reusing/creating/loading the
    /// right ACP session and switching the model in place when it changed.
    /// Returns the ACP session id so the caller can persist it for resume.
    func streamPrompt(
        _ text: String,
        cwd: URL,
        model: String,
        sessionId: String?,
        onEvent: @escaping @Sendable (GrokStreamEvent) -> Void
    ) async throws -> String? {
        try ensureStarted()
        try await initializeIfNeeded()

        let sid = try await resolveSession(requested: sessionId, cwd: cwd)

        // Set the model if this session hasn't had it set (always set after a
        // fresh new/load, since those reset `currentModel` to nil).
        let needsModel: Bool = {
            lock.lock(); defer { lock.unlock() }
            return currentModel != model
        }()
        if needsModel {
            _ = try? await request("session/set_model", ["sessionId": sid, "modelId": model])
            lock.lock(); currentModel = model; lock.unlock()
        }

        lock.lock(); promptOnEvent = onEvent; promptSessionId = sid; lock.unlock()
        defer {
            stopWatchdog()
            lock.lock(); promptOnEvent = nil; promptSessionId = nil; lock.unlock()
        }

        let result = try await promptRequest(sessionId: sid, text: text)
        let stop = result["stopReason"] as? String
        onEvent(GrokStreamEvent(type: "end", stopReason: stop, sessionId: sid))
        return sid
    }

    /// Spawn + initialise the agent ahead of the first prompt, so MCP boots
    /// while the user is still on the home screen instead of on first send.
    func prewarm() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try self.ensureStarted()
                try await self.initializeIfNeeded()
            } catch { /* first real prompt will surface any failure */ }
        }
    }

    /// Cancel the in-flight turn (ACP `session/cancel` notification). The agent
    /// ends the turn and the pending `session/prompt` response resolves.
    func cancel() {
        lock.lock(); let sid = promptSessionId; lock.unlock()
        guard let sid else { return }
        try? writeMessage(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sid]])
    }

    // MARK: - Session resolution

    private func resolveSession(requested: String?, cwd: URL) async throws -> String {
        if let requested {
            let current: String? = { lock.lock(); defer { lock.unlock() }; return currentSessionId }()
            if requested == current { return requested }
            // Try to load an existing on-disk session; fall back to a new one.
            do {
                _ = try await request("session/load", [
                    "sessionId": requested, "cwd": cwd.path, "mcpServers": [],
                ])
                setSession(requested)
                return requested
            } catch {
                return try await newSession(cwd: cwd)
            }
        }
        return try await newSession(cwd: cwd)
    }

    private func newSession(cwd: URL) async throws -> String {
        let result = try await request("session/new", ["cwd": cwd.path, "mcpServers": []])
        guard let sid = result["sessionId"] as? String else {
            throw GrokCLIError.invalidOutput
        }
        setSession(sid)
        return sid
    }

    /// A fresh/loaded session starts on its default model — force the next
    /// `set_model` by clearing `currentModel`.
    private func setSession(_ sid: String) {
        lock.lock(); currentSessionId = sid; currentModel = nil; lock.unlock()
    }

    // MARK: - Lifecycle

    private func ensureStarted() throws {
        startCondition.lock()
        while startInProgress {
            startCondition.wait()
        }
        lock.lock(); let running = process != nil; lock.unlock()
        if running {
            startCondition.unlock()
            return
        }
        startInProgress = true
        startCondition.unlock()

        guard FileManager.default.isExecutableFile(atPath: grokPath) else {
            finishStartAttempt()
            throw GrokCLIError.binaryNotFound
        }

        let p = Process()
        if FileManager.default.isExecutableFile(atPath: singletonPath) {
            p.executableURL = URL(fileURLWithPath: singletonPath)
            p.arguments = ["grok-cli", grokPath, "agent", "--always-approve", "stdio"]
        } else {
            p.executableURL = URL(fileURLWithPath: grokPath)
            p.arguments = ["agent", "--always-approve", "stdio"]
        }
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        let outHandle = outPipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data)
        }
        // Drain stderr so the pipe never fills and blocks the agent — and keep a
        // rolling tail of it so a crash/auth/rate-limit reason can be surfaced.
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendStderrTail(String(decoding: data, as: UTF8.self))
        }
        p.terminationHandler = { [weak self] proc in self?.handleTermination(exitCode: proc.terminationStatus) }

        do {
            try p.run()
        } catch {
            finishStartAttempt()
            throw error
        }

        lock.lock()
        process = p
        stdin = inPipe.fileHandleForWriting
        buffer = Data()
        stderrTail = ""
        initialized = false
        currentSessionId = nil
        currentModel = nil
        lock.unlock()
        finishStartAttempt()
    }

    private func finishStartAttempt() {
        startCondition.lock()
        startInProgress = false
        startCondition.broadcast()
        startCondition.unlock()
    }

    private func initializeIfNeeded() async throws {
        let done: Bool = { lock.lock(); defer { lock.unlock() }; return initialized }()
        if done { return }
        _ = try await request("initialize", [
            "protocolVersion": 1,
            // Declare no client-side fs/terminal: the agent uses its own tools
            // and won't call back to us (we have nothing to service those with).
            "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false]],
        ])
        lock.lock(); initialized = true; lock.unlock()
    }

    private func handleTermination(exitCode: Int32) {
        lock.lock()
        let pending = responders
        responders.removeAll()
        watchdog?.cancel()
        watchdog = nil
        promptRequestId = nil
        process = nil
        stdin = nil
        initialized = false
        currentSessionId = nil
        currentModel = nil
        promptOnEvent = nil
        promptSessionId = nil
        let tail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        // Fail anything still waiting so the UI surfaces an error / retries.
        // Lead with the friendly exit-code summary, but append whatever the agent
        // actually wrote to stderr (crash trace, auth failure, rate-limit notice)
        // so the reason is concrete rather than "the process exited".
        var message = CLIProcessMessage.friendly(name: "The Grok agent", exitCode: exitCode, stderr: tail)
        if tail.isEmpty {
            message = "The Grok agent process exited (code \(exitCode)) without reporting a reason. Try again; if it persists, run `grok agent` in a terminal to see the error."
        }
        for (_, responder) in pending {
            responder(.failure(GrokCLIError.processFailed(message)))
        }
    }

    /// Append to the rolling stderr tail, trimming from the front so it stays
    /// bounded. Called off the reader queue; guarded by `lock`.
    private func appendStderrTail(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        stderrTail += text
        if stderrTail.count > Self.stderrTailLimit {
            stderrTail = String(stderrTail.suffix(Self.stderrTailLimit))
        }
    }

    // MARK: - JSON-RPC plumbing

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id: Int = { lock.lock(); defer { lock.unlock() }; let i = nextId; nextId += 1; return i }()
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            responders[id] = { cont.resume(with: $0) }
            lock.unlock()
            do {
                try writeMessage(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
            } catch {
                lock.lock(); responders[id] = nil; lock.unlock()
                cont.resume(throwing: error)
            }
        }
    }

    /// Like `request` but for `session/prompt`: records the request id and arms
    /// the inactivity watchdog so a stalled turn fails (and the UI recovers)
    /// instead of hanging forever. The `defer` in `streamPrompt` stops it.
    private func promptRequest(sessionId sid: String, text: String) async throws -> [String: Any] {
        let id: Int = { lock.lock(); defer { lock.unlock() }; let i = nextId; nextId += 1; return i }()
        lock.lock(); promptRequestId = id; lock.unlock()
        startWatchdog()
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            responders[id] = { cont.resume(with: $0) }
            lock.unlock()
            do {
                try writeMessage([
                    "jsonrpc": "2.0", "id": id, "method": "session/prompt",
                    "params": ["sessionId": sid, "prompt": [["type": "text", "text": text]]],
                ])
            } catch {
                lock.lock(); responders[id] = nil; lock.unlock()
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Inactivity watchdog

    private func startWatchdog() {
        lock.lock()
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.setEventHandler { [weak self] in self?.watchdogFired() }
        timer.schedule(deadline: .now() + GrokCLIService.inactivityTimeout)
        watchdog = timer
        timer.resume()
        lock.unlock()
    }

    /// Reschedule the deadline on any sign of activity (a streamed chunk or an
    /// agent callback). No-op when no turn is in flight.
    private func scheduleWatchdog() {
        lock.lock()
        watchdog?.schedule(deadline: .now() + GrokCLIService.inactivityTimeout)
        lock.unlock()
    }

    private func stopWatchdog() {
        lock.lock()
        watchdog?.cancel()
        watchdog = nil
        promptRequestId = nil
        lock.unlock()
    }

    /// Fired when the agent has been silent past the timeout: fail the in-flight
    /// prompt and tell the agent to abandon the turn so the UI recovers.
    private func watchdogFired() {
        lock.lock()
        let id = promptRequestId
        let sid = promptSessionId
        let responder = id.flatMap { responders.removeValue(forKey: $0) }
        watchdog?.cancel()
        watchdog = nil
        promptRequestId = nil
        lock.unlock()
        if let sid {
            try? writeMessage(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sid]])
        }
        responder?(.failure(GrokCLIError.processFailed(
            "Grok stopped responding after \(Int(GrokCLIService.inactivityTimeout))s.")))
    }

    private func writeMessage(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var line = data
        line.append(Self.newline)
        lock.lock(); let handle = stdin; lock.unlock()
        guard let handle else { throw GrokCLIError.processFailed("grok agent is not running.") }
        try handle.write(contentsOf: line)
    }

    /// Append stdout bytes and dispatch every complete newline-terminated line.
    private func ingest(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: Self.newline) {
            lines.append(buffer.subdata(in: buffer.startIndex..<nl))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines where !line.isEmpty { handleLine(line) }
    }

    private func handleLine(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #if DEBUG
            NSLog("[GrokAgentSession] undecodable line: \(String(decoding: data, as: UTF8.self))")
            #endif
            return
        }

        if let method = obj["method"] as? String {
            if let id = obj["id"] {
                handleAgentRequest(method: method, id: id, params: obj["params"] as? [String: Any] ?? [:])
            } else {
                handleNotification(method: method, params: obj["params"] as? [String: Any] ?? [:])
            }
            return
        }

        // Response to one of our requests.
        guard let id = obj["id"] as? Int else { return }
        lock.lock(); let responder = responders.removeValue(forKey: id); lock.unlock()
        guard let responder else { return }
        if let err = obj["error"] as? [String: Any] {
            responder(.failure(GrokCLIError.processFailed(err["message"] as? String ?? "grok agent error")))
        } else {
            responder(.success(obj["result"] as? [String: Any] ?? [:]))
        }
    }

    private func handleNotification(method: String, params: [String: Any]) {
        guard method == "session/update",
              let update = params["update"] as? [String: Any],
              let kind = update["sessionUpdate"] as? String
        else { return }

        scheduleWatchdog()   // any streamed update counts as activity

        lock.lock(); let cb = promptOnEvent; lock.unlock()
        guard let cb else { return }

        // Live tool-call visibility: a `tool_call` seeds a running row, and each
        // `tool_call_update` refines its title/kind and attaches detail. These
        // are handled ahead of the text/thought mapping (whose `content` is a
        // single object) because a tool update's `content` is an array.
        switch kind {
        case "tool_call":
            if let payload = toolPayload(from: update, done: false) {
                cb(GrokStreamEvent(type: "tool", tool: payload))
            }
            return
        case "tool_call_update":
            // Treat an update as completion when it carries result content or an
            // explicit terminal status (completed/failed/cancelled/error).
            let statusStr = (update["status"] as? String)?.lowercased() ?? ""
            let hasContent = (update["content"] as? [[String: Any]])?.isEmpty == false
            let terminal = ["completed", "complete", "done", "failed", "error", "cancelled", "canceled"]
                .contains(statusStr)
            if let payload = toolPayload(from: update, done: hasContent || terminal) {
                cb(GrokStreamEvent(type: "tool", tool: payload))
            }
            return
        default:
            break
        }

        let text = chunkText(from: update)

        switch kind {
        case "agent_thought_chunk":
            if let text { cb(GrokStreamEvent(type: "thought", data: text)) }
        case "agent_message_chunk":
            if let text { cb(GrokStreamEvent(type: "text", data: text)) }
        default:
            #if DEBUG
            NSLog("[GrokAgentSession] unhandled sessionUpdate kind: \(kind)")
            #endif
            break
        }
    }

    /// Pull chunk text from `update.content`, which the agent sends either as a
    /// single `{type,text}` object or an array of such blocks (the array form is
    /// the same shape `toolPayload` walks). Returns nil when there's no text.
    private func chunkText(from update: [String: Any]) -> String? {
        if let obj = update["content"] as? [String: Any], let t = obj["text"] as? String {
            return t
        }
        if let arr = update["content"] as? [[String: Any]] {
            let texts = arr.compactMap { item -> String? in
                if let t = item["text"] as? String, !t.isEmpty { return t }
                if let inner = item["content"] as? [String: Any],
                   let t = inner["text"] as? String, !t.isEmpty { return t }
                return nil
            }
            if !texts.isEmpty { return texts.joined() }
        }
        return nil
    }

    /// Build a `ToolEventPayload` from an ACP `tool_call` / `tool_call_update`
    /// `update` object. Returns nil only when there's no `toolCallId` to key on.
    /// `detail` concatenates any diff (newText, and oldText if present) and any
    /// text content; for an execute call it also surfaces the command from
    /// `rawInput`.
    private func toolPayload(from update: [String: Any], done: Bool) -> ToolEventPayload? {
        guard let id = update["toolCallId"] as? String else { return nil }
        let title = (update["title"] as? String) ?? ""
        let kind = (update["kind"] as? String) ?? ""

        var parts: [String] = []

        // For an execute/shell call, lead with the command if rawInput carries one.
        if let rawInput = update["rawInput"] as? [String: Any] {
            if let command = rawInput["command"] as? String, !command.isEmpty {
                parts.append("$ " + command)
            } else if let command = rawInput["command"] as? [String],
                      !command.isEmpty {
                parts.append("$ " + command.joined(separator: " "))
            }
        }

        // Render each content item: diffs as newText (with oldText if present),
        // and text/content blocks as their text.
        if let content = update["content"] as? [[String: Any]] {
            for item in content {
                let itemType = item["type"] as? String
                switch itemType {
                case "diff":
                    let newText = item["newText"] as? String ?? ""
                    let oldText = item["oldText"] as? String
                    if let oldText, !oldText.isEmpty {
                        parts.append("- " + oldText)
                    }
                    if !newText.isEmpty {
                        parts.append("+ " + newText)
                    }
                case "content":
                    if let inner = item["content"] as? [String: Any],
                       let t = inner["text"] as? String, !t.isEmpty {
                        parts.append(t)
                    }
                default:
                    // Some updates nest text directly under content[].text.
                    if let t = item["text"] as? String, !t.isEmpty {
                        parts.append(t)
                    }
                }
            }
        }

        let detail = parts.joined(separator: "\n")
        return ToolEventPayload(id: id, title: title, kind: kind, detail: detail, done: done)
    }

    /// The agent occasionally calls back (e.g. a permission prompt). We launched
    /// with `--always-approve`, but answer defensively so a turn never hangs.
    private func handleAgentRequest(method: String, id: Any, params: [String: Any]) {
        scheduleWatchdog()   // the agent is doing work — keep the turn alive
        var result: [String: Any] = [:]
        if method.contains("permission") {
            let options = params["options"] as? [[String: Any]] ?? []
            let allow = options.first { ($0["kind"] as? String ?? "").contains("allow") } ?? options.first
            if let optionId = allow?["optionId"] {
                result = ["outcome": ["outcome": "selected", "optionId": optionId]]
            } else {
                result = ["outcome": ["outcome": "cancelled"]]
            }
        } else {
            #if DEBUG
            NSLog("[GrokAgentSession] unhandled agent request: \(method)")
            #endif
        }
        try? writeMessage(["jsonrpc": "2.0", "id": id, "result": result])
    }
}
