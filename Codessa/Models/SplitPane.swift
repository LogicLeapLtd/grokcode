import Foundation

struct SplitPane: Identifiable, Hashable {
    let id: UUID
    var page: MainPage
    var title: String
    var projectPath: String?
    var projectName: String?
    var projectBranch: String?
    var sessionId: String?
    var messages: [ChatMessage]
    var isNoProject: Bool
    var isLoading: Bool

    init(
        id: UUID = UUID(),
        page: MainPage,
        title: String,
        projectPath: String? = nil,
        projectName: String? = nil,
        projectBranch: String? = nil,
        sessionId: String? = nil,
        messages: [ChatMessage] = [],
        isNoProject: Bool = false,
        isLoading: Bool = false
    ) {
        self.id = id
        self.page = page
        self.title = title
        self.projectPath = projectPath
        self.projectName = projectName
        self.projectBranch = projectBranch
        self.sessionId = sessionId
        self.messages = messages
        self.isNoProject = isNoProject
        self.isLoading = isLoading
    }

    var subtitle: String {
        if isNoProject { return "No project" }
        if let projectBranch, !projectBranch.isEmpty, let projectName {
            return "\(projectName) · \(projectBranch)"
        }
        return projectName ?? page.label
    }
}

enum SplitPaneMove {
    case topLeft
    case up
    case down
    case left
    case right
    case newColumn
}

struct SplitPanePosition: Hashable {
    let index: Int
    let column: Int
    let row: Int
    let columnCount: Int
    let rowsInColumn: Int
}

enum SplitPaneDragPayload {
    private static let panePrefix = "codessa.split-pane:"
    private static let threadPrefix = "codessa.thread:"

    struct ThreadPayload: Codable, Hashable {
        let sessionId: String
        let title: String
        let projectPath: String?
        let isNoProject: Bool
    }

    static func pane(_ id: UUID) -> String {
        panePrefix + id.uuidString
    }

    static func thread(_ thread: ProjectThread, project: Project?) -> String {
        let payload = ThreadPayload(
            sessionId: thread.id,
            title: thread.title,
            projectPath: project?.path.standardizedFileURL.path,
            isNoProject: project == nil
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            return threadPrefix
        }
        return threadPrefix + data.base64EncodedString()
    }

    static func paneID(from string: String) -> UUID? {
        guard string.hasPrefix(panePrefix) else { return nil }
        return UUID(uuidString: String(string.dropFirst(panePrefix.count)))
    }

    static func threadPayload(from string: String) -> ThreadPayload? {
        guard string.hasPrefix(threadPrefix) else { return nil }
        let encoded = String(string.dropFirst(threadPrefix.count))
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(ThreadPayload.self, from: data)
    }
}

extension MainPage {
    var label: String {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .search: "Search"
        case .plugins: "Plugins"
        case .automations: "Automations"
        case .settings: "Settings"
        case .projectContext: "Project context"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .chat: "bubble.left.and.bubble.right"
        case .search: "text.magnifyingglass"
        case .plugins: "shippingbox"
        case .automations: "clock.arrow.circlepath"
        case .settings: "gearshape"
        case .projectContext: "doc.text"
        }
    }
}
