import Foundation

enum SidebarStatusFilter: String, CaseIterable, Identifiable, Codable {
    case all
    case withChats
    case noChats
    case pinnedOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .withChats: "With chats"
        case .noChats: "No chats"
        case .pinnedOnly: "Pinned only"
        }
    }
}

enum SidebarGroupBy: String, CaseIterable, Identifiable, Codable {
    case project
    case projectBranch
    case rootFolder
    case flatList

    var id: String { rawValue }

    var label: String {
        switch self {
        case .project: "By project"
        case .projectBranch: "By project → branch"
        case .rootFolder: "Recent projects"
        case .flatList: "Chronological list"
        }
    }

    var symbol: String {
        switch self {
        case .project: "square.stack"
        case .projectBranch: "arrow.triangle.branch"
        case .rootFolder: "square.stack"
        case .flatList: "clock"
        }
    }
}

enum SidebarSort: String, CaseIterable, Identifiable, Codable {
    case lastActive
    case nameAZ
    case created

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastActive: "Updated"
        case .nameAZ: "Name A–Z"
        case .created: "Created"
        }
    }

    var symbol: String {
        switch self {
        case .lastActive: "pencil"
        case .nameAZ: "textformat"
        case .created: "plus.bubble"
        }
    }

    /// The two options Codex surfaces in "Sort by".
    static var codexCases: [SidebarSort] { [.created, .lastActive] }
}

struct SidebarProjectGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let projects: [Project]
}

struct SidebarFlatThread: Identifiable, Hashable {
    let id: String
    let title: String
    let ageLabel: String
    let project: Project
    /// True when this row is a subagent spawned by another chat.
    var isSubagent: Bool = false
    /// The subagent's agent type (e.g. "Explore"), when known.
    var agentName: String? = nil
    /// Subagent chats spawned by this row, nested beneath it.
    var subThreads: [SidebarFlatThread] = []
    /// True for the optimistic "New chat" placeholder while a chat is starting.
    var isPending: Bool = false
}