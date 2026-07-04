import Foundation

extension AppViewModel {
    var isSplitViewVisible: Bool {
        splitPanes.count > 1
    }

    func openSplitView() {
        syncActiveSplitPaneFromCurrentState()
        let activeID = ensurePrimarySplitPane()
        guard splitPanes.count < maxSplitPaneCount else { return }
        let insertIndex = splitPanes.firstIndex(where: { $0.id == activeID }).map { $0 + 1 } ?? splitPanes.count
        splitPanes.insert(blankSplitPane(), at: min(insertIndex, splitPanes.count))
    }

    func closeSplitView(keeping paneID: UUID? = nil) {
        if let paneID, let pane = splitPanes.first(where: { $0.id == paneID }) {
            applySplitPane(pane)
        } else {
            syncActiveSplitPaneFromCurrentState()
        }
        splitPanes.removeAll()
        activeSplitPaneID = nil
    }

    func closeSplitPane(_ paneID: UUID) {
        guard let index = splitPanes.firstIndex(where: { $0.id == paneID }) else { return }
        guard splitPanes.count > 1 else {
            closeSplitView(keeping: paneID)
            return
        }

        let closingActivePane = activeSplitPaneID == paneID
        splitPanes.remove(at: index)

        if closingActivePane {
            let nextIndex = min(index, splitPanes.count - 1)
            let nextPane = splitPanes[nextIndex]
            applySplitPane(nextPane)
        }
    }

    func focusSplitPane(_ paneID: UUID) {
        guard activeSplitPaneID != paneID,
              let pane = splitPanes.first(where: { $0.id == paneID })
        else { return }

        syncActiveSplitPaneFromCurrentState()
        applySplitPane(pane)
    }

    func syncActiveSplitPaneFromCurrentState() {
        guard !splitPanes.isEmpty else { return }
        let paneID = activeSplitPaneID ?? ensurePrimarySplitPane()
        guard let index = splitPanes.firstIndex(where: { $0.id == paneID }) else { return }

        splitPanes[index].page = activePage
        splitPanes[index].title = currentSplitPaneTitle()
        splitPanes[index].projectPath = selectedProject?.path.standardizedFileURL.path
        splitPanes[index].projectName = selectedProject?.name
        splitPanes[index].projectBranch = selectedProject?.gitBranch
        splitPanes[index].sessionId = activeSessionId
        splitPanes[index].messages = messages
        splitPanes[index].isNoProject = workWithoutProject && selectedProject == nil
        splitPanes[index].isLoading = false
    }

    func openThreadInNewSplitPane(_ thread: ProjectThread, project: Project?) {
        syncActiveSplitPaneFromCurrentState()
        ensurePrimarySplitPane()
        guard splitPanes.count < maxSplitPaneCount else { return }

        let pane = SplitPane(
            page: .chat,
            title: thread.title,
            projectPath: project?.path.standardizedFileURL.path,
            projectName: project?.name,
            projectBranch: project?.gitBranch,
            sessionId: thread.id,
            isNoProject: project == nil,
            isLoading: true
        )
        splitPanes.append(pane)
        applySplitPane(pane)
    }

    func openDroppedThreadPayload(_ payload: SplitPaneDragPayload.ThreadPayload, in paneID: UUID) {
        guard splitPanes.contains(where: { $0.id == paneID }) else { return }
        if payload.isNoProject {
            let thread = noProjectThreads.first(where: { $0.id == payload.sessionId })
                ?? ProjectThread(id: payload.sessionId, title: payload.title, ageLabel: "")
            openThread(thread, project: nil, in: paneID)
            return
        }

        guard let projectPath = payload.projectPath,
              let project = projects.first(where: { $0.path.standardizedFileURL.path == projectPath })
        else { return }
        let thread = project.threads.first(where: { $0.id == payload.sessionId })
            ?? ProjectThread(id: payload.sessionId, title: payload.title, ageLabel: "")
        openThread(thread, project: project, in: paneID)
    }

    func handleSplitPaneDropPayload(_ payload: String, targetPaneID: UUID) -> Bool {
        if let draggedPaneID = SplitPaneDragPayload.paneID(from: payload) {
            moveSplitPane(draggedPaneID, before: targetPaneID)
            return true
        }

        if let threadPayload = SplitPaneDragPayload.threadPayload(from: payload) {
            openDroppedThreadPayload(threadPayload, in: targetPaneID)
            return true
        }

        return false
    }

    func dragPayload(for thread: ProjectThread, in project: Project?) -> String {
        SplitPaneDragPayload.thread(thread, project: project)
    }

    func splitPaneDragPayload(_ paneID: UUID) -> String {
        SplitPaneDragPayload.pane(paneID)
    }

    func splitPanePosition(for paneID: UUID) -> SplitPanePosition? {
        guard let index = splitPanes.firstIndex(where: { $0.id == paneID }) else { return nil }
        let column = index / 2
        let row = index % 2
        let columnCount = Int(ceil(Double(splitPanes.count) / 2.0))
        let rowsInColumn = min(2, splitPanes.count - column * 2)
        return SplitPanePosition(
            index: index,
            column: column,
            row: row,
            columnCount: columnCount,
            rowsInColumn: rowsInColumn
        )
    }

    func canMoveSplitPane(_ paneID: UUID, _ move: SplitPaneMove) -> Bool {
        guard let position = splitPanePosition(for: paneID) else { return false }
        switch move {
        case .topLeft:
            return position.index > 0
        case .up:
            return position.row > 0
        case .down:
            return position.row == 0 && position.rowsInColumn > 1
        case .left:
            return position.column > 0 && position.index - 2 >= 0
        case .right:
            return position.column < position.columnCount - 1 && position.index + 2 < splitPanes.count
        case .newColumn:
            let remainingPaneCount = splitPanes.count - 1
            return splitPanes.count > 2
                && position.index < splitPanes.count - 1
                && remainingPaneCount.isMultiple(of: 2)
        }
    }

    func moveSplitPane(_ paneID: UUID, _ move: SplitPaneMove) {
        guard canMoveSplitPane(paneID, move),
              let index = splitPanes.firstIndex(where: { $0.id == paneID })
        else { return }

        switch move {
        case .topLeft:
            let pane = splitPanes.remove(at: index)
            splitPanes.insert(pane, at: 0)
        case .up:
            splitPanes.swapAt(index, index - 1)
        case .down:
            splitPanes.swapAt(index, index + 1)
        case .left:
            splitPanes.swapAt(index, index - 2)
        case .right:
            splitPanes.swapAt(index, index + 2)
        case .newColumn:
            let pane = splitPanes.remove(at: index)
            splitPanes.append(pane)
        }
    }

    func moveSplitPane(_ draggedPaneID: UUID, before targetPaneID: UUID) {
        guard draggedPaneID != targetPaneID,
              let sourceIndex = splitPanes.firstIndex(where: { $0.id == draggedPaneID }),
              let targetIndex = splitPanes.firstIndex(where: { $0.id == targetPaneID })
        else { return }

        let pane = splitPanes.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        splitPanes.insert(pane, at: adjustedTarget)
    }

    private func openThread(_ thread: ProjectThread, project: Project?, in paneID: UUID) {
        if paneID == activeSplitPaneID {
            if let project {
                selectThread(thread, in: project)
            } else {
                selectNoProjectThread(thread)
            }
            return
        }

        guard let index = splitPanes.firstIndex(where: { $0.id == paneID }) else { return }
        splitPanes[index].page = .chat
        splitPanes[index].title = thread.title
        splitPanes[index].projectPath = project?.path.standardizedFileURL.path
        splitPanes[index].projectName = project?.name
        splitPanes[index].projectBranch = project?.gitBranch
        splitPanes[index].sessionId = thread.id
        splitPanes[index].messages = []
        splitPanes[index].isNoProject = project == nil
        splitPanes[index].isLoading = true
        loadMessagesAsync(for: thread.id, intoSplitPane: paneID)
    }

    @discardableResult
    private func ensurePrimarySplitPane() -> UUID {
        if let activeSplitPaneID, splitPanes.contains(where: { $0.id == activeSplitPaneID }) {
            return activeSplitPaneID
        }

        if splitPanes.isEmpty {
            let pane = currentSplitPaneSnapshot()
            splitPanes = [pane]
            activeSplitPaneID = pane.id
            return pane.id
        }

        let firstID = splitPanes[0].id
        activeSplitPaneID = firstID
        return firstID
    }

    private func applySplitPane(_ pane: SplitPane) {
        activeSplitPaneID = pane.id

        if pane.isNoProject {
            selectedProject = nil
            workWithoutProject = true
        } else if let projectPath = pane.projectPath,
                  let project = projects.first(where: { $0.path.standardizedFileURL.path == projectPath }) {
            selectedProject = project
            workWithoutProject = false
        }

        activeSessionId = pane.sessionId
        messages = pane.messages
        errorMessage = nil

        isApplyingSplitPaneFocus = true
        navigateTo(pane.page)
        isApplyingSplitPaneFocus = false

        syncActiveSplitPaneFromCurrentState()

        if pane.page == .chat, let sessionId = pane.sessionId, messages.isEmpty {
            loadMessagesAsync(for: sessionId)
        }
    }

    private func currentSplitPaneSnapshot() -> SplitPane {
        SplitPane(
            page: activePage,
            title: currentSplitPaneTitle(),
            projectPath: selectedProject?.path.standardizedFileURL.path,
            projectName: selectedProject?.name,
            projectBranch: selectedProject?.gitBranch,
            sessionId: activeSessionId,
            messages: messages,
            isNoProject: workWithoutProject && selectedProject == nil
        )
    }

    private func blankSplitPane() -> SplitPane {
        SplitPane(
            page: .home,
            title: "New chat",
            projectPath: selectedProject?.path.standardizedFileURL.path,
            projectName: selectedProject?.name,
            projectBranch: selectedProject?.gitBranch,
            isNoProject: workWithoutProject && selectedProject == nil
        )
    }

    private func currentSplitPaneTitle() -> String {
        if activePage == .chat,
           let firstUser = messages.first(where: { $0.role == .user })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !firstUser.isEmpty {
            return String(firstUser.prefix(72))
        }
        if activePage == .home { return "New chat" }
        return activePage.label
    }
}
