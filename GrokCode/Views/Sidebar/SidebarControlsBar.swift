import SwiftUI

struct SidebarControlsBar: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Text("Projects")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)

            Spacer(minLength: 0)

            viewSettingsMenu
            addProjectButton
        }
        .padding(.horizontal, 8)
    }

    private var isViewCustomized: Bool {
        model.sidebarStatusFilter != .all
            || model.sidebarGroupBy != .project
            || model.sidebarSort != .lastActive
    }

    private var viewSettingsMenu: some View {
        CodexMenuTrigger(minWidth: 220, edge: .bottom, highlightOnHover: false) { _ in
            controlIcon("slider.horizontal.3", isActive: isViewCustomized)
        } menu: { _ in
            CodexMenuContainer {
                CodexMenuSectionHeader(title: "Filter")
                ForEach(SidebarStatusFilter.allCases) { filter in
                    CodexMenuItem(title: filter.label, isSelected: model.sidebarStatusFilter == filter) {
                        model.sidebarStatusFilter = filter
                    }
                }
                CodexMenuDivider()
                CodexMenuSectionHeader(title: "Group by")
                ForEach(SidebarGroupBy.allCases) { mode in
                    CodexMenuItem(title: mode.label, isSelected: model.sidebarGroupBy == mode) {
                        model.sidebarGroupBy = mode
                    }
                }
                CodexMenuDivider()
                CodexMenuSectionHeader(title: "Sort")
                ForEach(SidebarSort.allCases) { sort in
                    CodexMenuItem(title: sort.label, isSelected: model.sidebarSort == sort) {
                        model.sidebarSort = sort
                    }
                }
            }
        }
        .help("View settings")
    }

    private var addProjectButton: some View {
        Button { model.addProjectFromPicker() } label: {
            controlIcon("plus", isActive: false)
        }
        .buttonStyle(.plain)
        .help("Add project folder")
    }

    private func controlIcon(_ symbol: String, isActive: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? CodexTheme.textPrimary : CodexTheme.textSecondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? CodexTheme.navHighlight : Color.clear)
            )
    }
}