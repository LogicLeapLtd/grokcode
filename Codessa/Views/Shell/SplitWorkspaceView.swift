import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SplitWorkspaceView: View {
    @Environment(AppViewModel.self) private var model

    private let paneGap: CGFloat = 8
    private let outerPadding: CGFloat = 8
    private let minimumColumnWidth: CGFloat = 460

    var body: some View {
        GeometryReader { geometry in
            let columns = paneColumns(model.splitPanes)
            let visibleColumnCount = visibleColumns(for: geometry.size.width, total: columns.count)
            let columnWidth = width(for: geometry.size.width, visibleColumns: visibleColumnCount)
            let availableHeight = max(0, geometry.size.height - outerPadding * 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: paneGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: paneGap) {
                            ForEach(column) { pane in
                                SplitPaneCard(
                                    pane: pane,
                                    position: model.splitPanePosition(for: pane.id),
                                    height: height(forRows: column.count, availableHeight: availableHeight)
                                )
                            }
                        }
                        .frame(width: columnWidth, height: availableHeight, alignment: .top)
                    }
                }
                .padding(outerPadding)
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func paneColumns(_ panes: [SplitPane]) -> [[SplitPane]] {
        stride(from: 0, to: panes.count, by: 2).map { start in
            Array(panes[start..<min(start + 2, panes.count)])
        }
    }

    private func visibleColumns(for width: CGFloat, total: Int) -> Int {
        guard total > 0 else { return 1 }
        let usable = max(1, width - outerPadding * 2)
        let count = Int((usable + paneGap) / (minimumColumnWidth + paneGap))
        return max(1, min(total, count))
    }

    private func width(for totalWidth: CGFloat, visibleColumns: Int) -> CGFloat {
        let usable = max(1, totalWidth - outerPadding * 2)
        let gaps = paneGap * CGFloat(max(visibleColumns - 1, 0))
        return max(minimumColumnWidth, (usable - gaps) / CGFloat(max(visibleColumns, 1)))
    }

    private func height(forRows rows: Int, availableHeight: CGFloat) -> CGFloat {
        rows > 1 ? max(260, (availableHeight - paneGap) / 2) : availableHeight
    }
}

private struct SplitPaneCard: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    let pane: SplitPane
    let position: SplitPanePosition?
    let height: CGFloat

    @State private var isDropTargeted = false

    private var isActive: Bool {
        model.activeSplitPaneID == pane.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(CodexTheme.divider.opacity(isActive ? 0.95 : 0.58))
                .frame(height: 1)

            paneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CodexTheme.mainBackground.opacity(isActive ? 0.72 : 0.50))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted
                        ? CodexTheme.focusAccent.opacity(0.95)
                        : (isActive ? CodexTheme.focusAccent.opacity(0.58) : CodexTheme.composerBorder.opacity(0.52)),
                    lineWidth: isDropTargeted || isActive ? 1.25 : 1
                )
        )
        .shadow(color: CodexTheme.shadowColor.opacity(isActive ? 0.26 : 0.14), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { model.focusSplitPane(pane.id) }
        .onDrop(of: [UTType.text], isTargeted: $isDropTargeted) { providers in
            performDrop(providers)
        }
        .animation(CodexMotion.quickSpring, value: isActive)
        .animation(CodexMotion.quickSpring, value: isDropTargeted)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: pane.page.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? CodexTheme.focusAccent : CodexTheme.textTertiary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(isActive ? activeTitle : pane.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(isActive ? activeSubtitle : pane.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            paneMenu
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .padding(.vertical, 8)
        .background(isActive ? CodexTheme.navHighlight.opacity(0.55) : Color.clear)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: model.splitPaneDragPayload(pane.id) as NSString) }
    }

    private var paneMenu: some View {
        CodexMenuTrigger(minWidth: 250, edge: .bottom, highlightOnHover: false) { isOpen in
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOpen ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                .frame(width: 26, height: 24)
                .codexHover(cornerRadius: 7)
                .contentShape(Rectangle())
        } menu: { close in
            CodexMenuContainer {
                CodexMenuItem(title: "Open in new window", systemImage: "macwindow") {
                    model.focusSplitPane(pane.id)
                    openWindow(id: "chat-popout")
                    close()
                }

                CodexMenuDivider()

                if model.canMoveSplitPane(pane.id, .topLeft) {
                    CodexMenuItem(title: "Move pane to top left", systemImage: "arrow.up.left") {
                        model.moveSplitPane(pane.id, .topLeft)
                        close()
                    }
                }
                if model.canMoveSplitPane(pane.id, .left) {
                    CodexMenuItem(title: "Move pane left", systemImage: "arrow.left") {
                        model.moveSplitPane(pane.id, .left)
                        close()
                    }
                }
                if model.canMoveSplitPane(pane.id, .right) {
                    CodexMenuItem(title: "Move pane right", systemImage: "arrow.right") {
                        model.moveSplitPane(pane.id, .right)
                        close()
                    }
                }
                if model.canMoveSplitPane(pane.id, .up) {
                    CodexMenuItem(title: "Move pane up", systemImage: "arrow.up") {
                        model.moveSplitPane(pane.id, .up)
                        close()
                    }
                }
                if model.canMoveSplitPane(pane.id, .down) {
                    CodexMenuItem(title: "Move pane down", systemImage: "arrow.down") {
                        model.moveSplitPane(pane.id, .down)
                        close()
                    }
                }
                if model.canMoveSplitPane(pane.id, .newColumn) {
                    CodexMenuItem(title: "Move pane to new column", systemImage: "rectangle.split.3x1") {
                        model.moveSplitPane(pane.id, .newColumn)
                        close()
                    }
                }

                CodexMenuDivider()

                if model.splitPanes.count > 1 {
                    CodexMenuItem(title: "Close pane", systemImage: "xmark.rectangle") {
                        model.closeSplitPane(pane.id)
                        close()
                    }
                    CodexMenuItem(title: "Close split view", systemImage: "rectangle") {
                        model.closeSplitView(keeping: pane.id)
                        close()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        if isActive {
            activeContent
        } else {
            inactiveContent
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch model.activePage {
        case .home:
            HomeView()
        case .chat:
            ChatView(showHeader: false, horizontalPadding: 24, verticalPadding: 20, transcriptMaxWidth: 680)
        case .search:
            SearchPageView()
        case .plugins:
            PluginsView()
        case .automations:
            AutomationsView()
        case .settings:
            SettingsView()
        case .projectContext:
            ProjectContextEditor()
        }
    }

    @ViewBuilder
    private var inactiveContent: some View {
        if pane.page == .chat {
            ChatTranscriptSnapshotView(
                messages: pane.messages,
                isLoading: pane.isLoading,
                emptyTitle: "Drop a chat here",
                horizontalPadding: 24,
                verticalPadding: 20,
                transcriptMaxWidth: 680
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: pane.page.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(CodexTheme.textTertiary)
                Text(pane.title)
                    .font(CodexTheme.bodyFont)
                    .foregroundStyle(CodexTheme.textSecondary)
                Text("Click to activate")
                    .font(CodexTheme.captionFont)
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var activeTitle: String {
        if model.activePage == .chat,
           let firstUser = model.messages.first(where: { $0.role == .user })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !firstUser.isEmpty {
            return String(firstUser.prefix(72))
        }
        return model.activePage == .home ? "New chat" : model.activePage.label
    }

    private var activeSubtitle: String {
        if model.workWithoutProject && model.selectedProject == nil { return "No project" }
        if let project = model.selectedProject {
            if let branch = project.gitBranch, !branch.isEmpty {
                return "\(project.name) · \(branch)"
            }
            return project.name
        }
        return model.activePage.label
    }

    private func performDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let string: String?
            if let data = item as? Data {
                string = String(data: data, encoding: .utf8)
            } else if let value = item as? String {
                string = value
            } else if let value = item as? NSString {
                string = value as String
            } else {
                string = nil
            }

            guard let string else { return }
            Task { @MainActor in
                _ = model.handleSplitPaneDropPayload(string, targetPaneID: pane.id)
            }
        }

        return true
    }
}
