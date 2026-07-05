import SwiftUI

struct SearchPageView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @Namespace private var scopeNamespace

    /// Index into the visible result list of the keyboard-highlighted row.
    @State private var highlightedIndex: Int?
    /// Pointer hover is tracked separately so a hover highlight cannot stick
    /// after the cursor leaves a row.
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

    private var branchCount: Int {
        Set(allProjects.compactMap(\.gitBranch).filter { !$0.isEmpty }).count
    }

    private var totalResultCount: Int {
        allProjects.count + allSessions.count
    }

    var body: some View {
        PageScaffold(maxWidth: 980, horizontalPadding: 32, topPadding: 30, bottomPadding: 28, spacing: 16, scrolls: false) {
            hero
                .opacity(pageSettled ? 1 : 0)
                .offset(y: pageSettled ? 0 : -8)

            searchField
                .opacity(pageSettled ? 1 : 0)
                .offset(y: pageSettled ? 0 : 8)

            workspace
                .opacity(pageSettled ? 1 : 0)
                .offset(y: pageSettled ? 0 : 14)
        }
        .onAppear {
            isFocused = true
            resetHighlight()
            withAnimation(reduceMotion ? nil : CodexMotion.panelSpring.delay(0.04)) {
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
    }

    // MARK: - Layout

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CodexTheme.accent.opacity(0.14))
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CodexTheme.focusAccent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text("Search")
                    .font(CodexTheme.headlineFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                Text("Projects, sessions, branches and previous work in one focused surface.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            SearchStatusPill(
                title: model.searchQuery.isEmpty ? "Indexed" : "Matching",
                value: "\(totalResultCount)",
                systemImage: model.searchQuery.isEmpty ? "tray.full" : "line.3.horizontal.decrease.circle"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            fallback: CodexTheme.composerBackground.opacity(0.48)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder.opacity(0.62), lineWidth: 1)
        )
    }

    private var workspace: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                searchRail
                    .frame(width: 192)
                resultsWorkspace
                    .frame(minWidth: 430, maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 14) {
                compactScopeStrip
                compactMetricStrip
                resultsWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var searchRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scope")
                    .font(CodexTheme.sectionLabelFont)
                    .foregroundStyle(CodexTheme.textTertiary)
                    .textCase(.uppercase)

                VStack(spacing: 6) {
                    ForEach(SearchScope.allCases) { scope in
                        scopeButton(scope, layout: .vertical)
                    }
                }
            }

            Rectangle()
                .fill(CodexTheme.divider.opacity(0.64))
                .frame(height: 1)

            VStack(spacing: 8) {
                SearchMetricTile(title: "Projects", value: "\(allProjects.count)", systemImage: "folder")
                SearchMetricTile(title: "Sessions", value: "\(allSessions.count)", systemImage: "bubble.left.and.bubble.right")
                SearchMetricTile(title: "Branches", value: "\(branchCount)", systemImage: "arrow.triangle.branch")
            }
        }
        .padding(14)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: CodexTheme.composerBackground.opacity(0.38)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder.opacity(0.52), lineWidth: 1)
        )
    }

    private var compactScopeStrip: some View {
        HStack(spacing: 6) {
            ForEach(SearchScope.allCases) { scope in
                scopeButton(scope, layout: .horizontal)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CodexTheme.pillBackground.opacity(0.72))
        )
    }

    private var compactMetricStrip: some View {
        HStack(spacing: 8) {
            SearchMetricTile(title: "Projects", value: "\(allProjects.count)", systemImage: "folder")
            SearchMetricTile(title: "Sessions", value: "\(allSessions.count)", systemImage: "bubble.left.and.bubble.right")
            SearchMetricTile(title: "Branches", value: "\(branchCount)", systemImage: "arrow.triangle.branch")
        }
    }

    private var resultsWorkspace: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: selectedScope)
            .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: showAllProjects)
            .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: showAllSessions)
            .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: model.searchQuery)
            .onChange(of: highlightedIndex) { _, new in
                guard let new, results.indices.contains(new) else { return }
                withAnimation(reduceMotion ? nil : CodexMotion.quickSpring) {
                    proxy.scrollTo(results[new].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        let title: String
        let message: String

        if model.searchQuery.isEmpty {
            title = selectedScope.emptyTitle
            message = "Codessa will surface indexed projects, saved sessions and branch context here."
        } else {
            title = "No matches"
            message = "Nothing matched \"\(model.searchQuery)\" in \(selectedScope.emptySearchContext)."
        }

        return EmptySearchState(
            systemImage: selectedScope.emptySystemImage,
            title: title,
            message: message
        )
        .searchResultReveal(index: 0)
    }

    private func scopeButton(_ scope: SearchScope, layout: ScopeButtonLayout) -> some View {
        let selected = selectedScope == scope
        return Button {
            withAnimation(reduceMotion ? nil : CodexMotion.quickSpring) {
                selectedScope = scope
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: scope.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(scope.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                if layout == .vertical {
                    Spacer(minLength: 4)
                }
                Text("\(count(for: scope))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? CodexTheme.textPrimary : CodexTheme.textTertiary)
            }
            .foregroundStyle(selected ? CodexTheme.textPrimary : CodexTheme.textSecondary)
            .padding(.horizontal, layout == .vertical ? 10 : 11)
            .padding(.vertical, 8)
            .frame(maxWidth: layout == .vertical ? .infinity : nil, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CodexTheme.navHighlight)
                        .matchedGeometryEffect(id: "search-scope-selection", in: scopeNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .codexHoverOverlay(cornerRadius: 10)
    }

    private func count(for scope: SearchScope) -> Int {
        switch scope {
        case .all: totalResultCount
        case .projects: allProjects.count
        case .sessions: allSessions.count
        }
    }

    // MARK: - Field

    private var searchField: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isFocused ? CodexTheme.accent.opacity(0.18) : CodexTheme.pillBackground.opacity(0.86))
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isFocused ? CodexTheme.focusAccent : CodexTheme.textSecondary)
            }
            .frame(width: 30, height: 30)

            TextField("", text: Binding(
                get: { model.searchQuery },
                set: { model.searchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .focused($isFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .placeholderOverlay("Search projects, sessions, paths and branches", visible: model.searchQuery.isEmpty, font: .system(size: 17, weight: .medium))
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
                        .font(.system(size: 15))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .codexHoverOverlay(Circle())
                .help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            interactive: true,
            tint: isFocused ? CodexTheme.accent.opacity(0.08) : nil,
            fallback: CodexTheme.composerBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isFocused ? CodexTheme.focusAccent.opacity(0.74) : CodexTheme.composerBorder, lineWidth: isFocused ? 1.25 : 1)
        )
        .shadow(color: isFocused ? CodexTheme.accent.opacity(0.20) : .clear, radius: 18, y: 6)
        .animation(reduceMotion ? nil : CodexMotion.quickSpring, value: isFocused)
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
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CodexTheme.pillBackground.opacity(0.75))
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexTheme.textSecondary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("\(visibleCount) of \(count)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(CodexTheme.textTertiary)
                }

                Spacer(minLength: 10)

                if canToggle {
                    Button(action: onToggle) {
                        HStack(spacing: 5) {
                            Text(showingAll ? "Fewer" : "All")
                            Image(systemName: showingAll ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexTheme.focusAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.70)))
                        .overlay(Capsule().strokeBorder(CodexTheme.composerBorder.opacity(0.45), lineWidth: 0.75))
                    }
                    .buttonStyle(CodexPressableStyle(scale: 0.97))
                    .codexHoverOverlay(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(CodexTheme.divider.opacity(0.55))
                .frame(height: 1)

            VStack(spacing: 4) {
                content()
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: CodexTheme.composerBackground.opacity(0.42)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder.opacity(0.56), lineWidth: 1)
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

private enum ScopeButtonLayout {
    case vertical
    case horizontal
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
        HStack(spacing: 12) {
            ResultIconTile(systemImage: "folder", highlighted: highlighted)

            VStack(alignment: .leading, spacing: 5) {
                Text(project.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(pathTail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !project.threads.isEmpty {
                        SearchMetadataPill(text: "\(project.threads.count) chat\(project.threads.count == 1 ? "" : "s")", systemImage: "text.bubble")
                    }
                    if let branch = project.gitBranch, !branch.isEmpty {
                        SearchMetadataPill(text: branch, systemImage: "arrow.triangle.branch")
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(highlighted ? CodexTheme.focusAccent : CodexTheme.textTertiary.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(rowBorder)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(highlighted ? CodexTheme.navHighlight : Color.clear)
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(highlighted ? CodexTheme.focusAccent.opacity(0.38) : Color.clear, lineWidth: 1)
    }
}

private struct SessionResultRow: View {
    let session: GrokSession
    let projectName: String?
    let dateLabel: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            ResultIconTile(systemImage: "bubble.left.and.bubble.right", highlighted: highlighted)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let projectName {
                        SearchMetadataPill(text: projectName, systemImage: "folder")
                    }
                    if !dateLabel.isEmpty {
                        SearchMetadataPill(text: dateLabel, systemImage: "clock")
                    }
                    Text(session.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(highlighted ? CodexTheme.focusAccent : CodexTheme.textTertiary.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(highlighted ? CodexTheme.navHighlight : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(highlighted ? CodexTheme.focusAccent.opacity(0.38) : Color.clear, lineWidth: 1)
        )
    }
}

private struct ResultIconTile: View {
    let systemImage: String
    let highlighted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(highlighted ? CodexTheme.accent.opacity(0.18) : CodexTheme.pillBackground.opacity(0.72))
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(highlighted ? CodexTheme.focusAccent : CodexTheme.textSecondary)
        }
        .frame(width: 34, height: 34)
    }
}

private struct SearchMetadataPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(CodexTheme.textTertiary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.54)))
    }
}

private struct SearchMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTheme.pillBackground.opacity(0.42))
        )
    }
}

private struct SearchStatusPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .textCase(.uppercase)
            }
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.64)))
        .overlay(Capsule().strokeBorder(CodexTheme.composerBorder.opacity(0.42), lineWidth: 0.75))
    }
}

private struct EmptySearchState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CodexTheme.pillBackground.opacity(0.62))
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .frame(width: 56, height: 56)

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexTheme.textPrimary)

            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(CodexTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(24)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: CodexTheme.composerBackground.opacity(0.34)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder.opacity(0.52), lineWidth: 1)
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
            .offset(y: appeared ? 0 : 8)
            .blur(radius: appeared ? 0 : 2)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(CodexMotion.panelSpring.delay(min(Double(index) * 0.025, 0.16))) {
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
