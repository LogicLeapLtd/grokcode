import SwiftUI

// MARK: - Command model

/// One actionable row in the ⌘K palette. Built fresh from the live model each
/// time the palette is shown so results always reflect current projects/chats.
private struct PaletteCommand: Identifiable {
    enum Group: String, CaseIterable {
        case action = "Actions"
        case page = "Pages"
        case project = "Projects"
        case chat = "Recent chats"

        /// Display order of the groups in the result list.
        var rank: Int {
            switch self {
            case .action: 0
            case .page: 1
            case .project: 2
            case .chat: 3
            }
        }
    }

    let id = UUID()
    let title: String
    let subtitle: String?
    let symbol: String
    let group: Group
    /// Lowercased haystack used for fuzzy matching (title + subtitle + group).
    let searchText: String
    let run: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        group: Group,
        run: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.group = group
        self.searchText = [title, subtitle ?? "", group.rawValue]
            .joined(separator: " ")
            .lowercased()
        self.run = run
    }
}

// MARK: - Fuzzy matching

private enum FuzzyMatcher {
    /// Subsequence match with a lightweight relevance score. Higher is better;
    /// `nil` means the query isn't a subsequence of the candidate at all.
    /// Rewards contiguous runs, word-boundary hits, and a prefix match.
    static func score(_ query: String, in haystack: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let q = Array(query)
        let h = Array(haystack)
        var qi = 0
        var score = 0
        var streak = 0
        var prevMatchIndex = -1

        for (hi, ch) in h.enumerated() where qi < q.count {
            guard ch == q[qi] else { continue }
            // Base point for the matched char.
            score += 1
            // Contiguous-run bonus (grows with the streak length).
            if prevMatchIndex == hi - 1 {
                streak += 1
                score += streak * 3
            } else {
                streak = 0
            }
            // Word-boundary bonus (start of string or after a separator).
            if hi == 0 || h[hi - 1] == " " || h[hi - 1] == "-" || h[hi - 1] == "/" || h[hi - 1] == "_" {
                score += 6
            }
            prevMatchIndex = hi
            qi += 1
        }

        guard qi == q.count else { return nil }
        // Whole-string prefix gets a strong boost so exact starts float up.
        if haystack.hasPrefix(query) { score += 20 }
        return score
    }
}

// MARK: - Command palette

/// VS Code / Codex-style ⌘K command palette: a centered floating panel with an
/// auto-focused search field and a fuzzy-filtered, grouped, keyboard-navigable
/// result list. Presented as an overlay by `ContentView`, gated on
/// `model.commandPaletteOpen`.
struct CommandPalette: View {
    @Environment(AppViewModel.self) private var model

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private let maxWidth: CGFloat = 560

    var body: some View {
        ZStack(alignment: .top) {
            // Dimmed backdrop — click anywhere to dismiss.
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .transition(.opacity)

            panel
                .frame(maxWidth: maxWidth)
                .padding(.horizontal, 24)
                .padding(.top, 96)
                .transition(.asymmetric(
                    insertion: CodexMotion.modalTransition,
                    removal: .scale(scale: 0.97).combined(with: .opacity).combined(with: .offset(y: -8))
                ))
        }
        .onAppear {
            highlighted = 0
            // Defer focus a tick so the field is in the hierarchy first.
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            searchField

            Rectangle()
                .fill(CodexTheme.divider)
                .frame(height: 1)

            results
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CodexTheme.menuBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CodexTheme.menuBorder, lineWidth: 1)
        )
        .shadow(color: CodexTheme.menuShadow, radius: 30, y: 16)
        // Stop backdrop taps that land on the panel from dismissing it.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(CodexTheme.textSecondary)

            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(CodexTheme.textPrimary)
                .focused($fieldFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                .placeholderOverlay(
                    "Search pages, projects, chats, actions…",
                    visible: query.isEmpty,
                    font: .system(size: 17)
                )
                .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
                .onKeyPress(.return) { runHighlighted(); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
                .onChange(of: query) { _, _ in highlighted = 0 }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let items = filteredCommands
        if items.isEmpty {
            VStack(spacing: 6) {
                Text("No results")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                Text("Try a different search")
                    .font(CodexTheme.captionFont)
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(grouped(items).enumerated()), id: \.element.group) { _, section in
                            sectionHeader(section.group)
                            ForEach(section.rows, id: \.command.id) { row in
                                CommandRow(
                                    command: row.command,
                                    isHighlighted: row.index == highlighted
                                )
                                .id(row.index)
                                .onHover { hovering in
                                    if hovering { highlighted = row.index }
                                }
                                .onTapGesture { run(row.command) }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 420)
                .onChange(of: highlighted) { _, new in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ group: PaletteCommand.Group) -> some View {
        Text(group.rawValue.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CodexTheme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: Data

    /// All commands built from the live model, before filtering.
    private var allCommands: [PaletteCommand] {
        var out: [PaletteCommand] = []

        // — Actions —
        out.append(PaletteCommand(title: "New chat", subtitle: "Start a fresh conversation", symbol: "square.and.pencil", group: .action) {
            model.startNewChat()
        })
        out.append(PaletteCommand(title: "Open settings", symbol: "gearshape", group: .action) {
            model.openSettings()
        })
        let planOn = model.isPlanMode
        out.append(PaletteCommand(
            title: planOn ? "Turn off plan mode" : "Turn on plan mode",
            subtitle: planOn ? "Switch back to full access" : "Read-only — plan without making changes",
            symbol: "list.bullet.clipboard",
            group: .action
        ) {
            model.isPlanMode.toggle()
        })

        // — Pages —
        let pages: [(MainPage, String, String)] = [
            (.home, "Home", "house"),
            (.search, "Search", "magnifyingglass"),
            (.plugins, "Plugins", "puzzlepiece.extension"),
            (.automations, "Automations", "clock"),
            (.settings, "Settings", "gearshape"),
        ]
        for (page, label, symbol) in pages {
            out.append(PaletteCommand(title: label, subtitle: "Go to \(label)", symbol: symbol, group: .page) {
                model.navigateTo(page)
            })
        }

        // — Projects —
        for project in model.projects {
            let subtitle = project.gitBranch.map { "\($0)" } ?? project.path.path
            out.append(PaletteCommand(title: project.name, subtitle: subtitle, symbol: "folder", group: .project) {
                model.selectProject(project)
                model.navigateTo(.home)
            })
        }

        // — Recent chats (project threads) —
        for project in model.projects {
            for thread in project.threads {
                let subtitle = "\(project.name) · \(thread.ageLabel)"
                out.append(PaletteCommand(title: thread.title, subtitle: subtitle, symbol: "bubble.left", group: .chat) {
                    model.selectThread(thread, in: project)
                })
            }
        }

        return out
    }

    /// Fuzzy-filtered + ranked commands for the current query.
    private var filteredCommands: [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return allCommands }

        let scored: [(cmd: PaletteCommand, score: Int)] = allCommands.compactMap { cmd in
            guard let s = FuzzyMatcher.score(trimmed, in: cmd.searchText) else { return nil }
            return (cmd, s)
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.cmd.group.rank != $1.cmd.group.rank { return $0.cmd.group.rank < $1.cmd.group.rank }
                return $0.cmd.title.localizedCaseInsensitiveCompare($1.cmd.title) == .orderedAscending
            }
            .map(\.cmd)
    }

    /// Stable flat ordering used for arrow-key navigation (matches render order:
    /// grouped by group rank, preserving relevance order within each group).
    private var orderedCommands: [PaletteCommand] {
        grouped(filteredCommands).flatMap { $0.rows.map(\.command) }
    }

    private struct Section {
        let group: PaletteCommand.Group
        let rows: [(command: PaletteCommand, index: Int)]
    }

    /// Group the filtered commands by their group (in group-rank order) and
    /// stamp each row with its global highlight index.
    private func grouped(_ commands: [PaletteCommand]) -> [Section] {
        var globalIndex = 0
        var sections: [Section] = []
        let groupsInOrder = PaletteCommand.Group.allCases.sorted { $0.rank < $1.rank }
        for group in groupsInOrder {
            let rows = commands.filter { $0.group == group }
            guard !rows.isEmpty else { continue }
            let stamped = rows.map { cmd -> (command: PaletteCommand, index: Int) in
                defer { globalIndex += 1 }
                return (cmd, globalIndex)
            }
            sections.append(Section(group: group, rows: stamped))
        }
        return sections
    }

    // MARK: Actions

    private func moveHighlight(by delta: Int) {
        let count = orderedCommands.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private func runHighlighted() {
        let ordered = orderedCommands
        guard ordered.indices.contains(highlighted) else { return }
        run(ordered[highlighted])
    }

    private func run(_ command: PaletteCommand) {
        command.run()
        dismiss()
    }

    private func dismiss() {
        fieldFocused = false
        model.commandPaletteOpen = false
    }
}

// MARK: - Row

private struct CommandRow: View {
    let command: PaletteCommand
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isHighlighted ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle = command.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CodexTheme.smallFont)
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if isHighlighted {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHighlighted ? CodexTheme.navHighlight : .clear)
        )
        .contentShape(Rectangle())
    }
}
