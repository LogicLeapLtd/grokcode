import SwiftUI

struct SearchPageView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @Namespace private var scopeNamespace

    @State private var highlightedIndex: Int?
    @State private var hoveredIndex: Int?
    @State private var selectedScope: SearchScope = .all
    @State private var showAllProjects = false
    @State private var showAllSessions = false
    @State private var pageSettled = false

    private let collapsedLimit = 5

    private var allProjects: [Project] {
        Array(model.filteredProjects)
    }

    private var allSessions: [GrokSession] {
        Array(model.filteredSessions)
    }

    private var scopedProjects: [Project] {
        selectedScope.includesProjects ? allProjects : []
    }

    private var scopedSessions: [GrokSession] {
        selectedScope.includesSessions ? allSessions : []
    }

    private var visibleProjects: [Project] {
        Array(scopedProjects.prefix(showAllProjects ? scopedProjects.count : collapsedLimit))
    }

    private var visibleSessions: [GrokSession] {
        Array(scopedSessions.prefix(showAllSessions ? scopedSessions.count : collapsedLimit))
    }

    private var results: [AppViewModel.SearchResult] {
        visibleProjects.map { .project($0) } + visibleSessions.map { .session($0) }
    }

    private var totalResultCount: Int {
        allProjects.count + allSessions.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            PageScaffold(maxWidth: 900, horizontalPadding: 36, topPadding: 34, bottomPadding: 92, spacing: 14) {
                header
                    .searchResultReveal(index: 0)

                searchField
                    .searchResultReveal(index: 1)

                scopeStrip
                    .searchResultReveal(index: 2)

                resultsList
                    .searchResultReveal(index: 3)
            }
            .onAppear {
                isFocused = true
                resetHighlight()
                withAnimation(reduceMotion ? nil : CodexMotion.panelSpring.delay(0.03)) {
                    pageSettled = true
                }
            }
            .task { await model.loadCLISessionsIfNeeded() }
            .onChange(of: model.searchQuery) { _, _ in
                showAllProjects = false
                showAllSessions = false
                resetHighlight()
            }
            .onChange(of: selectedScope) { _, _ in
                showAllProjects = false
                showAllSessions = false
                resetHighlight()
            }
            .onChange(of: highlightedIndex) { _, new in
                guard let new, results.indices.contains(new) else { return }
                withAnimation(reduceMotion ? nil : CodexMotion.quickSpring) {
                    proxy.scrollTo(results[new].id, anchor: .center)
                }
            }
        }
        .opacity(pageSettled ? 1 : 0)
    }

    // MARK: - Layout

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Search")
                    .font(CodexTheme.headlineFont)
                    .foregroundStyle(CodexTheme.textPrimary)

                Text("Find projects, sessions, branches and previous work without digging through the sidebar.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Text("\(totalResultCount) indexed")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.68)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isFocused ? CodexTheme.focusAccent : CodexTheme.textSecondary)
                .frame(width: 18)

            TextField("", text: Binding(
                get: { model.searchQuery },
                set: { model.searchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15.5, weight: .medium))
            .focused($isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .placeholderOverlay("Search projects, sessions, paths and branches", visible: model.searchQuery.isEmpty, font: .system(size: 15.5, weight: .medium))
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
                resetHighlight()
                return .handled
            }

            if !model.searchQuery.isEmpty {
                Button {
                    model.clearSearch()
                    showAllProjects = false
                    showAllSessions = false
                    resetHighlight()
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .codexHoverOverlay(Circle())
                .help("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            interactive: true,
            tint: isFocused ? CodexTheme.accent.opacity(0.04) : nil,
            fallback: CodexTheme.composerBackground.opacity(0.80)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFocused ? CodexTheme.focusAccent.opacity(0.42) : CodexTheme.composerBorder.opacity(0.72), lineWidth: 1)
        )
        .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: isFocused)
    }

    private var scopeStrip: some View {
        HStack(spacing: 6) {
            ForEach(SearchScope.allCases) { scope in
                scopeButton(scope)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CodexTheme.pillBackground.opacity(0.58))
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var resultsList: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if !visibleProjects.isEmpty {
                resultsSection(
                    title: "Projects",
                    systemImage: "folder",
                    count: allProjects.count,
                    visibleCount: visibleProjects.count,
                    canToggle: scopedProjects.count > collapsedLimit,
                    showingAll: showAllProjects,
                    onToggle: { toggleProjects() }
                ) {
                    ForEach(Array(visibleProjects.enumerated()), id: \.element.id) { offset, project in
                        let index = offset
                        ProjectResultRow(project: project, highlighted: isHighlighted(index))
                            .id(AppViewModel.SearchResult.project(project).id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(at: index) }
                            .onHover { hovering in updateHover(index, hovering: hovering) }
                            .searchResultReveal(index: offset)
                    }
                }
            }

            if !visibleSessions.isEmpty {
                resultsSection(
                    title: "Sessions",
                    systemImage: "bubble.left.and.bubble.right",
                    count: allSessions.count,
                    visibleCount: visibleSessions.count,
                    canToggle: scopedSessions.count > collapsedLimit,
                    showingAll: showAllSessions,
                    onToggle: { toggleSessions() }
                ) {
                    ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { offset, session in
                        let index = visibleProjects.count + offset
                        SessionResultRow(
                            session: session,
                            projectName: model.projectName(forSessionID: session.id),
                            dateLabel: model.searchAgeLabel(for: session.updated ?? session.created),
                            highlighted: isHighlighted(index)
                        )
                        .id(AppViewModel.SearchResult.session(session).id)
                        .contentShape(Rectangle())
                        .onTapGesture { open(at: index) }
                        .onHover { hovering in updateHover(index, hovering: hovering) }
                        .searchResultReveal(index: offset + visibleProjects.count)
                    }
                }
            }

            if results.isEmpty {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: selectedScope)
        .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: showAllProjects)
        .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: showAllSessions)
        .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: model.searchQuery)
    }

    private var emptyState: some View {
        let title: String
        let message: String

        if model.searchQuery.isEmpty {
            title = selectedScope.emptyTitle
            message = "Indexed projects and sessions will appear here."
        } else {
            title = "No matches"
            message = "Nothing matched \"\(model.searchQuery)\" in \(selectedScope.emptySearchContext)."
        }

        return EmptySearchState(
            systemImage: selectedScope.emptySystemImage,
            title: title,
            message: message
        )
    }

    private func scopeButton(_ scope: SearchScope) -> some View {
        let selected = selectedScope == scope
        return Button {
            withAnimation(reduceMotion ? nil : CodexMotion.quickSpring) {
                selectedScope = scope
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scope.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(scope.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                Text("\(count(for: scope))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? CodexTheme.textSecondary : CodexTheme.textTertiary)
            }
            .foregroundStyle(selected ? CodexTheme.textPrimary : CodexTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CodexTheme.navHighlight)
                        .matchedGeometryEffect(id: "search-scope-selection", in: scopeNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .codexHoverOverlay(cornerRadius: 8)
    }

    private func count(for scope: SearchScope) -> Int {
        switch scope {
        case .all: totalResultCount
        case .projects: allProjects.count
        case .sessions: allSessions.count
        }
    }

    // MARK: - Highlight state

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
            hoveredIndex = nil
        }
    }

    private func moveHighlight(by delta: Int) {
        let count = results.count
        guard count > 0 else { highlightedIndex = nil; return }

        let base = hoveredIndex ?? highlightedIndex
        hoveredIndex = nil
        let current = base ?? (delta > 0 ? -1 : count)
        highlightedIndex = min(max(current + delta, 0), count - 1)
    }

    private func resetHighlight() {
        highlightedIndex = results.isEmpty ? nil : 0
        hoveredIndex = nil
    }

    private func open(at index: Int) {
        let current = results
        guard current.indices.contains(index) else { return }
        model.openSearchResult(current[index])
    }

    private func toggleProjects() {
        withAnimation(reduceMotion ? nil : CodexMotion.quickSpring) {
            showAllProjects.toggle()
            resetHighlight()
        }
    }

    private func toggleSessions() {
        withAnimation(reduceMotion ? nil : CodexMotion.quickSpring) {
            showAllSessions.toggle()
            resetHighlight()
        }
    }

    @ViewBuilder
    private func resultsSection<Content: View>(
        title: String,
        systemImage: String,
        count: Int,
        visibleCount: Int,
        canToggle: Bool,
        showingAll: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)

                CountBadge(text: "\(visibleCount) of \(count)")

                Spacer(minLength: 10)

                if canToggle {
                    Button(action: onToggle) {
                        HStack(spacing: 4) {
                            Text(showingAll ? "Fewer" : "All")
                            Image(systemName: showingAll ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.focusAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.68)))
                    }
                    .buttonStyle(CodexPressableStyle(scale: 0.98))
                    .codexHoverOverlay(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(CodexTheme.divider.opacity(0.50))
                .frame(height: 1)

            VStack(spacing: 1) {
                content()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            fallback: CodexTheme.composerBackground.opacity(0.42)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder.opacity(0.52), lineWidth: 1)
        )
    }
}

// MARK: - Search scope

private enum SearchScope: String, CaseIterable, Identifiable {
    case all
    case projects
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .projects: "Projects"
        case .sessions: "Sessions"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .projects: "folder"
        case .sessions: "bubble.left.and.bubble.right"
        }
    }

    var includesProjects: Bool {
        self == .all || self == .projects
    }

    var includesSessions: Bool {
        self == .all || self == .sessions
    }

    var emptyTitle: String {
        switch self {
        case .all: "Nothing indexed yet"
        case .projects: "No projects indexed"
        case .sessions: "No sessions indexed"
        }
    }

    var emptySearchContext: String {
        switch self {
        case .all: "projects or sessions"
        case .projects: "projects"
        case .sessions: "sessions"
        }
    }

    var emptySystemImage: String {
        switch self {
        case .all: "magnifyingglass"
        case .projects: "folder.badge.questionmark"
        case .sessions: "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Rows

private struct ProjectResultRow: View {
    let project: Project
    let highlighted: Bool

    private var pathTail: String {
        let parts = project.path.path.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    var body: some View {
        HStack(spacing: 9) {
            ResultIconTile(systemImage: "folder", highlighted: highlighted)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(pathTail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !project.threads.isEmpty {
                        Text("\(project.threads.count) chat\(project.threads.count == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                    }

                    if let branch = project.gitBranch, !branch.isEmpty {
                        SearchMetadataPill(text: branch, systemImage: "arrow.triangle.branch")
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(highlighted ? CodexTheme.hoverBackground : Color.clear)
    }
}

private struct SessionResultRow: View {
    let session: GrokSession
    let projectName: String?
    let dateLabel: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 9) {
            ResultIconTile(systemImage: "bubble.left.and.bubble.right", highlighted: highlighted)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.summary)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let projectName {
                        Label(projectName, systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                    }

                    if !dateLabel.isEmpty {
                        Label(dateLabel, systemImage: "clock")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(highlighted ? CodexTheme.hoverBackground : Color.clear)
        )
    }
}

private struct ResultIconTile: View {
    let systemImage: String
    let highlighted: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(highlighted ? CodexTheme.focusAccent : CodexTheme.textSecondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(CodexTheme.pillBackground.opacity(highlighted ? 0.82 : 0.52))
            )
    }
}

private struct CountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CodexTheme.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.46)))
    }
}

private struct SearchMetadataPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(CodexTheme.textTertiary)
    }
}

private struct EmptySearchState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(CodexTheme.textTertiary)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexTheme.textPrimary)

            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(CodexTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(20)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            fallback: CodexTheme.composerBackground.opacity(0.34)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder.opacity(0.48), lineWidth: 1)
        )
    }
}

// MARK: - Animation helpers

private struct SearchResultReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 5)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(CodexMotion.panelSpring.delay(min(Double(index) * 0.018, 0.10))) {
                        appeared = true
                    }
                }
            }
    }
}

private extension View {
    func searchResultReveal(index: Int) -> some View {
        modifier(SearchResultReveal(index: index))
    }
}
