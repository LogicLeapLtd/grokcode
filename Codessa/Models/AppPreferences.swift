import Foundation

enum SettingsPreferenceScope {
    case all
    case general
    case appearance
    case personalization
    case shortcuts
    case mcp
    case hooks
    case cli
    case data
    case archive
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

struct AppPreferences: Codable, Equatable {
    enum LaunchPage: String, CaseIterable, Identifiable, Codable {
        case restoreLast
        case home
        case search
        case plugins
        case automations
        case settings

        var id: String { rawValue }

        var label: String {
            switch self {
            case .restoreLast: "Restore last page"
            case .home: "Home"
            case .search: "Search"
            case .plugins: "Plugins"
            case .automations: "Automations"
            case .settings: "Settings"
            }
        }
    }

    enum Accent: String, CaseIterable, Identifiable, Codable {
        case purple
        case blue
        case green
        case orange
        case pink

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum Density: String, CaseIterable, Identifiable, Codable {
        case comfortable
        case compact
        case dense

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum BubbleStyle: String, CaseIterable, Identifiable, Codable {
        case modern
        case compact
        case transcript

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ToolCallStyle: String, CaseIterable, Identifiable, Codable {
        case expanded
        case compact
        case hiddenWhenDone

        var id: String { rawValue }

        var label: String {
            switch self {
            case .expanded: "Expanded"
            case .compact: "Compact"
            case .hiddenWhenDone: "Hide when done"
            }
        }
    }

    enum ContextFilePolicy: String, CaseIterable, Identifiable, Codable {
        case preferAgents
        case preferGrok
        case existingOnly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .preferAgents: "Prefer AGENTS.md"
            case .preferGrok: "Prefer GROK.md"
            case .existingOnly: "Existing file only"
            }
        }
    }

    enum LanguagePreference: String, CaseIterable, Identifiable, Codable {
        case system
        case britishEnglish
        case americanEnglish

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: "System"
            case .britishEnglish: "British English"
            case .americanEnglish: "American English"
            }
        }
    }

    enum ResponseLength: String, CaseIterable, Identifiable, Codable {
        case concise
        case balanced
        case detailed

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ExplanationDepth: String, CaseIterable, Identifiable, Codable {
        case direct
        case normal
        case teach

        var id: String { rawValue }

        var label: String {
            switch self {
            case .direct: "Direct"
            case .normal: "Normal"
            case .teach: "Teach me"
            }
        }
    }

    enum TonePreset: String, CaseIterable, Identifiable, Codable {
        case plain
        case warm
        case senior
        case terse

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ShortcutPreset: String, CaseIterable, Identifiable, Codable {
        case codessa
        case vscode
        case jetbrains

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ServerFilter: String, CaseIterable, Identifiable, Codable {
        case all
        case enabled
        case disabled

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ServerSort: String, CaseIterable, Identifiable, Codable {
        case name
        case status
        case detail

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum HookFilter: String, CaseIterable, Identifiable, Codable {
        case all
        case pending
        case trusted

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ArchiveSort: String, CaseIterable, Identifiable, Codable {
        case name
        case chats
        case path

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum ArchiveFilter: String, CaseIterable, Identifiable, Codable {
        case all
        case hasChats
        case empty

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All"
            case .hasChats: "With chats"
            case .empty: "Empty"
            }
        }
    }

    enum AttachmentBehavior: String, CaseIterable, Identifiable, Codable {
        case keep
        case clearAfterSend
        case ask

        var id: String { rawValue }

        var label: String {
            switch self {
            case .keep: "Keep"
            case .clearAfterSend: "Clear after send"
            case .ask: "Ask"
            }
        }
    }

    enum NewChatLocation: String, CaseIterable, Identifiable, Codable {
        case selectedProject
        case defaultProject
        case noProject

        var id: String { rawValue }

        var label: String {
            switch self {
            case .selectedProject: "Selected project"
            case .defaultProject: "Default project"
            case .noProject: "No project"
            }
        }
    }

    var launchPage: LaunchPage = .restoreLast
    var restoreLastPage = true
    var openSplitViewOnLaunch = false
    var showLaunchMascot = true
    var allowFollowupQueue = true
    var defaultPursueGoal = false
    var defaultPlanMode = false
    var keepComposerDraft = false
    var clearComposerAfterSend = true
    var confirmStopRunning = false
    var confirmDestructiveActions = true
    var defaultAttachmentBehavior: AttachmentBehavior = .clearAfterSend
    var defaultNewChatLocation: NewChatLocation = .selectedProject

    var accent: Accent = .purple
    var highContrast = false
    var vibrancyEnabled = true
    var ambientBackgroundEnabled = true
    var reduceMotion = false
    var animationSpeed = 1.0
    var uiFontSize = 13.0
    var chatFontSize = 14.0
    var codeFontSize = 12.0
    var messageDensity: Density = .comfortable
    var bubbleStyle: BubbleStyle = .modern
    var showTimestamps = false
    var toolCallStyle: ToolCallStyle = .expanded
    var wrapCode = true
    var showCodeLineNumbers = false

    var contextFilePolicy: ContextFilePolicy = .preferAgents
    var contextEnabled = true
    var languagePreference: LanguagePreference = .system
    var responseLength: ResponseLength = .balanced
    var explanationDepth: ExplanationDepth = .normal
    var tonePreset: TonePreset = .warm
    var preferBritishEnglish = true
    var avoidEmDashes = true
    var preserveUserWording = true
    var draftOnlyMessaging = true
    var showPlansByDefault = true
    var askBeforeAssumptions = false
    var includeProjectRules = true
    var includeStyleRules = true

    var shortcutPreset: ShortcutPreset = .codessa
    var shortcutsEnabled = true
    var shortcutSearch = ""
    var customShortcuts: [String: String] = [:]

    var mcpSearch = ""
    var mcpFilter: ServerFilter = .all
    var mcpSort: ServerSort = .name
    var mcpShowDetails = true
    var mcpShowEnvKeys = true
    var mcpRequireWriteConfirmation = true

    var hookSearch = ""
    var hookFilter: HookFilter = .all
    var hookCompactView = false
    var hookShowCommandPreview = true
    var hookRequireTrustAllConfirmation = true

    var grokBinaryOverride = ""
    var forceOneShotMode = false
    var inactivityTimeoutSeconds = 180.0
    var defaultSessionLimit = 30
    var copyDiagnosticsIncludesSettings = true

    var retentionDays = 90.0
    var autoCleanOnLaunch = false
    var exportBeforeDelete = true
    var includeSettingsInDiagnostics = true
    var includeSystemInfoInDiagnostics = true

    var archiveSearch = ""
    var archiveSort: ArchiveSort = .name
    var archiveFilter: ArchiveFilter = .all
    var keepPinnedUnarchived = true
    var autoArchiveInactiveProjects = false
    var archiveInactiveDays = 60.0

    static let defaults = AppPreferences()
}
