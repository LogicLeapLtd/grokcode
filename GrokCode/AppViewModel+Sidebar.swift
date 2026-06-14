import AppKit
import Foundation

/// Sidebar-lane behaviour layered onto `AppViewModel`. Stored properties live in
/// `AppViewModel.swift` (Foundation lane); this extension only adds methods and
/// derived values the sidebar UI needs — chat rename/delete, the resize-handle
/// width writer, branch sub-grouping (#25), and small helpers for the chat-row
/// context menu (#27) and the capitalised relative ages (#29).
extension AppViewModel {

    // MARK: - Resize handle (#22)

    /// Apply a new sidebar width from the trailing drag handle. The stored
    /// property's `didSet` clamps to `220...420` and persists, so callers can
    /// pass a raw drag value; we round to a whole point to avoid sub-pixel
    /// churn while dragging.
    func setSidebarWidth(_ width: Double) {
        sidebarWidth = (width).rounded()
    }

    /// Convenience used by the drag gesture: translate a starting width plus the
    /// horizontal drag distance into a clamped width.
    func resizeSidebar(from startWidth: Double, by deltaX: Double) {
        setSidebarWidth(startWidth + deltaX)
    }

    // MARK: - Collapse (#23)

    /// Width of the collapsed icon rail. Kept here (not in CodexTheme, which the
    /// Theme lane owns) so the sidebar can size its rail consistently.
    var collapsedSidebarWidth: Double { 56 }

    /// Effective sidebar width accounting for the collapsed rail (#22/#23).
    var effectiveSidebarWidth: Double {
        sidebarCollapsed ? collapsedSidebarWidth : sidebarWidth
    }

    // MARK: - New chat (#28)

    /// The visible "New chat" affordance at the top of the chat list. Mirrors the
    /// nav row but lives above the project/thread list. Routes through the same
    /// reset as the nav "New chat" so behaviour stays identical.
    func startNewChatFromList() {
        startNewChat()
    }

    // MARK: - Chat rename / delete (#27)

    /// Rename a thread in-memory. Updates the thread inside its project (and the
    /// mirrored `selectedProject`) so the new title shows immediately. Persistence
    /// is intentionally in-memory only: titles are otherwise derived from grok's
    /// session summary on the next index refresh.
    func renameThread(_ thread: ProjectThread, to newTitle: String, in project: Project) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateThread(id: thread.id, in: project) { $0.title = trimmed }
    }

    /// Remove a thread from its project's list (in-memory). If the deleted thread
    /// was the active conversation, clear the chat back to a fresh state.
    func deleteThread(_ thread: ProjectThread, in project: Project) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[pIndex].threads.removeAll { $0.id == thread.id }
        if selectedProject?.id == project.id {
            selectedProject = projects[pIndex]
        }
        if activeSessionId == thread.id {
            startNewChat()
        }
    }

    /// Copy a chat's title to the clipboard (#27 "Copy").
    func copyThreadTitle(_ thread: ProjectThread) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(thread.title, forType: .string)
    }

    private func mutateThread(id: String, in project: Project, _ transform: (inout ProjectThread) -> Void) {
        guard let pIndex = projects.firstIndex(where: { $0.id == project.id }),
              let tIndex = projects[pIndex].threads.firstIndex(where: { $0.id == id }) else { return }
        transform(&projects[pIndex].threads[tIndex])
        if selectedProject?.id == project.id {
            selectedProject = projects[pIndex]
        }
    }

    // MARK: - Branch sub-grouping (#25)

    /// Group a project's threads by their `branch` for the "By project → branch"
    /// sidebar mode. Threads without a recorded branch fall back to the project's
    /// current git branch (if any) and are otherwise bucketed under a `nil`
    /// header. Order: the project's current branch first, then the rest A→Z, with
    /// the unknown bucket last.
    func branchGroups(for project: Project) -> [SidebarBranchGroup] {
        let current = project.gitBranch
        let grouped = Dictionary(grouping: project.threads) { thread in
            thread.branch ?? current
        }

        let namedKeys = grouped.keys.compactMap { $0 }.sorted { lhs, rhs in
            if lhs == current { return true }
            if rhs == current { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        var groups: [SidebarBranchGroup] = namedKeys.map { key in
            SidebarBranchGroup(id: key, branch: key, threads: grouped[key] ?? [])
        }
        if let unknown = grouped[nil], !unknown.isEmpty {
            groups.append(SidebarBranchGroup(id: "∅", branch: nil, threads: unknown))
        }
        return groups
    }
}

/// One branch bucket within a project, for the "By project → branch" grouping
/// (#25). `branch == nil` means the chats whose branch couldn't be determined.
struct SidebarBranchGroup: Identifiable, Hashable {
    let id: String
    let branch: String?
    let threads: [ProjectThread]
}
