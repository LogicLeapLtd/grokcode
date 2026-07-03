import AppKit
import Foundation

// MARK: - Home & Search view-model surface (HomeSearch lane)
//
// All stored state for these surfaces lives on `AppViewModel` (Foundation owns
// that file). This extension only adds *derived* values and *actions* the Home
// and Search views consume — no new stored properties.

/// One row in the Home "recent chats" strip. Carries everything the row needs
/// to render (title, project, branch, relative age) and to open (the owning
/// `ProjectThread` + `Project`, fed to `selectThread(_:in:)`).
struct HomeRecentChat: Identifiable, Hashable {
    let id: String
    let title: String
    let projectName: String
    let branch: String?
    let ageLabel: String
    let thread: ProjectThread
    let project: Project
}

/// One quick-action card under the Home headline.
struct HomeQuickAction: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let page: MainPage
}

extension AppViewModel {
    // MARK: Home — recent chats

    /// The most-recently-active chats across all projects, newest first, for the
    /// Home strip. Derived from each project's indexed threads; projects are
    /// ranked by `lastActiveAt`, and within a project threads keep their indexed
    /// order (already newest-first from `SessionIndexService`).
    func recentHomeChats(limit: Int = 4) -> [HomeRecentChat] {
        let ranked = projects
            .filter { !$0.threads.isEmpty }
            .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }

        var rows: [HomeRecentChat] = []
        for project in ranked {
            for thread in project.threads {
                rows.append(
                    HomeRecentChat(
                        id: thread.id,
                        title: thread.title,
                        projectName: project.name,
                        branch: thread.branch ?? project.gitBranch,
                        ageLabel: thread.ageLabel,
                        thread: thread,
                        project: project
                    )
                )
                if rows.count >= limit { return rows }
            }
        }
        return rows
    }

    /// Open a Home recent-chat row in the chat view.
    func openRecentChat(_ chat: HomeRecentChat) {
        selectThread(chat.thread, in: chat.project)
    }

    // MARK: Home — quick actions

    /// The quick-action cards shown under the headline. "New chat" is handled
    /// specially (it resets the conversation) — see `runQuickAction(_:)`.
    var homeQuickActions: [HomeQuickAction] {
        [
            HomeQuickAction(id: "new", title: "New chat",
                            subtitle: "Start a fresh conversation",
                            systemImage: "square.and.pencil", page: .home),
            HomeQuickAction(id: "plugins", title: "Browse plugins",
                            subtitle: "Add tools & MCP servers",
                            systemImage: "puzzlepiece.extension", page: .plugins),
            HomeQuickAction(id: "search", title: "Search",
                            subtitle: "Find projects & past chats",
                            systemImage: "magnifyingglass", page: .search),
            HomeQuickAction(id: "automations", title: "Automations",
                            subtitle: "Saved prompts & schedules",
                            systemImage: "clock", page: .automations),
        ]
    }

    /// Run a Home quick-action: "New chat" clears the conversation; everything
    /// else navigates to its page.
    func runQuickAction(_ action: HomeQuickAction) {
        if action.id == "new" {
            startNewChat()
        } else {
            navigateTo(action.page)
        }
    }

    // MARK: Home — Grok install guidance (#31)

    /// One-line shell command that installs the Grok CLI. Surfaced (copyable) in
    /// the Home banner when `grokAvailable` is false.
    var grokInstallCommand: String {
        "curl -fsSL https://x.ai/grok-cli/install.sh | sh"
    }

    /// Docs URL for installing / authenticating the Grok CLI.
    var grokDocsURLString: String { "https://docs.x.ai/docs/grok-cli" }

    /// Copy the install command to the pasteboard (Home banner "Copy" action).
    func copyGrokInstallCommand() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(grokInstallCommand, forType: .string)
    }

    /// Open the Grok CLI docs in the default browser (Home banner "Docs" action).
    func openGrokDocs() {
        guard let url = URL(string: grokDocsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Search — keyboard navigation (#32)

    /// Flat, ordered list of the currently-visible search results (Projects then
    /// Sessions, matching the on-screen section order). Backs Up/Down highlight
    /// movement and Return-to-open. Each entry is tagged with its kind so the
    /// view can render the right row and `openSearchResult` can route correctly.
    enum SearchResult: Identifiable, Hashable {
        case project(Project)
        case session(GrokSession)

        var id: String {
            switch self {
            case .project(let p): "project:\(p.id.uuidString)"
            case .session(let s): "session:\(s.id)"
            }
        }
    }

    /// The visible results in render order, honoring the same `.prefix` caps the
    /// view uses, so keyboard index ↔ on-screen row stay in sync.
    func searchResults(projectLimit: Int = 12, sessionLimit: Int = 12) -> [SearchResult] {
        let projectRows = filteredProjects.prefix(projectLimit).map(SearchResult.project)
        let sessionRows = filteredSessions.prefix(sessionLimit).map(SearchResult.session)
        return Array(projectRows) + Array(sessionRows)
    }

    /// Open a highlighted search result (Return / click).
    func openSearchResult(_ result: SearchResult) {
        switch result {
        case .project(let project):
            selectProject(project)
        case .session(let session):
            // Sessions index by their summary across projects; jump into the
            // chat surface, selecting the owning project's thread when we can
            // resolve it, otherwise just open the matching thread by id.
            if let (project, thread) = threadAndProject(forSessionID: session.id) {
                selectThread(thread, in: project)
            } else {
                navigateTo(.chat)
            }
        }
    }

    /// Resolve a session id back to the project + thread that owns it (threads
    /// share the session id), so a Search "Sessions" hit can open the real chat.
    private func threadAndProject(forSessionID id: String) -> (Project, ProjectThread)? {
        for project in projects {
            if let thread = project.threads.first(where: { $0.id == id }) {
                return (project, thread)
            }
        }
        return nil
    }

    /// Best-effort project label for a session row (the project whose thread
    /// carries this id), shown as a subtitle in richer Search rows.
    func projectName(forSessionID id: String) -> String? {
        threadAndProject(forSessionID: id)?.0.name
    }

    /// Relative-age label for a date (Today / Yesterday / Nd / Nw). Public so the
    /// Search session rows can show a date alongside the snippet.
    func searchAgeLabel(for date: Date?) -> String {
        guard let date else { return "" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
    }

    /// Clear the Search query (Esc when the field is empty does nothing extra).
    func clearSearch() {
        searchQuery = ""
    }
}
