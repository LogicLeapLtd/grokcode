import Foundation

/// A coding-agent CLI that Codessa can drive. Codessa is a Codex-first workspace
/// with optional support for Claude Code, Cursor, Gemini, Grok, Z.AI, and any
/// custom CLI the user points it at. A provider is pure configuration:
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
    /// Whether Codessa has a first-class runtime adapter for this provider's
    /// CLI protocol. Providers without one can still be surfaced and configured,
    /// but the run path will use the generic/custom command runner.
    let streamingWired: Bool

    var isCustom: Bool { explicitBinaryPath != nil }

    // MARK: - Known catalog

    static let claude = AgentProvider(
        id: "claude", name: "Claude Code", shortName: "Claude",
        binaryNames: ["claude"], explicitBinaryPath: nil,
        installCommand: "npm install -g @anthropic-ai/claude-code",
        docsURL: "https://docs.anthropic.com/en/docs/claude-code",
        monogram: "Cl", streamingWired: true)

    static let codex = AgentProvider(
        id: "codex", name: "ChatGPT Codex", shortName: "Codex",
        binaryNames: ["codex"], explicitBinaryPath: nil,
        installCommand: "npm install -g @openai/codex",
        docsURL: "https://learn.chatgpt.com/docs/codex/cli",
        monogram: "Cx", streamingWired: true)

    static let cursor = AgentProvider(
        id: "cursor", name: "Cursor", shortName: "Cursor",
        binaryNames: ["cursor-agent", "agent"], explicitBinaryPath: nil,
        installCommand: "curl https://cursor.com/install -fsS | bash",
        docsURL: "https://docs.cursor.com/en/cli/overview",
        monogram: "Cu", streamingWired: false)

    static let gemini = AgentProvider(
        id: "gemini", name: "Gemini CLI", shortName: "Gemini",
        binaryNames: ["gemini"], explicitBinaryPath: nil,
        installCommand: "npm install -g @google/gemini-cli",
        docsURL: "https://github.com/google-gemini/gemini-cli",
        monogram: "Ge", streamingWired: true)

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

    /// The known providers, in dock order. ChatGPT Codex leads the experience;
    /// the other local agents remain available as optional alternatives.
    static let known: [AgentProvider] = [codex, claude, cursor, gemini, grok, zai]

    /// The primary provider used for new installs and execution fallbacks.
    static let wiredDefault: AgentProvider = codex

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
            streamingWired: true)
    }
}

nonisolated enum ProviderAuthStatus: String, Hashable, Codable {
    case authenticated
    case unauthenticated
    case unknown

    var label: String {
        switch self {
        case .authenticated: "Authenticated"
        case .unauthenticated: "Sign in required"
        case .unknown: "Unknown auth"
        }
    }
}

nonisolated enum ProviderRuntimeState: String, Hashable, Codable {
    case ready
    case warning
    case error
    case disabled

    var label: String {
        switch self {
        case .ready: "Ready"
        case .warning: "Setup needed"
        case .error: "Error"
        case .disabled: "Disabled"
        }
    }
}

nonisolated struct ProviderOptionChoice: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    var isDefault: Bool

    init(id: String, title: String, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}

nonisolated struct ProviderOptionDescriptor: Identifiable, Hashable, Codable {
    enum Kind: String, Hashable, Codable {
        case select
        case toggle
        case readOnly
    }

    let id: String
    let title: String
    let kind: Kind
    var choices: [ProviderOptionChoice]
    var currentValue: String?
    var detail: String?

    init(
        id: String,
        title: String,
        kind: Kind = .select,
        choices: [ProviderOptionChoice] = [],
        currentValue: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.choices = choices
        self.currentValue = currentValue ?? choices.first(where: \.isDefault)?.id
        self.detail = detail
    }

    var defaultValue: String? {
        currentValue ?? choices.first(where: \.isDefault)?.id ?? choices.first?.id
    }
}

/// The live detection state for a provider, surfaced to the onboarding dock and
/// Settings. `binaryPath` is populated when the CLI was found on disk.
nonisolated struct ProviderStatus: Identifiable, Hashable {
    let provider: AgentProvider
    let installed: Bool
    let binaryPath: String?
    var version: String?
    var authStatus: ProviderAuthStatus
    var authLabel: String?
    var authEmail: String?
    var runtimeState: ProviderRuntimeState
    var message: String?
    var models: [GrokModelOption]

    var id: String { provider.id }
    var runtimeReady: Bool { installed && runtimeState == .ready }

    init(
        provider: AgentProvider,
        installed: Bool,
        binaryPath: String?,
        version: String? = nil,
        authStatus: ProviderAuthStatus = .unknown,
        authLabel: String? = nil,
        authEmail: String? = nil,
        runtimeState: ProviderRuntimeState? = nil,
        message: String? = nil,
        models: [GrokModelOption]? = nil
    ) {
        self.provider = provider
        self.installed = installed
        self.binaryPath = binaryPath
        self.version = version
        self.authStatus = authStatus
        self.authLabel = authLabel
        self.authEmail = authEmail
        self.runtimeState = runtimeState ?? (installed ? .warning : .warning)
        self.message = message
        self.models = models ?? AgentProviderModelCatalog.models(for: provider)
    }
}
