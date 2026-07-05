import SwiftUI

/// The Plugins page. Three tabs:
///  - Discover: Codessa's own curated marketplace.
///  - Manage: auto-synced local integrations from other coding agents.
///  - Installed: what you've added.
struct PluginsView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tab: String, CaseIterable, Identifiable {
        case discover, importing, installed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .discover: "Discover"
            case .importing: "Manage"
            case .installed: "Installed"
            }
        }
        var symbol: String {
            switch self {
            case .discover: "square.grid.2x2"
            case .importing: "slider.horizontal.3"
            case .installed: "checkmark.seal"
            }
        }
    }

    @State private var tab: Tab = .discover
    @State private var pageSettled = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        PageScaffold(maxWidth: 900, horizontalPadding: 36, topPadding: 44, spacing: 18) {
            header
                .pluginPageReveal(index: 0)
            overviewStrip
                .pluginPageReveal(index: 1)
            filterBar
                .pluginPageReveal(index: 2)
            LazyVStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .pluginPageReveal(index: 3)
        }
        .overlay(alignment: .bottom) { toastOverlay }
        .onAppear {
            model.refreshPlugins()
            model.syncInstalledFromGrok()
            searchFocused = false
            withAnimation(reduceMotion ? nil : CodexMotion.panelSpring.delay(0.03)) {
                pageSettled = true
            }
            // Refresh the community list from the marketplace (remote manifest,
            // on-disk cache fallback) each time the page appears.
            Task { await model.loadCommunityPlugins() }
        }
        .opacity(pageSettled ? 1 : 0)
        .sheet(isPresented: Binding(
            get: { model.publishSheetOpen },
            set: { model.publishSheetOpen = $0 }
        )) {
            PublishPluginSheet(
                onPublish: { entry in
                    // Persist to the local published store + refresh the catalog,
                    // and surface a toast — WITHOUT closing the sheet, so its
                    // success state (copy manifest / open repo) stays visible.
                    MarketplaceService.shared.publish(entry)
                    model.refreshPublishedPlugins()
                    model.pluginToast = "Published \(entry.name)"
                },
                onClose: { model.publishSheetOpen = false }
            )
        }
    }

    // MARK: Toast (#33)

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.pluginToast {
            PluginToast(text: toast)
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast)
                .task(id: toast) {
                    // Auto-dismiss ~2.5s after the latest toast appears. Keyed on
                    // the text so a new toast restarts the timer rather than being
                    // cut short by a previous one.
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(CodexMotion.quickSpring) { model.pluginToast = nil }
                }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CodexTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.accent.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.accent.opacity(0.18), lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Plugins")
                        .font(CodexTheme.serif(29, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("Discover, install, and manage the capabilities Codessa can hand to its agents.")
                        .font(CodexTheme.captionFont)
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
                }
            }
            Spacer(minLength: 18)
            HStack(spacing: 8) {
                publishButton
                rescanButton
            }
            .padding(.top, 4)
        }
    }

    private var publishButton: some View {
        Button { model.publishSheetOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill").font(.system(size: 11, weight: .semibold))
                Text("Publish").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(CodexTheme.sendButtonActiveForeground)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .frame(height: 28)
            .background(Capsule().fill(CodexTheme.sendButtonActiveBackground))
            .contentShape(Capsule())
        }
        .buttonStyle(CodexPressableStyle())
        .codexHoverOverlay(cornerRadius: 14)
        .help("Publish your own plugin to the Codessa marketplace")
    }

    private var rescanButton: some View {
        Button { model.refreshPlugins() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                Text("Sync").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .frame(height: 28)
            .background(Capsule().fill(CodexTheme.pillBackground))
            .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .codexHoverOverlay(cornerRadius: 14)
        .help("Sync local MCP servers, plugins and skills")
    }

    // MARK: Overview

    private var overviewStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                discoverMetric
                manageMetric
                installedMetric
                disabledMetric
            }
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    discoverMetric
                    manageMetric
                }
                HStack(spacing: 10) {
                    installedMetric
                    disabledMetric
                }
            }
        }
    }

    private var discoverMetric: some View {
        metricCard(
            icon: "square.grid.2x2",
            title: "Discover",
            value: "\(MarketplaceCatalog.plugins.count + model.communityPlugins.count)",
            caption: "Curated and community",
            tint: CodexTheme.accent
        )
    }

    private var manageMetric: some View {
        metricCard(
            icon: "slider.horizontal.3",
            title: "Manage",
            value: "\(model.importablePlugins.count)",
            caption: "Synced locally",
            tint: Color(red: PluginSource.cursor.tint.red, green: PluginSource.cursor.tint.green, blue: PluginSource.cursor.tint.blue)
        )
    }

    private var installedMetric: some View {
        metricCard(
            icon: "checkmark.seal",
            title: "Installed",
            value: "\(model.installedPlugins.count)",
            caption: "Ready for chats",
            tint: Color(red: PluginSource.agents.tint.red, green: PluginSource.agents.tint.green, blue: PluginSource.agents.tint.blue)
        )
    }

    private var disabledMetric: some View {
        metricCard(
            icon: "pause.circle",
            title: "Disabled",
            value: "\(disabledManagedCount)",
            caption: "Paused at source",
            tint: CodexTheme.textTertiary
        )
    }

    private func metricCard(icon: String, title: String, value: String, caption: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(CodexTheme.sans(18, weight: .bold))
                    .foregroundStyle(CodexTheme.textPrimary)
                HStack(spacing: 5) {
                    Text(title)
                        .font(CodexTheme.smallFont)
                        .foregroundStyle(CodexTheme.textSecondary)
                    Text(caption)
                        .font(CodexTheme.smallFont)
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.composerBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(CodexTheme.textSecondary)
            TextField("", text: Binding(
                get: { model.pluginSearchQuery },
                set: { model.pluginSearchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($searchFocused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .placeholderOverlay("Search plugins", visible: model.pluginSearchQuery.isEmpty, font: .system(size: 15))
            if !model.pluginSearchQuery.isEmpty {
                Button { model.pluginSearchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(CodexTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.mainBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(searchFocused ? CodexTheme.focusAccent : CodexTheme.divider, lineWidth: 1))
    }

    // MARK: Segmented control

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                segmentedControl
                Spacer(minLength: 8)
                searchField
                    .frame(maxWidth: 360)
            }
            VStack(alignment: .leading, spacing: 10) {
                segmentedControl
                searchField
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CodexTheme.sidebarBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { segment($0) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.mainBackground))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func segment(_ item: Tab) -> some View {
        let selected = tab == item
        let count: Int = {
            switch item {
            case .discover: return discoverFiltered.count
            case .importing: return importFiltered.count
            case .installed: return installedFiltered.count
            }
        }()
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
                    .fill(selected ? CodexTheme.composerBackground : .clear)
                    .shadow(color: selected ? CodexTheme.shadowColor.opacity(0.25) : .clear, radius: 2, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Filtering

    /// True when there's an active (non-whitespace) search query. While true the
    /// results span every tab (#35) rather than just the selected one.
    private var isSearching: Bool {
        !model.pluginSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matchesQuery(_ plugin: Plugin) -> Bool {
        let q = model.pluginSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return plugin.name.localizedCaseInsensitiveContains(q)
            || plugin.subtitle.localizedCaseInsensitiveContains(q)
            || plugin.detail.localizedCaseInsensitiveContains(q)
            || plugin.sourceTool.displayName.localizedCaseInsensitiveContains(q)
    }

    private var installedIDs: Set<String> { Set(model.installedPlugins.map(\.id)) }
    private var disabledManagedCount: Int { model.importablePlugins.filter { !$0.isLocallyEnabled }.count }

    /// Curated marketplace, with `isInstalled` reflecting the installed set.
    private var marketplaceFiltered: [Plugin] {
        MarketplaceCatalog.plugins
            .map { $0.settingInstalled(installedIDs.contains($0.id)) }
            .filter(matchesQuery)
    }
    private var importFiltered: [Plugin] { model.importablePlugins.filter(matchesQuery) }
    private var installedFiltered: [Plugin] { model.installedPlugins.filter(matchesQuery) }

    /// Community marketplace plugins (loaded from `MarketplaceService`), with
    /// `isInstalled` reflecting the installed set so the row's Add/Installed
    /// control is correct.
    private var communityFiltered: [Plugin] {
        model.communityPlugins
            .map { $0.settingInstalled(installedIDs.contains($0.id)) }
            .filter(matchesQuery)
    }
    private var discoverFiltered: [Plugin] { marketplaceFiltered + communityFiltered }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isSearching {
            globalSearchContent
        } else {
            tabContent
        }
    }

    /// #35 — while searching, results span every tab. Each non-empty category is
    /// shown as its own section so the user finds a match without hunting through
    /// tabs; the segment badges above already reflect the per-tab match counts.
    @ViewBuilder
    private var globalSearchContent: some View {
        let totalMatches = discoverFiltered.count + importFiltered.count + installedFiltered.count
        if totalMatches == 0 {
            emptyState(symbol: "magnifyingglass", title: "No matches",
                       subtitle: "Nothing across Discover, Manage or Installed matches \u{201C}\(model.pluginSearchQuery)\u{201D}.")
        } else {
            if !installedFiltered.isEmpty {
                searchSection(icon: "checkmark.seal", title: "Installed", tab: .installed, items: installedFiltered)
            }
            if !marketplaceFiltered.isEmpty {
                searchSection(icon: "sparkles", title: "Curated", tab: .discover, items: marketplaceFiltered)
            }
            if !communityFiltered.isEmpty {
                searchSection(icon: "person.2", title: "Community", tab: .discover, items: communityFiltered, authorSource: true)
            }
            if !importFiltered.isEmpty {
                searchSection(icon: "slider.horizontal.3", title: "Manage", tab: .importing, items: importFiltered)
            }
        }
    }

    /// One category block in global-search mode. Tapping the header jumps to that
    /// tab (and the search box keeps filtering it there).
    private func searchSection(icon: String, title: String, tab destination: Tab, items: [Plugin], authorSource: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(CodexMotion.quickSpring) { tab = destination }
            } label: {
                HStack(spacing: 8) {
                    sectionGlyph(icon)
                    Text(title)
                        .font(CodexTheme.controlTitleFont)
                        .foregroundStyle(CodexTheme.textPrimary)
                    countBadge(items.count)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(CodexTheme.textTertiary.opacity(0.7))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if authorSource {
                communityCardStack(items)
            } else {
                cardStack(items)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .discover:
            if marketplaceFiltered.isEmpty && communityFiltered.isEmpty {
                emptyState(symbol: "magnifyingglass", title: "No matches",
                           subtitle: "Nothing in the marketplace matches \u{201C}\(model.pluginSearchQuery)\u{201D}.")
            } else {
                if !marketplaceFiltered.isEmpty {
                    sectionHeaderRow(icon: "sparkles", title: "Curated by Codessa", count: marketplaceFiltered.count)
                        .pluginPageReveal(index: 0)
                    cardStack(marketplaceFiltered)
                }
                communitySection
            }
        case .importing:
            if importFiltered.isEmpty {
                emptyState(symbol: "slider.horizontal.3",
                           title: model.pluginSearchQuery.isEmpty ? "Nothing synced yet" : "No matches",
                           subtitle: model.pluginSearchQuery.isEmpty
                            ? "No MCP servers, plugins, skills, hooks or commands were found in your Grok, Claude, Codex, Cursor or shared agent setups. Add one to those tools, then Sync."
                            : "No synced integrations match \u{201C}\(model.pluginSearchQuery)\u{201D}.")
            } else {
                ForEach(groupedBySource(importFiltered), id: \.0) { source, items in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 9) {
                            sourceBadge(source)
                            Text(source.displayName).font(CodexTheme.controlTitleFont).foregroundStyle(CodexTheme.textPrimary)
                            countBadge(items.count)
                            Spacer(minLength: 0)
                        }
                        .pluginPageReveal(index: 0)
                        cardStack(items)
                    }
                }
            }
        case .installed:
            if installedFiltered.isEmpty {
                emptyState(symbol: "tray",
                           title: model.pluginSearchQuery.isEmpty ? "No plugins installed yet" : "No matches",
                           subtitle: model.pluginSearchQuery.isEmpty
                            ? "Add plugins from the Discover marketplace or the synced Manage inventory."
                            : "No installed plugins match \u{201C}\(model.pluginSearchQuery)\u{201D}.")
            } else {
                cardStack(installedFiltered)
            }
        }
    }

    private func groupedBySource(_ plugins: [Plugin]) -> [(PluginSource, [Plugin])] {
        let order = Dictionary(uniqueKeysWithValues: PluginSource.allCases.enumerated().map { ($1, $0) })
        return Dictionary(grouping: plugins, by: \.sourceTool)
            .sorted { (order[$0.key] ?? 99) < (order[$1.key] ?? 99) }
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
    }

    /// Community marketplace section, shown in Discover below the curated list.
    /// Lists `communityFiltered` in the same row style as the curated cards
    /// (with the publisher's author surfaced). When there's nothing to show and
    /// no active search, a subtle invitation to publish takes its place.
    @ViewBuilder
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderRow(icon: "person.2", title: "Community",
                             count: communityFiltered.isEmpty ? 0 : communityFiltered.count)
            .pluginPageReveal(index: 0)
            if communityFiltered.isEmpty {
                if isSearching {
                    Text("No community plugins match \u{201C}\(model.pluginSearchQuery)\u{201D}.")
                        .font(.system(size: 13))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pluginPageReveal(index: 1)
                } else {
                    Button { model.publishSheetOpen = true } label: {
                        Text("No community plugins yet — be the first to publish.")
                            .font(.system(size: 13))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Publish your own plugin to the Codessa marketplace")
                    .pluginPageReveal(index: 1)
                }
            } else {
                communityCardStack(communityFiltered)
            }
        }
    }

    /// Like `cardStack`, but each row carries a community author caption when the
    /// entry provided one (preserved on `Plugin.rawConfig["author"]`).
    private func communityCardStack(_ plugins: [Plugin]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plugins.enumerated()), id: \.element.id) { index, plugin in
                if index > 0 {
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                        .padding(.leading, PluginRow.Metrics.textColumnInset)
                }
                PluginRow(plugin: plugin, authorOverride: plugin.rawConfig["author"])
                    .pluginPageReveal(index: index)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.composerBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionHeaderRow(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            sectionGlyph(icon)
            Text(title)
                .font(CodexTheme.controlTitleFont)
                .foregroundStyle(CodexTheme.textPrimary)
            if count > 0 { countBadge(count) }
            Spacer(minLength: 0)
        }
    }

    private func cardStack(_ plugins: [Plugin]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plugins.enumerated()), id: \.element.id) { index, plugin in
                if index > 0 {
                    // Inset the divider to line up with the start of the title
                    // column (icon tile width + leading padding + gutter).
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                        .padding(.leading, PluginRow.Metrics.textColumnInset)
                }
                PluginRow(plugin: plugin)
                    .pluginPageReveal(index: index)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.composerBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sourceBadge(_ source: PluginSource) -> some View {
        let tint = Color(red: source.tint.red, green: source.tint.green, blue: source.tint.blue)
        return Image(systemName: source.iconSystemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.14)))
    }

    private func sectionGlyph(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CodexTheme.accent)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(CodexTheme.accent.opacity(0.12)))
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(CodexTheme.smallFont)
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(CodexTheme.pillBackground))
    }

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        // Shared centered empty-state from the page-scaffold contract, so "No
        // matches" / "Nothing synced yet" sit centered in the column rather than
        // pinned to a corner.
        PageEmptyState(systemImage: symbol, title: title, message: subtitle, minHeight: 320)
    }
}

// MARK: - Plugin row

private struct PluginRow: View {
    @Environment(AppViewModel.self) private var model
    let plugin: Plugin
    /// When set (community rows), shows a "by <author>" caption under the title.
    var authorOverride: String? = nil
    @State private var showConfigure = false
    @State private var confirmingDelete = false

    /// Shared layout constants so the divider inset, icon column and text column
    /// stay on one consistent grid across every row.
    enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let iconSize: CGFloat = 42
        static let iconGutter: CGFloat = 13
        /// Where the title/subtitle column starts, measured from the card edge.
        static let textColumnInset: CGFloat = horizontalPadding + iconSize + iconGutter
    }

    private var tint: Color {
        Color(red: plugin.sourceTool.tint.red, green: plugin.sourceTool.tint.green, blue: plugin.sourceTool.tint.blue)
    }

    private var hasMeaningfulSubtitle: Bool {
        plugin.subtitle.trimmingCharacters(in: CharacterSet(charactersIn: "> \n\t-—·")).count > 1
    }

    /// Env vars / API keys are only configurable on MCP servers (the only kind
    /// grok launches with an `--env` blob), and only once installed.
    private var canConfigure: Bool {
        plugin.isInstalled && plugin.kind == .mcpServer
    }

    private var canShowManagementControls: Bool {
        authorOverride == nil && (plugin.supportsLocalDisable || plugin.supportsLocalDelete)
    }

    private var authorText: String? {
        guard let author = authorOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
              !author.isEmpty else { return nil }
        return author
    }

    private var transportText: String? {
        if plugin.isRemoteServer { return "Remote" }
        if let command = plugin.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty {
            return command
        }
        if let url = plugin.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            return "URL"
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.iconGutter) {
            icon
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(plugin.displayName)
                        .font(CodexTheme.sans(14.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                    if !plugin.isLocallyEnabled { statusTag("Disabled") }
                }
                if hasMeaningfulSubtitle {
                    Text(plugin.subtitle)
                        .font(CodexTheme.captionFont)
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    metaChip(plugin.sourceTool.displayName, systemName: plugin.sourceTool.iconSystemName)
                    metaChip(plugin.kind.label, systemName: plugin.kind.symbol)
                    if let transportText {
                        metaChip(transportText, systemName: plugin.isRemoteServer ? "network" : "terminal")
                    }
                    if let authorText {
                        metaChip("by \(authorText)", systemName: "person")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if canConfigure { configureButton }
                if canShowManagementControls {
                    if plugin.supportsLocalDisable { enableToggleButton }
                    if plugin.supportsLocalDelete { deleteButton }
                }
                actionControl
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 74)
        .contentShape(Rectangle())
        .codexHover(cornerRadius: 0)
        .sheet(isPresented: $showConfigure) {
            PluginConfigureSheet(plugin: plugin)
        }
        .confirmationDialog(
            "Delete \(plugin.displayName)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.deleteLocalPlugin(plugin)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local definition from \(plugin.sourceTool.displayName). Config-backed MCP servers are removed from their source file; file-backed items are moved to Trash when possible.")
        }
    }

    private var configureButton: some View {
        Button { showConfigure = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .medium))
                Text("Configure").font(CodexTheme.smallFont)
            }
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(CodexTheme.pillBackground))
            .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Edit environment variables / API keys for \(plugin.displayName)")
    }

    private var enableToggleButton: some View {
        let nextEnabled = !plugin.isLocallyEnabled
        return managementIconButton(
            systemName: plugin.isLocallyEnabled ? "power" : "power.circle.fill",
            tint: plugin.isLocallyEnabled ? CodexTheme.textSecondary : CodexTheme.accentOrange,
            help: "\(nextEnabled ? "Enable" : "Disable") \(plugin.displayName)"
        ) {
            model.setLocalPlugin(plugin, enabled: nextEnabled)
        }
    }

    private var deleteButton: some View {
        managementIconButton(
            systemName: "trash",
            tint: CodexTheme.textTertiary,
            help: "Delete \(plugin.displayName)"
        ) {
            confirmingDelete = true
        }
    }

    private var icon: some View {
        Image(systemName: plugin.iconSystemName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.20), lineWidth: 1))
    }

    private func statusTag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(CodexTheme.pillBackground))
    }

    private func metaChip(_ text: String, systemName: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(CodexTheme.smallFont)
                .lineLimit(1)
        }
        .foregroundStyle(CodexTheme.textTertiary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.72)))
    }

    private func managementIconButton(
        systemName: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CodexTheme.pillBackground))
                .overlay(Circle().strokeBorder(CodexTheme.divider, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .codexHoverOverlay(Circle())
        .help(help)
    }

    @ViewBuilder
    private var actionControl: some View {
        if plugin.isInstalled {
            Button { model.removePluginViaGrok(plugin) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text("Installed").font(CodexTheme.smallFont)
                }
                .foregroundStyle(CodexTheme.textSecondary)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(CodexTheme.pillBackground))
                .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Remove \(plugin.displayName)")
        } else if !plugin.isLocallyEnabled {
            HStack(spacing: 5) {
                Image(systemName: "pause.circle").font(.system(size: 11, weight: .medium))
                Text("Disabled").font(CodexTheme.smallFont)
            }
            .foregroundStyle(CodexTheme.textTertiary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(CodexTheme.pillBackground))
            .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
        } else {
            Button { model.installPluginViaGrok(plugin) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CodexTheme.accentOrange)
                    Text(plugin.sourceTool == .builtin ? "Add" : "Import").font(CodexTheme.smallFont)
                        .foregroundStyle(CodexTheme.textPrimary)
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(CodexTheme.pillBackground))
                .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .codexHoverOverlay(cornerRadius: 13)
            .help("Add \(plugin.displayName)")
        }
    }
}

// MARK: - Toast (#33)

/// A small bottom-anchored confirmation pill (e.g. "Added cloudflare"). Auto-
/// dismissal is owned by the presenting view's `.task(id:)`.
private struct PluginToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CodexTheme.accentOrange)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(CodexTheme.composerBackground)
                .shadow(color: CodexTheme.shadowColor.opacity(0.28), radius: 14, y: 5)
        )
        .overlay(Capsule(style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }
}

// MARK: - Animation helpers

private struct PluginPageReveal: ViewModifier {
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
    func pluginPageReveal(index: Int) -> some View {
        modifier(PluginPageReveal(index: index))
    }
}

// MARK: - Configure sheet (#34)

/// Edit a plugin's environment variables / API keys (`Plugin.env`). On save the
/// values are persisted and, for MCP servers, re-registered with grok via
/// `updatePluginEnv` so `--env KEY=VALUE` reaches the launched server.
private struct PluginConfigureSheet: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plugin: Plugin

    /// Editable KEY/VALUE rows. Order is stabilised on appear; `id` keeps row
    /// identity stable across edits (so focus / SwiftUI diffing behaves).
    @State private var rows: [EnvRow] = []

    private struct EnvRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    private var tint: Color {
        Color(red: plugin.sourceTool.tint.red, green: plugin.sourceTool.tint.green, blue: plugin.sourceTool.tint.blue)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(CodexTheme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    if rows.isEmpty {
                        emptyRowsState
                    } else {
                        ForEach($rows) { $row in
                            envRow($row)
                        }
                    }
                    addRowButton
                }
                .padding(20)
            }
            .frame(maxHeight: 360)
            Divider().background(CodexTheme.divider)
            footer
        }
        .frame(width: 540)
        .background(CodexTheme.mainBackground)
        .onAppear(perform: seedRows)
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: plugin.iconSystemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Configure \(plugin.displayName)")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text(plugin.sourceKindCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .codexHover(cornerRadius: 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CodexTheme.pillBackground))
                    .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(cornerRadius: 9)

            Button(action: save) {
                Text("Save")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CodexTheme.sendButtonActiveBackground))
                    .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(cornerRadius: 9)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Body pieces

    private var intro: some View {
        Text("Set environment variables passed to this server (e.g. API keys). They're stored with the plugin and applied as --env KEY=VALUE when grok launches it.")
            .font(.system(size: 12))
            .foregroundStyle(CodexTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyRowsState: some View {
        Text("No variables yet. Add one below.")
            .font(.system(size: 13))
            .foregroundStyle(CodexTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func envRow(_ row: Binding<EnvRow>) -> some View {
        HStack(spacing: 8) {
            TextField("", text: row.key)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .placeholderOverlay("KEY", visible: row.wrappedValue.key.isEmpty, font: .system(size: 13, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(width: 180, alignment: .leading)
                .background(inputBackground)

            Text("=").font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textTertiary)

            TextField("", text: row.value)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .placeholderOverlay("value", visible: row.wrappedValue.value.isEmpty, font: .system(size: 13, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(inputBackground)

            Button { removeRow(row.wrappedValue.id) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this variable")
        }
    }

    private var addRowButton: some View {
        Button { rows.append(EnvRow(key: "", value: "")) } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                Text("Add variable").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CodexTheme.pillBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexHoverOverlay(cornerRadius: 9)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(CodexTheme.composerBackground)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(CodexTheme.composerBorder, lineWidth: 1))
    }

    // MARK: Actions

    private func seedRows() {
        rows = plugin.env
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { EnvRow(key: $0.key, value: $0.value) }
    }

    private func removeRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
    }

    private func save() {
        // Collapse rows to a map: trimmed non-empty keys win; later rows override
        // earlier duplicates.
        var env: [String: String] = [:]
        for row in rows {
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            env[key] = row.value
        }
        model.updatePluginEnv(plugin, env: env)
        dismiss()
    }
}
