import Foundation

struct Project: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var path: URL
    var threads: [ProjectThread]
    var lastActiveAt: Date?
    var createdAt: Date?
    /// Current git branch, if the folder is a git repo (nil otherwise).
    var gitBranch: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        threads: [ProjectThread] = [],
        lastActiveAt: Date? = nil,
        createdAt: Date? = nil,
        gitBranch: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path.standardizedFileURL
        self.threads = threads
        self.lastActiveAt = lastActiveAt
        self.createdAt = createdAt
        self.gitBranch = gitBranch
    }

    var displayName: String {
        if name.count > 20 {
            return String(name.prefix(17)) + "..."
        }
        return name
    }

    var statusLabel: String {
        threads.isEmpty ? "No chats" : ""
    }
}

nonisolated struct ProjectThread: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var ageLabel: String
    /// Git branch this thread was worked on, if known (used by the
    /// "By project → branch" sidebar grouping). Optional/back-compatible.
    var branch: String?
    /// True when this thread is a subagent session spawned by another chat.
    /// Subagents are rendered nested beneath their parent chat in the sidebar.
    var isSubagent: Bool
    /// The subagent's agent type (e.g. "Explore"), when known. Surfaced as a
    /// small label on the nested row. nil for ordinary chats.
    var agentName: String?
    /// Subagent chats spawned by this thread, nested beneath it in the sidebar.
    /// Empty for ordinary chats and for subagents themselves (one level deep).
    var subThreads: [ProjectThread]
    /// True for the optimistic placeholder row shown the instant a new chat is
    /// started, before grok has persisted the session to disk. Rendered with a
    /// soft pulse and the title "New chat" until the real session is indexed.
    var isPending: Bool

    init(
        id: String,
        title: String,
        ageLabel: String,
        branch: String? = nil,
        isSubagent: Bool = false,
        agentName: String? = nil,
        subThreads: [ProjectThread] = [],
        isPending: Bool = false
    ) {
        self.id = id
        self.title = title
        self.ageLabel = ageLabel
        self.branch = branch
        self.isSubagent = isSubagent
        self.agentName = agentName
        self.subThreads = subThreads
        self.isPending = isPending
    }
}

/// The optimistic "New chat" placeholder shown in the sidebar the moment a new
/// conversation is started, before grok writes the session to disk. Cleared once
/// the real session is indexed (or the run fails before creating one).
struct PendingChat: Identifiable, Hashable {
    let id: String
    /// The project the chat belongs to (nil for a no-project scratch chat, which
    /// has no sidebar project row to attach to).
    let projectPath: URL?

    init(projectPath: URL?) {
        self.id = "pending-" + UUID().uuidString
        self.projectPath = projectPath?.standardizedFileURL
    }
}

struct GrokSession: Identifiable, Hashable {
    let id: String
    var summary: String
    var created: Date?
    var updated: Date?
    var status: String
}

enum PermissionMode: String, CaseIterable, Identifiable, Codable {
    case fullAccess = "bypassPermissions"
    case acceptEdits = "acceptEdits"
    case auto = "auto"
    case plan = "plan"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullAccess: "Full access"
        case .acceptEdits: "Accept edits"
        case .auto: "Auto"
        case .plan: "Plan mode"
        }
    }

    var detail: String {
        switch self {
        case .fullAccess: "Run everything without asking"
        case .acceptEdits: "Auto-approve file edits, ask for the rest"
        case .auto: "Approve safe actions automatically"
        case .plan: "Read-only — plan without making changes"
        }
    }

    var symbol: String {
        switch self {
        case .fullAccess: "lock.open"
        case .acceptEdits: "pencil"
        case .auto: "checkmark.shield"
        case .plan: "list.bullet.clipboard"
        }
    }
}

enum EffortLevel: String, CaseIterable, Identifiable, Codable {
    case low, medium, high, xhigh, max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra high"
        case .max: "Max"
        }
    }

}

nonisolated struct GrokModelOption: Identifiable, Hashable {
    let id: String
    var isDefault: Bool
    var providerId: String
    var providerName: String
    var runtimeId: String?
    var title: String?
    var shortTitle: String?
    var isCustom: Bool
    var optionDescriptors: [ProviderOptionDescriptor]

    init(
        id: String,
        isDefault: Bool,
        providerId: String = AgentProvider.grok.id,
        providerName: String = AgentProvider.grok.shortName,
        runtimeId: String? = nil,
        title: String? = nil,
        shortTitle: String? = nil,
        isCustom: Bool = false,
        optionDescriptors: [ProviderOptionDescriptor] = []
    ) {
        self.id = id
        self.isDefault = isDefault
        self.providerId = providerId
        self.providerName = providerName
        self.runtimeId = runtimeId
        self.title = title
        self.shortTitle = shortTitle
        self.isCustom = isCustom
        self.optionDescriptors = optionDescriptors
    }

    /// Model ids that are known *fast* (non-reasoning) agents. Anything not in
    /// this set is treated as a reasoning model (see `isReasoningModel`).
    static let knownFastModelIDs: Set<String> = [
        "grok-composer-2.5-fast",
        "grok-composer-2.5",
        "grok-build",
        "grok-code-fast",
        "grok-code-fast-1",
    ]

    /// Friendly, human-readable name for the model id.
    var displayName: String {
        if let title, !title.isEmpty { return title }
        switch id {
        case "grok-composer-2.5-fast": return "Composer 2.5 Fast"
        case "grok-composer-2.5": return "Composer 2.5"
        case "grok-build": return "Build"
        case "grok-4": return "Grok 4"
        case "grok-4-fast": return "Grok 4 Fast"
        // Frontier models routed by agent modes. The provider is already conveyed
        // by the logo/section header, so these are the bare product names.
        case "claude-fable-5": return "Fable 5"
        case "claude-opus-4-8": return "Opus 4.8"
        case "claude-sonnet-5": return "Sonnet 5"
        case "claude-haiku-4-5", "claude-haiku-4-5-20251001": return "Haiku 4.5"
        case "gpt-5.5": return "GPT-5.5"
        case "gpt-5", "gpt-5-codex": return "GPT-5"
        case "auto-gemini-3": return "Auto (Gemini 3 Pro)"
        case "auto-gemini-2.5": return "Auto (Gemini 2.5 Pro)"
        case "gemini-3.1-pro-preview": return "Gemini 3.1 Pro (Preview)"
        case "gemini-3-pro-preview": return "Gemini 3 Pro (Preview)"
        case "gemini-3-flash-preview": return "Gemini 3 Flash (Preview)"
        case "gemini-2.5-pro": return "Gemini 2.5 Pro"
        case "gemini-2.5-flash": return "Gemini 2.5 Flash"
        default:
            // Fall back to a title-cased version of the raw id, with common
            // suffixes normalised (e.g. "2.5" stays intact, "fast" → "Fast").
            let cleaned = id
                .replacingOccurrences(of: "grok-", with: "")
                .split(separator: "-")
                .map(Self.displayToken)
                .joined(separator: " ")
            return cleaned.isEmpty ? id : cleaned
        }
    }

    private static func displayToken(_ token: Substring) -> String {
        let raw = String(token)
        switch raw.lowercased() {
        case "ai": return "AI"
        case "api": return "API"
        case "cli": return "CLI"
        case "glm": return "GLM"
        case "gpt": return "GPT"
        default:
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    /// Name used in menu lists, marking the default option.
    var menuName: String {
        isDefault ? "\(displayName) (default)" : displayName
    }

    var providerMenuName: String {
        Self.providerScopedName(providerName: providerName, modelName: menuName)
    }

    /// The model-name label. Provider names never belong in a model-name field —
    /// the UI already conveys the provider via its logo and section header — so
    /// this returns the model name alone (never "Provider · Model").
    static func providerScopedName(providerName: String, modelName: String) -> String {
        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "Model" : model
    }

    var reasoningDescriptor: ProviderOptionDescriptor? {
        optionDescriptors.first {
            let key = $0.id.lowercased()
            return key.contains("reasoning") || key.contains("effort") || key.contains("thinking")
        }
    }

    /// True for models that perform multi-step reasoning and honor a reasoning
    /// effort level. Less brittle than an exact id match: any `grok-4*` model or
    /// anything advertising "reasoning" qualifies, as does any id not on the
    /// known-fast list (so newly-released reasoning models default to reasoning).
    var isReasoningModel: Bool {
        if reasoningDescriptor != nil { return true }
        let lower = id.lowercased()
        if lower.contains("grok-4") || lower.contains("reasoning") { return true }
        return !Self.knownFastModelIDs.contains(id)
    }
}

/// A single tool invocation surfaced inside an assistant turn (Codex-style live
/// tool-call visibility). Built from ACP `tool_call` / `tool_call_update`
/// notifications: `tool_call` seeds a running row (id + title); successive
/// `tool_call_update`s refine the title/kind and attach a human-readable
/// `detail`, and the row flips to `.done` when the update carries a result (or
/// the turn ends).
nonisolated struct ToolCallEntry: Identifiable, Hashable {
    /// Lifecycle of a tool row. `.running` until the update clearly completes.
    enum Status: String, Hashable {
        case running
        case done
    }

    /// The ACP `toolCallId` — stable across the seeding `tool_call` and every
    /// `tool_call_update`, so the view model can upsert in place.
    let id: String
    /// Best title to show (refined by later updates, e.g. "Edit <path>").
    var title: String
    /// The update `kind` (e.g. "edit", "execute", "read", "search"); drives the
    /// row icon. Empty until a `tool_call_update` reports it.
    var kind: String
    /// Human-readable expanded detail: for an edit, the newText (and oldText if
    /// present); for execute, the command + output text. Empty until known.
    var detail: String
    /// Running while in flight, done once a result lands / the turn ends.
    var status: Status

    init(
        id: String,
        title: String,
        kind: String = "",
        detail: String = "",
        status: Status = .running
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.detail = detail
        self.status = status
    }
}

nonisolated struct ChatMessage: Identifiable, Hashable {
    enum Role: String, Hashable {
        case user
        case assistant
        case system

        /// Human label shown above the message. Codex shows "You" for the
        /// person and leaves the assistant turn unlabelled; system/tool turns
        /// are surfaced inline.
        var label: String {
            switch self {
            case .user: "You"
            case .assistant: "Grok"
            case .system: "System"
            }
        }
    }

    let id: UUID
    var role: Role
    /// Final answer body (streamed from `text` events).
    var text: String
    /// Reasoning trace (streamed from `thought` events) rendered as a
    /// collapsible "Thinking" block, Codex-style.
    var reasoning: String
    /// True while the assistant turn is actively streaming.
    var isStreaming: Bool
    /// A follow-up the user submitted mid-run; rendered as a pending bubble
    /// and auto-sent when the in-flight run finishes.
    var isQueued: Bool
    /// Surfaced failure text when a run errors out.
    var errorText: String?
    /// Live tool calls grok made during this turn (reads/edits/commands),
    /// surfaced as expandable rows in chat order. Empty for turns with no tools.
    var toolCalls: [ToolCallEntry]
    /// Absolute file paths attached to this user turn, rendered as chips beneath
    /// the bubble (with hover preview / click-to-fullscreen for images). The raw
    /// `[<path>]` tokens are kept out of the visible message text.
    var attachments: [String]

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        reasoning: String = "",
        isStreaming: Bool = false,
        isQueued: Bool = false,
        errorText: String? = nil,
        toolCalls: [ToolCallEntry] = [],
        attachments: [String] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.isStreaming = isStreaming
        self.isQueued = isQueued
        self.errorText = errorText
        self.toolCalls = toolCalls
        self.attachments = attachments
    }

    /// True when nothing has streamed yet and we're still waiting on the model.
    var isAwaitingFirstToken: Bool {
        isStreaming && text.isEmpty && reasoning.isEmpty && errorText == nil
    }
}

enum MainPage: String, CaseIterable, Identifiable, Hashable {
    case home
    case chat
    case search
    case plugins
    case automations
    case settings
    /// Full-page editor for a project's AGENTS.md / GROK.md context file (was a
    /// modal sheet; now a page).
    case projectContext

    var id: String { rawValue }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case newChat
    case search
    case plugins
    case automations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newChat: "New chat"
        case .search: "Search"
        case .plugins: "Plugins"
        case .automations: "Automations"
        }
    }

    var symbol: String {
        switch self {
        case .newChat: "square.and.pencil"
        case .search: "magnifyingglass"
        case .plugins: "puzzlepiece.extension"
        case .automations: "clock.arrow.circlepath"
        }
    }
}
