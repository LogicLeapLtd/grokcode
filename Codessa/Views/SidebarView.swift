import AppKit
import SwiftUI

private enum SidebarMetrics {
    static let outerHorizontal: CGFloat = 8
    static let rowHorizontal: CGFloat = 10
    static let rowVertical: CGFloat = 5
    static let headerVertical: CGFloat = 6
    static let navHorizontal: CGFloat = 9
    static let navVertical: CGFloat = 6
    static let navSpacing: CGFloat = 9
    static let childVertical: CGFloat = 4
    static let sectionGap: CGFloat = 6
    static let titleFont: CGFloat = 12
    static let bodyFont: CGFloat = 13
    static let navFont: CGFloat = 14
    static let detailFont: CGFloat = 11.5
    static let captionFont: CGFloat = 10.5
    static let iconFont: CGFloat = 13
    static let navIconFont: CGFloat = 14.5
    static let navIconBox: CGFloat = 19
    static let cornerRadius: CGFloat = 7
    static let nameIndent: CGFloat = 18
    static let branchHeaderIndent: CGFloat = 11
    static let railButtonWidth: CGFloat = 38
    static let railButtonHeight: CGFloat = 32
    static let accountMenuWidth: CGFloat = 260
}

private struct CollapsedRailTooltipAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SidebarView: View {
    @Environment(AppViewModel.self) private var model
    @EnvironmentObject private var license: LicenseManager
    @EnvironmentObject private var update: UpdateService
    var limitedMode = false
    var forceCollapsed = false

    /// Transient, view-local chat state. There is no Foundation-backed store for
    /// per-chat pin/archive, so these live with the view (reset on relaunch).
    @State private var pinnedThreadIDs: Set<String> = []
    @State private var archivedThreadIDs: Set<String> = []
    /// Inline-rename state (#27): the row being edited and its draft text.
    @State private var renamingThreadID: String?
    @State private var renameDraft: String = ""
    /// Project pending a rename via the context menu, and its draft label.
    @State private var projectPendingRename: Project?
    @State private var projectRenameDraft: String = ""
    /// Live drag width so the resize feels immediate (committed to the model).
    @State private var dragStartWidth: Double?
    /// Collapsed-rail item currently showing its outside-the-sidebar tooltip.
    @State private var hoveredRailItem: String?
    @State private var sidebarScrollOffset: CGFloat = 0
    @State private var sidebarScrollContentHeight: CGFloat = 0
    /// Threads (flat list) whose subagent rows are expanded. Subagents start
    /// collapsed so a busy chat doesn't flood the sidebar by default.
    @State private var expandedFlatSubagentIDs: Set<String> = []

    private func toggleFlatSubagents(_ id: String) {
        if expandedFlatSubagentIDs.contains(id) {
            expandedFlatSubagentIDs.remove(id)
        } else {
            expandedFlatSubagentIDs.insert(id)
        }
    }

    var body: some View {
        Group {
            if usesCollapsedLayout {
                // Pin each branch to its natural width so the content never
                // reflows/truncates as the outer frame animates between widths;
                // the outer `.clipped()` simply reveals/hides it, which keeps the
                // crossfade smooth instead of churning the layout every frame.
                collapsedRail
                    // `.center`, not `.leading` — the rail's icon column is
                    // narrower than the rail itself, so `.leading` here would
                    // shove it flush to the left edge with a dead gap on the
                    // right instead of centering it in the available width.
                    .frame(width: currentSidebarWidth, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                expandedBody
                    .frame(width: currentSidebarWidth, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(width: currentSidebarWidth, alignment: .leading)
        .clipped()
        .alert("Rename project", isPresented: Binding(
            get: { projectPendingRename != nil },
            set: { if !$0 { projectPendingRename = nil } }
        )) {
            TextField("Project name", text: $projectRenameDraft)
            Button("Cancel", role: .cancel) { projectPendingRename = nil }
            Button("Rename") {
                if let project = projectPendingRename {
                    model.renameProject(project, to: projectRenameDraft)
                }
                projectPendingRename = nil
            }
        } message: {
            Text("Set a custom name for this project in the sidebar. This doesn't rename the folder on disk.")
        }
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
        .overlayPreferenceValue(CollapsedRailTooltipAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if usesCollapsedLayout,
                   let hoveredRailItem,
                   let anchor = anchors[hoveredRailItem] {
                    let rect = proxy[anchor]

                    RailTooltip(text: hoveredRailItem)
                        .fixedSize()
                        .offset(x: rect.maxX + 10, y: rect.midY - 15)
                        .allowsHitTesting(false)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: -4)),
                            removal: .opacity
                        ))
                        .zIndex(10)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if !usesCollapsedLayout { resizeHandle }
        }
        .animation(CodexMotion.sidebarCollapse, value: usesCollapsedLayout)
        .animation(CodexMotion.quickSpring, value: hoveredRailItem)
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
                .padding(.horizontal, SidebarMetrics.outerHorizontal)
                .padding(.bottom, 10)

            projectsSection

            Spacer(minLength: 0)

            Rectangle()
                .fill(CodexTheme.divider)
                .frame(height: 1)

            accountRow
        }
        .padding(.top, 0)
    }

    /// Tiny top spacer; window-level controls now live beside the traffic
    /// lights, so the first nav row can sit closer to the title bar.
    private var header: some View {
        Color.clear
            .frame(height: 2)
            .background(NonDraggableRegion())
    }

    private var navSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SidebarSection.allCases) { section in
                navRow(section)
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
            HStack(spacing: SidebarMetrics.navSpacing) {
                Image(systemName: section.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: SidebarMetrics.navIconFont, weight: .regular))
                    .foregroundStyle(navIconColor(active: active, locked: locked))
                    .frame(width: SidebarMetrics.navIconBox)
                Text(section.title)
                    .font(.system(size: SidebarMetrics.navFont, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
            }
            .padding(.horizontal, SidebarMetrics.navHorizontal)
            .padding(.vertical, SidebarMetrics.navVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SidebarMetrics.cornerRadius, style: .continuous)
                    .fill(active ? CodexTheme.navHighlight : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: SidebarMetrics.cornerRadius)
        .opacity(locked ? 0.5 : 1)
        .help(locked ? "\(section.title) requires the full app" : section.title)
        .animation(CodexMotion.quickSpring, value: active)
        .animation(CodexMotion.quickSpring, value: locked)
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: SidebarMetrics.sectionGap) {
            SidebarControlsBar()

            GeometryReader { viewport in
                ZStack(alignment: .trailing) {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if model.sidebarGroupBy == .flatList {
                                flatThreadList
                            } else {
                                groupedProjectList
                            }

                            if showsProjectEmptyState {
                                projectEmptyState
                            }

                            if !model.noProjectThreads.isEmpty {
                                NoProjectChatsSection(
                                    threads: model.noProjectThreads,
                                    activeThreadId: showsThreadSelection ? model.activeSessionId : nil,
                                    renamingThreadID: $renamingThreadID,
                                    renameDraft: $renameDraft,
                                    isThreadPinned: { pinnedThreadIDs.contains($0) },
                                    isThreadArchived: { archivedThreadIDs.contains($0) },
                                    onSelectThread: { model.selectNoProjectThread($0) },
                                    onThreadAction: handleNoProjectThreadAction,
                                    onCommitRename: commitNoProjectRename
                                )
                            }
                        }
                        .padding(.top, 2)
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
                    .font(.system(size: SidebarMetrics.captionFont, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, SidebarMetrics.rowHorizontal)
                    .padding(.top, 6)
                    .padding(.bottom, 3)
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
                    onRevealProject: { model.revealProjectInSidebar(project) },
                    onNewChat: { model.startNewChatInProject(project) },
                    onToggleCollapse: { model.toggleProjectCollapsed(project) },
                    onToggleBranchCollapse: { model.toggleBranchCollapsed(project, branch: $0.branch) },
                    onSelectThread: { thread in
                        model.selectThread(thread, in: project)
                    },
                    onTogglePin: { model.togglePinProject(project) },
                    onArchive: { model.archiveProject(project) },
                    onRevealInFinder: { model.revealProjectInFinder(project) },
                    onCreateWorktree: { model.createWorktree(for: project) },
                    onBeginRename: {
                        projectRenameDraft = project.name
                        projectPendingRename = project
                    },
                    onRemove: { model.removeProjectFromSidebar(project) },
                    onThreadAction: { action, thread in
                        handleThreadAction(action, thread: thread, in: project)
                    },
                    onCommitRename: { thread in commitRename(thread, in: project) }
                )
            }
        }
    }

    private var showsProjectEmptyState: Bool {
        model.sidebarGroupBy != .flatList
            && model.sidebarProjectGroups.isEmpty
            && model.noProjectThreads.isEmpty
    }

    private var projectEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(projectEmptyTitle)
                .font(.system(size: SidebarMetrics.bodyFont, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
            Text(projectEmptyDetail)
                .font(.system(size: SidebarMetrics.captionFont))
                .foregroundStyle(CodexTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if model.sidebarStatusFilter != .all, !model.projects.isEmpty {
                Button {
                    model.sidebarStatusFilter = .all
                    model.persistSidebarPreferences()
                } label: {
                    Label("Show all folders", systemImage: "square.grid.2x2")
                        .font(.system(size: SidebarMetrics.captionFont, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CodexTheme.textSecondary)
                .codexHover(cornerRadius: 6)
            }
        }
        .padding(.horizontal, SidebarMetrics.rowHorizontal)
        .padding(.vertical, 8)
    }

    private var projectEmptyTitle: String {
        if model.projects.isEmpty { return "No project folders" }
        switch model.sidebarStatusFilter {
        case .withChats: return "No projects with chats"
        case .pinnedOnly: return "No pinned projects"
        case .noChats, .all: return "No projects"
        }
    }

    private var projectEmptyDetail: String {
        if model.projects.isEmpty {
            return "Add a folder to scan for projects."
        }
        switch model.sidebarStatusFilter {
        case .withChats:
            return "\(model.projects.count) folder\(model.projects.count == 1 ? "" : "s") discovered, hidden by the With chats filter."
        case .pinnedOnly:
            return "\(model.projects.count) folder\(model.projects.count == 1 ? "" : "s") discovered, but none are pinned."
        case .noChats, .all:
            return "Try refreshing projects or adding another folder."
        }
    }

    private var flatThreadList: some View {
        Group {
            if model.sidebarFlatThreads.isEmpty {
                Text("No chats")
                    .font(CodexTheme.smallFont)
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, SidebarMetrics.rowHorizontal)
                    .padding(.vertical, 6)
            } else {
                ForEach(model.sidebarFlatThreads) { item in
                    if item.isPending {
                        PendingChatRow(leadingInset: 0)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            flatThreadRow(item)
                            if !item.subThreads.isEmpty {
                                let expanded = expandedFlatSubagentIDs.contains(item.id)
                                subagentToggleRow(count: item.subThreads.count,
                                                   isExpanded: expanded,
                                                   leadingInset: 12) {
                                    toggleFlatSubagents(item.id)
                                }
                                if expanded {
                                    ForEach(item.subThreads) { sub in
                                        flatSubagentRow(sub)
                                    }
                                }
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
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(item.title)
                        .font(.system(size: SidebarMetrics.bodyFont, weight: .regular))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(item.ageLabel)
                        .font(.system(size: SidebarMetrics.detailFont))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .fixedSize()
                }

                HStack(spacing: 4) {
                    Text(item.project.name)
                        .font(.system(size: SidebarMetrics.detailFont))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let branch = item.project.gitBranch {
                        BranchChip(branch: branch)
                    }
                }
                .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, SidebarMetrics.rowHorizontal)
            .padding(.vertical, SidebarMetrics.rowVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? CodexTheme.navHighlight : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 0)
        .contextMenu {
            threadContextMenu(
                ProjectThread(id: item.id, title: item.title, ageLabel: item.ageLabel),
                in: item.project
            )
        }
        .onDrag {
            NSItemProvider(
                object: model.dragPayload(
                    for: ProjectThread(id: item.id, title: item.title, ageLabel: item.ageLabel),
                    in: item.project
                ) as NSString
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
            .padding(.horizontal, SidebarMetrics.rowHorizontal)
            .padding(.vertical, SidebarMetrics.childVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? CodexTheme.navHighlight : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 0)
        .help(item.title)
        .onDrag {
            NSItemProvider(
                object: model.dragPayload(
                    for: ProjectThread(id: item.id, title: item.title, ageLabel: item.ageLabel),
                    in: item.project
                ) as NSString
            )
        }
        .id(item.id)
    }

    /// Bottom-of-sidebar account row (replaces the old standalone "Settings"
    /// row): avatar + display name + plan, opening a menu with Settings and
    /// the rest of the account-level actions. Full-bleed edge-to-edge (with a
    /// divider above it, since it sits flush against the sidebar's bottom
    /// edge) to match the rest of the sidebar's full-width rows.
    private var accountRow: some View {
        CodexMenuTrigger(minWidth: 240, maxWidth: SidebarMetrics.accountMenuWidth, edge: .top, highlightOnHover: false) { isOpen in
            HStack(spacing: 9) {
                AccountAvatar(initials: accountInitials)
                VStack(alignment: .leading, spacing: 0) {
                    Text(accountDisplayName)
                        .font(.system(size: SidebarMetrics.bodyFont, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(accountPlanLabel)
                        .font(.system(size: SidebarMetrics.detailFont))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOpen ? CodexTheme.navHighlight : Color.clear)
            .contentShape(Rectangle())
        } menu: { close in
            accountMenuContent(close: close)
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 0)
    }

    /// The account dropdown's contents — shared by the expanded sidebar's
    /// `accountRow` and the collapsed rail's icon-only equivalent, so both
    /// layouts offer the same actions instead of drifting out of sync.
    @ViewBuilder
    private func accountMenuContent(close: @escaping () -> Void) -> some View {
        CodexMenuContainer {
            HStack(spacing: 8) {
                AccountAvatar(initials: accountInitials, diameter: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(accountDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(accountPlanLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            CodexMenuDivider()

            CodexMenuItem(title: "Settings", systemImage: "gearshape") {
                model.navigateTo(.settings)
                close()
            }
            CodexMenuItem(
                title: update.updateAvailableInBackground ? "Update available" : "Check for updates",
                subtitle: update.updateAvailableInBackground ? "A newer version is ready to install" : nil,
                systemImage: "arrow.down.circle"
            ) {
                update.presentDialog()
                close()
            }

            if !license.activeLicenseKey.isEmpty {
                CodexMenuDivider()
                CodexMenuItem(title: "Deactivate license", systemImage: "key.slash", isDestructive: true) {
                    Task { await license.deactivateThisDevice() }
                    close()
                }
            }

            CodexMenuDivider()
            CodexMenuItem(title: "Quit Codessa", systemImage: "power", isDestructive: true) {
                NSApp.terminate(nil)
            }
        }
    }

    /// Two-letter initials for the avatar, from the macOS account's full name.
    private var accountInitials: String {
        let parts = NSFullUserName()
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(parts).uppercased()
        return initials.isEmpty ? "?" : initials
    }

    private var accountDisplayName: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "You" : name
    }

    /// "Free" whenever the build is unmonetised (the current default — see
    /// `LicenseManager.isFree`); otherwise reflects the real license status so
    /// this stays correct if the app is re-monetised later.
    private var accountPlanLabel: String {
        guard !LicenseManager.isFree else { return "Free" }
        switch license.status {
        case .licensed: return "Pro"
        case .trial: return "Trial"
        case .expired, .invalid, .checking: return "Free"
        }
    }

    // MARK: - Collapsed rail (#23)

    /// A slim icon-only rail. Nav + the account menu stay reachable (the latter
    /// mirrors `accountRow` so collapsing the sidebar never hides an action
    /// that's only reachable when expanded).
    private var collapsedRail: some View {
        VStack(spacing: 3) {
            ForEach(SidebarSection.allCases) { section in
                railButton(
                    symbol: section.symbol,
                    accessibilityLabel: isLimited(section) ? "\(section.title) requires the full app" : section.title,
                    active: isPrimaryNavActive(section),
                    locked: isLimited(section)
                ) { handleNav(section) }
            }

            Spacer(minLength: 0)

            collapsedAccountButton
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func railButton(symbol: String, accessibilityLabel: String, active: Bool = false, locked: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            guard !locked else { return }
            action()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(navIconColor(active: active, locked: locked))
                    .frame(width: SidebarMetrics.railButtonWidth, height: SidebarMetrics.railButtonHeight)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .offset(x: -5, y: -5)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: SidebarMetrics.cornerRadius, style: .continuous)
                    .fill(active ? CodexTheme.navHighlight : Color.clear)
            )
            .codexHover(cornerRadius: SidebarMetrics.cornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(locked ? 0.5 : 1)
        .accessibilityLabel(Text(accessibilityLabel))
        .onHover { hovering in
            if hovering {
                hoveredRailItem = accessibilityLabel
            } else if hoveredRailItem == accessibilityLabel {
                hoveredRailItem = nil
            }
        }
        .anchorPreference(key: CollapsedRailTooltipAnchorKey.self, value: .bounds) {
            [accessibilityLabel: $0]
        }
        .animation(CodexMotion.quickSpring, value: locked)
    }

    private func navIconColor(active: Bool, locked: Bool) -> Color {
        if locked { return CodexTheme.textTertiary }
        return active ? CodexTheme.navIconActiveForeground : CodexTheme.navIconForeground
    }

    /// The collapsed rail's account entry point — same sizing/hover treatment
    /// as `railButton`, but an avatar opening the shared account menu instead
    /// of navigating straight to Settings.
    private var collapsedAccountButton: some View {
        CodexMenuTrigger(minWidth: 240, maxWidth: SidebarMetrics.accountMenuWidth, edge: .top, highlightOnHover: false) { isOpen in
            AccountAvatar(initials: accountInitials, diameter: 22)
                .frame(width: SidebarMetrics.railButtonWidth, height: SidebarMetrics.railButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: SidebarMetrics.cornerRadius, style: .continuous)
                        .fill(isOpen ? CodexTheme.navHighlight : Color.clear)
                )
                .codexHover(cornerRadius: SidebarMetrics.cornerRadius)
                .contentShape(Rectangle())
        } menu: { close in
            accountMenuContent(close: close)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Account"))
        .onHover { hovering in
            if hovering {
                hoveredRailItem = "Account"
            } else if hoveredRailItem == "Account" {
                hoveredRailItem = nil
            }
        }
        .anchorPreference(key: CollapsedRailTooltipAnchorKey.self, value: .bounds) {
            ["Account": $0]
        }
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
        case .chat, .projectContext:
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
        case .openInSplitView:
            model.openThreadInNewSplitPane(thread, project: project)
        }
    }

    private func commitRename(_ thread: ProjectThread, in project: Project) {
        let draft = renameDraft
        renamingThreadID = nil
        renameDraft = ""
        model.renameThread(thread, to: draft, in: project)
    }

    /// Mirrors `handleThreadAction`/`commitRename` for the standalone "Chats"
    /// section, whose threads have no project to route the action through.
    private func handleNoProjectThreadAction(_ action: ThreadAction, thread: ProjectThread) {
        switch action {
        case .rename:
            renamingThreadID = thread.id
            renameDraft = thread.title
        case .delete:
            model.deleteNoProjectThread(thread)
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
        case .openInSplitView:
            model.openThreadInNewSplitPane(thread, project: nil)
        }
    }

    private func commitNoProjectRename(_ thread: ProjectThread) {
        let draft = renameDraft
        renamingThreadID = nil
        renameDraft = ""
        model.renameNoProjectThread(thread, to: draft)
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
        Button("Open in split view") { handleThreadAction(.openInSplitView, thread: thread, in: project) }
        Divider()
        Button("Delete", role: .destructive) { handleThreadAction(.delete, thread: thread, in: project) }
    }
}

/// Actions surfaced on a chat row's right-click menu (#27).
enum ThreadAction {
    case rename, delete, archive, unarchive, pin, unpin, copy, openInSplitView
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

// MARK: - Right-click catcher

/// Reports right-clicks (and control-clicks) so we can open a themed `CodexMenu`
/// instead of AppKit's native `NSMenu`. Placed as an overlay: its `hitTest`
/// returns `nil` for ordinary left-clicks so hover, selection and inner buttons
/// keep working — it only claims secondary clicks, then fires `onRightClick`.
private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only intercept secondary (right / control) clicks; pass every other
            // event straight through to the SwiftUI content beneath.
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            case .leftMouseDown, .leftMouseUp
                where event.modifierFlags.contains(.control):
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                onRightClick?()
            } else {
                super.mouseDown(with: event)
            }
        }
    }
}

// MARK: - Collapsed rail tooltip

private struct RailTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(CodexTheme.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(
                TooltipBubble()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                TooltipBubble()
                    .stroke(CodexTheme.composerBorder.opacity(0.72), lineWidth: 0.5)
            )
        .shadow(color: CodexTheme.shadowColor.opacity(0.35), radius: 8, x: 0, y: 3)
    }
}

private struct TooltipBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let pointerWidth: CGFloat = 8
        let pointerHeight: CGFloat = 14
        let cornerRadius: CGFloat = 8
        let bodyMinX = rect.minX + pointerWidth
        let pointerTopY = rect.midY - pointerHeight / 2
        let pointerBottomY = rect.midY + pointerHeight / 2

        var path = Path()
        path.move(to: CGPoint(x: bodyMinX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: bodyMinX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX, y: pointerBottomY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: bodyMinX, y: pointerTopY))
        path.addLine(to: CGPoint(x: bodyMinX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX + cornerRadius, y: rect.minY),
            control: CGPoint(x: bodyMinX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Account avatar

/// A small circular initials avatar for the bottom-of-sidebar account row.
private struct AccountAvatar: View {
    let initials: String
    var diameter: CGFloat = 22

    var body: some View {
        Circle()
            .fill(CodexTheme.accent)
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(initials)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
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
                .font(.system(size: 10.5))
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
                .font(.system(size: SidebarMetrics.bodyFont))
                .foregroundStyle(CodexTheme.textSecondary)
                .padding(.leading, leadingInset)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, SidebarMetrics.rowHorizontal)
        .padding(.vertical, SidebarMetrics.rowVertical)
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

// MARK: - Subagent collapse toggle

/// A small tappable "N subagents" row that shows/hides the nested subagent rows
/// beneath a chat. Subagents default to collapsed (see the callers' `@State`),
/// so a chat that spawned many subagents doesn't flood the sidebar by default.
private func subagentToggleRow(count: Int, isExpanded: Bool, leadingInset: CGFloat,
                                action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12)
            Text("\(count) subagent\(count == 1 ? "" : "s")")
                .font(.system(size: 10.5, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(CodexTheme.textTertiary)
        .padding(.leading, leadingInset)
        .padding(.trailing, SidebarMetrics.rowHorizontal)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .animation(CodexMotion.quickSpring, value: isExpanded)
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
    let onRevealProject: () -> Void
    let onNewChat: () -> Void
    let onToggleCollapse: () -> Void
    let onToggleBranchCollapse: (SidebarBranchGroup) -> Void
    let onSelectThread: (ProjectThread) -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void
    let onRevealInFinder: () -> Void
    let onCreateWorktree: () -> Void
    let onBeginRename: () -> Void
    let onRemove: () -> Void
    let onThreadAction: (ThreadAction, ProjectThread) -> Void
    let onCommitRename: (ProjectThread) -> Void

    /// Drives the themed right-click menu (custom `CodexMenu`, not native NSMenu).
    @Environment(CodexMenuController.self) private var menuController
    @State private var menuID = UUID()
    @State private var headerFrame: CGRect = .zero

    /// Reveals the trailing "+" (new chat) button while the row is hovered.
    @State private var rowHovering = false
    /// Threads whose subagent rows are expanded. Subagents start collapsed so a
    /// busy chat doesn't flood the sidebar with nested rows by default.
    @State private var expandedSubagentThreadIDs: Set<String> = []

    // Indent for a project's child rows (chat titles). Deliberately tighter than
    // aligning fully under the project name — just past the chevron/folder so the
    // nesting reads clearly without eating horizontal space. Branch sub-headers
    // sit a touch shallower so their chats nest visibly beneath them.
    private let nameIndent: CGFloat = SidebarMetrics.nameIndent
    private let branchHeaderIndent: CGFloat = SidebarMetrics.branchHeaderIndent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: both the leading chevron and the project name area act
            // as disclosure controls. The plus keeps new-chat creation separate.
            HStack(spacing: 0) {
                if collapsibleEnabled {
                    Button(action: onToggleCollapse) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                            .frame(width: 14, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(collapsed ? "Expand project" : "Collapse project")
                } else {
                    Color.clear.frame(width: 14, height: 18)
                }

                Button {
                    if collapsibleEnabled {
                        onToggleCollapse()
                    } else {
                        onRevealProject()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPinned ? "pin.fill" : "folder")
                            .font(.system(size: SidebarMetrics.iconFont, weight: .regular))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .frame(width: SidebarMetrics.navIconBox)

                        // Full name, truncating only when it actually runs out of
                        // width (no premature hard clip). Takes the space left of
                        // the right-pinned branch chip.
                        Text(project.name)
                            .font(.system(size: SidebarMetrics.bodyFont, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(project.name)

                        Spacer(minLength: 8)

                        if let branch = project.gitBranch {
                            BranchChip(branch: branch)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapsibleEnabled ? (collapsed ? "Expand \(project.name)" : "Collapse \(project.name)") : "Select \(project.name)")

                // Quick "new chat in this project" affordance, revealed on hover
                // of the row so it doesn't clutter the resting state.
                Button(action: onNewChat) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 20, height: 20)
                        .codexHover(cornerRadius: 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(rowHovering ? 1 : 0)
                .help("New chat in \(project.name)")
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, SidebarMetrics.headerVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { rowHovering = $0 }
            .background(isSelected ? CodexTheme.navHighlight : Color.clear)
            .contentShape(Rectangle())
            .codexHover(cornerRadius: 0)
            // Key the header's hover state to the project so a recycled row in
            // the LazyVStack can't retain a stale highlight from another project.
            .id(project.id)
            .animation(CodexMotion.quickSpring, value: collapsed)
            // Track the header's global frame so the themed menu can anchor to it,
            // then catch right-/control-clicks to open it (no native NSMenu).
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { headerFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, frame in headerFrame = frame }
                }
            )
            .overlay(RightClickCatcher { openProjectMenu() })

            if !collapsed {
                if project.threads.isEmpty {
                    HStack(spacing: 0) {
                        Text("No chats")
                            .font(.system(size: SidebarMetrics.bodyFont))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .padding(.leading, nameIndent)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, SidebarMetrics.rowHorizontal)
                    .padding(.vertical, SidebarMetrics.rowVertical)
                } else if groupByBranch {
                    branchGroupedThreads
                } else {
                    ForEach(project.threads) { thread in
                        threadRow(thread)
                    }
                }
            }
        }
        .padding(.bottom, collapsed ? 0 : 2)
    }

    // MARK: - Themed right-click menu

    private func openProjectMenu() {
        menuController.toggle(id: menuID, anchor: headerFrame, minWidth: 224, edge: .bottom) {
            projectMenuContent
        }
    }

    /// Runs a menu action and dismisses the menu in one step.
    private func runMenu(_ action: @escaping () -> Void) {
        menuController.close()
        action()
    }

    @ViewBuilder
    private var projectMenuContent: some View {
        CodexMenuContainer {
            CodexMenuSectionHeader(title: project.name)
            if collapsibleEnabled {
                CodexMenuItem(title: collapsed ? "Expand" : "Collapse",
                              systemImage: collapsed ? "chevron.down" : "chevron.up") {
                    runMenu(onToggleCollapse)
                }
                CodexMenuDivider()
            }
            CodexMenuItem(title: isPinned ? "Unpin project" : "Pin project",
                          systemImage: isPinned ? "pin.slash" : "pin") {
                runMenu(onTogglePin)
            }
            CodexMenuItem(title: "Reveal in Finder", systemImage: "folder") {
                runMenu(onRevealInFinder)
            }
            CodexMenuItem(title: "Create permanent worktree", systemImage: "arrow.triangle.branch") {
                runMenu(onCreateWorktree)
            }
            CodexMenuItem(title: "Rename project", systemImage: "pencil") {
                runMenu(onBeginRename)
            }
            CodexMenuDivider()
            CodexMenuItem(title: "Archive chats", systemImage: "archivebox") {
                runMenu(onArchive)
            }
            CodexMenuItem(title: "Remove", systemImage: "xmark", isDestructive: true) {
                runMenu(onRemove)
            }
        }
    }

    /// "By project → branch" sub-grouping (#25): a small branch sub-header per
    /// bucket, then that branch's chats.
    private var branchGroupedThreads: some View {
        ForEach(branchGroups) { group in
            let branchCollapsed = isBranchCollapsed(group)

            Button {
                if collapsibleEnabled { onToggleBranchCollapse(group) }
            } label: {
                HStack(spacing: 3) {
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
                .padding(.trailing, SidebarMetrics.rowHorizontal)
                .padding(.top, 4)
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
            VStack(alignment: .leading, spacing: 0) {
                singleThreadRow(thread)
                if !thread.subThreads.isEmpty {
                    let expanded = expandedSubagentThreadIDs.contains(thread.id)
                    subagentToggleRow(count: thread.subThreads.count,
                                      isExpanded: expanded,
                                      leadingInset: nameIndent) {
                        if expanded {
                            expandedSubagentThreadIDs.remove(thread.id)
                        } else {
                            expandedSubagentThreadIDs.insert(thread.id)
                        }
                    }
                    if expanded {
                        ForEach(thread.subThreads) { sub in
                            subagentRow(sub)
                        }
                    }
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
                    HStack(spacing: 6) {
                        if isThreadPinned(thread.id) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(CodexTheme.textTertiary)
                        }
                        Text(thread.title)
                            .font(.system(size: SidebarMetrics.bodyFont))
                            .foregroundStyle(isActive ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, isThreadPinned(thread.id) ? 0 : nameIndent)

                        Spacer(minLength: 8)

                        Text(thread.ageLabel)
                            .font(.system(size: SidebarMetrics.detailFont))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .fixedSize()
                    }
                    .padding(.horizontal, SidebarMetrics.rowHorizontal)
                    .padding(.vertical, SidebarMetrics.rowVertical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isActive ? CodexTheme.navHighlight : Color.clear)
                    .opacity(isThreadArchived(thread.id) ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .codexHover(cornerRadius: 0)
                .contextMenu { rowContextMenu(thread) }
                .onDrag {
                    NSItemProvider(object: SplitPaneDragPayload.thread(thread, project: project) as NSString)
                }
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
            HStack(spacing: 5) {
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
            .padding(.horizontal, SidebarMetrics.rowHorizontal)
            .padding(.vertical, SidebarMetrics.childVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? CodexTheme.navHighlight : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 0)
        .help(thread.title)
        .contextMenu { rowContextMenu(thread) }
        .onDrag {
            NSItemProvider(object: SplitPaneDragPayload.thread(thread, project: project) as NSString)
        }
        .id(thread.id)
    }

    /// Inline rename text field shown in place of the row (#27 Rename).
    private func renameField(_ thread: ProjectThread) -> some View {
        TextField("", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: SidebarMetrics.bodyFont))
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.leading, nameIndent)
            .padding(.horizontal, SidebarMetrics.rowHorizontal)
            .padding(.vertical, SidebarMetrics.rowVertical)
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
        Button("Open in split view") { onThreadAction(.openInSplitView, thread) }
        Divider()
        Button("Delete", role: .destructive) { onThreadAction(.delete, thread) }
    }
}

// MARK: - No-project chats section

/// Standalone sidebar section, below the projects list, for chats started with
/// "Don't work in a project". These sessions have no project to nest under, so
/// they get their own collapsible "Chats" header and a flat list of rows —
/// otherwise mirrors `ProjectSidebarBlock`'s thread/subagent rows.
private struct NoProjectChatsSection: View {
    let threads: [ProjectThread]
    let activeThreadId: String?
    @Binding var renamingThreadID: String?
    @Binding var renameDraft: String
    let isThreadPinned: (String) -> Bool
    let isThreadArchived: (String) -> Bool
    let onSelectThread: (ProjectThread) -> Void
    let onThreadAction: (ThreadAction, ProjectThread) -> Void
    let onCommitRename: (ProjectThread) -> Void

    @State private var collapsed = false
    /// Threads whose subagent rows are expanded. Subagents start collapsed so a
    /// busy chat doesn't flood the sidebar with nested rows by default.
    @State private var expandedSubagentThreadIDs: Set<String> = []

    private let nameIndent: CGFloat = SidebarMetrics.nameIndent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                collapsed.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .frame(width: 14, height: 18)
                    Text("Chats")
                        .font(.system(size: SidebarMetrics.bodyFont, weight: .semibold))
                        .foregroundStyle(CodexTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .padding(.vertical, SidebarMetrics.headerVertical)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .codexHover(cornerRadius: 0)
            .help(collapsed ? "Expand chats" : "Collapse chats")

            if !collapsed {
                ForEach(threads) { thread in
                    threadRow(thread)
                }
            }
        }
        .padding(.top, 5)
        .animation(CodexMotion.quickSpring, value: collapsed)
    }

    /// A chat row plus any subagent chats it spawned, nested beneath it.
    @ViewBuilder
    private func threadRow(_ thread: ProjectThread) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            singleThreadRow(thread)
            if !thread.subThreads.isEmpty {
                let expanded = expandedSubagentThreadIDs.contains(thread.id)
                subagentToggleRow(count: thread.subThreads.count,
                                  isExpanded: expanded,
                                  leadingInset: nameIndent) {
                    if expanded {
                        expandedSubagentThreadIDs.remove(thread.id)
                    } else {
                        expandedSubagentThreadIDs.insert(thread.id)
                    }
                }
                if expanded {
                    ForEach(thread.subThreads) { sub in
                        subagentRow(sub)
                    }
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
                    HStack(spacing: 6) {
                        if isThreadPinned(thread.id) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(CodexTheme.textTertiary)
                        }
                        Text(thread.title)
                            .font(.system(size: SidebarMetrics.bodyFont))
                            .foregroundStyle(isActive ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, isThreadPinned(thread.id) ? 0 : nameIndent)

                        Spacer(minLength: 8)

                        Text(thread.ageLabel)
                            .font(.system(size: SidebarMetrics.detailFont))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .fixedSize()
                    }
                    .padding(.horizontal, SidebarMetrics.rowHorizontal)
                    .padding(.vertical, SidebarMetrics.rowVertical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isActive ? CodexTheme.navHighlight : Color.clear)
                    .opacity(isThreadArchived(thread.id) ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .codexHover(cornerRadius: 0)
                .contextMenu { rowContextMenu(thread) }
                .onDrag {
                    NSItemProvider(object: SplitPaneDragPayload.thread(thread, project: nil) as NSString)
                }
            }
        }
        .id(thread.id)
    }

    @ViewBuilder
    private func subagentRow(_ thread: ProjectThread) -> some View {
        let isActive = activeThreadId == thread.id

        Button { onSelectThread(thread) } label: {
            HStack(spacing: 5) {
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
            .padding(.horizontal, SidebarMetrics.rowHorizontal)
            .padding(.vertical, SidebarMetrics.childVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? CodexTheme.navHighlight : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHover(cornerRadius: 0)
        .help(thread.title)
        .contextMenu { rowContextMenu(thread) }
        .onDrag {
            NSItemProvider(object: SplitPaneDragPayload.thread(thread, project: nil) as NSString)
        }
        .id(thread.id)
    }

    private func renameField(_ thread: ProjectThread) -> some View {
        TextField("", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: SidebarMetrics.bodyFont))
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.leading, nameIndent)
            .padding(.horizontal, SidebarMetrics.rowHorizontal)
            .padding(.vertical, SidebarMetrics.rowVertical)
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
        Button("Open in split view") { onThreadAction(.openInSplitView, thread) }
        Divider()
        Button("Delete", role: .destructive) { onThreadAction(.delete, thread) }
    }
}
