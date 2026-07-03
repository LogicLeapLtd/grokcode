import Foundation

/// The community plugin marketplace manifest — Codessa's *own* registry, hosted
/// as a single JSON file in the `logicleaplabs/grokcode-marketplace` repo and
/// also written locally for the user's published entries.
///
/// Shape (stable, versioned):
/// ```json
/// {
///   "version": 1,
///   "plugins": [ { … MarketplaceEntry … } ]
/// }
/// ```
///
/// `MarketplaceService` loads the remote file into this type, and the local
/// "published" store is the same type so the two are trivially interchangeable.
struct MarketplaceManifest: Codable, Hashable {
    /// Schema version. Bumped if the entry shape changes incompatibly. Decoders
    /// should tolerate unknown future versions (we only read fields we know).
    var version: Int

    /// Every published plugin in this manifest.
    var plugins: [MarketplaceEntry]

    init(version: Int = MarketplaceManifest.currentVersion, plugins: [MarketplaceEntry] = []) {
        self.version = version
        self.plugins = plugins
    }

    /// The schema version this build writes.
    static let currentVersion = 1

    /// An empty manifest at the current schema version.
    static let empty = MarketplaceManifest(version: currentVersion, plugins: [])
}

/// One community plugin in the marketplace manifest. This maps 1:1 onto the
/// app's `Plugin` value type, plus marketplace-only metadata (`author`,
/// `homepage`) that the curated `MarketplaceCatalog` doesn't carry.
///
/// All fields decode defensively: a malformed or partial entry should never
/// crash the decode of a whole manifest, so optionals default sensibly and the
/// only truly required field is `name`.
struct MarketplaceEntry: Codable, Hashable, Identifiable {
    /// Display name, e.g. `"Context7"`. Also the basis of the derived `Plugin.id`.
    var name: String

    /// One-line human description shown under the name.
    var detail: String

    /// SF Symbol for the plugin's card/row. Falls back to the kind symbol when
    /// absent (handled in the `Plugin` mapping).
    var iconSystemName: String?

    /// Integration category. Stored as the `PluginKind` raw value (e.g.
    /// `"mcpServer"`); defaults to `.mcpServer` when missing/unknown.
    var kind: PluginKind

    // MARK: Transport / launch configuration (all optional)

    /// Executable for stdio MCP servers / command plugins (e.g. `"npx"`).
    var command: String?

    /// Argument vector for stdio servers / commands.
    var args: [String]

    /// Endpoint for http/sse MCP servers (e.g. `"https://mcp.example.com"`).
    var url: String?

    /// Environment variables to inject at launch (values may be `"${TOKEN}"`).
    var env: [String: String]

    // MARK: Marketplace metadata (entry-only — not on `Plugin`)

    /// Publisher handle/name, e.g. `"logicleaplabs"`. Surfaced in the UI and
    /// stashed onto the mapped `Plugin.rawConfig` so it survives round-trips.
    var author: String?

    /// Optional homepage / docs URL for the plugin (a project page, not the MCP
    /// endpoint). Opened with `NSWorkspace` from the surface lane.
    var homepage: String?

    /// Stable identity for SwiftUI lists. Mirrors the derived `Plugin.id`.
    var id: String { Self.pluginID(for: name) }

    init(
        name: String,
        detail: String = "",
        iconSystemName: String? = nil,
        kind: PluginKind = .mcpServer,
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        env: [String: String] = [:],
        author: String? = nil,
        homepage: String? = nil
    ) {
        self.name = name
        self.detail = detail
        self.iconSystemName = iconSystemName
        self.kind = kind
        self.command = command
        self.args = args
        self.url = url
        self.env = env
        self.author = author
        self.homepage = homepage
    }

    // MARK: Defensive decoding

    private enum CodingKeys: String, CodingKey {
        case name, detail, iconSystemName, kind, command, args, url, env, author, homepage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        iconSystemName = try c.decodeIfPresent(String.self, forKey: .iconSystemName)
        // Tolerate an unknown/missing kind string → default to MCP server.
        kind = (try c.decodeIfPresent(PluginKind.self, forKey: .kind)) ?? .mcpServer
        command = try c.decodeIfPresent(String.self, forKey: .command)
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        url = try c.decodeIfPresent(String.self, forKey: .url)
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        author = try c.decodeIfPresent(String.self, forKey: .author)
        homepage = try c.decodeIfPresent(String.self, forKey: .homepage)
    }

    // MARK: Mapping → Plugin

    /// The marketplace prefix used for derived `Plugin.id`s, e.g.
    /// `"community:context7"`. Distinct from `"marketplace:"` (the curated
    /// catalog) so community and built-in entries never collide.
    static let idPrefix = "community"

    /// Deterministic `Plugin.id` for a given entry name: lower-cased, spaces →
    /// hyphens, non-alphanumerics stripped, prefixed with `community:`. Two
    /// loads of the same entry always yield the same id (de-dupe / install
    /// tracking depends on this).
    static func pluginID(for name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
            .map(String.init)
            .joined()
        let trimmed = slug.isEmpty ? "plugin" : slug
        return "\(idPrefix):\(trimmed)"
    }

    /// Map this manifest entry to the app's `Plugin` value type. `sourceTool`
    /// reuses the existing `.builtin` case (Plugin.swift is not Foundation's
    /// file); the community provenance + marketplace metadata are preserved on
    /// `rawConfig` so surfaces can badge "Community", show the author, and open
    /// the homepage without a new `PluginSource` case.
    func toPlugin(isInstalled: Bool = false) -> Plugin {
        var raw: [String: String] = ["marketplace": "community"]
        if let author, !author.isEmpty { raw["author"] = author }
        if let homepage, !homepage.isEmpty { raw["homepage"] = homepage }

        return Plugin(
            id: Self.pluginID(for: name),
            name: name,
            kind: kind,
            sourceTool: .builtin,
            detail: detail,
            iconSystemName: iconSystemName ?? kind.symbol,
            command: command,
            url: url,
            args: args,
            env: env,
            isInstalled: isInstalled,
            sourcePath: "",
            rawConfig: raw
        )
    }
}
