import SwiftUI

/// The Plugins page — a Codex-style catalogue of integrations (MCP servers,
/// skills, hooks, commands) discovered from the local grok / Claude / Codex /
/// Cursor configs. Two tabs: Discover (the full catalogue, grouped by source,
/// with Import controls) and Installed.
struct PluginsView: View {
    @Environment(AppViewModel.self) private var model

    private enum Tab: String, CaseIterable, Identifiable {
        case discover, installed
        var id: String { rawValue }
        var title: String { self == .discover ? "Discover" : "Installed" }
        var symbol: String { self == .discover ? "square.grid.2x2" : "checkmark.seal" }
    }

    @State private var tab: Tab = .discover
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField.padding(.top, 20)
            segmentedControl.padding(.top, 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    content
                }
                .padding(.top, 22)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 40)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.mainBackground)
        .onAppear {
            model.refreshPlugins()
            // Land on whichever tab has something to show.
            tab = model.installedPlugins.isEmpty ? .discover : .installed
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
        Button { model.refreshPlugins() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                Text("Rescan").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodexTheme.pillBackground))
            .codexHover()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Rescan local tool configs for plugins")
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(CodexTheme.textSecondary)
            TextField("Search plugins", text: Binding(
                get: { model.pluginSearchQuery },
                set: { model.pluginSearchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($searchFocused)
            if !model.pluginSearchQuery.isEmpty {
                Button { model.pluginSearchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(CodexTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CodexTheme.composerBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CodexTheme.composerBorder, lineWidth: 1))
    }

    // MARK: - Segmented control

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { segment($0) }
            Spacer(minLength: 0)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.pillBackground))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segment(_ item: Tab) -> some View {
        let selected = tab == item
        let count = item == .discover ? discoverFiltered.count : installedFiltered.count
        return Button {
            withAnimation(CodexMotion.quickSpring) { tab = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 11, weight: .medium))
                Text(item.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? CodexTheme.textSecondary : CodexTheme.textTertiary)
                }
            }
            .foregroundStyle(selected ? CodexTheme.textPrimary : CodexTheme.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? CodexTheme.mainBackground : .clear)
                    .shadow(color: selected ? CodexTheme.shadowColor.opacity(0.25) : .clear, radius: 2, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtering

    private func matchesQuery(_ plugin: Plugin) -> Bool {
        let q = model.pluginSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return plugin.name.localizedCaseInsensitiveContains(q)
            || plugin.subtitle.localizedCaseInsensitiveContains(q)
            || plugin.sourceTool.displayName.localizedCaseInsensitiveContains(q)
    }

    private var installedFiltered: [Plugin] { model.installedPlugins.filter(matchesQuery) }
    private var discoverFiltered: [Plugin] { model.importablePlugins.filter(matchesQuery) }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .discover:
            if discoverFiltered.isEmpty {
                emptyState(
                    symbol: "puzzlepiece.extension",
                    title: model.pluginSearchQuery.isEmpty ? "Nothing discovered" : "No matches",
                    subtitle: model.pluginSearchQuery.isEmpty
                        ? "No grok, Claude, Codex, or Cursor configs were found. Add an MCP server or skill to one of those tools, then Rescan."
                        : "No plugins match \u{201C}\(model.pluginSearchQuery)\u{201D}."
                )
            } else {
                ForEach(groupedBySource(discoverFiltered), id: \.0) { source, items in
                    sourceSection(source: source, plugins: items)
                }
            }
        case .installed:
            if installedFiltered.isEmpty {
                emptyState(
                    symbol: "tray",
                    title: model.pluginSearchQuery.isEmpty ? "No plugins installed yet" : "No matches",
                    subtitle: model.pluginSearchQuery.isEmpty
                        ? "Browse the Discover tab and import the MCP servers, skills, and commands you want to use."
                        : "No installed plugins match \u{201C}\(model.pluginSearchQuery)\u{201D}."
                )
            } else {
                ForEach(groupedBySource(installedFiltered), id: \.0) { source, items in
                    sourceSection(source: source, plugins: items)
                }
            }
        }
    }

    // MARK: - Grouping

    private func groupedBySource(_ plugins: [Plugin]) -> [(PluginSource, [Plugin])] {
        let order = Dictionary(uniqueKeysWithValues: PluginSource.allCases.enumerated().map { ($1, $0) })
        return Dictionary(grouping: plugins, by: \.sourceTool)
            .sorted { (order[$0.key] ?? 99) < (order[$1.key] ?? 99) }
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
    }

    // MARK: - Sections

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

    private func cardStack(_ plugins: [Plugin]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plugins.enumerated()), id: \.element.id) { index, plugin in
                if index > 0 {
                    Rectangle().fill(CodexTheme.divider).frame(height: 1).padding(.leading, 52)
                }
                PluginRow(plugin: plugin)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CodexTheme.mainBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    private func sourceBadge(_ source: PluginSource) -> some View {
        let tint = Color(red: source.tint.red, green: source.tint.green, blue: source.tint.blue)
        return Image(systemName: source.iconSystemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.14)))
    }

    // MARK: - Empty state (vertically centered so the page never looks empty/jammed)

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
        .frame(maxWidth: .infinity, minHeight: 380, alignment: .center)
    }
}

// MARK: - Plugin row

private struct PluginRow: View {
    @Environment(AppViewModel.self) private var model
    let plugin: Plugin

    private var tint: Color {
        Color(red: plugin.sourceTool.tint.red, green: plugin.sourceTool.tint.green, blue: plugin.sourceTool.tint.blue)
    }

    /// Skip empty / frontmatter-artifact subtitles like ">" so rows stay clean.
    private var hasMeaningfulSubtitle: Bool {
        plugin.subtitle.trimmingCharacters(in: CharacterSet(charactersIn: "> \n\t-—·")).count > 1
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
                    if plugin.isRemoteServer { tag("Remote") }
                }
                if hasMeaningfulSubtitle {
                    Text(plugin.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }

    private func tag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(CodexTheme.pillBackground))
    }

    @ViewBuilder
    private var actionControl: some View {
        if plugin.isInstalled {
            Button { model.removePlugin(plugin) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text("Installed").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(CodexTheme.textSecondary)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(CodexTheme.pillBackground))
                .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(CodexPressableStyle())
            .help("Remove \(plugin.displayName)")
        } else {
            Button { model.installPlugin(plugin) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Import").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(CodexTheme.sendButtonActiveBackground))
                .contentShape(Capsule())
            }
            .buttonStyle(CodexPressableStyle())
            .help("Import \(plugin.displayName)")
        }
    }
}
