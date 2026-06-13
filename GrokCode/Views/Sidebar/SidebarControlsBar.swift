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
        Menu {
            Section("Filter") {
                ForEach(SidebarStatusFilter.allCases) { filter in
                    Button {
                        model.sidebarStatusFilter = filter
                    } label: {
                        if model.sidebarStatusFilter == filter {
                            Label(filter.label, systemImage: "checkmark")
                        } else {
                            Text(filter.label)
                        }
                    }
                }
            }

            Section("Group by") {
                ForEach(SidebarGroupBy.allCases) { mode in
                    Button {
                        model.sidebarGroupBy = mode
                    } label: {
                        if model.sidebarGroupBy == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            }

            Section("Sort") {
                ForEach(SidebarSort.allCases) { sort in
                    Button {
                        model.sidebarSort = sort
                    } label: {
                        if model.sidebarSort == sort {
                            Label(sort.label, systemImage: "checkmark")
                        } else {
                            Text(sort.label)
                        }
                    }
                }
            }
        } label: {
            controlIcon("slider.horizontal.3", isActive: isViewCustomized)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
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