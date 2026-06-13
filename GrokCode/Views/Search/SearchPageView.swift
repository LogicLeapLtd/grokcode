import SwiftUI

struct SearchPageView: View {
    @Environment(AppViewModel.self) private var model
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Search")
                .font(CodexTheme.headlineFont)
                .foregroundStyle(CodexTheme.textPrimary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CodexTheme.textSecondary)
                TextField("", text: Binding(
                    get: { model.searchQuery },
                    set: { model.searchQuery = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .placeholderOverlay("Search projects and sessions", visible: model.searchQuery.isEmpty, font: .system(size: 16))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodexTheme.composerBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !model.filteredProjects.isEmpty {
                        resultsSection("Projects") {
                            ForEach(model.filteredProjects.prefix(12)) { project in
                                Button {
                                    model.selectProject(project)
                                } label: {
                                    Text(project.name)
                                        .font(.system(size: 16))
                                        .foregroundStyle(CodexTheme.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 3)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(CodexPressableStyle())
                            }
                        }
                    }

                    if !model.filteredSessions.isEmpty {
                        resultsSection("Sessions") {
                            ForEach(model.filteredSessions.prefix(12)) { session in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.summary)
                                        .font(.system(size: 16))
                                        .foregroundStyle(CodexTheme.textPrimary)
                                        .lineLimit(2)
                                    Text(session.id)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(CodexTheme.textTertiary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    if model.searchQuery.isEmpty {
                        Text("Type to search projects and Grok sessions")
                            .font(.system(size: 14))
                            .foregroundStyle(CodexTheme.textTertiary)
                    }
                }
            }
        }
        .padding(48)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.mainBackground)
        .onAppear { isFocused = true }
    }

    @ViewBuilder
    private func resultsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CodexTheme.textSecondary)
            content()
        }
    }
}
