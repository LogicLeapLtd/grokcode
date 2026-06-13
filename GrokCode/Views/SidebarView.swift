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
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.sidebarGroupBy == .flatList {
                        flatThreadList
                    } else {
                        groupedProjectList
                    }
                }
                .animation(CodexMotion.expandSpring, value: model.sidebarProjectGroups.count)
                .animation(CodexMotion.expandSpring, value: model.sidebarFlatThreads.count)
                .animation(CodexMotion.expandSpring, value: model.selectedProject?.id)
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
                                    .font(.system(size: 12, weight: .medium))
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
                        .padding(.vertical, 5)
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
    let onSelectProject: () -> Void
    let onSelectThread: (ProjectThread) -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelectProject) {
                HStack(spacing: 7) {
                    Image(systemName: isPinned ? "pin.fill" : "folder")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 15)

                    Text(project.displayName)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? CodexTheme.navHighlight : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle(scale: 0.99))
            .contextMenu {
                Button(isPinned ? "Unpin" : "Pin", action: onTogglePin)
                Button("Archive", action: onArchive)
            }

            if project.threads.isEmpty {
                Text("No chats")
                    .font(CodexTheme.smallFont)
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.leading, 30)
                    .padding(.vertical, 2)
                    .padding(.bottom, 2)
            }

            if isSelected {
                ForEach(Array(project.threads.enumerated()), id: \.element.id) { index, thread in
                    Button {
                        onSelectThread(thread)
                    } label: {
                        HStack(spacing: 0) {
                            Text(thread.title)
                                .font(.system(size: 12))
                                .foregroundStyle(CodexTheme.textSecondary)
                                .lineLimit(1)
                                .padding(.leading, 22)

                            Spacer(minLength: 8)

                            Text(thread.ageLabel)
                                .font(CodexTheme.smallFont)
                                .foregroundStyle(CodexTheme.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CodexPressableStyle(scale: 0.99))
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .codexStaggeredAppear(index: index)
                }
            }
        }
        .animation(CodexMotion.expandSpring, value: isSelected)
        .animation(CodexMotion.expandSpring, value: project.threads.count)
    }
}