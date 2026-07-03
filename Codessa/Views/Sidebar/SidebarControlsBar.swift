import SwiftUI

struct SidebarControlsBar: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            // #21 — larger, heavier "Projects" header so the chat column reads
            // as a titled section rather than a faint caption.
            Text("Projects")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CodexTheme.textSecondary)

            Spacer(minLength: 0)

            collapseButton
            organizeMenu
            addProjectButton
        }
        .padding(.horizontal, 8)
    }

    private var collapseButton: some View {
        Button { model.toggleProjectsCollapsed() } label: {
            controlIcon(model.allProjectsCollapsed
                        ? "arrow.up.left.and.arrow.down.right"
                        : "arrow.down.right.and.arrow.up.left")
        }
        .buttonStyle(.plain)
        .help(model.allProjectsCollapsed ? "Expand all projects" : "Collapse all projects")
    }

    private var organizeMenu: some View {
        CodexMenuTrigger(minWidth: 210, edge: .bottom, highlightOnHover: false,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "organize") { _ in
            controlIcon("ellipsis")
        } menu: { close in
            CodexMenuContainer {
                CodexMenuItem(title: "Archive all chats", systemImage: "archivebox") {
                    model.archiveAllProjects(); close()
                }
                CodexMenuDivider()
                CodexFlyoutItem(title: "Organize sidebar", systemImage: "square.stack") {
                    ForEach(SidebarGroupBy.allCases) { mode in
                        CodexMenuItem(
                            title: mode.label,
                            systemImage: mode.symbol,
                            isSelected: model.sidebarGroupBy == mode
                        ) {
                            model.sidebarGroupBy = mode
                            model.persistSidebarPreferences()
                            close()
                        }
                    }
                }
                CodexFlyoutItem(title: "Sort by", systemImage: "clock") {
                    ForEach(SidebarSort.codexCases) { sort in
                        CodexMenuItem(
                            title: sort.label,
                            systemImage: sort.symbol,
                            isSelected: model.sidebarSort == sort
                        ) {
                            model.sidebarSort = sort
                            model.persistSidebarPreferences()
                            close()
                        }
                    }
                }
            }
        }
        .help("Sidebar options")
    }

    private var addProjectButton: some View {
        Button { model.addProjectFromPicker() } label: {
            controlIcon("folder.badge.plus")
        }
        .buttonStyle(.plain)
        .help("Add project folder")
    }

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(CodexTheme.textSecondary)
            .frame(width: 26, height: 24)
            .codexHover(cornerRadius: 6)
            .contentShape(Rectangle())
    }
}
