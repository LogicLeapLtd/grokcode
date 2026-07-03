import Foundation

/// Registers / unregisters MCP servers with the local `grok` CLI by shelling out
/// to `grok mcp add|remove|list`.
///
/// The GUI keeps its own persisted "installed" set (see `PluginImportService`),
/// but for `PluginKind.mcpServer` plugins that set is only meaningful if the
/// server is *actually* registered with grok — otherwise "Installed" is a lie.
/// This service is the bridge: `add(_:)` / `remove(_:)` mutate grok's real MCP
/// registry, and `listServerNames()` reads it back so the Installed tab can be
/// reconciled with ground truth on appear.
///
/// `nonisolated` + `@unchecked Sendable`: this type owns no mutable state (only
/// the resolved binary path, computed once and immutable), so it is safe to call
/// from any actor / off the main thread. All work is synchronous `Process` I/O,
/// so callers should hop to a background task before invoking the mutating calls.
nonisolated final class GrokMCPService: @unchecked Sendable {
    static let shared = GrokMCPService()

    /// Absolute path to the `grok` binary, resolved once at init using the same
    /// candidate list as `GrokCLIService` (the brief specifies `~/.grok/bin/grok`
    /// first; the homebrew/usr-local fallbacks keep parity with the CLI service).
    private let grokPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.grok/bin/grok",
            "/usr/local/bin/grok",
            "/opt/homebrew/bin/grok",
        ]
        grokPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    /// Whether the grok binary is present & executable. When false, every call
    /// below is a no-op that reports failure, so the GUI can fall back to a
    /// local-only "installed" flag without registering anything.
    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: grokPath)
    }

    // MARK: - Mutating registry calls

    /// Register `plugin` as an MCP server with grok.
    ///
    /// - Local (stdio) servers:  `grok mcp add <name> [--env K=V ...] -- <command> <args...>`
    /// - Remote (http/sse):      `grok mcp add <name> --url <url> [--env K=V ...]`
    ///
    /// The server name is the plugin's name, sanitised to a grok-safe slug. Env
    /// vars (`plugin.env`) are threaded through as repeated `--env KEY=VALUE`
    /// flags so configured API keys reach the launched server.
    ///
    /// Returns `true` when grok exits 0 (or the server already existed). Returns
    /// `false` if grok is missing, the plugin has neither a command nor a URL, or
    /// the command failed. Safe to call off the main actor; blocks on `Process`.
    @discardableResult
    func add(_ plugin: Plugin) -> Bool {
        guard isAvailable else { return false }

        let name = Self.serverName(for: plugin)
        guard !name.isEmpty else { return false }

        var arguments = ["mcp", "add", name]

        // Env flags apply to both transports; emit before the `--` separator so
        // they bind to the `add` subcommand, not the spawned command's argv.
        for key in plugin.env.keys.sorted() {
            guard let value = plugin.env[key], !key.isEmpty else { continue }
            arguments += ["--env", "\(key)=\(value)"]
        }

        if let url = plugin.url, !url.isEmpty,
           (plugin.command?.isEmpty ?? true) {
            // Remote MCP server.
            arguments += ["--url", url]
        } else if let command = plugin.command, !command.isEmpty {
            // Local stdio server: everything after `--` is the server's argv.
            arguments.append("--")
            arguments.append(command)
            arguments += plugin.args
        } else {
            // Nothing to launch — not an MCP server we can register.
            return false
        }

        return run(arguments).ok
    }

    /// Unregister the MCP server backing `plugin` (`grok mcp remove <name>`).
    ///
    /// Best-effort: a non-zero exit (e.g. the server was never registered) is
    /// swallowed, because the caller's goal — "this server is not registered" —
    /// is satisfied either way. Safe to call off the main actor; blocks.
    func remove(_ plugin: Plugin) {
        guard isAvailable else { return }
        let name = Self.serverName(for: plugin)
        guard !name.isEmpty else { return }
        _ = run(["mcp", "remove", name])
    }

    // MARK: - Reading the registry

    /// The names of MCP servers currently registered with grok (`grok mcp list`),
    /// parsed leniently from the CLI's text output. Empty when grok is missing or
    /// the command fails. Safe to call off the main actor; blocks.
    func listServerNames() -> [String] {
        guard isAvailable else { return [] }
        let result = run(["mcp", "list"])
        guard result.ok || !result.output.isEmpty else { return [] }
        return Self.parseServerNames(from: result.output)
    }

    // MARK: - Naming

    /// Sanitise a plugin's name into a stable, grok-safe server name: lowercase,
    /// non-alphanumerics collapsed to single hyphens, trimmed. Deterministic so
    /// `add` and `remove` always target the same registry entry for a plugin.
    static func serverName(for plugin: Plugin) -> String {
        let lowered = plugin.name.lowercased()
        var slug = ""
        var lastWasHyphen = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                slug.append("-")
                lastWasHyphen = true
            }
        }
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    // MARK: - Parsing

    /// Pull server names out of `grok mcp list` output. The CLI prints one server
    /// per line; this tolerates a few common shapes:
    ///   `name`                         → "name"
    ///   `name: npx -y some-server`     → "name"
    ///   `name  →  https://…`           → "name"
    ///   `• name (stdio)`               → "name"
    /// Header / blank / decorative lines are skipped.
    static func parseServerNames(from output: String) -> [String] {
        var names: [String] = []
        var seen = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Strip common bullet / list prefixes.
            for prefix in ["• ", "- ", "* ", "→ ", "● "] {
                if line.hasPrefix(prefix) { line.removeFirst(prefix.count) }
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Skip an obvious header row.
            let lowered = line.lowercased()
            if lowered.hasPrefix("name") && (lowered.contains("command") || lowered.contains("transport") || lowered.contains("url")) {
                continue
            }
            if lowered.hasPrefix("no mcp") || lowered.hasPrefix("no servers") {
                continue
            }

            // The token before the first delimiter is the server name.
            let token = line.prefix { ch in
                ch != ":" && ch != " " && ch != "\t" && ch != "→"
            }
            let name = token.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    // MARK: - Process

    private struct RunResult {
        let ok: Bool
        let output: String
    }

    /// Run `grok <arguments>` synchronously, capturing stdout+stderr. Mirrors
    /// `GrokCLIService.runCapture`'s environment handling (`NO_COLOR=1`).
    private func run(_ arguments: [String]) -> RunResult {
        guard FileManager.default.isExecutableFile(atPath: grokPath) else {
            return RunResult(ok: false, output: "")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: grokPath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return RunResult(ok: false, output: "\(error)")
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let combined = String(decoding: outData, as: UTF8.self) + String(decoding: errData, as: UTF8.self)
        return RunResult(ok: process.terminationStatus == 0, output: combined)
    }
}
