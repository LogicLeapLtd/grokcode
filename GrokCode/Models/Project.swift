import Foundation

struct Project: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var path: URL
    var threads: [ProjectThread]
    var lastActiveAt: Date?
    var createdAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        threads: [ProjectThread] = [],
        lastActiveAt: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path.standardizedFileURL
        self.threads = threads
        self.lastActiveAt = lastActiveAt
        self.createdAt = createdAt
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

struct ProjectThread: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var ageLabel: String
}

struct GrokSession: Identifiable, Hashable {
    let id: String
    var summary: String
    var created: Date?
    var updated: Date?
    var status: String
}

enum PermissionMode: String, CaseIterable, Identifiable {
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
}

enum EffortLevel: String, CaseIterable, Identifiable {
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

struct GrokModelOption: Identifiable, Hashable {
    let id: String
    var isDefault: Bool

    /// Friendly, human-readable name for the model id.
    var displayName: String {
        switch id {
        case "grok-composer-2.5-fast": return "Composer 2.5 Fast"
        case "grok-composer-2.5": return "Composer 2.5"
        case "grok-build": return "Build"
        case "grok-4": return "Grok 4"
        default:
            // Fall back to a title-cased version of the raw id.
            return id
                .replacingOccurrences(of: "grok-", with: "")
                .split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// Name used in menu lists, marking the default option.
    var menuName: String {
        isDefault ? "\(displayName) (default)" : displayName
    }

    /// True for models that perform multi-step reasoning and honor a reasoning effort level.
    var isReasoningModel: Bool {
        id == "grok-4"
    }
}

struct ChatMessage: Identifiable, Hashable {
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

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        reasoning: String = "",
        isStreaming: Bool = false,
        isQueued: Bool = false,
        errorText: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.isStreaming = isStreaming
        self.isQueued = isQueued
        self.errorText = errorText
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
        case .plugins: "at"
        case .automations: "clock"
        }
    }
}