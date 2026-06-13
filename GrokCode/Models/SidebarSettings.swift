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
    case rootFolder
    case flatList

    var id: String { rawValue }

    var label: String {
        switch self {
        case .project: "By project"
        case .rootFolder: "Recent projects"
        case .flatList: "Chronological list"
        }
    }

    var symbol: String {
        switch self {
        case .project: "square.stack"
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
}