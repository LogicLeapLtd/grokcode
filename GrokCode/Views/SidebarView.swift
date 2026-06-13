import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navSection
                .padding(.bottom, 10)

            Rectangle()
                .fill(CodexTheme.divider)
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)

            projectsSection

            Spacer(minLength: 0)

            settingsButton
                .padding(.top, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(width: CodexTheme.sidebarWidth)
        .background(CodexTheme.sidebarBackground)
        .onChange(of: model.sidebarStatusFilter) { _, _ in model.persistSidebarPreferences() }
        .onChange(of: model.sidebarGroupBy) { _, _ in model.persistSidebarPreferences() }
        .onChange(of: model.sidebarSort) { _, _ in model.persistSidebarPreferences() }
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
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.activeSidebarSection == section ? CodexTheme.navHighlight : Color.clear)
                    )
                    .codexHover()
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle(scale: 0.98))
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
                .animation(CodexMotion.expandSpring, value: model.sidebarProjectGroups.count)
                .animation(CodexMotion.expandSpring, value: model.projectsCollapsed)
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
                    isSelected: model.selectedProject?.id == project.id,
                    isPinned: model.isPinned(project),
                    collapsed: model.projectsCollapsed,
                    activeThreadId: model.activeSessionId,
                    onSelectProject: { model.selectProject(project) },
                    onSelectThread: { thread in
                        model.selectThread(thread, in: project)
                    },
                    onTogglePin: { model.togglePinProject(project) },
                    onArchive: { model.archiveProject(project) }
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
                                Spacer(minLength: 8)
                                Text(item.ageLabel)
                                    .font(CodexTheme.smallFont)
                                    .foregroundStyle(CodexTheme.textTertiary)
                            }

                            Text(item.project.name)
                                .font(CodexTheme.smallFont)
                                .foregroundStyle(CodexTheme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(model.activeSessionId == item.id ? CodexTheme.navHighlight : Color.clear)
                        )
                        .codexHover(cornerRadius: 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CodexPressableStyle(scale: 0.99))
                }
            }
        }
    }

    private var settingsButton: some View {
        Button {
            model.openSettings()
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
            .codexHover()
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle(scale: 0.98))
    }

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
}

private struct ProjectSidebarBlock: View {
    let project: Project
    let isSelected: Bool
    let isPinned: Bool
    let collapsed: Bool
    let activeThreadId: String?
    let onSelectProject: () -> Void
    let onSelectThread: (ProjectThread) -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void

    // Folder icon (16) + spacing (8) + row inset (8) → align sub-rows under the name.
    private let nameIndent: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
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
                        .layoutPriority(1)

                    if let branch = project.gitBranch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9, weight: .medium))
                            Text(branch)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(CodexTheme.textTertiary)
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? CodexTheme.navHighlight : Color.clear)
                )
                .codexHover(cornerRadius: 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle(scale: 0.99))
            .contextMenu {
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
                } else {
                    ForEach(project.threads) { thread in
                        threadRow(thread)
                    }
                }
            }
        }
        .padding(.bottom, collapsed ? 0 : 4)
    }

    private func threadRow(_ thread: ProjectThread) -> some View {
        let isActive = activeThreadId == thread.id
        return Button { onSelectThread(thread) } label: {
            HStack(spacing: 8) {
                Text(thread.title)
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, nameIndent)

                Spacer(minLength: 8)

                Text(thread.ageLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? CodexTheme.navHighlight : Color.clear)
            )
            .codexHover(cornerRadius: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle(scale: 0.99))
    }
}