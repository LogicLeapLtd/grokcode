import Foundation

/// What kind of integration a `Plugin` represents. The raw values are stable
/// identifiers persisted as part of a plugin's `id` and in UserDefaults, so do
/// not rename them.
///
/// `extension` is a reserved word in Swift, hence the trailing underscore on
/// the case (`extension_`); the raw value stays `"extension"`.
nonisolated enum PluginKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case mcpServer = "mcpServer"
    case skill = "skill"
    case hook = "hook"
    case command = "command"
    case extension_ = "extension"
    case automation = "automation"

    var id: String { rawValue }

    /// Singular human label ("MCP Server", "Skill", …).
    var label: String {
        switch self {
        case .mcpServer: "MCP Server"
        case .skill: "Skill"
        case .hook: "Hook"
        case .command: "Command"
        case .extension_: "Extension"
        case .automation: "Automation"
        }
    }

    /// Plural label used for section headers ("MCP Servers", "Skills", …).
    var pluralLabel: String {
        switch self {
        case .mcpServer: "MCP Servers"
        case .skill: "Skills"
        case .hook: "Hooks"
        case .command: "Commands"
        case .extension_: "Extensions"
        case .automation: "Automations"
        }
    }

    /// SF Symbol shown on a plugin row / card for this kind.
    var symbol: String {
        switch self {
        case .mcpServer: "server.rack"
        case .skill: "wand.and.stars"
        case .hook: "bolt.horizontal"
        case .command: "terminal"
        case .extension_: "puzzlepiece.extension"
        case .automation: "clock.arrow.circlepath"
        }
    }

    /// Stable ordering for grouped lists (MCP servers first, automations last).
    nonisolated var sortOrder: Int {
        switch self {
        case .mcpServer: 0
        case .skill: 1
        case .command: 2
        case .hook: 3
        case .extension_: 4
        case .automation: 5
        }
    }
}

/// The tool a plugin was discovered from. Raw values are stable identifiers and
/// also form the prefix of a plugin's `id` (e.g. `"claude:cloudflare"`); do not
/// rename them.
nonisolated enum PluginSource: String, CaseIterable, Identifiable, Hashable, Codable {
    case grok
    case claude
    case codex
    case cursor
    case agents
    case builtin

    var id: String { rawValue }

    /// Human label for the source tool ("Grok CLI", "Claude Code", …).
    var displayName: String {
        switch self {
        case .grok: "Grok CLI"
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .agents: "Shared Agents"
        case .builtin: "Built-in"
        }
    }

    /// SF Symbol used as the source badge / chip icon.
    var iconSystemName: String {
        switch self {
        case .grok: "sparkle"
        case .claude: "ant"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .agents: "person.2.badge.gearshape"
        case .builtin: "shippingbox"
        }
    }

    /// A stable tint color expressed as a 0–1 sRGB triple. Views build a
    /// `Color(red:green:blue:)` from this so the model file stays free of any
    /// SwiftUI dependency.
    var tint: (red: Double, green: Double, blue: Double) {
        switch self {
        case .grok: (0.45, 0.36, 0.92)      // violet
        case .claude: (0.92, 0.45, 0.18)    // Codex accent orange
        case .codex: (0.09, 0.09, 0.09)     // near-black
        case .cursor: (0.18, 0.55, 0.92)    // blue
        case .agents: (0.25, 0.65, 0.46)    // green
        case .builtin: (0.42, 0.42, 0.42)   // grey
        }
    }
}

/// A discovered or installed integration (MCP server, skill, hook, command,
/// extension, or automation) sourced from one of the supported CLI tools.
///
/// Value type only. All configuration is captured in plain strings / a
/// `[String: String]` blob so the whole model is `Codable` and `Hashable` and
/// can be round-tripped through UserDefaults as JSON.
nonisolated struct Plugin: Identifiable, Hashable, Codable, Sendable {
    /// Stable, deterministic identifier, e.g. `"claude:cloudflare"` —
    /// `"<source>:<name>"`, optionally further qualified by kind/scope. Two
    /// discoveries of the same logical plugin MUST produce the same `id` so the
    /// import service can de-dupe and track installation state across refreshes.
    let id: String

    /// Display name, e.g. `"cloudflare"`, `"code-review"`, `"pagespeed"`.
    var name: String

    /// The category of integration.
    var kind: PluginKind

    /// Which tool this was discovered from.
    var sourceTool: PluginSource

    /// One-line human description shown under the name (server endpoint, skill
    /// summary, hook event, etc.).
    var detail: String

    /// SF Symbol for this specific plugin. Defaults to `kind.symbol` but can be
    /// overridden per plugin (e.g. a branded MCP server).
    var iconSystemName: String

    // MARK: MCP / command configuration (all optional)

    /// Executable for stdio MCP servers / command-style plugins (e.g. `"npx"`).
    var command: String?

    /// Endpoint for http/sse MCP servers (e.g. `"https://mcp.vercel.com"`).
    var url: String?

    /// Argument vector for stdio servers / commands.
    var args: [String]

    /// Environment variables to inject when launching (values may be redacted
    /// placeholders such as `"${GITHUB_TOKEN}"`).
    var env: [String: String]

    // MARK: State

    /// True when this plugin is recorded in the app's installed set.
    var isInstalled: Bool

    /// Absolute path the definition was read from (config file, skill dir,
    /// hook script). Empty for purely in-memory / remote definitions.
    var sourcePath: String

    /// Catch-all for any extra source-specific fields the importer wants to
    /// preserve (transport type, version, scope, marketplace, project path, …).
    /// Kept as flat strings so the whole struct stays `Codable`.
    var rawConfig: [String: String]

    init(
        id: String,
        name: String,
        kind: PluginKind,
        sourceTool: PluginSource,
        detail: String,
        iconSystemName: String? = nil,
        command: String? = nil,
        url: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        isInstalled: Bool = false,
        sourcePath: String = "",
        rawConfig: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sourceTool = sourceTool
        self.detail = detail
        self.iconSystemName = iconSystemName ?? kind.symbol
        self.command = command
        self.url = url
        self.args = args
        self.env = env
        self.isInstalled = isInstalled
        self.sourcePath = sourcePath
        self.rawConfig = rawConfig
    }

    // MARK: Display helpers

    /// Primary label for a row / card.
    var displayName: String { name }

    /// Secondary line: the detail text, falling back to a transport summary or
    /// the kind label when no detail was supplied.
    var subtitle: String {
        if !detail.isEmpty { return detail }
        if let url, !url.isEmpty { return url }
        if let command, !command.isEmpty {
            return ([command] + args).joined(separator: " ")
        }
        return kind.label
    }

    /// "<Source> · <Kind>" chip caption, e.g. "Claude Code · MCP Server".
    var sourceKindCaption: String {
        "\(sourceTool.displayName) · \(kind.label)"
    }

    /// True for http/sse style remote MCP servers (has a URL but no command).
    var isRemoteServer: Bool {
        kind == .mcpServer && (url?.isEmpty == false) && (command?.isEmpty != false)
    }

    /// Whether the underlying local definition is active in its source tool.
    /// Missing metadata defaults to enabled so older persisted plugins decode as
    /// active and marketplace rows are not accidentally labelled disabled.
    var isLocallyEnabled: Bool {
        let enabled = rawConfig["enabled"]?.lowercased()
        let disabled = rawConfig["disabled"]?.lowercased()
        return enabled != "false" && disabled != "true"
    }

    /// True when Codessa knows how to toggle this definition without deleting
    /// it. Config-backed MCPs use config edits; file-backed items use a
    /// reversible `.disabled` rename.
    var supportsLocalDisable: Bool {
        guard sourceTool != .builtin else { return false }
        switch rawConfig["disableMode"] {
        case "toml-enabled", "json-mcp-bucket", "directory-rename", "file-rename":
            return true
        default:
            return false
        }
    }

    /// True when Codessa knows how to remove the local definition from disk or
    /// from its source config.
    var supportsLocalDelete: Bool {
        guard sourceTool != .builtin else { return false }
        switch rawConfig["deleteMode"] {
        case "toml-mcp-entry", "json-mcp-entry", "trash":
            return true
        default:
            return false
        }
    }

    /// Convenience: a copy flipped to installed/uninstalled. Used by the import
    /// service so it never mutates discovered values in place.
    func settingInstalled(_ installed: Bool) -> Plugin {
        var copy = self
        copy.isInstalled = installed
        return copy
    }

    // MARK: Hashable / Equatable — identity is the stable id.

    static func == (lhs: Plugin, rhs: Plugin) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
