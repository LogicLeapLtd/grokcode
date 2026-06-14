import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var model

    /// Transient, view-local chat state. There is no Foundation-backed store for
    /// per-chat pin/archive, so these live with the view (reset on relaunch).
    @State private var pinnedThreadIDs: Set<String> = []
    @State private var archivedThreadIDs: Set<String> = []
    /// Inline-rename state (#27): the row being edited and its draft text.
    @State private var renamingThreadID: String?
    @State private var renameDraft: String = ""
    /// Live drag width so the resize feels immediate (committed to the model).
    @State private var dragStartWidth: Double?

    var body: some View {
        Group {
            if model.sidebarCollapsed {
                collapsedRail
            } else {
                expandedBody
            }
        }
        .frame(width: model.effectiveSidebarWidth)
        .background {
            // Translucent "liquid glass" sidebar that samples the desktop behind
            // the (non-opaque) window — see WindowConfigurator on ContentView.
            VisualEffectView(material: .sidebar)
                .overlay(CodexTheme.sidebarBackground.opacity(0.30))
                .overlay(CodexTheme.glassTint)
                .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            if !model.sidebarCollapsed { resizeHandle }
        }
        .animation(CodexMotion.expandSpring, value: model.sidebarCollapsed)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: model.sidebarWidth)
        .onChange(of: model.sidebarStatusFilter) { _, _ in model.persistSidebarPreferences() }
        .onChange(of: model.sidebarGroupBy) { _, _ in model.persistSidebarPreferences() }
        .onChange(of: model.sidebarSort) { _, _ in model.persistSidebarPreferences() }
    }

    // MARK: - Expanded sidebar

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)

            navSection
                .padding(.bottom, 14)

            projectsSection

            Spacer(minLength: 0)

            settingsButton
                .padding(.top, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 30)          // clearance for the traffic lights (full-size content)
        .padding(.bottom, 14)
    }

    /// Top-of-sidebar row with the collapse toggle (#23).
    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            collapseToggle
        }
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
        .help("Collapse sidebar")
    }

    private var navSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SidebarSection.allCases) { section in
                Button {
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
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.activeSidebarSection == section ? CodexTheme.navHighlight : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .codexHover()
                .animation(CodexMotion.quickSpring, value: model.activeSidebarSection)
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarControlsBar()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if model.sidebarGroupBy == .flatList {
                        flatThreadList
                    } else {
                        groupedProjectList
                    }
                }
                .padding(.top, 2)
                .padding(.trailing, 6)   // gutter so the scrollbar sits past the rows, not over them
                .animation(CodexMotion.expandSpring, value: model.sidebarProjectGroups.count)
                .animation(CodexMotion.expandSpring, value: model.projectsCollapsed)
                .animation(CodexMotion.expandSpring, value: model.collapsedProjectPaths)
            }
            .scrollIndicators(.visible)
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
                    isSelected: model.selectedProject?.id == project.id,
                    isPinned: model.isPinned(project),
                    collapsed: model.isProjectCollapsed(project),
                    groupByBranch: model.sidebarGroupBy == .projectBranch,
                    branchGroups: model.branchGroups(for: project),
                    collapsibleEnabled: model.collapsibleGroupsEnabled,
                    isBranchCollapsed: { model.isBranchCollapsed(project, branch: $0.branch) },
                    activeThreadId: model.activeSessionId,
                    renamingThreadID: $renamingThreadID,
                    renameDraft: $renameDraft,
                    isThreadPinned: { pinnedThreadIDs.contains($0) },
                    isThreadArchived: { archivedThreadIDs.contains($0) },
                    onSelectProject: { model.selectProject(project) },
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
                                .fill(model.activeSessionId == item.id ? CodexTheme.navHighlight : Color.clear)
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
            }
        }
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
                    help: section.title,
                    active: model.activeSidebarSection == section
                ) { handleNav(section) }
            }

            Spacer(minLength: 0)

            railButton(symbol: "gearshape", help: "Settings",
                       active: model.activePage == .settings) {
                model.navigateTo(.settings)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 30)
        .padding(.bottom, 14)
    }

    private func railButton(symbol: String, help: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(CodexTheme.textPrimary)
                .frame(width: 40, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? CodexTheme.navHighlight : Color.clear)
                )
                .codexHover(cornerRadius: 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
                        let start = dragStartWidth ?? model.sidebarWidth
                        if dragStartWidth == nil { dragStartWidth = start }
                        model.resizeSidebar(from: start, by: Double(value.translation.width))
                    }
                    .onEnded { _ in dragStartWidth = nil }
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
    let onToggleCollapse: () -> Void
    let onToggleBranchCollapse: (SidebarBranchGroup) -> Void
    let onSelectThread: (ProjectThread) -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void
    let onThreadAction: (ThreadAction, ProjectThread) -> Void
    let onCommitRename: (ProjectThread) -> Void

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

                        Text(project.displayName)
                            .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        // Always show a branch indicator; "none" when the project
                        // folder isn't a git repo, so it never implies a branch.
                        BranchChip(branch: project.gitBranch ?? "none")

                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 2)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? CodexTheme.navHighlight : Color.clear)
            )
            .contentShape(Rectangle())
            .codexHover(cornerRadius: 7)
            // Key the header's hover state to the project so a recycled row in
            // the LazyVStack can't retain a stale highlight from another project.
            .id(project.id)
            .animation(CodexMotion.quickSpring, value: collapsed)
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

    @ViewBuilder
    private func threadRow(_ thread: ProjectThread) -> some View {
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
