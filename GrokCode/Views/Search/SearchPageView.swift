import SwiftUI

struct SearchPageView: View {
    @Environment(AppViewModel.self) private var model
    @FocusState private var isFocused: Bool

    /// Index into `model.searchResults()` of the keyboard-highlighted row, or
    /// `nil` when nothing is highlighted (e.g. an empty query). Up/Down move it,
    /// Return opens it.
    @State private var highlightedIndex: Int?

    /// Index of the row the cursor is *currently* over, or `nil` when the cursor
    /// is over no row. This is kept separate from `highlightedIndex` (keyboard)
    /// so a hover highlight can NEVER stick after the mouse leaves: every row
    /// resets this on `onHover(false)`, and the active query/result identity is
    /// what each row matches against, so a stale index can't paint a phantom
    /// highlight on a different row.
    @State private var hoveredIndex: Int?

    private let projectLimit = 12
    private let sessionLimit = 12

    private var results: [AppViewModel.SearchResult] {
        model.searchResults(projectLimit: projectLimit, sessionLimit: sessionLimit)
    }

    var body: some View {
        PageScaffold(maxWidth: 720, scrolls: false) {
            Text("Search")
                .font(CodexTheme.headlineFont)
                .foregroundStyle(CodexTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            searchField

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        let projects = Array(model.filteredProjects.prefix(projectLimit))
                        let sessions = Array(model.filteredSessions.prefix(sessionLimit))

                        if !projects.isEmpty {
                            resultsSection("Projects") {
                                ForEach(Array(projects.enumerated()), id: \.element.id) { offset, project in
                                    let index = offset
                                    ProjectResultRow(project: project, highlighted: isHighlighted(index))
                                        .id(AppViewModel.SearchResult.project(project).id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { open(at: index) }
                                        .onHover { hovering in
                                            updateHover(index, hovering: hovering)
                                        }
                                }
                            }
                        }

                        if !sessions.isEmpty {
                            resultsSection("Sessions") {
                                ForEach(Array(sessions.enumerated()), id: \.element.id) { offset, session in
                                    let index = projects.count + offset
                                    SessionResultRow(
                                        session: session,
                                        projectName: model.projectName(forSessionID: session.id),
                                        dateLabel: model.searchAgeLabel(for: session.updated ?? session.created),
                                        highlighted: isHighlighted(index)
                                    )
                                    .id(AppViewModel.SearchResult.session(session).id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { open(at: index) }
                                    .onHover { hovering in
                                        updateHover(index, hovering: hovering)
                                    }
                                }
                            }
                        }

                        if model.searchQuery.isEmpty {
                            Text("Type to search projects and Grok sessions")
                                .font(.system(size: 14))
                                .foregroundStyle(CodexTheme.textTertiary)
                        } else if results.isEmpty {
                            Text("No matches for “\(model.searchQuery)”")
                                .font(.system(size: 14))
                                .foregroundStyle(CodexTheme.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: highlightedIndex) { _, new in
                    guard let new, results.indices.contains(new) else { return }
                    withAnimation(CodexMotion.quickSpring) {
                        proxy.scrollTo(results[new].id, anchor: .center)
                    }
                }
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: model.searchQuery) { _, _ in
            // Reset the highlight to the first result whenever the query changes,
            // so Return after typing opens the top hit. Also drop any stale hover
            // index — the rows underneath the cursor have changed identity.
            highlightedIndex = results.isEmpty ? nil : 0
            hoveredIndex = nil
        }
    }

    // MARK: Highlight state

    /// A row is highlighted when the cursor is actively over it, OR (when the
    /// cursor is over nothing) when it's the keyboard-selected row. Active hover
    /// always wins so the pointer's row lights up immediately; once the cursor
    /// leaves every row, `hoveredIndex` is `nil` and we fall back to keyboard.
    private func isHighlighted(_ index: Int) -> Bool {
        if let hoveredIndex {
            return hoveredIndex == index
        }
        return highlightedIndex == index
    }

    private func updateHover(_ index: Int, hovering: Bool) {
        if hovering {
            hoveredIndex = index
        } else if hoveredIndex == index {
            // Only clear if we're the row that was last marked hovered. This
            // avoids a race in Lazy/stacked containers where an enter event for
            // the next row arrives before the exit event for the previous one.
            hoveredIndex = nil
        }
    }

    // MARK: Field

    private var searchField: some View {
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
            .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
            .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
            .onKeyPress(.return) {
                if let index = highlightedIndex {
                    open(at: index)
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                if model.searchQuery.isEmpty { return .ignored }
                model.clearSearch()
                highlightedIndex = nil
                hoveredIndex = nil
                return .handled
            }

            if !model.searchQuery.isEmpty {
                Button {
                    model.clearSearch()
                    highlightedIndex = nil
                    hoveredIndex = nil
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search (Esc)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTheme.composerBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
    }

    // MARK: Keyboard helpers

    private func moveHighlight(by delta: Int) {
        let count = results.count
        guard count > 0 else { highlightedIndex = nil; return }
        // Keyboard nav takes over from wherever the cursor last was, then the
        // pointer is no longer the source of truth until it moves again.
        let base = hoveredIndex ?? highlightedIndex
        hoveredIndex = nil
        let current = base ?? (delta > 0 ? -1 : count)
        let next = min(max(current + delta, 0), count - 1)
        highlightedIndex = next
    }

    private func open(at index: Int) {
        let current = results
        guard current.indices.contains(index) else { return }
        model.openSearchResult(current[index])
    }

    @ViewBuilder
    private func resultsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CodexTheme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

private struct ProjectResultRow: View {
    let project: Project
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Text(project.path.path)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let branch = project.gitBranch {
                branchChip(branch)
            }
            if !project.threads.isEmpty {
                Text("\(project.threads.count) chat\(project.threads.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(highlighted ? CodexTheme.navHighlight : .clear)
    }

    private func branchChip(_ branch: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .medium))
            Text(branch)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(CodexTheme.textTertiary)
    }
}

private struct SessionResultRow: View {
    let session: GrokSession
    let projectName: String?
    let dateLabel: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let projectName {
                        Label(projectName, systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                        dot
                    }
                    if !dateLabel.isEmpty {
                        Text(dateLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(CodexTheme.textTertiary)
                        dot
                    }
                    Text(session.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? CodexTheme.navHighlight : .clear)
        )
    }

    private var dot: some View {
        Text("·")
            .font(.system(size: 11))
            .foregroundStyle(CodexTheme.textTertiary)
    }
}
