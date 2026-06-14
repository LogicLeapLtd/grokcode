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
    private let lock = NSLock()

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

    private static let newline = UInt8(ascii: "\n")

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.grok/bin/grok",
            "/usr/local/bin/grok",
            "/opt/homebrew/bin/grok",
        ]
        grokPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
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
        defer { lock.lock(); promptOnEvent = nil; promptSessionId = nil; lock.unlock() }

        let result = try await request("session/prompt", [
            "sessionId": sid,
            "prompt": [["type": "text", "text": text]],
        ])
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
        lock.lock(); let running = process != nil; lock.unlock()
        if running { return }

        guard FileManager.default.isExecutableFile(atPath: grokPath) else {
            throw GrokCLIError.binaryNotFound
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: grokPath)
        p.arguments = ["agent", "--always-approve", "stdio"]
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
        // Drain stderr so the pipe never fills and blocks the agent.
        errPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        p.terminationHandler = { [weak self] _ in self?.handleTermination() }

        try p.run()

        lock.lock()
        process = p
        stdin = inPipe.fileHandleForWriting
        buffer = Data()
        initialized = false
        currentSessionId = nil
        currentModel = nil
        lock.unlock()
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

    private func handleTermination() {
        lock.lock()
        let pending = responders
        responders.removeAll()
        process = nil
        stdin = nil
        initialized = false
        currentSessionId = nil
        currentModel = nil
        promptOnEvent = nil
        promptSessionId = nil
        lock.unlock()
        // Fail anything still waiting so the UI surfaces an error / retries.
        for (_, responder) in pending {
            responder(.failure(GrokCLIError.processFailed("The grok agent process exited.")))
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
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

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

        let text = (update["content"] as? [String: Any])?["text"] as? String
        lock.lock(); let cb = promptOnEvent; lock.unlock()
        guard let cb else { return }

        switch kind {
        case "agent_thought_chunk":
            if let text { cb(GrokStreamEvent(type: "thought", data: text)) }
        case "agent_message_chunk":
            if let text { cb(GrokStreamEvent(type: "text", data: text)) }
        default:
            break
        }
    }

    /// The agent occasionally calls back (e.g. a permission prompt). We launched
    /// with `--always-approve`, but answer defensively so a turn never hangs.
    private func handleAgentRequest(method: String, id: Any, params: [String: Any]) {
        var result: [String: Any] = [:]
        if method.contains("permission") {
            let options = params["options"] as? [[String: Any]] ?? []
            let allow = options.first { ($0["kind"] as? String ?? "").contains("allow") } ?? options.first
            if let optionId = allow?["optionId"] {
                result = ["outcome": ["outcome": "selected", "optionId": optionId]]
            } else {
                result = ["outcome": ["outcome": "cancelled"]]
            }
        }
        try? writeMessage(["jsonrpc": "2.0", "id": id, "result": result])
    }
}
