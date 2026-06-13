import SwiftUI

struct SidebarControlsBar: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Projects")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.textSecondary)

                Spacer(minLength: 0)

                viewSettingsMenu
                addProjectButton
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)

                TextField("Filter projects", text: Binding(
                    get: { model.sidebarProjectSearch },
                    set: { model.sidebarProjectSearch = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textPrimary)

                if !model.sidebarProjectSearch.isEmpty {
                    Button {
                        model.sidebarProjectSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(CodexTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexTheme.pillBackground)
            )
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