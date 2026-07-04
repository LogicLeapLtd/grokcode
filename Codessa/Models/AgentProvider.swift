import Foundation

/// A coding-agent CLI that Codessa can drive. Codessa is a *provider-agnostic*
/// shell — Grok is one option among Claude Code, Codex, Cursor, Gemini, Z.AI,
/// and any custom CLI the user points it at. A provider is pure configuration:
/// which executables to look for, how to install it, where its docs live, and
/// whether Codessa currently has a wired streaming adapter for its protocol.
///
/// `nonisolated`: this is an immutable value type with no UI state, read from
/// the nonisolated `ProviderRegistry` as well as the `@MainActor` view model, so
/// it opts out of the module's default main-actor isolation.
nonisolated struct AgentProvider: Identifiable, Hashable, Codable {
    let id: String
    /// Full product name, e.g. "Claude Code".
    let name: String
    /// Compact label for the onboarding dock, e.g. "Claude".
    let shortName: String
    /// Executable names probed on `PATH` and common install dirs (first match
    /// wins). Empty for a custom provider, which carries `explicitBinaryPath`.
    let binaryNames: [String]
    /// An explicit absolute binary path — set only for user-defined custom
    /// providers, where the user picked the executable directly.
    let explicitBinaryPath: String?
    /// One-line install command surfaced in onboarding when not detected.
    let installCommand: String
    /// Docs URL opened by the "Install docs" affordance.
    let docsURL: String
    /// A 1–2 char monogram used as a fallback glyph in the provider dock.
    let monogram: String
    /// Whether Codessa has a wired, tested streaming adapter for this provider's
    /// CLI protocol. Grok is fully wired today; the others are detected and
    /// selectable, and Codessa is honest that live runs route through the wired
    /// engine until each provider's protocol is implemented.
    let streamingWired: Bool

    var isCustom: Bool { explicitBinaryPath != nil }

    // MARK: - Known catalog

    static let claude = AgentProvider(
        id: "claude", name: "Claude Code", shortName: "Claude",
        binaryNames: ["claude"], explicitBinaryPath: nil,
        installCommand: "npm install -g @anthropic-ai/claude-code",
        docsURL: "https://docs.anthropic.com/en/docs/claude-code",
        monogram: "Cl", streamingWired: false)

    static let codex = AgentProvider(
        id: "codex", name: "Codex", shortName: "Codex",
        binaryNames: ["codex"], explicitBinaryPath: nil,
        installCommand: "npm install -g @openai/codex",
        docsURL: "https://github.com/openai/codex",
        monogram: "Cx", streamingWired: false)

    static let cursor = AgentProvider(
        id: "cursor", name: "Cursor", shortName: "Cursor",
        binaryNames: ["cursor-agent"], explicitBinaryPath: nil,
        installCommand: "curl https://cursor.com/install -fsS | bash",
        docsURL: "https://docs.cursor.com/en/cli/overview",
        monogram: "Cu", streamingWired: false)

    static let gemini = AgentProvider(
        id: "gemini", name: "Gemini CLI", shortName: "Gemini",
        binaryNames: ["gemini"], explicitBinaryPath: nil,
        installCommand: "npm install -g @google/gemini-cli",
        docsURL: "https://github.com/google-gemini/gemini-cli",
        monogram: "Ge", streamingWired: false)

    static let grok = AgentProvider(
        id: "grok", name: "Grok Code", shortName: "Grok",
        binaryNames: ["grok"], explicitBinaryPath: nil,
        installCommand: "npm install -g @vibe-kit/grok-cli",
        docsURL: "https://github.com/superagent-ai/grok-cli",
        monogram: "Gr", streamingWired: true)

    static let zai = AgentProvider(
        id: "zai", name: "Z.AI", shortName: "Z.AI",
        binaryNames: ["zai", "z"], explicitBinaryPath: nil,
        installCommand: "npm install -g @zai/cli",
        docsURL: "https://z.ai",
        monogram: "Z", streamingWired: false)

    /// The known providers, in dock order. Grok sits mid-list, not first — no
    /// single provider is the focus.
    static let known: [AgentProvider] = [claude, cursor, codex, gemini, grok, zai]

    /// The provider whose engine actually powers live runs today. Selection can
    /// point elsewhere, but this is the wired fallback.
    static let wiredDefault: AgentProvider = grok

    /// Build a custom provider from a user-picked executable.
    static func custom(name: String, binaryPath: String) -> AgentProvider {
        let base = (binaryPath as NSString).lastPathComponent
        return AgentProvider(
            id: "custom:" + binaryPath,
            name: name.isEmpty ? base : name,
            shortName: name.isEmpty ? base : name,
            binaryNames: [base],
            explicitBinaryPath: binaryPath,
            installCommand: binaryPath,
            docsURL: "",
            monogram: String((name.isEmpty ? base : name).prefix(1)).uppercased(),
            streamingWired: false)
    }
}

/// The live detection state for a provider, surfaced to the onboarding dock and
/// Settings. `binaryPath` is populated when the CLI was found on disk.
nonisolated struct ProviderStatus: Identifiable, Hashable {
    let provider: AgentProvider
    let installed: Bool
    let binaryPath: String?

    var id: String { provider.id }
}
