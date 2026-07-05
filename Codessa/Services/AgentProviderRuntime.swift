import Foundation

nonisolated enum AgentProviderRuntimeError: LocalizedError {
    case providerUnavailable(String)
    case processFailed(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let message), .processFailed(let message), .unsupported(let message):
            message
        }
    }
}

nonisolated struct ProviderRunRequest: Sendable {
    let provider: AgentProvider
    let binaryPath: String
    let prompt: String
    let cwd: URL
    let model: GrokModelOption
    let permissionMode: PermissionMode
    let options: [String: String]
    let check: Bool
    let sessionId: String?
}

nonisolated enum AgentProviderModelCatalog {
    static func models(for provider: AgentProvider) -> [GrokModelOption] {
        switch provider.id {
        case AgentProvider.claude.id:
            return [
                model("claude-fable-5", "Fable 5", provider, runtimeId: "fable", isDefault: true, options: [claudeReasoning(defaultValue: "high")]),
                model("claude-opus-4-8", "Opus 4.8", provider, runtimeId: "opus", options: [claudeReasoning(defaultValue: "high")]),
                model("claude-sonnet-5", "Sonnet 5", provider, runtimeId: "sonnet", options: [claudeReasoning(defaultValue: "high")]),
            ]
        case AgentProvider.codex.id:
            return [
                model("gpt-5.5", "GPT 5.5", provider, isDefault: true, options: [codexReasoning(defaultValue: "high")]),
                model("gpt-5.4", "GPT 5.4", provider, options: [codexReasoning(defaultValue: "high")]),
                model("gpt-5.4-mini", "GPT 5.4 Mini", provider, options: [codexReasoning(defaultValue: "medium")]),
                model("gpt-5.3-codex-spark", "GPT 5.3 Codex Spark", provider, options: [codexReasoning(defaultValue: "medium")]),
            ]
        case AgentProvider.cursor.id:
            return [
                model("auto", "Auto", provider, isDefault: true),
                model("composer-2.5", "Composer 2.5", provider),
                model("opus-4.8", "Opus 4.8", provider),
                model("gpt-5.5-high-fast", "GPT 5.5 High Fast", provider),
                model("gemini-3.1-pro", "Gemini 3.1 Pro", provider),
                model("grok-4.3", "Grok 4.3", provider),
            ]
        case AgentProvider.gemini.id:
            return [
                model("auto-gemini-3", "Auto (Gemini 3)", provider, runtimeId: "gemini-3-pro-preview", isDefault: true, options: [geminiThinking(defaultValue: "high", values: ["low", "high"])]),
                model("auto-gemini-2.5", "Auto (Gemini 2.5)", provider, runtimeId: "gemini-2.5-pro", options: [geminiThinking(defaultValue: "high", values: ["low", "medium", "high"])]),
                model("gemini-3.1-pro-preview", "gemini-3.1-pro-preview", provider, options: [geminiThinking(defaultValue: "high", values: ["low", "medium", "high"])]),
                model("gemini-3-pro-preview", "gemini-3-pro-preview", provider, options: [geminiThinking(defaultValue: "high", values: ["low", "medium", "high"])]),
                model("gemini-3-flash-preview", "gemini-3-flash-preview", provider, options: [geminiThinking(defaultValue: "high", values: ["minimal", "low", "medium", "high"])]),
                model("gemini-2.5-pro", "gemini-2.5-pro", provider, options: [geminiThinking(defaultValue: "high", values: ["low", "medium", "high"])]),
                model("gemini-2.5-flash", "gemini-2.5-flash", provider, options: [geminiThinking(defaultValue: "medium", values: ["low", "medium", "high"])]),
            ]
        case AgentProvider.grok.id:
            return [
                model("grok-build", "Grok Build", provider, isDefault: true, options: [grokEffort(defaultValue: "medium")]),
                model("grok-composer-2.5-fast", "Grok Composer 2.5 Fast", provider),
                model("grok-4", "Grok 4", provider, options: [grokEffort(defaultValue: "medium")]),
            ]
        case AgentProvider.zai.id:
            return [
                model("glm-5.2[1m]", "GLM-5.2 (1M)", provider, isDefault: true),
                model("glm-4.7", "GLM-4.7", provider),
            ]
        default:
            return [
                model("default", "Default", provider, isDefault: true, isCustom: provider.isCustom)
            ]
        }
    }

    static func model(
        _ id: String,
        _ title: String,
        _ provider: AgentProvider,
        runtimeId: String? = nil,
        isDefault: Bool = false,
        isCustom: Bool = false,
        options: [ProviderOptionDescriptor] = []
    ) -> GrokModelOption {
        GrokModelOption(
            id: id,
            isDefault: isDefault,
            providerId: provider.id,
            providerName: provider.shortName,
            runtimeId: runtimeId,
            title: title,
            shortTitle: title,
            isCustom: isCustom,
            optionDescriptors: options
        )
    }

    static func reasoningChoices(_ values: [String], defaultValue: String) -> [ProviderOptionChoice] {
        values.map { raw in
            ProviderOptionChoice(id: raw, title: reasoningTitle(raw), isDefault: raw == defaultValue)
        }
    }

    static func reasoningTitle(_ raw: String) -> String {
        switch raw {
        case "none": "None"
        case "minimal": "Minimal"
        case "low": "Low"
        case "medium": "Medium"
        case "high": "High"
        case "xhigh": "Extra High"
        case "max": "Max"
        default: raw
        }
    }

    static func claudeReasoning(defaultValue: String) -> ProviderOptionDescriptor {
        ProviderOptionDescriptor(
            id: "effort",
            title: "Reasoning",
            choices: reasoningChoices(["low", "medium", "high", "xhigh", "max"], defaultValue: defaultValue)
        )
    }

    static func codexReasoning(defaultValue: String) -> ProviderOptionDescriptor {
        ProviderOptionDescriptor(
            id: "model_reasoning_effort",
            title: "Reasoning",
            choices: reasoningChoices(["minimal", "low", "medium", "high", "xhigh"], defaultValue: defaultValue)
        )
    }

    static func grokEffort(defaultValue: String) -> ProviderOptionDescriptor {
        ProviderOptionDescriptor(
            id: "effort",
            title: "Reasoning",
            choices: reasoningChoices(["low", "medium", "high", "xhigh", "max"], defaultValue: defaultValue)
        )
    }

    static func geminiThinking(defaultValue: String, values: [String]) -> ProviderOptionDescriptor {
        ProviderOptionDescriptor(
            id: "thinking_level",
            title: "Thinking level",
            kind: .readOnly,
            choices: reasoningChoices(values, defaultValue: defaultValue),
            detail: "Gemini CLI default unless the installed CLI exposes a thinking-level flag."
        )
    }
}

nonisolated final class AgentProviderRuntime: @unchecked Sendable {
    static let shared = AgentProviderRuntime()

    private let registry = ProviderRegistry.shared
    private let grok = GrokCLIService.shared
    private let processLock = NSLock()
    private var runningProcess: Process?

    func snapshots(for statuses: [ProviderStatus]) async -> [ProviderStatus] {
        await withTaskGroup(of: ProviderStatus.self) { group in
            for status in statuses {
                group.addTask { await self.snapshot(for: status.provider, binaryPath: status.binaryPath) }
            }
            var out: [ProviderStatus] = []
            for await status in group {
                out.append(status)
            }
            let order = Dictionary(uniqueKeysWithValues: statuses.enumerated().map { ($0.element.id, $0.offset) })
            return out.sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        }
    }

    func snapshot(for provider: AgentProvider, binaryPath: String? = nil) async -> ProviderStatus {
        let path = binaryPath ?? registry.resolveBinary(for: provider)
        var status = ProviderStatus(
            provider: provider,
            installed: path != nil,
            binaryPath: path,
            authStatus: path == nil ? .unknown : .unknown,
            runtimeState: path == nil ? .warning : .warning,
            message: path == nil ? "\(provider.shortName) CLI was not found." : "Checking \(provider.shortName)...",
            models: AgentProviderModelCatalog.models(for: provider)
        )
        guard let path else { return status }

        status.version = try? await version(for: provider, binaryPath: path)
        switch provider.id {
        case AgentProvider.claude.id:
            await enrichClaude(&status, path: path)
        case AgentProvider.codex.id:
            await enrichCodex(&status, path: path)
        case AgentProvider.grok.id:
            await enrichGrok(&status)
        case AgentProvider.cursor.id:
            status.authStatus = .unknown
            status.runtimeState = .warning
            status.message = "Cursor is installed. ACP model discovery/runtime still needs the Cursor adapter path."
        case AgentProvider.gemini.id:
            status.authStatus = .unknown
            status.runtimeState = .ready
            status.message = "Gemini CLI is installed. Auth will be validated by the first run."
        case AgentProvider.zai.id:
            status.authStatus = .unknown
            status.runtimeState = .warning
            status.message = "Z.AI CLI shape is not confirmed. Configure it as a custom command if this binary needs special arguments."
        default:
            status.authStatus = .unknown
            status.runtimeState = .ready
            status.message = "Custom provider is executable. Codessa will pass the prompt through stdin."
        }
        return status
    }

    func streamPrompt(
        request: ProviderRunRequest,
        onEvent: @escaping @Sendable (GrokStreamEvent) -> Void
    ) async throws -> String? {
        if request.provider.id == AgentProvider.grok.id {
            let effortRaw = request.options["effort"] ?? request.options["reasoning"] ?? "medium"
            let effort = EffortLevel(rawValue: effortRaw) ?? .medium
            return try await grok.streamPrompt(
                request.prompt,
                cwd: request.cwd,
                model: request.model.id,
                permissionMode: request.permissionMode,
                effort: effort,
                check: request.check,
                sessionId: request.sessionId,
                onEvent: onEvent
            )
        }

        let output = try await runOneShot(request)
        let text = extractAssistantText(from: output, providerId: request.provider.id)
        if !text.isEmpty {
            onEvent(GrokStreamEvent(type: "text", data: text))
        }
        onEvent(GrokStreamEvent(type: "end", data: nil, sessionId: nil))
        return nil
    }

    func cancel() {
        grok.cancel()
        processLock.lock()
        let process = runningProcess
        runningProcess = nil
        processLock.unlock()
        process?.terminate()
    }

    private func enrichClaude(_ status: inout ProviderStatus, path: String) async {
        guard let output = try? await capture(path, ["auth", "status"]) else {
            status.authStatus = .unknown
            status.runtimeState = .warning
            status.message = "Claude Code is installed, but auth status could not be read."
            return
        }
        let loggedIn = output.range(of: #""loggedIn"\s*:\s*true"#, options: .regularExpression) != nil
        status.authStatus = loggedIn ? .authenticated : .unauthenticated
        status.runtimeState = loggedIn ? .ready : .warning
        status.authLabel = output.contains("claude.ai") ? "Claude.ai" : nil
        status.authEmail = firstRegex(#""email"\s*:\s*"([^"]+)""#, in: output)
        status.message = loggedIn ? "Claude Code is ready." : "Run `claude auth login`."
    }

    private func enrichCodex(_ status: inout ProviderStatus, path: String) async {
        let output = (try? await capture(path, ["login", "status"])) ?? ""
        let loggedIn = output.localizedCaseInsensitiveContains("logged in")
        status.authStatus = loggedIn ? .authenticated : .unauthenticated
        status.runtimeState = loggedIn ? .ready : .warning
        status.authLabel = loggedIn ? "ChatGPT" : nil
        status.message = loggedIn ? "Codex is ready." : "Run `codex login`."
    }

    private func enrichGrok(_ status: inout ProviderStatus) async {
        do {
            let discovered = try await grok.listModels()
            if !discovered.isEmpty {
                status.models = discovered.map {
                    GrokModelOption(
                        id: $0.id,
                        isDefault: $0.isDefault,
                        providerId: AgentProvider.grok.id,
                        providerName: AgentProvider.grok.shortName,
                        title: $0.displayName,
                        optionDescriptors: $0.isReasoningModel ? [AgentProviderModelCatalog.grokEffort(defaultValue: "medium")] : []
                    )
                }
            }
            status.authStatus = .authenticated
            status.runtimeState = .ready
            status.message = "Grok is ready."
        } catch {
            status.authStatus = .unknown
            status.runtimeState = .warning
            status.message = error.localizedDescription
        }
    }

    private func version(for provider: AgentProvider, binaryPath: String) async throws -> String? {
        let args = provider.id == AgentProvider.cursor.id ? ["about"] : ["--version"]
        let output = try await capture(binaryPath, args, timeout: 8)
        return firstRegex(#"\b(\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9._-]+)?)\b"#, in: output)
    }

    private func runOneShot(_ request: ProviderRunRequest) async throws -> String {
        let command = command(for: request)
        return try await capture(
            request.binaryPath,
            command.arguments,
            cwd: request.cwd,
            environment: command.environment,
            stdin: command.stdin,
            timeout: 600
        )
    }

    private func command(for request: ProviderRunRequest) -> (arguments: [String], environment: [String: String], stdin: String?) {
        let model = request.model.runtimeId ?? request.model.id
        switch request.provider.id {
        case AgentProvider.claude.id:
            var args = [
                "--print",
                "--output-format", "stream-json",
                "--include-partial-messages",
                "--verbose",
                "--model", model,
                "--permission-mode", claudePermission(request.permissionMode),
            ]
            if let effort = request.options["effort"] ?? request.options["reasoning"] {
                args += ["--effort", effort]
            }
            args.append(request.prompt)
            return (args, [:], nil)
        case AgentProvider.codex.id:
            var args = [
                "exec",
                "--json",
                "--skip-git-repo-check",
                "-C", request.cwd.path,
                "-m", model,
                "-s", codexSandbox(request.permissionMode),
                "-c", #"approval_policy="\#(codexApproval(request.permissionMode))""#,
            ]
            if let effort = request.options["model_reasoning_effort"] ?? request.options["reasoning"] {
                args += ["-c", #"model_reasoning_effort="\#(effort)""#]
            }
            args.append(request.prompt)
            return (args, [:], nil)
        case AgentProvider.gemini.id:
            return (["--prompt", request.prompt, "--model", model, "--output-format", "json"], [:], nil)
        case AgentProvider.cursor.id:
            return (["-p", request.prompt, "--model", model], [:], nil)
        default:
            return ([model], [:], request.prompt)
        }
    }

    private func capture(
        _ binaryPath: String,
        _ arguments: [String],
        cwd: URL? = nil,
        environment: [String: String] = [:],
        stdin: String? = nil,
        timeout: TimeInterval = 20
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = cwd }
            var env = ProcessInfo.processInfo.environment
            environment.forEach { env[$0.key] = $0.value }
            env["PATH"] = Self.providerPATH(existing: env["PATH"])
            env["NO_COLOR"] = "1"
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let stdinPipe = Pipe()
            if stdin != nil { process.standardInput = stdinPipe }

            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { process.terminate() }

            process.terminationHandler = { [weak self] proc in
                timer.cancel()
                self?.clearRunningProcess(proc)
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if proc.terminationStatus == 0 || !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(returning: out + (err.isEmpty ? "" : "\n" + err))
                } else {
                    let name = (binaryPath as NSString).lastPathComponent.capitalized
                    continuation.resume(throwing: AgentProviderRuntimeError.processFailed(
                        CLIProcessMessage.friendly(name: name.isEmpty ? "The provider" : name,
                                                   exitCode: proc.terminationStatus, stderr: err)))
                }
            }

            do {
                setRunningProcess(process)
                timer.resume()
                try process.run()
                if let stdin {
                    stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
                    try? stdinPipe.fileHandleForWriting.close()
                }
            } catch {
                timer.cancel()
                clearRunningProcess(process)
                continuation.resume(throwing: error)
            }
        }
    }

    private func setRunningProcess(_ process: Process) {
        processLock.lock(); defer { processLock.unlock() }
        runningProcess = process
    }

    private func clearRunningProcess(_ process: Process) {
        processLock.lock(); defer { processLock.unlock() }
        if runningProcess === process { runningProcess = nil }
    }

    private func extractAssistantText(from output: String, providerId: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)

        if providerId == AgentProvider.claude.id {
            return extractClaudeAssistantText(from: lines) ?? rawNonJSONText(from: output)
        }

        var fragments: [String] = []

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            fragments += extractStrings(from: object, preferredKeys: [
                "text", "delta", "data", "message", "content", "output", "last_message"
            ])
        }

        let joined = fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: providerId == AgentProvider.claude.id ? "" : "\n")
        if !joined.isEmpty { return joined }

        return rawNonJSONText(from: output)
    }

    /// Claude Code's `stream-json` contains lifecycle and hook records alongside
    /// assistant output. Parse only the assistant/result shapes we intentionally
    /// surface so hook stdout or metadata never becomes chat text, and so partial
    /// deltas are still usable if the final assistant message is absent.
    private func extractClaudeAssistantText(from lines: [String]) -> String? {
        var finalAssistantText: [String] = []
        var streamedDeltas: [String] = []
        var resultText: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }

            switch type {
            case "assistant":
                if let message = object["message"] as? [String: Any] {
                    finalAssistantText += claudeTextBlocks(from: message["content"])
                }
            case "stream_event":
                guard let event = object["event"] as? [String: Any],
                      let eventType = event["type"] as? String
                else { continue }
                if eventType == "content_block_delta",
                   let delta = event["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    streamedDeltas.append(text)
                }
            case "result":
                if let result = object["result"] as? String {
                    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { resultText = trimmed }
                }
            default:
                continue
            }
        }

        let final = finalAssistantText.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty { return final }

        let streamed = streamedDeltas.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !streamed.isEmpty { return streamed }

        if let resultText { return resultText }
        return nil
    }

    private func claudeTextBlocks(from value: Any?) -> [String] {
        if let array = value as? [Any] {
            return array.flatMap { claudeTextBlocks(from: $0) }
        }
        guard let dict = value as? [String: Any],
              (dict["type"] as? String) == "text",
              let text = dict["text"] as? String
        else { return [] }
        return [text]
    }

    private func rawNonJSONText(from output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractStrings(from value: Any, preferredKeys: [String]) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] {
            return array.flatMap { extractStrings(from: $0, preferredKeys: preferredKeys) }
        }
        guard let dict = value as? [String: Any] else { return [] }
        var out: [String] = []
        for key in preferredKeys {
            if let nested = dict[key] {
                out += extractStrings(from: nested, preferredKeys: preferredKeys)
            }
        }
        return out
    }

    private func claudePermission(_ mode: PermissionMode) -> String {
        switch mode {
        case .fullAccess: "bypassPermissions"
        case .acceptEdits: "acceptEdits"
        case .auto: "auto"
        case .plan: "plan"
        }
    }

    private func codexSandbox(_ mode: PermissionMode) -> String {
        switch mode {
        case .fullAccess: "danger-full-access"
        case .acceptEdits, .auto: "workspace-write"
        case .plan: "read-only"
        }
    }

    private func codexApproval(_ mode: PermissionMode) -> String {
        switch mode {
        case .fullAccess, .plan: "never"
        case .acceptEdits, .auto: "on-request"
        }
    }

    private func firstRegex(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[valueRange])
    }

    private static func providerPATH(existing: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var entries = existing?.split(separator: ":").map(String.init) ?? []
        entries += [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/current/bin",
            "\(home)/.claude/local",
            "\(home)/.grok/bin",
            "\(home)/.cursor/bin",
            "\(home)/.codex/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/homebrew/opt/python@3.14/bin",
            "/opt/homebrew/opt/python@3.13/bin",
            "/opt/homebrew/opt/python@3.12/bin",
            "/opt/homebrew/opt/python@3.11/bin",
            "/opt/homebrew/opt/python@3.10/bin",
            "/usr/local/opt/python@3.14/bin",
            "/usr/local/opt/python@3.13/bin",
            "/usr/local/opt/python@3.12/bin",
            "/usr/local/opt/python@3.11/bin",
            "/usr/local/opt/python@3.10/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var seen = Set<String>()
        return entries.filter { seen.insert($0).inserted }.joined(separator: ":")
    }
}
