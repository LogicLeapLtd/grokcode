import Foundation

nonisolated enum GrokCLIError: LocalizedError {
    case binaryNotFound
    case processFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Grok CLI not found. Install it or run `grok login`."
        case .processFailed(let message):
            message
        case .invalidOutput:
            "Grok returned unexpected output."
        }
    }
}

/// Carried on a `"tool"` `GrokStreamEvent` to surface a live tool call (an ACP
/// `tool_call` / `tool_call_update`) up to the view model. `id` is the ACP
/// `toolCallId` (stable across the seed + every refinement); `done` flips true
/// once the update carries a result (or the turn ends).
nonisolated struct ToolEventPayload: Equatable, Sendable {
    /// ACP `toolCallId`, used to upsert the matching row in place.
    let id: String
    /// Best title known so far (refined by later updates).
    let title: String
    /// Update kind ("edit"/"execute"/"read"/"search"…); empty until reported.
    let kind: String
    /// Human-readable expanded detail (diff newText, command + output…); empty
    /// until a `tool_call_update` provides content.
    let detail: String
    /// True once the call has clearly completed.
    let done: Bool

    init(id: String, title: String, kind: String = "", detail: String = "", done: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.detail = detail
        self.done = done
    }
}

nonisolated struct GrokStreamEvent: Decodable {
    let type: String
    let data: String?
    let stopReason: String?
    let sessionId: String?
    let requestId: String?
    /// Set only on `type == "tool"` events (the JSON stream never carries this;
    /// it's populated by the warm `GrokAgentSession` ACP mapping).
    let tool: ToolEventPayload?

    enum CodingKeys: String, CodingKey {
        case type, data, stopReason, sessionId, requestId
        // Tolerate snake_case variants if the CLI ever emits them.
        case stopReasonSnake = "stop_reason"
        case sessionIdSnake = "session_id"
        case requestIdSnake = "request_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        data = try c.decodeIfPresent(String.self, forKey: .data)
        stopReason = try c.decodeIfPresent(String.self, forKey: .stopReason)
            ?? c.decodeIfPresent(String.self, forKey: .stopReasonSnake)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
            ?? c.decodeIfPresent(String.self, forKey: .sessionIdSnake)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
            ?? c.decodeIfPresent(String.self, forKey: .requestIdSnake)
        tool = nil
    }

    /// Construct an event directly. Used by the warm `GrokAgentSession` client to
    /// map ACP `session/update` notifications onto this shape.
    init(type: String, data: String? = nil, stopReason: String? = nil,
         sessionId: String? = nil, requestId: String? = nil,
         tool: ToolEventPayload? = nil) {
        self.type = type
        self.data = data
        self.stopReason = stopReason
        self.sessionId = sessionId
        self.requestId = requestId
        self.tool = tool
    }
}

/// Thread-safe holder for the per-run streaming state. The stdout readability
/// handler, the watchdog timer, and the termination handler all run on
/// different threads, so every field is guarded by `lock`.
private nonisolated final class StreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionId: String?
    private var stderr = ""
    private var buffer = Data()
    private var didTimeout = false
    private var didFinish = false

    private static let newline = UInt8(ascii: "\n")

    /// Append incoming stdout bytes; returns whatever complete (newline-
    /// terminated) lines are now available. Operating on raw bytes means a
    /// multi-byte UTF-8 character split across a read boundary can never corrupt
    /// or drop an event.
    func appendStdout(_ data: Data, flush: Bool) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: Self.newline) {
            lines.append(buffer.subdata(in: buffer.startIndex..<nl))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        if flush, !buffer.isEmpty {
            lines.append(buffer)
            buffer.removeAll()
        }
        return lines
    }

    func appendStderr(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        stderr += text
    }

    func setSession(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        sessionId = id
    }

    func markTimedOut() {
        lock.lock(); defer { lock.unlock() }
        didTimeout = true
    }

    /// Atomically claim completion exactly once. Returns nil if another thread
    /// already finished; otherwise the snapshot needed to resume.
    func claimFinish() -> (timedOut: Bool, sessionId: String?, stderr: String)? {
        lock.lock(); defer { lock.unlock() }
        if didFinish { return nil }
        didFinish = true
        return (didTimeout, sessionId, stderr)
    }
}

nonisolated final class GrokCLIService: @unchecked Sendable {
    static let shared = GrokCLIService()

    /// Inactivity watchdog: if the CLI emits nothing for this long we assume a
    /// stall (auth hang, never-ending run) and terminate it so the UI recovers.
    static let inactivityTimeout: TimeInterval = 180

    /// Whether to route prompts through the warm `grok agent stdio` session
    /// (MCP boots once instead of per message). Settings can disable it.
    static var useWarmSession: Bool {
        UserDefaults.standard.object(forKey: "grokcode.useWarmSession") as? Bool ?? true
    }

    private let grokPath: String
    private let singletonPath: String
    private let processLock = NSLock()
    private var runningProcess: Process?
    /// Set when the user explicitly cancels, so a forced termination is
    /// reported as a graceful stop rather than a failure.
    private var didCancel = false

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

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: grokPath)
    }

    func listModels() async throws -> [GrokModelOption] {
        let output = try await runCapture(arguments: ["models"])
        return parseModels(from: output)
    }

    func listSessions(limit: Int = 30) async throws -> [GrokSession] {
        let output = try await runCapture(arguments: ["sessions", "list", "-n", "\(limit)"])
        return parseSessions(from: output)
    }

    func streamPrompt(
        _ prompt: String,
        cwd: URL,
        model: String,
        permissionMode: PermissionMode,
        effort: EffortLevel = .medium,
        check: Bool = false,
        sessionId: String?,
        onEvent: @escaping @Sendable (GrokStreamEvent) -> Void
    ) async throws -> String? {
        // Fast path: the long-lived `grok agent stdio` session keeps MCP warm,
        // so prompts after the first stream instantly. Plan mode (read-only) and
        // Pursue-goal (`--check`) need the one-shot path's `--permission-mode` /
        // `--check`, so they fall through to the per-message process below.
        if Self.useWarmSession, permissionMode != .plan, !check {
            return try await GrokAgentSession.shared.streamPrompt(
                prompt, cwd: cwd, model: model, sessionId: sessionId, onEvent: onEvent)
        }

        var args = [
            "-p", prompt,
            "-m", model,
            "--cwd", cwd.path,
            "--output-format", "streaming-json",
            "--permission-mode", permissionMode.rawValue,
            "--effort", effort.rawValue,
        ]

        if check {
            args.append("--check")
        }

        if let sessionId {
            args += ["-r", sessionId]
        }

        return try await runStreaming(arguments: args, onEvent: onEvent)
    }

    func cancel() {
        // Stop the warm in-flight turn (no-op if the one-shot path is in use)…
        GrokAgentSession.shared.cancel()
        // …and terminate any one-shot process.
        processLock.lock()
        didCancel = true
        let process = runningProcess
        processLock.unlock()
        process?.terminate()
    }

    private func consumeCancelFlag() -> Bool {
        processLock.lock(); defer { processLock.unlock() }
        let value = didCancel
        return value
    }

    private func resetCancelFlag() {
        processLock.lock(); defer { processLock.unlock() }
        didCancel = false
    }

    private func setRunningProcess(_ process: Process?) {
        processLock.lock(); defer { processLock.unlock() }
        runningProcess = process
    }

    // MARK: - Process helpers

    private func runCapture(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            guard FileManager.default.isExecutableFile(atPath: grokPath) else {
                continuation.resume(throwing: GrokCLIError.binaryNotFound)
                return
            }

            let process = Process()
            configureGrokProcess(process, arguments: arguments)

            var env = ProcessInfo.processInfo.environment
            env["NO_COLOR"] = "1"
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let out = String(decoding: outData, as: UTF8.self)
                let err = String(decoding: errData, as: UTF8.self)

                if proc.terminationStatus == 0 || !out.isEmpty {
                    continuation.resume(returning: out + err)
                } else {
                    continuation.resume(throwing: GrokCLIError.processFailed(
                        CLIProcessMessage.friendly(name: "Grok", exitCode: proc.terminationStatus, stderr: err)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func runStreaming(
        arguments: [String],
        onEvent: @escaping @Sendable (GrokStreamEvent) -> Void
    ) async throws -> String? {
        // Reset cancel flag for this run.
        resetCancelFlag()

        let state = StreamState()

        return try await withCheckedThrowingContinuation { continuation in
            guard FileManager.default.isExecutableFile(atPath: grokPath) else {
                continuation.resume(throwing: GrokCLIError.binaryNotFound)
                return
            }

            let process = Process()
            configureGrokProcess(process, arguments: arguments)

            var env = ProcessInfo.processInfo.environment
            env["NO_COLOR"] = "1"
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            setRunningProcess(process)

            let outHandle = stdout.fileHandleForReading
            let errHandle = stderr.fileHandleForReading

            // Inactivity watchdog: reset on every byte of activity; if it ever
            // fires, the CLI has stalled — terminate it.
            let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "grok.watchdog"))
            let timeout = Self.inactivityTimeout
            let armWatchdog: @Sendable () -> Void = {
                watchdog.schedule(deadline: .now() + timeout)
            }
            watchdog.setEventHandler {
                state.markTimedOut()
                process.terminate()
            }
            armWatchdog()
            watchdog.resume()

            let decode: @Sendable ([Data]) -> Void = { lines in
                for lineData in lines {
                    guard !lineData.isEmpty,
                          let event = try? JSONDecoder().decode(GrokStreamEvent.self, from: lineData)
                    else { continue }
                    onEvent(event)
                    if let sid = event.sessionId {
                        state.setSession(sid)
                    }
                }
            }

            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                armWatchdog()
                decode(state.appendStdout(data, flush: false))
            }

            errHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                state.appendStderr(String(decoding: data, as: UTF8.self))
            }

            process.terminationHandler = { [weak self] proc in
                watchdog.cancel()
                // Drain whatever is left on the pipe, then flush any trailing
                // buffered line (e.g. a final event with no newline).
                let remaining = outHandle.readDataToEndOfFile()
                decode(state.appendStdout(remaining, flush: true))
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                self?.setRunningProcess(nil)

                guard let snapshot = state.claimFinish() else { return }
                let cancelled = self?.consumeCancelFlag() ?? false

                if snapshot.timedOut {
                    continuation.resume(throwing: GrokCLIError.processFailed(
                        "Grok timed out after \(Int(timeout))s with no response. The process was stopped."))
                } else if cancelled {
                    // User-initiated stop: graceful, return whatever session we have.
                    continuation.resume(returning: snapshot.sessionId)
                } else if proc.terminationStatus == 0 || snapshot.sessionId != nil {
                    continuation.resume(returning: snapshot.sessionId)
                } else {
                    let err = snapshot.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: GrokCLIError.processFailed(
                        CLIProcessMessage.friendly(name: "Grok", exitCode: proc.terminationStatus, stderr: err)))
                }
            }

            do {
                try process.run()
            } catch {
                watchdog.cancel()
                if state.claimFinish() != nil {
                    setRunningProcess(nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureGrokProcess(_ process: Process, arguments: [String]) {
        if FileManager.default.isExecutableFile(atPath: singletonPath) {
            process.executableURL = URL(fileURLWithPath: singletonPath)
            process.arguments = ["grok-cli", grokPath] + arguments
        } else {
            process.executableURL = URL(fileURLWithPath: grokPath)
            process.arguments = arguments
        }
    }

    // MARK: - Parsing

    private func parseModels(from output: String) -> [GrokModelOption] {
        var models: [GrokModelOption] = []
        var defaultModel: String?

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Default model:") {
                defaultModel = trimmed.replacingOccurrences(of: "Default model:", with: "").trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let cleaned = trimmed
                    .replacingOccurrences(of: "* ", with: "")
                    .replacingOccurrences(of: "- ", with: "")
                    .replacingOccurrences(of: " (default)", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty, !cleaned.hasPrefix("Available") {
                    models.append(GrokModelOption(id: cleaned, isDefault: cleaned == defaultModel))
                }
            }
        }

        if models.isEmpty {
            models = [
                GrokModelOption(id: "grok-composer-2.5-fast", isDefault: true),
                GrokModelOption(id: "grok-build", isDefault: false),
                GrokModelOption(id: "grok-4", isDefault: false),
            ]
        }

        return models
    }

    private func parseSessions(from output: String) -> [GrokSession] {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > 2 else { return [] }

        var sessions: [GrokSession] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for line in lines.dropFirst(2) {
            let parts = line.split(omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 5 else { continue }

            let id = parts[0]
            let created = dateFormatter.date(from: parts[1])
            let updated = dateFormatter.date(from: parts[2])
            let status = parts[3]
            let summary = parts.dropFirst(4).joined(separator: " ")

            sessions.append(GrokSession(
                id: id,
                summary: summary,
                created: created,
                updated: updated,
                status: status
            ))
        }

        return sessions
    }
}
