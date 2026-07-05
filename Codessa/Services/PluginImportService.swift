import Foundation

/// Read-only scanner + installed-set persistence for `Plugin`.
///
/// Discovers importable integrations (MCP servers, skills, hooks, commands,
/// extensions/plugins, automations) from the supported CLI tools' on-disk
/// configuration, and persists the user's installed set as JSON in
/// `UserDefaults` under `"grokcode.installedPlugins"`.
///
/// Plain class — no `@MainActor`, mirroring `ProjectDiscovery`. It is
/// constructed and called from the `@MainActor` `AppViewModel`, so all public
/// methods are synchronous. Every scan is defensive: missing or malformed files
/// are skipped silently and never throw.
final class PluginImportService {

    // MARK: Stored

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    /// Single UserDefaults key holding `Data` = `JSONEncoder().encode([Plugin])`.
    private let installedKey = "grokcode.installedPlugins"

    private var home: URL { fileManager.homeDirectoryForCurrentUser }

    init() {}

    // MARK: - Discovery

    /// Scan every supported tool's config and return de-duplicated importable
    /// plugins. `isInstalled` on each result reflects the persisted installed
    /// set. Never throws — missing/malformed files are skipped silently.
    func discoverImportable() -> [Plugin] {
        let installedIDs = Set(installedPlugins().map(\.id))

        var byID: [String: Plugin] = [:]
        // Merge every source; first writer wins on id collision so per-source
        // order is deterministic. Discovery order: claude, grok, codex,
        // cursor, then shared `.agents` surfaces.
        for plugin in discoverClaude() + discoverGrok() + discoverCodex() + discoverCursor() + discoverAgents() {
            if byID[plugin.id] == nil {
                byID[plugin.id] = plugin
            }
        }

        return byID.values
            .map { $0.settingInstalled(installedIDs.contains($0.id)) }
            .sorted(by: Self.sortPlugins)
    }

    /// Stable display ordering: by kind sortOrder, then source, then name.
    private nonisolated static func sortPlugins(_ a: Plugin, _ b: Plugin) -> Bool {
        if a.kind.sortOrder != b.kind.sortOrder {
            return a.kind.sortOrder < b.kind.sortOrder
        }
        if a.sourceTool.rawValue != b.sourceTool.rawValue {
            return a.sourceTool.rawValue < b.sourceTool.rawValue
        }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    // MARK: Claude — ~/.claude.json, ~/.mcp.json, ~/.claude/{skills,commands,agents,hooks}, installed plugins

    func discoverClaude() -> [Plugin] {
        var out: [Plugin] = []
        let claudeDir = home.appendingPathComponent(".claude")

        // Global MCP servers: ~/.claude.json -> mcpServers
        if let root = readJSONObject(at: home.appendingPathComponent(".claude.json")) {
            let configPath = home.appendingPathComponent(".claude.json").path
            if let servers = root["mcpServers"] as? [String: Any] {
                out += mcpPlugins(from: servers, source: .claude, sourcePath: configPath)
            }
            if let servers = root["disabledMcpServers"] as? [String: Any] {
                out += mcpPlugins(from: servers, source: .claude, sourcePath: configPath, enabled: false)
            }
            // Per-project MCP servers: projects["<path>"].mcpServers
            if let projects = root["projects"] as? [String: Any] {
                for (projectPath, value) in projects {
                    guard let proj = value as? [String: Any] else { continue }
                    if let servers = proj["mcpServers"] as? [String: Any], !servers.isEmpty {
                        out += mcpPlugins(
                            from: servers,
                            source: .claude,
                            sourcePath: configPath,
                            projectPath: projectPath
                        )
                    }
                    if let servers = proj["disabledMcpServers"] as? [String: Any], !servers.isEmpty {
                        out += mcpPlugins(
                            from: servers,
                            source: .claude,
                            sourcePath: configPath,
                            projectPath: projectPath,
                            enabled: false
                        )
                    }
                }
            }
        }

        // Shared project MCP file: ~/.mcp.json -> mcpServers
        if let root = readJSONObject(at: home.appendingPathComponent(".mcp.json")),
           let servers = root["mcpServers"] as? [String: Any] {
            out += mcpPlugins(
                from: servers,
                source: .claude,
                sourcePath: home.appendingPathComponent(".mcp.json").path
            )
        }
        if let root = readJSONObject(at: home.appendingPathComponent(".mcp.json")),
           let servers = root["disabledMcpServers"] as? [String: Any] {
            out += mcpPlugins(
                from: servers,
                source: .claude,
                sourcePath: home.appendingPathComponent(".mcp.json").path,
                enabled: false
            )
        }

        // Skills: ~/.claude/skills/<name>/SKILL.md
        out += skillPlugins(in: claudeDir.appendingPathComponent("skills"), source: .claude)

        // Commands: ~/.claude/commands/*.md
        out += commandPlugins(in: claudeDir.appendingPathComponent("commands"), source: .claude)

        // Agents (treated as skills): ~/.claude/agents/*.md
        out += markdownPlugins(
            in: claudeDir.appendingPathComponent("agents"),
            source: .claude,
            kind: .skill,
            detailPrefix: "Agent"
        )

        // Hooks: scripts under ~/.claude/hooks/
        out += scriptHookPlugins(in: claudeDir.appendingPathComponent("hooks"), source: .claude)

        // Installed Claude Code plugins (extensions): ~/.claude/plugins/installed_plugins.json
        out += claudeInstalledPlugins(
            at: claudeDir.appendingPathComponent("plugins/installed_plugins.json")
        )

        return out
    }

    // MARK: Grok — ~/.grok/config.toml, ~/.grok/{skills,hooks}

    func discoverGrok() -> [Plugin] {
        var out: [Plugin] = []
        let grokDir = home.appendingPathComponent(".grok")
        let configURL = grokDir.appendingPathComponent("config.toml")

        // MCP servers: [mcp_servers.<name>] tables in config.toml
        out += tomlMCPServers(at: configURL, source: .grok)

        // Skills: ~/.grok/skills/<name>/SKILL.md
        out += skillPlugins(in: grokDir.appendingPathComponent("skills"), source: .grok)

        // Hooks: ~/.grok/hooks/*.json (each file may declare several events)
        out += jsonHookPlugins(in: grokDir.appendingPathComponent("hooks"), source: .grok)

        return out
    }

    // MARK: Codex — ~/.codex/{mcp-configs,config.toml,skills,automations,hooks.json}

    func discoverCodex() -> [Plugin] {
        var out: [Plugin] = []
        let codexDir = home.appendingPathComponent(".codex")

        // MCP servers (curated catalogue): ~/.codex/mcp-configs/mcp-servers.json
        let mcpConfig = codexDir.appendingPathComponent("mcp-configs/mcp-servers.json")
        if let root = readJSONObject(at: mcpConfig),
           let servers = root["mcpServers"] as? [String: Any] {
            out += mcpPlugins(from: servers, source: .codex, sourcePath: mcpConfig.path)
        }
        if let root = readJSONObject(at: mcpConfig),
           let servers = root["disabledMcpServers"] as? [String: Any] {
            out += mcpPlugins(from: servers, source: .codex, sourcePath: mcpConfig.path, enabled: false)
        }

        // MCP servers (active): [mcp_servers.<name>] tables in config.toml
        out += tomlMCPServers(at: codexDir.appendingPathComponent("config.toml"), source: .codex)

        // Skills: ~/.codex/skills/<name>/SKILL.md
        out += skillPlugins(in: codexDir.appendingPathComponent("skills"), source: .codex)

        // Installed Codex plugins: ~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/.codex-plugin/plugin.json
        out += extensionPlugins(in: codexDir.appendingPathComponent("plugins/cache"), source: .codex)

        // Automations (display-only import items): ~/.codex/automations/<id>/automation.toml
        out += codexAutomations(in: codexDir.appendingPathComponent("automations"))

        // Hooks: ~/.codex/hooks.json
        out += jsonHookFile(at: codexDir.appendingPathComponent("hooks.json"), source: .codex, name: "hooks")

        return out
    }

    // MARK: Cursor — ~/.cursor/mcp.json, ~/.cursor/skills-cursor

    func discoverCursor() -> [Plugin] {
        var out: [Plugin] = []
        let cursorDir = home.appendingPathComponent(".cursor")

        // MCP servers: ~/.cursor/mcp.json -> mcpServers
        let mcpURL = cursorDir.appendingPathComponent("mcp.json")
        if let root = readJSONObject(at: mcpURL),
           let servers = root["mcpServers"] as? [String: Any] {
            out += mcpPlugins(from: servers, source: .cursor, sourcePath: mcpURL.path)
        }
        if let root = readJSONObject(at: mcpURL),
           let servers = root["disabledMcpServers"] as? [String: Any] {
            out += mcpPlugins(from: servers, source: .cursor, sourcePath: mcpURL.path, enabled: false)
        }

        // Skills: ~/.cursor/skills-cursor/<name>/SKILL.md
        out += skillPlugins(in: cursorDir.appendingPathComponent("skills-cursor"), source: .cursor)

        return out
    }

    // MARK: Shared agents — ~/.agents/{skills,plugins}

    func discoverAgents() -> [Plugin] {
        var out: [Plugin] = []
        let agentsDir = home.appendingPathComponent(".agents")

        out += skillPlugins(in: agentsDir.appendingPathComponent("skills"), source: .agents)
        out += extensionPlugins(in: agentsDir.appendingPathComponent("plugins"), source: .agents)

        return out
    }

    // MARK: - Installed set (persistence)

    /// Plugins the user has installed, decoded from UserDefaults (full Plugin
    /// blobs, each with `isInstalled == true`). `[]` on any failure.
    func installedPlugins() -> [Plugin] {
        guard let data = defaults.data(forKey: installedKey) else { return [] }
        guard let decoded = try? JSONDecoder().decode([Plugin].self, from: data) else { return [] }
        return decoded.map { $0.settingInstalled(true) }
    }

    /// Mark installed: stores the full Plugin (`settingInstalled(true)`) under
    /// the persistence key, keyed by id. Idempotent (replace-by-id).
    func install(_ plugin: Plugin) {
        var current = installedPlugins()
        current.removeAll { $0.id == plugin.id }
        current.append(plugin.settingInstalled(true))
        persist(current)
    }

    /// Remove from the installed set by id. Idempotent (filter-by-id).
    func remove(_ plugin: Plugin) {
        var current = installedPlugins()
        let before = current.count
        current.removeAll { $0.id == plugin.id }
        guard current.count != before else { return }
        persist(current)
    }

    /// True if a plugin with this id is in the installed set.
    func isInstalled(_ plugin: Plugin) -> Bool {
        installedPlugins().contains { $0.id == plugin.id }
    }

    private func persist(_ plugins: [Plugin]) {
        guard let data = try? JSONEncoder().encode(plugins) else { return }
        defaults.set(data, forKey: installedKey)
    }

    // MARK: - Local management

    /// Enable/disable a source definition in-place. Config-backed MCP servers
    /// stay in their config file; file-backed skills/hooks/plugins are renamed
    /// to/from a `.disabled` suffix. Returns false if this plugin is not backed
    /// by a manageable local definition.
    @discardableResult
    func setEnabled(_ plugin: Plugin, enabled: Bool) -> Bool {
        guard plugin.supportsLocalDisable else { return false }
        switch plugin.rawConfig["disableMode"] {
        case "toml-enabled":
            return writeTOMLMCPEnabled(plugin, enabled: enabled)
        case "json-mcp-bucket":
            return moveJSONMCP(plugin, enabled: enabled)
        case "directory-rename", "file-rename":
            return renameDefinition(plugin, enabled: enabled)
        default:
            return false
        }
    }

    /// Delete a source definition. File-backed definitions are moved to Trash
    /// when possible; config-backed MCP servers are removed from their config.
    @discardableResult
    func deleteDefinition(_ plugin: Plugin) -> Bool {
        guard plugin.supportsLocalDelete else { return false }

        let ok: Bool
        switch plugin.rawConfig["deleteMode"] {
        case "toml-mcp-entry":
            ok = deleteTOMLMCP(plugin)
        case "json-mcp-entry":
            ok = deleteJSONMCP(plugin)
        case "trash":
            ok = trashDefinition(plugin)
        default:
            ok = false
        }

        if ok { remove(plugin) }
        return ok
    }

    // MARK: - MCP parsing (JSON `mcpServers` map)

    /// Build MCP `Plugin`s from a `mcpServers` dictionary (Claude/Cursor/Codex
    /// JSON shape). Each value may be stdio (`command`/`args`/`env`) or remote
    /// (`type` http/sse + `url`). Skips anything unparsable.
    private func mcpPlugins(
        from servers: [String: Any],
        source: PluginSource,
        sourcePath: String,
        projectPath: String? = nil,
        enabled: Bool = true
    ) -> [Plugin] {
        servers.compactMap { name, raw -> Plugin? in
            guard let cfg = raw as? [String: Any] else { return nil }

            let type = (cfg["type"] as? String)?.lowercased()
            let url = (cfg["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let command = (cfg["command"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let args = (cfg["args"] as? [Any])?.compactMap { $0 as? String } ?? []
            let env = (cfg["env"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
            let description = (cfg["description"] as? String) ?? ""

            // A server with neither a URL nor a command is not launchable.
            guard url != nil || command != nil else { return nil }

            // Detail: explicit description wins, else endpoint / command summary.
            let detail: String
            if !description.isEmpty {
                detail = description
            } else if let url {
                detail = url
            } else if let command {
                detail = ([command] + args).joined(separator: " ")
            } else {
                detail = ""
            }

            var rawConfig: [String: String] = [:]
            if let type { rawConfig["type"] = type }
            else { rawConfig["type"] = (url != nil) ? "http" : "stdio" }
            if let projectPath { rawConfig["projectPath"] = projectPath }
            rawConfig["enabled"] = enabled ? "true" : "false"
            rawConfig["source"] = "json"
            rawConfig["disableMode"] = "json-mcp-bucket"
            rawConfig["deleteMode"] = "json-mcp-entry"

            // Project-scoped servers get a qualified id so global + per-project
            // entries of the same name don't collide.
            let id: String
            if let projectPath {
                id = "\(source.rawValue):\(name)@\(stableProjectToken(projectPath))"
            } else {
                id = "\(source.rawValue):\(name)"
            }

            return Plugin(
                id: id,
                name: name,
                kind: .mcpServer,
                sourceTool: source,
                detail: detail,
                command: command,
                url: url,
                args: args,
                env: env,
                sourcePath: sourcePath,
                rawConfig: rawConfig
            )
        }
    }

    /// Short, stable token for a project path so qualified MCP ids stay readable
    /// and deterministic across refreshes.
    private func stableProjectToken(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        let trimmed = last.isEmpty ? path : last
        return trimmed
    }

    // MARK: - MCP parsing (TOML `[mcp_servers.<name>]` tables)

    /// Parse `[mcp_servers.<name>]` tables out of a TOML file line-wise (no TOML
    /// dependency in-tree). Tolerant: anything it cannot read is skipped. Handles
    /// `command`, `args = [...]` (single or multi-line), `url`, `enabled`, and a
    /// nested `[mcp_servers.<name>.env]` table.
    private func tomlMCPServers(at url: URL, source: PluginSource) -> [Plugin] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        struct ServerDraft {
            var command: String?
            var url: String?
            var args: [String] = []
            var env: [String: String] = [:]
            var enabled = true
        }

        var drafts: [String: ServerDraft] = [:]
        var order: [String] = []

        // Current parsing context.
        var currentName: String?
        var inEnvTable = false
        var collectingArgs = false
        var argsBuffer = ""

        let lines = text.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Continue an unterminated multi-line args array first.
            if collectingArgs {
                argsBuffer += " " + line
                if line.contains("]") {
                    collectingArgs = false
                    if let name = currentName {
                        drafts[name]?.args = parseTOMLStringArray(argsBuffer)
                    }
                    argsBuffer = ""
                }
                continue
            }

            if line.isEmpty || line.hasPrefix("#") { continue }

            // Section header?
            if line.hasPrefix("[") {
                inEnvTable = false
                currentName = nil

                let header = sectionHeaderName(line)
                // [mcp_servers.<name>] or [mcp_servers.<name>.env]
                if header.hasPrefix("mcp_servers.") {
                    let remainder = String(header.dropFirst("mcp_servers.".count))
                    if remainder.hasSuffix(".env") {
                        let name = unquoteTOMLKey(String(remainder.dropLast(".env".count)))
                        if drafts[name] == nil {
                            drafts[name] = ServerDraft()
                            order.append(name)
                        }
                        currentName = name
                        inEnvTable = true
                    } else if !remainder.contains(".") {
                        let name = unquoteTOMLKey(remainder)
                        if drafts[name] == nil {
                            drafts[name] = ServerDraft()
                            order.append(name)
                        }
                        currentName = name
                    }
                    // Deeper nesting (e.g. .headers) is ignored on purpose.
                }
                continue
            }

            // Key/value inside a tracked table.
            guard let name = currentName,
                  let eq = line.firstIndex(of: "=") else { continue }

            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            if inEnvTable {
                if let value = parseTOMLString(valuePart) {
                    drafts[name]?.env[unquoteTOMLKey(key)] = value
                }
                continue
            }

            switch key {
            case "command":
                drafts[name]?.command = parseTOMLString(valuePart)
            case "url":
                drafts[name]?.url = parseTOMLString(valuePart)
            case "enabled":
                drafts[name]?.enabled = (valuePart == "true")
            case "args":
                if valuePart.contains("[") && !valuePart.contains("]") {
                    collectingArgs = true
                    argsBuffer = valuePart
                } else {
                    drafts[name]?.args = parseTOMLStringArray(valuePart)
                }
            default:
                break
            }
        }

        return order.compactMap { name -> Plugin? in
            guard let draft = drafts[name] else { return nil }
            let command = draft.command.flatMap { $0.isEmpty ? nil : $0 }
            let serverURL = draft.url.flatMap { $0.isEmpty ? nil : $0 }
            guard command != nil || serverURL != nil else { return nil }

            let detail: String
            if let serverURL {
                detail = serverURL
            } else if let command {
                detail = ([command] + draft.args).joined(separator: " ")
            } else {
                detail = ""
            }

            var rawConfig: [String: String] = [
                "type": serverURL != nil ? "http" : "stdio",
                "enabled": draft.enabled ? "true" : "false",
                "disableMode": "toml-enabled",
                "deleteMode": "toml-mcp-entry",
            ]
            rawConfig["source"] = "toml"

            return Plugin(
                id: "\(source.rawValue):\(name)",
                name: name,
                kind: .mcpServer,
                sourceTool: source,
                detail: detail,
                command: command,
                url: serverURL,
                args: draft.args,
                env: draft.env,
                sourcePath: url.path,
                rawConfig: rawConfig
            )
        }
    }

    // MARK: - Skills (directories containing SKILL.md)

    /// Each immediate subdirectory containing `SKILL.md` (case-insensitive) is a
    /// skill. `detail` = the frontmatter `description`/`short-description` first
    /// line if cheaply available, else "".
    private func skillPlugins(in dir: URL, source: PluginSource) -> [Plugin] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [Plugin] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }

            guard let skillFile = skillManifestURL(in: entry) else { continue }
            let disabled = isDisabledURL(entry)
            let name = enabledName(for: entry.lastPathComponent)
            let detail = frontmatterDescription(at: skillFile)

            out.append(Plugin(
                id: "\(source.rawValue):\(name)",
                name: name,
                kind: .skill,
                sourceTool: source,
                detail: detail,
                sourcePath: skillFile.path,
                rawConfig: [
                    "scope": "user",
                    "enabled": disabled ? "false" : "true",
                    "disableMode": "directory-rename",
                    "deleteMode": "trash",
                    "definitionPath": entry.path,
                ]
            ))
        }
        return out
    }

    private func skillManifestURL(in dir: URL) -> URL? {
        for candidate in ["SKILL.md", "skill.md", "Skill.md"] {
            let url = dir.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func isDisabledURL(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".disabled")
    }

    private func enabledName(for component: String) -> String {
        component.hasSuffix(".disabled")
            ? String(component.dropLast(".disabled".count))
            : component
    }

    private func logicalPathExtension(_ url: URL) -> String {
        let enabledComponent = enabledName(for: url.lastPathComponent)
        return (enabledComponent as NSString).pathExtension.lowercased()
    }

    private func markdownDefinitionName(_ url: URL) -> String? {
        guard logicalPathExtension(url) == "md" else { return nil }
        let enabledComponent = enabledName(for: url.lastPathComponent)
        return (enabledComponent as NSString).deletingPathExtension
    }

    private func jsonDefinitionName(_ url: URL) -> String {
        let enabledComponent = enabledName(for: url.lastPathComponent)
        return (enabledComponent as NSString).deletingPathExtension
    }

    private func scriptDefinitionName(_ url: URL) -> String {
        let enabledComponent = enabledName(for: url.lastPathComponent)
        let name = (enabledComponent as NSString).deletingPathExtension
        return name.isEmpty ? enabledComponent : name
    }

    // MARK: - Commands (~/.<tool>/commands/*.md)

    private func commandPlugins(in dir: URL, source: PluginSource) -> [Plugin] {
        markdownPlugins(in: dir, source: source, kind: .command, detailPrefix: nil)
    }

    /// Generic `*.md` scanner used for commands and agents. `name` = filename
    /// without extension. `detail` = frontmatter description, or the prefix.
    private func markdownPlugins(
        in dir: URL,
        source: PluginSource,
        kind: PluginKind,
        detailPrefix: String?
    ) -> [Plugin] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [Plugin] = []
        for entry in entries {
            guard let name = markdownDefinitionName(entry) else { continue }
            let disabled = isDisabledURL(entry)
            var detail = frontmatterDescription(at: entry)
            if detail.isEmpty, let detailPrefix { detail = detailPrefix }

            out.append(Plugin(
                id: "\(source.rawValue):\(name)",
                name: name,
                kind: kind,
                sourceTool: source,
                detail: detail,
                sourcePath: entry.path,
                rawConfig: [
                    "scope": "user",
                    "enabled": disabled ? "false" : "true",
                    "disableMode": "file-rename",
                    "deleteMode": "trash",
                    "definitionPath": entry.path,
                ]
            ))
        }
        return out
    }

    // MARK: - Hooks

    /// Claude-style hooks: executable scripts under a hooks directory. `detail`
    /// is the file kind (extension) since scripts carry no event metadata.
    private func scriptHookPlugins(in dir: URL, source: PluginSource) -> [Plugin] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [Plugin] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true
            else { continue }
            // JSON hook configs are handled by jsonHookPlugins; here we take scripts.
            let logicalExt = logicalPathExtension(entry)
            if logicalExt == "json" { continue }
            let name = scriptDefinitionName(entry)
            let detail = logicalExt.isEmpty ? "Hook script" : "\(logicalExt) hook"
            let disabled = isDisabledURL(entry)

            out.append(Plugin(
                id: "\(source.rawValue):\(name)",
                name: name,
                kind: .hook,
                sourceTool: source,
                detail: detail,
                sourcePath: entry.path,
                rawConfig: [
                    "format": "script",
                    "enabled": disabled ? "false" : "true",
                    "disableMode": "file-rename",
                    "deleteMode": "trash",
                    "definitionPath": entry.path,
                ]
            ))
        }
        return out
    }

    /// Grok-style hook config files: `*.json` each declaring one or more events
    /// under a top-level `hooks` map. One Plugin per file; `detail` = event names.
    private func jsonHookPlugins(in dir: URL, source: PluginSource) -> [Plugin] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [Plugin] = []
        for entry in entries where logicalPathExtension(entry) == "json" {
            let name = jsonDefinitionName(entry)
            out += jsonHookFile(at: entry, source: source, name: name)
        }
        return out
    }

    /// Parse a single hook JSON file (`{ "hooks": { "<Event>": [...] } }`) into
    /// one Plugin. Returns `[]` if the file is absent or has no events.
    private func jsonHookFile(at url: URL, source: PluginSource, name: String) -> [Plugin] {
        guard let root = readJSONObject(at: url) else { return [] }
        let events: [String]
        if let hooks = root["hooks"] as? [String: Any] {
            events = hooks.keys.sorted()
        } else {
            events = root.keys.sorted()
        }
        guard !events.isEmpty else { return [] }

        let detail = events.joined(separator: ", ")
        let disabled = isDisabledURL(url)
        return [Plugin(
            id: "\(source.rawValue):\(name)",
            name: name,
            kind: .hook,
            sourceTool: source,
            detail: detail,
            sourcePath: url.path,
            rawConfig: [
                "events": detail,
                "format": "json",
                "enabled": disabled ? "false" : "true",
                "disableMode": "file-rename",
                "deleteMode": "trash",
                "definitionPath": url.path,
            ]
        )]
    }

    // MARK: - Claude installed plugins (extensions)

    /// `~/.claude/plugins/installed_plugins.json` (version 2 shape):
    /// `{ "plugins": { "<name>@<marketplace>": [ { scope, version, … } ] } }`.
    /// Each key becomes an `extension_` Plugin.
    private func claudeInstalledPlugins(at url: URL) -> [Plugin] {
        guard let root = readJSONObject(at: url),
              let plugins = root["plugins"] as? [String: Any] else { return [] }

        var out: [Plugin] = []
        for (key, value) in plugins {
            // key = "<name>@<marketplace>"
            let parts = key.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            let pluginName = parts.first.map(String.init) ?? key
            let marketplace = parts.count > 1 ? String(parts[1]) : ""

            var version = ""
            var scope = ""
            if let installs = value as? [Any],
               let first = installs.first as? [String: Any] {
                version = (first["version"] as? String) ?? ""
                scope = (first["scope"] as? String) ?? ""
            }

            var detailBits: [String] = []
            if !marketplace.isEmpty { detailBits.append(marketplace) }
            if !version.isEmpty, version != "unknown" { detailBits.append("v\(version)") }
            let detail = detailBits.isEmpty ? "Claude Code plugin" : detailBits.joined(separator: " · ")

            var rawConfig: [String: String] = ["format": "claude-plugin"]
            if !marketplace.isEmpty { rawConfig["marketplace"] = marketplace }
            if !version.isEmpty { rawConfig["version"] = version }
            if !scope.isEmpty { rawConfig["scope"] = scope }

            out.append(Plugin(
                id: "\(PluginSource.claude.rawValue):\(pluginName)",
                name: pluginName,
                kind: .extension_,
                sourceTool: .claude,
                detail: detail,
                sourcePath: url.path,
                rawConfig: rawConfig
            ))
        }
        return out
    }

    // MARK: - Plugin manifests (Codex/shared agent plugin folders)

    /// Recursively scans a plugin/cache root for Codex/agent plugin manifests.
    /// We cap traversal depth so a plugin's own dependency tree never becomes
    /// part of discovery.
    private func extensionPlugins(in dir: URL, source: PluginSource) -> [Plugin] {
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootDepth = dir.pathComponents.count
        var seenDefinitionPaths = Set<String>()
        var out: [Plugin] = []

        for case let manifest as URL in enumerator {
            let depth = manifest.pathComponents.count - rootDepth
            if depth > 6 {
                enumerator.skipDescendants()
                continue
            }
            guard manifest.lastPathComponent == "plugin.json" else { continue }
            guard let plugin = extensionPlugin(at: manifest, source: source) else { continue }
            let definitionPath = plugin.rawConfig["definitionPath"] ?? plugin.sourcePath
            guard seenDefinitionPaths.insert(definitionPath).inserted else { continue }
            out.append(plugin)
        }

        return out
    }

    private func extensionPlugin(at manifest: URL, source: PluginSource) -> Plugin? {
        guard let root = readJSONObject(at: manifest) else { return nil }
        let interface = root["interface"] as? [String: Any] ?? [:]

        let manifestParent = manifest.deletingLastPathComponent()
        let definitionURL: URL
        if manifestParent.lastPathComponent.hasPrefix(".") {
            definitionURL = manifestParent.deletingLastPathComponent()
        } else {
            definitionURL = manifestParent
        }

        let disabled = isDisabledURL(definitionURL)
        let rawName = (root["name"] as? String)
            ?? (interface["displayName"] as? String)
            ?? definitionURL.lastPathComponent
        let name = enabledName(for: rawName)
        let displayName = (interface["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
        let detail = (interface["shortDescription"] as? String)
            ?? (root["description"] as? String)
            ?? "Plugin"
        let version = (root["version"] as? String) ?? ""

        var rawConfig: [String: String] = [
            "format": "plugin-manifest",
            "enabled": disabled ? "false" : "true",
            "disableMode": "directory-rename",
            "deleteMode": "trash",
            "definitionPath": definitionURL.path,
        ]
        if !version.isEmpty { rawConfig["version"] = version }

        return Plugin(
            id: "\(source.rawValue):plugin:\(name)",
            name: displayName,
            kind: .extension_,
            sourceTool: source,
            detail: firstSentence(detail),
            sourcePath: manifest.path,
            rawConfig: rawConfig
        )
    }

    // MARK: - Codex automations (display-only import items)

    /// `~/.codex/automations/<id>/automation.toml` → a `kind = .automation`
    /// Plugin for the import catalogue. (Runnable user automations are the
    /// separate `Automation` model.)
    private func codexAutomations(in dir: URL) -> [Plugin] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [Plugin] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let tomlURL = entry.appendingPathComponent("automation.toml")
            guard let text = try? String(contentsOf: tomlURL, encoding: .utf8) else { continue }
            let disabled = isDisabledURL(entry)

            let fields = parseFlatTOML(text)
            let id = fields["id"] ?? entry.lastPathComponent
            let name = fields["name"] ?? id
            let kindLabel = fields["kind"] ?? ""        // cron / heartbeat
            let status = fields["status"] ?? ""
            let model = fields["model"] ?? ""

            var detailBits: [String] = []
            if !kindLabel.isEmpty { detailBits.append(kindLabel) }
            if !status.isEmpty { detailBits.append(status.lowercased()) }
            let detail = detailBits.isEmpty ? "Codex automation" : detailBits.joined(separator: " · ")

            var rawConfig: [String: String] = ["format": "codex-automation"]
            if !kindLabel.isEmpty { rawConfig["kind"] = kindLabel }
            if !status.isEmpty { rawConfig["status"] = status }
            if !model.isEmpty { rawConfig["model"] = model }
            if let rrule = fields["rrule"] { rawConfig["rrule"] = rrule }
            rawConfig["enabled"] = disabled ? "false" : "true"
            rawConfig["disableMode"] = "directory-rename"
            rawConfig["deleteMode"] = "trash"
            rawConfig["definitionPath"] = entry.path

            out.append(Plugin(
                id: "\(PluginSource.codex.rawValue):\(id)",
                name: name,
                kind: .automation,
                sourceTool: .codex,
                detail: detail,
                sourcePath: tomlURL.path,
                rawConfig: rawConfig
            ))
        }
        return out
    }

    // MARK: - Local management helpers

    private func writeTOMLMCPEnabled(_ plugin: Plugin, enabled: Bool) -> Bool {
        guard let url = sourceFileURL(for: plugin),
              var text = try? String(contentsOf: url, encoding: .utf8) else { return false }

        var lines = text.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: { line in
            guard let section = mcpSection(from: line) else { return false }
            return section.name == plugin.name && section.nested == nil
        }) else { return false }

        let desired = "enabled = \(enabled)"
        var didReplace = false
        var index = headerIndex + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            if trimmed.hasPrefix("enabled") && trimmed.contains("=") {
                lines[index] = desired
                didReplace = true
                break
            }
            index += 1
        }

        if !didReplace {
            lines.insert(desired, at: headerIndex + 1)
        }

        text = lines.joined(separator: "\n")
        return writeString(text, to: url)
    }

    private func deleteTOMLMCP(_ plugin: Plugin) -> Bool {
        guard let url = sourceFileURL(for: plugin),
              let original = try? String(contentsOf: url, encoding: .utf8) else { return false }

        var keep: [String] = []
        var skipping = false

        for line in original.components(separatedBy: "\n") {
            if let section = mcpSection(from: line) {
                skipping = section.name == plugin.name
                if skipping { continue }
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                skipping = false
            }

            if !skipping { keep.append(line) }
        }

        let updated = keep.joined(separator: "\n")
        guard updated != original else { return false }
        return writeString(updated, to: url)
    }

    private func moveJSONMCP(_ plugin: Plugin, enabled: Bool) -> Bool {
        guard let url = sourceFileURL(for: plugin),
              var root = readJSONObject(at: url) else { return false }

        let changed: Bool
        if let projectPath = plugin.rawConfig["projectPath"] {
            var projects = root["projects"] as? [String: Any] ?? [:]
            var project = projects[projectPath] as? [String: Any] ?? [:]
            changed = moveJSONMCPEntry(named: plugin.name, in: &project, enabled: enabled)
            projects[projectPath] = project
            root["projects"] = projects
        } else {
            changed = moveJSONMCPEntry(named: plugin.name, in: &root, enabled: enabled)
        }

        guard changed else { return false }
        return writeJSONObject(root, to: url)
    }

    private func deleteJSONMCP(_ plugin: Plugin) -> Bool {
        guard let url = sourceFileURL(for: plugin),
              var root = readJSONObject(at: url) else { return false }

        let changed: Bool
        if let projectPath = plugin.rawConfig["projectPath"] {
            var projects = root["projects"] as? [String: Any] ?? [:]
            var project = projects[projectPath] as? [String: Any] ?? [:]
            changed = deleteJSONMCPEntry(named: plugin.name, in: &project)
            projects[projectPath] = project
            root["projects"] = projects
        } else {
            changed = deleteJSONMCPEntry(named: plugin.name, in: &root)
        }

        guard changed else { return false }
        return writeJSONObject(root, to: url)
    }

    private func moveJSONMCPEntry(named name: String, in container: inout [String: Any], enabled: Bool) -> Bool {
        let sourceKey = enabled ? "disabledMcpServers" : "mcpServers"
        let destinationKey = enabled ? "mcpServers" : "disabledMcpServers"

        var source = container[sourceKey] as? [String: Any] ?? [:]
        var destination = container[destinationKey] as? [String: Any] ?? [:]

        if destination[name] != nil, source[name] == nil { return true }
        guard let config = source.removeValue(forKey: name) else { return false }

        destination[name] = config
        if source.isEmpty {
            container.removeValue(forKey: sourceKey)
        } else {
            container[sourceKey] = source
        }
        container[destinationKey] = destination
        return true
    }

    private func deleteJSONMCPEntry(named name: String, in container: inout [String: Any]) -> Bool {
        var changed = false
        for key in ["mcpServers", "disabledMcpServers"] {
            var servers = container[key] as? [String: Any] ?? [:]
            if servers.removeValue(forKey: name) != nil {
                changed = true
                if servers.isEmpty {
                    container.removeValue(forKey: key)
                } else {
                    container[key] = servers
                }
            }
        }
        return changed
    }

    private func renameDefinition(_ plugin: Plugin, enabled: Bool) -> Bool {
        guard let current = definitionURL(for: plugin) else { return false }
        let target = enabled ? enabledURL(for: current) : disabledURL(for: current)
        guard current.path != target.path else { return true }
        guard fileManager.fileExists(atPath: current.path),
              !fileManager.fileExists(atPath: target.path) else { return false }

        do {
            try fileManager.moveItem(at: current, to: target)
            return true
        } catch {
            return false
        }
    }

    private func trashDefinition(_ plugin: Plugin) -> Bool {
        guard let url = definitionURL(for: plugin),
              fileManager.fileExists(atPath: url.path) else { return false }

        do {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            return true
        } catch {
            do {
                try fileManager.removeItem(at: url)
                return true
            } catch {
                return false
            }
        }
    }

    private func definitionURL(for plugin: Plugin) -> URL? {
        let path = plugin.rawConfig["definitionPath"] ?? plugin.sourcePath
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func sourceFileURL(for plugin: Plugin) -> URL? {
        guard !plugin.sourcePath.isEmpty else { return nil }
        return URL(fileURLWithPath: plugin.sourcePath)
    }

    private func disabledURL(for url: URL) -> URL {
        if isDisabledURL(url) { return url }
        return url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".disabled")
    }

    private func enabledURL(for url: URL) -> URL {
        guard isDisabledURL(url) else { return url }
        let enabledComponent = enabledName(for: url.lastPathComponent)
        return url.deletingLastPathComponent().appendingPathComponent(enabledComponent)
    }

    private func mcpSection(from line: String) -> (name: String, nested: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }
        let header = sectionHeaderName(trimmed)
        guard header.hasPrefix("mcp_servers.") else { return nil }

        let remainder = String(header.dropFirst("mcp_servers.".count))
        if remainder.hasPrefix("\"") || remainder.hasPrefix("'") {
            let quote = remainder.first!
            let body = remainder.dropFirst()
            guard let end = body.firstIndex(of: quote) else { return nil }
            let name = String(body[..<end])
            let after = body[body.index(after: end)...]
            let nested = after.hasPrefix(".") ? String(after.dropFirst()) : nil
            return (name, nested)
        }

        let parts = remainder.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        let nested = parts.count > 1 ? String(parts[1]) : nil
        return (unquoteTOMLKey(String(first)), nested)
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) -> Bool {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func writeString(_ text: String, to url: URL) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - JSON helpers

    private func readJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let object = try? JSONSerialization.jsonObject(with: data, options: [])
        return object as? [String: Any]
    }

    // MARK: - Frontmatter helpers

    /// Read the YAML-style frontmatter `description:` / `short-description:`
    /// from the first ~40 lines of a markdown/skill file. Returns "" if absent.
    /// Cheap: reads the file once, stops at the closing `---`.
    private func frontmatterDescription(at url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let lines = text.components(separatedBy: .newlines)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return ""
        }

        for line in lines.dropFirst().prefix(60) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            let lower = trimmed.lowercased()
            for key in ["description:", "short-description:"] {
                if lower.hasPrefix(key) {
                    var value = String(trimmed.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
                    value = stripWrappingQuotes(value)
                    if !value.isEmpty { return firstSentence(value) }
                }
            }
        }
        return ""
    }

    /// Keep frontmatter detail to one sentence so rows stay single-line.
    private func firstSentence(_ text: String) -> String {
        if let dot = text.firstIndex(of: ".") {
            let sentence = String(text[..<dot]).trimmingCharacters(in: .whitespaces)
            if sentence.count >= 12 { return sentence }
        }
        return text
    }

    // MARK: - Tiny TOML scalar parsing

    /// Extract the dotted name from a section header line, e.g.
    /// `[mcp_servers.foo.env]` -> `mcp_servers.foo.env`. Handles `[[...]]` too.
    private func sectionHeaderName(_ line: String) -> String {
        var s = line
        while s.hasPrefix("[") { s.removeFirst() }
        while s.hasSuffix("]") { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Parse a single TOML string scalar (`"..."` or `'...'`). Returns nil for
    /// non-string values (numbers, bools, inline tables/arrays).
    private func parseTOMLString(_ raw: String) -> String? {
        var value = raw
        // Drop a trailing inline comment outside of quotes (best effort).
        if let hash = value.firstIndex(of: "#"),
           !value.hasPrefix("\""), !value.hasPrefix("'") {
            value = String(value[..<hash])
        }
        value = value.trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2) ||
           (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2) {
            return String(value.dropFirst().dropLast())
        }
        return nil
    }

    /// Parse a TOML inline string array `["a", "b"]` (possibly reassembled from
    /// multiple lines) into `[String]`. Tolerant of trailing commas/whitespace.
    private func parseTOMLStringArray(_ raw: String) -> [String] {
        guard let open = raw.firstIndex(of: "["),
              let close = raw.lastIndex(of: "]"), open < close else { return [] }
        let inner = String(raw[raw.index(after: open)..<close])
        var result: [String] = []
        var current = ""
        var inString = false
        var quoteChar: Character = "\""
        var iterator = inner.makeIterator()
        var pending: Character? = iterator.next()
        while let ch = pending {
            pending = iterator.next()
            if inString {
                if ch == quoteChar {
                    inString = false
                    result.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                inString = true
                quoteChar = ch
            }
            // commas / whitespace outside strings are separators — ignored.
        }
        return result
    }

    /// Strip surrounding quotes from a bare key (`"name"` -> `name`).
    private func unquoteTOMLKey(_ key: String) -> String {
        stripWrappingQuotes(key.trimmingCharacters(in: .whitespaces))
    }

    private func stripWrappingQuotes(_ value: String) -> String {
        if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2) ||
           (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Parse a flat top-level TOML file into `[key: stringValue]`, taking only
    /// scalar string/number/bool values at the root (no section nesting). Used
    /// for the small `automation.toml` manifests.
    private func parseFlatTOML(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("[") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = unquoteTOMLKey(String(line[..<eq]))
            let valuePart = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if let str = parseTOMLString(valuePart) {
                fields[key] = str
            } else {
                // bare number / bool — strip a trailing comment.
                var v = valuePart
                if let hash = v.firstIndex(of: "#") { v = String(v[..<hash]) }
                fields[key] = v.trimmingCharacters(in: .whitespaces)
            }
        }
        return fields
    }
}
