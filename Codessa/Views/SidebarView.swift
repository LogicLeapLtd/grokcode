import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var model
    var limitedMode = false
    var forceCollapsed = false

    /// Transient, view-local chat state. There is no Foundation-backed store for
    /// per-chat pin/archive, so these live with the view (reset on relaunch).
    @State private var pinnedThreadIDs: Set<String> = []
    @State private var archivedThreadIDs: Set<String> = []
    /// Inline-rename state (#27): the row being edited and its draft text.
    @State private var renamingThreadID: String?
    @State private var renameDraft: String = ""
    /// Live drag width so the resize feels immediate (committed to the model).
    @State private var dragStartWidth: Double?
    /// Which collapsed-rail item is hovered, keyed by its label — drives the
    /// custom slide-in tooltip that replaces the slow system `.help()` bubble.
    @State private var hoveredRailItem: String?
    @State private var sidebarScrollOffset: CGFloat = 0
    @State private var sidebarScrollContentHeight: CGFloat = 0

    var body: some View {
        Group {
            if usesCollapsedLayout {
                // Pin each branch to its natural width so the content never
                // reflows/truncates as the outer frame animates between widths;
                // the outer `.clipped()` simply reveals/hides it, which keeps the
                // crossfade smooth instead of churning the layout every frame.
                collapsedRail
                    .frame(width: currentSidebarWidth, alignment: .leading)
                    .transition(.opacity)
            } else {
                expandedBody
                    .frame(width: currentSidebarWidth, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(width: currentSidebarWidth, alignment: .leading)
        .clipped()
        .background {
            // Translucent "liquid glass" sidebar that samples the desktop behind
            // the (non-opaque) window — see WindowConfigurator on ContentView.
            // Mostly the behind-window vibrancy (Liquid Glass on Tahoe) so the
            // sidebar reads as genuinely semi-transparent; only the faintest tint
            // for text legibility.
            VisualEffectView(material: .sidebar)
                .overlay(CodexTheme.glassTint)
                .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            if !usesCollapsedLayout { resizeHandle }
        }
        .animation(CodexMotion.sidebarCollapse, value: usesCollapsedLayout)
        // Animate width changes ONLY when they aren't from the live drag (e.g.
        // restoring a saved width). During an active drag the width tracks the
        // cursor 1:1 with no implicit spring, which removes the stutter.
        .animation(model.isResizingSidebar ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.92),
                   value: model.sidebarWidth)
        .onChange(of: model.sidebarStatusFilter) { _, _ in model.persistSidebarPreferences() }
        .onChange(of: model.sidebarGroupBy) { _, _ in model.persistSidebarPreferences() }
        .onChange(of: model.sidebarSort) { _, _ in model.persistSidebarPreferences() }
    }

    private var usesCollapsedLayout: Bool {
        forceCollapsed || model.sidebarCollapsed
    }

    private var currentSidebarWidth: Double {
        usesCollapsedLayout ? model.collapsedSidebarWidth : model.sidebarWidth
    }

    // MARK: - Expanded sidebar

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 2)

            navSection
                .padding(.bottom, 14)

            projectsSection

            Spacer(minLength: 0)

            settingsButton
                .padding(.top, 8)
        }
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    /// Slim top strip that just clears the macOS traffic-light controls, so the
    /// first nav row ("New chat") sits right beneath them. The collapse toggle
    /// now lives on the "New chat" row (see `navSection`).
    private var header: some View {
        Color.clear
            .frame(height: 12)
            // The strip overlaps the title-bar drag region; mark it draggable-safe
            // so a press here doesn't fight the window drag.
            .background(NonDraggableRegion())
    }

    private var collapseToggle: some View {
        Button { model.toggleSidebarCollapsed() } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 28, height: 26)
                .codexHover(cornerRadius: 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
    }

    private var navSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SidebarSection.allCases) { section in
                if section == .newChat {
                    // The collapse toggle rides on the trailing edge of the
                    // "New chat" row so it lines up with it, instead of floating
                    // alone in the title-bar strip above.
                    ZStack(alignment: .trailing) {
                        navRow(section)
                        collapseToggle
                            .padding(.trailing, 4)
                    }
                } else {
                    navRow(section)
                }
            }
        }
    }

    private func navRow(_ section: SidebarSection) -> some View {
        let locked = isLimited(section)
        let active = isPrimaryNavActive(section)

        return Button {
            guard !locked else { return }
            handleNav(section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .frame(width: 16)
                Text(section.title)
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? CodexTheme.navHighlight : Color.clear)
            )
            .shortcutHint(shortcutKeys(for: section),
                          alignment: .trailing,
                          x: section == .newChat ? -40 : -8,
                          enabled: !locked)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover()
        .opacity(locked ? 0.5 : 1)
        .help(locked ? "\(section.title) requires the full app" : section.title)
        .animation(CodexMotion.quickSpring, value: active)
        .animation(CodexMotion.quickSpring, value: locked)
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarControlsBar()

            GeometryReader { viewport in
                ZStack(alignment: .trailing) {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            if model.sidebarGroupBy == .flatList {
                                flatThreadList
                            } else {
                                groupedProjectList
                            }
                        }
                        .padding(.top, 2)
                        .padding(.trailing, 2)
                        .background(
                            GeometryReader { content in
                                Color.clear
                                    .preference(key: SidebarScrollOffsetKey.self,
                                                value: content.frame(in: .named(SidebarScrollSpace)).minY)
                                    .preference(key: SidebarScrollContentHeightKey.self,
                                                value: content.size.height)
                            }
                        )
                        .animation(CodexMotion.expandSpring, value: model.sidebarProjectGroups.count)
                        .animation(CodexMotion.expandSpring, value: model.projectsCollapsed)
                        .animation(CodexMotion.expandSpring, value: model.collapsedProjectPaths)
                    }
                    .scrollIndicators(.hidden)
                    .background(SidebarScrollViewConfigurator())

                    VisualEffectView(material: .sidebar)
                        .overlay(CodexTheme.glassTint)
                        .frame(width: 12)
                        .allowsHitTesting(false)

                    SidebarSlimScrollbar(
                        offset: sidebarScrollOffset,
                        contentHeight: sidebarScrollContentHeight,
                        viewportHeight: viewport.size.height
                    )
                    .padding(.trailing, 5)
                }
                .coordinateSpace(name: SidebarScrollSpace)
                .onPreferenceChange(SidebarScrollOffsetKey.self) { sidebarScrollOffset = $0 }
                .onPreferenceChange(SidebarScrollContentHeightKey.self) { sidebarScrollContentHeight = $0 }
            }
        }
    }

    private var groupedProjectList: some View {
        ForEach(model.sidebarProjectGroups) { group in
            if !group.title.isEmpty {
                Text(group.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            ForEach(group.projects) { project in
                ProjectSidebarBlock(
                    project: project,
                    isSelected: showsProjectSelection && model.selectedProject?.id == project.id,
                    isPinned: model.isPinned(project),
                    collapsed: model.isProjectCollapsed(project),
                    groupByBranch: model.sidebarGroupBy == .projectBranch,
                    branchGroups: model.branchGroups(for: project),
                    collapsibleEnabled: model.collapsibleGroupsEnabled,
                    isBranchCollapsed: { model.isBranchCollapsed(project, branch: $0.branch) },
                    activeThreadId: showsThreadSelection ? model.activeSessionId : nil,
                    renamingThreadID: $renamingThreadID,
                    renameDraft: $renameDraft,
                    isThreadPinned: { pinnedThreadIDs.contains($0) },
                    isThreadArchived: { archivedThreadIDs.contains($0) },
                    onSelectProject: { model.openProjectDetail(project) },
                    onNewChat: { model.startNewChatInProject(project) },
                    onToggleCollapse: { model.toggleProjectCollapsed(project) },
                    onToggleBranchCollapse: { model.toggleBranchCollapsed(project, branch: $0.branch) },
                    onSelectThread: { thread in
                        model.selectThread(thread, in: project)
                    },
                    onTogglePin: { model.togglePinProject(project) },
                    onArchive: { model.archiveProject(project) },
                    onThreadAction: { action, thread in
                        handleThreadAction(action, thread: thread, in: project)
                    },
                    onCommitRename: { thread in commitRename(thread, in: project) }
                )
            }
        }
    }

    private var flatThreadList: some View {
        Group {
            if model.sidebarFlatThreads.isEmpty {
                Text("No chats")
                    .font(CodexTheme.smallFont)
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.sidebarFlatThreads) { item in
                    if item.isPending {
                        PendingChatRow(leadingInset: 0)
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            flatThreadRow(item)
                            ForEach(item.subThreads) { sub in
                                flatSubagentRow(sub)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func flatThreadRow(_ item: SidebarFlatThread) -> some View {
        let isActive = showsThreadSelection && model.activeSessionId == item.id

        Button {
            model.selectThread(
                ProjectThread(id: item.id, title: item.title, ageLabel: item.ageLabel),
                in: item.project
            )
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(item.ageLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .fixedSize()
                }

                HStack(spacing: 5) {
                    Text(item.project.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    BranchChip(branch: item.project.gitBranch ?? "none")
                }
                .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? CodexTheme.navHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 7)
        .contextMenu {
            threadContextMenu(
                ProjectThread(id: item.id, title: item.title, ageLabel: item.ageLabel),
                in: item.project
            )
        }
        // Bind hover state to the row identity so a recycled slot
        // can't keep a stale highlight after the cursor leaves.
        .id(item.id)
    }

    /// A subagent row nested beneath its parent chat in the flat list.
    @ViewBuilder
    private func flatSubagentRow(_ item: SidebarFlatThread) -> some View {
        let isActive = showsThreadSelection && model.activeSessionId == item.id

        Button {
            model.selectThread(
                ProjectThread(id: item.id, title: item.title, ageLabel: item.ageLabel),
                in: item.project
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.leading, 12)

                if let agent = item.agentName, !agent.isEmpty {
                    SubagentChip(name: agent)
                }

                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(item.ageLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? CodexTheme.navHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 7)
        .help(item.title)
        .id(item.id)
    }

    private var settingsButton: some View {
        Button {
            model.navigateTo(.settings)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .frame(width: 16)
                Text("Settings")
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(model.activePage == .settings ? CodexTheme.navHighlight : Color.clear)
            )
            .shortcutHint(["⌘", ","], alignment: .trailing, x: -8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover()
    }

    // MARK: - Collapsed rail (#23)

    /// A slim icon-only rail. The toggle expands it; nav + settings stay reachable.
    private var collapsedRail: some View {
        VStack(spacing: 4) {
            railButton(symbol: "sidebar.left", help: "Expand sidebar") {
                model.toggleSidebarCollapsed()
            }
            .padding(.bottom, 6)

            ForEach(SidebarSection.allCases) { section in
                railButton(
                    symbol: section.symbol,
                    help: isLimited(section) ? "\(section.title) requires the full app" : section.title,
                    active: isPrimaryNavActive(section),
                    locked: isLimited(section)
                ) { handleNav(section) }
            }

            Spacer(minLength: 0)

            railButton(symbol: "gearshape", help: "Settings",
                       active: model.activePage == .settings) {
                model.navigateTo(.settings)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func railButton(symbol: String, help: String, active: Bool = false, locked: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            guard !locked else { return }
            action()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .frame(width: 40, height: 34)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .offset(x: -6, y: -6)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? CodexTheme.navHighlight : Color.clear)
            )
            .codexHover(cornerRadius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.5 : 1)
        .onHover { hovering in
            if hovering {
                hoveredRailItem = help
            } else if hoveredRailItem == help {
                hoveredRailItem = nil
            }
        }
        // A styled tooltip that floats to the right of the rail. The custom
        // `.trailing` alignment guide pins the bubble's *leading* edge to the
        // button's trailing edge, so it sits fully outside the slim rail.
        .overlay(alignment: .trailing) {
            if hoveredRailItem == help {
                RailTooltip(text: help)
                    .alignmentGuide(.trailing) { $0[.leading] }
                    .offset(x: 12)
                    .allowsHitTesting(false)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -6)),
                        removal: .opacity
                    ))
                    .zIndex(1)
            }
        }
        .animation(CodexMotion.quickSpring, value: hoveredRailItem)
        .animation(CodexMotion.quickSpring, value: locked)
    }

    // MARK: - Resize handle (#22)

    /// A 6pt-wide trailing strip; drag to resize, writing `model.sidebarWidth`.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = model.sidebarWidth
                            model.isResizingSidebar = true
                        }
                        let start = dragStartWidth ?? model.sidebarWidth
                        // Apply width with animations explicitly disabled so the
                        // edge follows the cursor exactly (no spring lag/stutter).
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            model.resizeSidebar(from: start, by: Double(value.translation.width))
                        }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        model.isResizingSidebar = false
                        model.commitSidebarWidth()
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    // MARK: - Navigation & actions

    private func handleNav(_ section: SidebarSection) {
        switch section {
        case .newChat:
            model.startNewChat()
        case .search:
            if model.activePage == .search {
                model.searchQuery = ""
                model.navigateTo(.home)
            } else {
                model.navigateTo(.search)
            }
        case .plugins:
            model.navigateTo(model.activePage == .plugins ? .home : .plugins)
        case .automations:
            model.navigateTo(model.activePage == .automations ? .home : .automations)
        }
    }

    private var showsProjectSelection: Bool {
        switch model.activePage {
        case .chat, .projectDetail, .projectContext:
            true
        case .home, .search, .plugins, .automations, .settings:
            false
        }
    }

    private var showsThreadSelection: Bool {
        model.activePage == .chat
    }

    private func isPrimaryNavActive(_ section: SidebarSection) -> Bool {
        model.activePage != .settings && model.activeSidebarSection == section
    }

    private func isLimited(_ section: SidebarSection) -> Bool {
        limitedMode && section == .automations
    }

    private func shortcutKeys(for section: SidebarSection) -> [String]? {
        switch section {
        case .newChat: ["⌘", "N"]
        case .search: ["⌘", "F"]
        case .plugins: ["⌘", "3"]
        case .automations: ["⌘", "4"]
        }
    }

    private func handleThreadAction(_ action: ThreadAction, thread: ProjectThread, in project: Project) {
        switch action {
        case .rename:
            renamingThreadID = thread.id
            renameDraft = thread.title
        case .delete:
            model.deleteThread(thread, in: project)
        case .archive:
            archivedThreadIDs.insert(thread.id)
        case .unarchive:
            archivedThreadIDs.remove(thread.id)
        case .pin:
            pinnedThreadIDs.insert(thread.id)
        case .unpin:
            pinnedThreadIDs.remove(thread.id)
        case .copy:
            model.copyThreadTitle(thread)
        }
    }

    private func commitRename(_ thread: ProjectThread, in project: Project) {
        let draft = renameDraft
        renamingThreadID = nil
        renameDraft = ""
        model.renameThread(thread, to: draft, in: project)
    }

    /// Shared context-menu builder used by the flat list (the grouped list builds
    /// its own inside `ProjectSidebarBlock` so it can drive inline rename).
    @ViewBuilder
    private func threadContextMenu(_ thread: ProjectThread, in project: Project) -> some View {
        Button("Rename") { handleThreadAction(.rename, thread: thread, in: project) }
        if pinnedThreadIDs.contains(thread.id) {
            Button("Unpin") { handleThreadAction(.unpin, thread: thread, in: project) }
        } else {
            Button("Pin") { handleThreadAction(.pin, thread: thread, in: project) }
        }
        if archivedThreadIDs.contains(thread.id) {
            Button("Unarchive") { handleThreadAction(.unarchive, thread: thread, in: project) }
        } else {
            Button("Archive") { handleThreadAction(.archive, thread: thread, in: project) }
        }
        Button("Copy") { handleThreadAction(.copy, thread: thread, in: project) }
        Divider()
        Button("Delete", role: .destructive) { handleThreadAction(.delete, thread: thread, in: project) }
    }
}

/// Actions surfaced on a chat row's right-click menu (#27).
enum ThreadAction {
    case rename, delete, archive, unarchive, pin, unpin, copy
}

// MARK: - Sidebar scroll tuning

private let SidebarScrollSpace = "CodessaSidebarScrollSpace"

private struct SidebarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SidebarScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SidebarSlimScrollbar: View {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    var body: some View {
        let maxScroll = max(contentHeight - viewportHeight, 1)
        let progress = min(max(-offset / maxScroll, 0), 1)
        let thumbHeight = max(28, viewportHeight * min(viewportHeight / max(contentHeight, 1), 1))
        let travel = max(viewportHeight - thumbHeight, 0)

        Capsule()
            .fill(CodexTheme.textTertiary.opacity(0.32))
            .frame(width: 2, height: thumbHeight)
            .offset(y: progress * travel)
            .frame(width: 4, height: viewportHeight, alignment: .top)
            .opacity(contentHeight > viewportHeight + 6 ? 1 : 0)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: progress)
            .animation(CodexMotion.quickSpring, value: contentHeight)
    }
}

/// SwiftUI can still inherit a chunky legacy scroller gutter on macOS when the
/// user's system preference is "Show scroll bars: Always". The sidebar should
/// scroll, but it should not reserve or paint that wide track.
private struct SidebarScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { ScrollChrome.hideNativeScrollers(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { ScrollChrome.hideNativeScrollers(from: nsView) }
    }
}

// MARK: - Collapsed-rail tooltip

/// A small, attractive tooltip shown beside a collapsed-rail icon on hover.
/// Replaces the slow, OS-styled system `.help()` bubble with an instant,
/// theme-matched glass pill plus a little pointer toward the icon.
private struct RailTooltip: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            // A small triangular pointer aiming back at the rail icon.
            Triangle()
                .fill(.ultraThinMaterial)
                .frame(width: 6, height: 11)
                .overlay(
                    Triangle().stroke(CodexTheme.composerBorder.opacity(0.7), lineWidth: 0.5)
                )

            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(CodexTheme.composerBorder.opacity(0.7), lineWidth: 0.5)
                )
        }
        .shadow(color: CodexTheme.shadowColor.opacity(0.35), radius: 8, x: 0, y: 3)
    }
}

/// A left-pointing triangle used as the tooltip's pointer.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Branch chip (#24)

/// A small "arrow.triangle.branch" chip showing a chat/project's git branch.
private struct BranchChip: View {
    let branch: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .medium))
            Text(branch)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(CodexTheme.textTertiary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            Capsule(style: .continuous).fill(CodexTheme.pillBackground.opacity(0.6))
        )
        // Branch names truncate in the chip — reveal the full name on hover.
        .help(branch)
    }
}

// MARK: - Pending chat row

/// The optimistic "New chat" row shown the instant a conversation starts, before
/// grok persists the session. Softly pulses to read as "in progress", then is
/// replaced by the real chat row once the session is indexed.
private struct PendingChatRow: View {
    /// Leading inset so the row lines up with sibling chat titles (grouped list)
    /// or sits flush (flat list).
    var leadingInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Text("New chat")
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textSecondary)
                .padding(.leading, leadingInset)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(reduceMotion ? 0.6 : (pulse ? 0.35 : 1.0))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .help("Starting a new chat…")
    }
}

// MARK: - Subagent chip

/// A small "sparkles" chip naming a subagent's agent type (e.g. "Explore"),
/// shown on nested subagent rows so the agent kind reads at a glance.
private struct SubagentChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 8, weight: .semibold))
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(CodexTheme.textTertiary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            Capsule(style: .continuous).fill(CodexTheme.pillBackground.opacity(0.6))
        )
        .fixedSize()
    }
}

// MARK: - Project block

private struct ProjectSidebarBlock: View {
    let project: Project
    let isSelected: Bool
    let isPinned: Bool
    let collapsed: Bool
    let groupByBranch: Bool
    let branchGroups: [SidebarBranchGroup]
    /// When false, collapse chevrons are hidden and every header stays expanded.
    let collapsibleEnabled: Bool
    let isBranchCollapsed: (SidebarBranchGroup) -> Bool
    let activeThreadId: String?
    @Binding var renamingThreadID: String?
    @Binding var renameDraft: String
    let isThreadPinned: (String) -> Bool
    let isThreadArchived: (String) -> Bool
    let onSelectProject: () -> Void
    let onNewChat: () -> Void
    let onToggleCollapse: () -> Void
    let onToggleBranchCollapse: (SidebarBranchGroup) -> Void
    let onSelectThread: (ProjectThread) -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void
    let onThreadAction: (ThreadAction, ProjectThread) -> Void
    let onCommitRename: (ProjectThread) -> Void

    /// Reveals the trailing "+" (new chat) button while the row is hovered.
    @State private var rowHovering = false

    // Indent for a project's child rows (chat titles). Deliberately tighter than
    // aligning fully under the project name — just past the chevron/folder so the
    // nesting reads clearly without eating horizontal space. Branch sub-headers
    // sit a touch shallower so their chats nest visibly beneath them.
    private let nameIndent: CGFloat = 20
    private let branchHeaderIndent: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Header row: a separate leading chevron toggles collapse, while the
            // name area selects the project. Both share a single hover highlight.
            HStack(spacing: 0) {
                if collapsibleEnabled {
                    Button(action: onToggleCollapse) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                            .frame(width: 18, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(collapsed ? "Expand project" : "Collapse project")
                } else {
                    Color.clear.frame(width: 18, height: 22)
                }

                Button(action: onSelectProject) {
                    HStack(spacing: 8) {
                        Image(systemName: isPinned ? "pin.fill" : "folder")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .frame(width: 16)

                        // Full name, truncating only when it actually runs out of
                        // width (no premature hard clip). Takes the space left of
                        // the right-pinned branch chip.
                        Text(project.name)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(project.name)

                        Spacer(minLength: 8)

                        // Branch indicator pinned to the right; "none" when the
                        // folder isn't a git repo so it never implies a branch.
                        BranchChip(branch: project.gitBranch ?? "none")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(project.name) overview")

                // Quick "new chat in this project" affordance, revealed on hover
                // of the row so it doesn't clutter the resting state.
                Button(action: onNewChat) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 22, height: 22)
                        .codexHover(cornerRadius: 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(rowHovering ? 1 : 0)
                .help("New chat in \(project.name)")
            }
            .padding(.leading, 2)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { rowHovering = $0 }
            .background(isSelected ? CodexTheme.navHighlight : Color.clear)
            .contentShape(Rectangle())
            .codexHover(cornerRadius: 0)
            // Key the header's hover state to the project so a recycled row in
            // the LazyVStack can't retain a stale highlight from another project.
            .id(project.id)
            .animation(CodexMotion.quickSpring, value: collapsed)
            // Double-tap anywhere on the project row toggles its expansion
            // (quick alternative to the leading chevron). Runs alongside the
            // single-tap "open overview" so both gestures stay available.
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if collapsibleEnabled { onToggleCollapse() }
                }
            )
            .contextMenu {
                if collapsibleEnabled {
                    Button(collapsed ? "Expand" : "Collapse", action: onToggleCollapse)
                    Divider()
                }
                Button(isPinned ? "Unpin" : "Pin", action: onTogglePin)
                Button("Archive", action: onArchive)
            }

            if !collapsed {
                if project.threads.isEmpty {
                    HStack(spacing: 0) {
                        Text("No chats")
                            .font(.system(size: 13))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .padding(.leading, nameIndent)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                } else if groupByBranch {
                    branchGroupedThreads
                } else {
                    ForEach(project.threads) { thread in
                        threadRow(thread)
                    }
                }
            }
        }
        .padding(.bottom, collapsed ? 0 : 4)
    }

    /// "By project → branch" sub-grouping (#25): a small branch sub-header per
    /// bucket, then that branch's chats.
    private var branchGroupedThreads: some View {
        ForEach(branchGroups) { group in
            let branchCollapsed = isBranchCollapsed(group)

            Button {
                if collapsibleEnabled { onToggleBranchCollapse(group) }
            } label: {
                HStack(spacing: 4) {
                    if collapsibleEnabled {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(branchCollapsed ? 0 : 90))
                            .frame(width: 12)
                    }
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .semibold))
                    Text(group.branch ?? "none")
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(CodexTheme.textTertiary)
                .padding(.leading, branchHeaderIndent)
                .padding(.trailing, 8)
                .padding(.top, 5)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!collapsibleEnabled)
            .animation(CodexMotion.quickSpring, value: branchCollapsed)

            if !branchCollapsed {
                ForEach(group.threads) { thread in
                    threadRow(thread)
                }
            }
        }
    }

    /// A chat row plus any subagent chats it spawned, nested beneath it.
    @ViewBuilder
    private func threadRow(_ thread: ProjectThread) -> some View {
        if thread.isPending {
            PendingChatRow(leadingInset: nameIndent)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                singleThreadRow(thread)
                ForEach(thread.subThreads) { sub in
                    subagentRow(sub)
                }
            }
        }
    }

    @ViewBuilder
    private func singleThreadRow(_ thread: ProjectThread) -> some View {
        let isActive = activeThreadId == thread.id
        let isRenaming = renamingThreadID == thread.id

        Group {
            if isRenaming {
                renameField(thread)
            } else {
                Button { onSelectThread(thread) } label: {
                    HStack(spacing: 8) {
                        if isThreadPinned(thread.id) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(CodexTheme.textTertiary)
                        }
                        Text(thread.title)
                            .font(.system(size: 13))
                            .foregroundStyle(isActive ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, isThreadPinned(thread.id) ? 0 : nameIndent)

                        Spacer(minLength: 8)

                        Text(thread.ageLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isActive ? CodexTheme.navHighlight : Color.clear)
                    )
                    .opacity(isThreadArchived(thread.id) ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .codexHover(cornerRadius: 7)
                .contextMenu { rowContextMenu(thread) }
            }
        }
        // Tie hover state to the row's identity so a recycled LazyVStack slot
        // can't carry a stale "hovering" highlight onto a different chat.
        .id(thread.id)
    }

    /// A nested subagent chat row, indented beneath the chat that spawned it.
    /// Tighter and dimmer than a normal row, with a leading branch-connector and
    /// an agent-type chip so it reads as a child of the parent conversation.
    @ViewBuilder
    private func subagentRow(_ thread: ProjectThread) -> some View {
        let isActive = activeThreadId == thread.id

        Button { onSelectThread(thread) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.leading, nameIndent)

                if let agent = thread.agentName, !agent.isEmpty {
                    SubagentChip(name: agent)
                }

                Text(thread.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(thread.ageLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? CodexTheme.navHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 7)
        .help(thread.title)
        .contextMenu { rowContextMenu(thread) }
        .id(thread.id)
    }

    /// Inline rename text field shown in place of the row (#27 Rename).
    private func renameField(_ thread: ProjectThread) -> some View {
        TextField("", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.leading, nameIndent)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(CodexTheme.composerBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
            )
            .onSubmit { onCommitRename(thread) }
            .onExitCommand { renamingThreadID = nil }
    }

    @ViewBuilder
    private func rowContextMenu(_ thread: ProjectThread) -> some View {
        Button("Rename") { onThreadAction(.rename, thread) }
        if isThreadPinned(thread.id) {
            Button("Unpin") { onThreadAction(.unpin, thread) }
        } else {
            Button("Pin") { onThreadAction(.pin, thread) }
        }
        if isThreadArchived(thread.id) {
            Button("Unarchive") { onThreadAction(.unarchive, thread) }
        } else {
            Button("Archive") { onThreadAction(.archive, thread) }
        }
        Button("Copy") { onThreadAction(.copy, thread) }
        Divider()
        Button("Delete", role: .destructive) { onThreadAction(.delete, thread) }
    }
}
