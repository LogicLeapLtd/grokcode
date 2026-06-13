import SwiftUI

/// The Plugins page — a Codex-style catalogue of integrations (MCP servers,
/// skills, hooks, commands, extensions, automations) discovered from the local
/// grok / claude / codex / cursor configs.
///
/// Layout mirrors Codex's plugins surface: a large title + subtitle, a search
/// field, a segmented "Installed / Available / Import" control, then sections of
/// rounded cards. Installed plugins carry a remove control; discovered ones an
/// Import button. All state is read from / written to `AppViewModel` per the
/// project contract; this view owns no model state of its own beyond the
/// selected tab.
struct PluginsView: View {
    @Environment(AppViewModel.self) private var model

    /// The three top-level segments of the page.
    private enum Tab: String, CaseIterable, Identifiable {
        case installed, available, importable
        var id: String { rawValue }
        var title: String {
            switch self {
            case .installed: "Installed"
            case .available: "Available"
            case .importable: "Import"
            }
        }
        var symbol: String {
            switch self {
            case .installed: "checkmark.seal"
            case .available: "square.grid.2x2"
            case .importable: "square.and.arrow.down"
            }
        }
    }

    @State private var tab: Tab = .installed
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
                .padding(.top, 20)
            segmentedControl
                .padding(.top, 18)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    content
                }
                .padding(.top, 22)
                .padding(.bottom, 48)
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 44)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.mainBackground)
        .onAppear {
            model.refreshPlugins()
            searchFocused = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Plugins")
                    .font(CodexTheme.headlineFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                Text("MCP servers, skills, hooks, and commands discovered from your grok, Claude, Codex, and Cursor setups.")
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            rescanButton
        }
    }

    private var rescanButton: some View {
        Button {
            model.refreshPlugins()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                Text("Rescan")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexTheme.pillBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle())
        .help("Rescan local tool configs for plugins")
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(CodexTheme.textSecondary)
            TextField("Search plugins", text: Binding(
                get: { model.pluginSearchQuery },
                set: { model.pluginSearchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($searchFocused)
            if !model.pluginSearchQuery.isEmpty {
                Button {
                    model.pluginSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTheme.composerBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
    }

    // MARK: - Segmented control (custom — never native Picker)

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                segment(item)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CodexTheme.pillBackground)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segment(_ item: Tab) -> some View {
        let selected = tab == item
        let count = badgeCount(for: item)
        return Button {
            withAnimation(CodexMotion.quickSpring) { tab = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? CodexTheme.textSecondary : CodexTheme.textTertiary)
                }
            }
            .foregroundStyle(selected ? CodexTheme.textPrimary : CodexTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? CodexTheme.mainBackground : .clear)
                    .shadow(color: selected ? CodexTheme.shadowColor.opacity(0.25) : .clear, radius: 2, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badgeCount(for tab: Tab) -> Int? {
        switch tab {
        case .installed: return installedFiltered.count
        case .available: return availableFiltered.count
        case .importable: return importFiltered.count
        }
    }

    // MARK: - Filtering

    private func matchesQuery(_ plugin: Plugin) -> Bool {
        let q = model.pluginSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return plugin.name.localizedCaseInsensitiveContains(q)
            || plugin.subtitle.localizedCaseInsensitiveContains(q)
            || plugin.sourceTool.displayName.localizedCaseInsensitiveContains(q)
    }

    /// Installed plugins matching the search query.
    private var installedFiltered: [Plugin] {
        model.installedPlugins.filter(matchesQuery)
    }

    /// Everything the user could install — discovered plugins not already in the
    /// installed set — matching the query.
    private var availableFiltered: [Plugin] {
        let installedIDs = Set(model.installedPlugins.map(\.id))
        return model.importablePlugins
            .filter { !installedIDs.contains($0.id) }
            .filter(matchesQuery)
    }

    /// The full discovered catalogue (the "Import" tab shows everything, marking
    /// already-installed entries) matching the query.
    private var importFiltered: [Plugin] {
        model.importablePlugins.filter(matchesQuery)
    }

    // MARK: - Content per tab

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .installed:
            installedContent
        case .available:
            catalogue(availableFiltered,
                      emptyTitle: model.pluginSearchQuery.isEmpty ? "Nothing to install" : "No matches",
                      emptySubtitle: model.pluginSearchQuery.isEmpty
                        ? "Every plugin discovered on this machine is already installed."
                        : "No available plugins match \"\(model.pluginSearchQuery)\".",
                      emptySymbol: "square.grid.2x2")
        case .importable:
            catalogue(importFiltered,
                      emptyTitle: model.pluginSearchQuery.isEmpty ? "Nothing discovered" : "No matches",
                      emptySubtitle: model.pluginSearchQuery.isEmpty
                        ? "No grok, Claude, Codex, or Cursor configs were found. Add an MCP server or skill to one of those tools, then Rescan."
                        : "No plugins match \"\(model.pluginSearchQuery)\".",
                      emptySymbol: "square.and.arrow.down")
        }
    }

    // MARK: Installed tab

    @ViewBuilder
    private var installedContent: some View {
        if installedFiltered.isEmpty {
            emptyState(
                symbol: "puzzlepiece.extension",
                title: model.pluginSearchQuery.isEmpty ? "No plugins installed" : "No matches",
                subtitle: model.pluginSearchQuery.isEmpty
                    ? "Open the Import tab to add MCP servers, skills, and commands from your local tools."
                    : "No installed plugins match \"\(model.pluginSearchQuery)\"."
            )
            if model.pluginSearchQuery.isEmpty && !model.importablePlugins.isEmpty {
                Button {
                    withAnimation(CodexMotion.quickSpring) { tab = .importable }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                        Text("Browse \(model.importablePlugins.count) discovered plugins")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.sendButtonActiveBackground)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
            }
        } else {
            ForEach(groupedByKind(installedFiltered), id: \.0) { kind, plugins in
                pluginSection(kind: kind, plugins: plugins)
            }
        }
    }

    // MARK: Catalogue (Available / Import tabs) — grouped by source tool

    @ViewBuilder
    private func catalogue(_ plugins: [Plugin],
                           emptyTitle: String,
                           emptySubtitle: String,
                           emptySymbol: String) -> some View {
        if plugins.isEmpty {
            emptyState(symbol: emptySymbol, title: emptyTitle, subtitle: emptySubtitle)
        } else {
            ForEach(groupedBySource(plugins), id: \.0) { source, items in
                sourceSection(source: source, plugins: items)
            }
        }
    }

    // MARK: - Grouping helpers

    /// Group + sort by `PluginKind.sortOrder` (Installed tab).
    private func groupedByKind(_ plugins: [Plugin]) -> [(PluginKind, [Plugin])] {
        Dictionary(grouping: plugins, by: \.kind)
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
    }

    /// Group by source tool, ordered by the enum's declaration order (Import /
    /// Available tabs).
    private func groupedBySource(_ plugins: [Plugin]) -> [(PluginSource, [Plugin])] {
        let order = Dictionary(uniqueKeysWithValues: PluginSource.allCases.enumerated().map { ($1, $0) })
        return Dictionary(grouping: plugins, by: \.sourceTool)
            .sorted { (order[$0.key] ?? 99) < (order[$1.key] ?? 99) }
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
    }

    // MARK: - Sections

    private func pluginSection(kind: PluginKind, plugins: [Plugin]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: kind.pluralLabel, symbol: kind.symbol, count: plugins.count)
            cardStack(plugins)
        }
    }

    private func sourceSection(source: PluginSource, plugins: [Plugin]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                sourceBadge(source)
                Text(source.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text("\(plugins.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
                Spacer(minLength: 0)
            }
            cardStack(plugins)
        }
    }

    private func sectionHeader(title: String, symbol: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)
            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.textTertiary)
            Spacer(minLength: 0)
        }
    }

    /// A vertically-stacked card containing the plugin rows, divided by hairlines
    /// — the Codex "grouped list" card look.
    private func cardStack(_ plugins: [Plugin]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plugins.enumerated()), id: \.element.id) { index, plugin in
                if index > 0 {
                    Rectangle()
                        .fill(CodexTheme.divider)
                        .frame(height: 1)
                        .padding(.leading, 52)
                }
                PluginRow(plugin: plugin)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTheme.mainBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.divider, lineWidth: 1)
        )
    }

    // MARK: - Source badge

    private func sourceBadge(_ source: PluginSource) -> some View {
        let tint = Color(red: source.tint.red, green: source.tint.green, blue: source.tint.blue)
        return Image(systemName: source.iconSystemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }

    // MARK: - Empty state

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(CodexTheme.textTertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(CodexTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Plugin row

/// A single plugin card row: kind/brand icon, name, subtitle, source·kind
/// caption, and an install/remove control driven off `plugin.isInstalled`.
private struct PluginRow: View {
    @Environment(AppViewModel.self) private var model
    let plugin: Plugin

    private var tint: Color {
        Color(red: plugin.sourceTool.tint.red,
              green: plugin.sourceTool.tint.green,
              blue: plugin.sourceTool.tint.blue)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(plugin.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                    if plugin.isRemoteServer {
                        tag("Remote")
                    }
                }
                Text(plugin.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(plugin.sourceKindCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            actionControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .codexHover(cornerRadius: 11)
    }

    private var icon: some View {
        Image(systemName: plugin.iconSystemName)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
    }

    private func tag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(CodexTheme.pillBackground)
            )
    }

    @ViewBuilder
    private var actionControl: some View {
        if plugin.isInstalled {
            Button {
                model.removePlugin(plugin)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Installed")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(CodexTheme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(CodexTheme.pillBackground)
                )
                .overlay(
                    Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(CodexPressableStyle())
            .help("Remove \(plugin.displayName)")
        } else {
            Button {
                model.installPlugin(plugin)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Import")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(CodexTheme.sendButtonActiveBackground)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(CodexPressableStyle())
            .help("Import \(plugin.displayName)")
        }
    }
}
