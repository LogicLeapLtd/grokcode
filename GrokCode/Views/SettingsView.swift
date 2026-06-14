import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Full-page Settings surface (routed via `MainPage.settings`). Left section
/// nav + scrolling content pane, styled with CodexTheme tokens and the custom
/// menu engine. Transient state (MCP server list, cache size, toast,
/// confirmations) is held here as `@State`, fed by `AppViewModel+Settings`.
struct SettingsView: View {
    @Environment(AppViewModel.self) private var model
    @State private var section: Section = .general

    // Transient, view-local state (no new AppViewModel stored props).
    @State private var mcpServers: [MCPServerInfo] = []
    @State private var mcpLoading = false
    @State private var storageInfo: SessionStorageInfo?
    @State private var toast: String?
    @State private var toastWork: DispatchWorkItem?
    @State private var confirmingClear = false

    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case sidebar = "Sidebar"
        case performance = "Performance"
        case data = "Data"
        case hooks = "Hooks"
        case cli = "Grok CLI"
        case shortcuts = "Shortcuts"
        case about = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .sidebar: "sidebar.left"
            case .performance: "bolt"
            case .data: "externaldrive"
            case .hooks: "bolt.horizontal"
            case .cli: "terminal"
            case .shortcuts: "keyboard"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        // Center the whole nav + content block at the shared page width so
        // Settings lines up at the same gutters as every other detail page,
        // instead of full-bleeding edge to edge.
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(CodexTheme.divider).frame(width: 1)
            content
        }
        .frame(maxWidth: Self.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity)
        .background(CodexTheme.mainBackground)
    }

    /// Shared page width: the section nav (204pt + 1pt divider) plus the
    /// 820pt content column from `PageScaffold`, so the content rhythm matches
    /// the other detail pages while the nav sits to its left.
    private static let navWidth: CGFloat = 204
    private static let pageMaxWidth: CGFloat = navWidth + 1 + 820

    // MARK: - Section nav

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 8)

            ForEach(Section.allCases) { item in
                Button { withAnimation(CodexMotion.quickSpring) { section = item } } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(section == item ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                            .frame(width: 18)
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: section == item ? .medium : .regular))
                            .foregroundStyle(CodexTheme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(section == item ? CodexTheme.navHighlight : .clear)
                    )
                    .codexHover(cornerRadius: 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: Self.navWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.sidebarBackground)
    }

    // MARK: - Content pane

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch section {
                    case .general: generalSection
                    case .sidebar: sidebarSection
                    case .performance: performanceSection
                    case .data: dataSection
                    case .hooks: hooksSection
                    case .cli: cliSection
                    case .shortcuts: shortcutsSection
                    case .about: aboutSection
                    }
                }
                .codexPage("settings-\(section.rawValue)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { toastBanner }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("General")

            settingRow("Appearance", "Match the system, or force light / dark.") {
                CodexMenuTrigger(minWidth: 180) { _ in
                    fieldLabel(model.appearance.label)
                } menu: { close in
                    CodexMenuContainer {
                        ForEach(AppAppearance.allCases) { option in
                            CodexMenuItem(title: option.label, isSelected: model.appearance == option) {
                                model.appearance = option; close()
                            }
                        }
                    }
                }
            }

            settingRow("Default model", "Used when starting a new chat.") {
                CodexMenuTrigger(minWidth: 240) { _ in
                    fieldLabel(model.selectedModel?.displayName ?? "Model")
                } menu: { close in
                    CodexMenuContainer {
                        ForEach(model.models) { option in
                            CodexMenuItem(
                                title: option.displayName,
                                subtitle: option.isReasoningModel ? "Reasoning" : "Fast",
                                isSelected: model.selectedModel == option
                            ) { model.selectedModel = option; model.persistDefaults(); close() }
                        }
                    }
                }
            }

            settingRow("Default permission mode", "How much Grok can do without asking.") {
                CodexMenuTrigger(minWidth: 280) { _ in
                    fieldLabel(model.permissionMode.label)
                } menu: { close in
                    CodexMenuContainer {
                        ForEach(PermissionMode.allCases) { mode in
                            CodexMenuItem(title: mode.label, subtitle: mode.detail,
                                          isSelected: model.permissionMode == mode) {
                                model.permissionMode = mode; model.persistDefaults(); close()
                            }
                        }
                    }
                }
            }

            if model.selectedModel?.isReasoningModel == true {
                settingRow("Reasoning effort", "Only applies to reasoning models (Grok 4).") {
                    CodexMenuTrigger(minWidth: 180) { _ in
                        fieldLabel(model.effortLevel.label)
                    } menu: { close in
                        CodexMenuContainer {
                            ForEach(EffortLevel.allCases) { level in
                                CodexMenuItem(title: level.label, isSelected: model.effortLevel == level) {
                                    model.effortLevel = level; model.persistDefaults(); close()
                                }
                            }
                        }
                    }
                }
            }

            settingRow("Default project", "Where new chats start.") {
                CodexMenuTrigger(minWidth: 240) { _ in
                    fieldLabel(model.defaultProjectLabel)
                } menu: { close in
                    CodexMenuContainer {
                        CodexMenuItem(title: "Don't work in a project",
                                      systemImage: "circle.slash",
                                      isSelected: model.workWithoutProject) {
                            model.setDefaultProject(nil); close()
                        }
                        if !model.projects.isEmpty { CodexMenuDivider() }
                        ForEach(model.projects) { project in
                            CodexMenuItem(
                                title: project.name,
                                systemImage: "folder",
                                isSelected: !model.workWithoutProject && model.selectedProject?.id == project.id
                            ) { model.setDefaultProject(project); close() }
                        }
                    }
                }
            }

            Divider().background(CodexTheme.divider).padding(.vertical, 2)

            toggleRow("Send on Return",
                      "When on, Return sends and ⇧Return makes a newline. When off, it's reversed.",
                      isOn: Binding(get: { model.sendOnReturn }, set: { model.sendOnReturn = $0 }))
        }
    }

    // MARK: - Sidebar

    private var sidebarSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Sidebar")

            settingRow("Default grouping", "How chats are organised in the sidebar.") {
                CodexMenuTrigger(minWidth: 240) { _ in
                    fieldLabel(model.sidebarGroupBy.label)
                } menu: { close in
                    CodexMenuContainer {
                        ForEach(SidebarGroupBy.allCases) { option in
                            CodexMenuItem(title: option.label, systemImage: option.symbol,
                                          isSelected: model.sidebarGroupBy == option) {
                                model.sidebarGroupBy = option
                                model.persistSidebarPreferences()
                                close()
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default width")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                        Text("Width of the sidebar when the app launches.")
                            .font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
                    }
                    Spacer()
                    Text("\(Int(model.sidebarWidth)) pt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(CodexTheme.textSecondary)
                }
                Slider(
                    value: Binding(get: { model.sidebarWidth }, set: { model.sidebarWidth = $0 }),
                    in: 220...420, step: 2
                )
                .tint(CodexTheme.textPrimary)
            }

            Divider().background(CodexTheme.divider).padding(.vertical, 2)

            toggleRow("Start collapsed",
                      "Launch with the sidebar collapsed to icons.",
                      isOn: Binding(get: { model.sidebarCollapsed }, set: { model.sidebarCollapsed = $0 }))

            toggleRow("Collapsible groups",
                      "Show chevrons so project and branch headers can collapse and expand their chats.",
                      isOn: Binding(get: { model.collapsibleGroupsEnabled },
                                    set: { model.collapsibleGroupsEnabled = $0 }))
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Performance")

            toggleRow("Warm Grok session",
                      "Keep a Grok agent running in the background so MCP boots once and follow-up prompts stream instantly.",
                      isOn: Binding(get: { model.warmSessionEnabled }, set: { model.warmSessionEnabled = $0 }))

            Divider().background(CodexTheme.divider).padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("MCP servers")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                    if mcpLoading {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button { reloadMCP() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .frame(width: 24, height: 24)
                            .codexHover(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                    .help("Reload from grok mcp list")
                }
                Text("Servers Grok can call as tools. Toggle one off to disable it without removing the config.")
                    .font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
            }

            mcpList
        }
        .task(id: section) {
            if section == .performance, mcpServers.isEmpty { reloadMCP() }
        }
    }

    @ViewBuilder
    private var mcpList: some View {
        if mcpServers.isEmpty {
            cardContainer {
                Text(mcpLoading ? "Loading servers…" : "No MCP servers configured.")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 12)
            }
        } else {
            cardContainer {
                VStack(spacing: 0) {
                    ForEach(Array(mcpServers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 {
                            Rectangle().fill(CodexTheme.divider).frame(height: 1)
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 12))
                                .foregroundStyle(server.enabled ? CodexTheme.textSecondary : CodexTheme.textTertiary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(CodexTheme.textPrimary)
                                Text(server.detail.isEmpty ? "—" : server.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(CodexTheme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            MiniSwitch(isOn: server.enabled)
                                .onTapGesture { toggleMCP(server) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Data")

            cardContainer {
                VStack(spacing: 0) {
                    infoCardRow("Local sessions", storageInfo.map { "\($0.count)" } ?? "—")
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                    infoCardRow("On disk", storageInfo?.sizeLabel ?? "Calculating…")
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                    infoCardRow("Location", "~/.grok/sessions")
                }
            }

            HStack(spacing: 10) {
                pillButton("Export sessions…", icon: "square.and.arrow.up") { exportSessions() }
                pillButton("Clear sessions…", icon: "trash", destructive: true) { confirmingClear = true }
                Spacer(minLength: 0)
            }

            Text("Exporting writes every conversation summary to a single JSON file. Clearing permanently deletes all local Grok sessions — this can't be undone.")
                .font(.system(size: 12)).foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: section) {
            if section == .data { storageInfo = await model.loadSessionStorageInfo() }
        }
        .confirmationDialog(
            "Delete all local sessions?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete all sessions", role: .destructive) { clearSessions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every conversation stored under ~/.grok/sessions. It can't be undone.")
        }
    }

    // MARK: - Hooks

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Hooks")
            HooksReviewContent(showsHeader: false)
        }
    }

    // MARK: - Grok CLI

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Grok CLI")

            HStack(spacing: 8) {
                Image(systemName: model.grokAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.grokAvailable ? Color.green : CodexTheme.accentOrange)
                Text(model.grokAvailable ? "Grok CLI detected" : "Grok CLI not found")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
            }

            cardContainer {
                VStack(spacing: 0) {
                    infoCardRow("Path", model.grokBinaryPath)
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                    infoCardRow("Models available", "\(model.models.count)")
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                    infoCardRow("Recent sessions", "\(model.sessions.count)")
                }
            }

            HStack(spacing: 10) {
                pillButton("Run grok login", icon: "person.badge.key") { model.runGrokLogin() }
                Spacer(minLength: 0)
            }

            Text("If the CLI isn't detected, install it or run `grok login` in a terminal to authenticate.")
                .font(.system(size: 12)).foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Keyboard shortcuts")
            cardContainer {
                VStack(spacing: 0) {
                    let items = Self.shortcutItems
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Rectangle().fill(CodexTheme.divider).frame(height: 1)
                        }
                        HStack {
                            Text(item.label)
                                .font(.system(size: 13)).foregroundStyle(CodexTheme.textPrimary)
                            Spacer(minLength: 16)
                            HStack(spacing: 4) {
                                ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                                    keyCap(key)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private static let shortcutItems: [(label: String, keys: [String])] = [
        ("New chat", ["⌘", "N"]),
        ("Search", ["⌘", "F"]),
        ("Settings", ["⌘", ","]),
        ("Home", ["⌘", "1"]),
        ("Search page", ["⌘", "2"]),
        ("Plugins", ["⌘", "3"]),
        ("Automations", ["⌘", "4"]),
        ("Cycle permission mode", ["⇧", "⌘", "M"]),
        ("Stop / dismiss", ["Esc"]),
    ]

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("About")

            HStack(spacing: 14) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("GrokCode")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("Version \(AppViewModel.appVersionString)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(CodexTheme.textSecondary)
                    Text("A native macOS front-end for the Grok CLI.")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                Spacer(minLength: 0)
            }

            cardContainer {
                VStack(spacing: 0) {
                    linkRow("GitHub repository", icon: "chevron.left.forwardslash.chevron.right",
                            url: "https://github.com/joshmatthews/GrokCodeGUI")
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                    linkRow("Grok CLI docs", icon: "book",
                            url: "https://docs.x.ai/docs/grok-cli")
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                    linkRow("Report an issue", icon: "exclamationmark.bubble",
                            url: "https://github.com/joshmatthews/GrokCodeGUI/issues/new")
                }
            }
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CodexTheme.menuBackground)
                        .shadow(color: CodexTheme.menuShadow, radius: 12, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(CodexTheme.menuBorder, lineWidth: 1)
                )
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func reloadMCP() {
        mcpLoading = true
        Task {
            let servers = await model.loadMCPServers()
            mcpServers = servers
            mcpLoading = false
        }
    }

    private func toggleMCP(_ server: MCPServerInfo) {
        // Optimistic flip so the switch animates immediately.
        if let i = mcpServers.firstIndex(of: server) {
            mcpServers[i] = MCPServerInfo(name: server.name, detail: server.detail, enabled: !server.enabled)
        }
        Task {
            let refreshed = await model.setMCPServer(server, enabled: !server.enabled)
            mcpServers = refreshed
        }
    }

    private func exportSessions() {
        model.exportSessions { message, info in
            storageInfo = info
            showToast(message)
        }
    }

    private func clearSessions() {
        model.clearAllSessions { message, info in
            storageInfo = info
            showToast(message)
        }
    }

    private func showToast(_ message: String) {
        toastWork?.cancel()
        withAnimation(CodexMotion.quickSpring) { toast = message }
        let work = DispatchWorkItem {
            withAnimation(CodexMotion.quickSpring) { toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: - Shared helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.bottom, 2)
    }

    private func settingRow<Control: View>(_ title: String, _ subtitle: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(CodexTheme.divider, lineWidth: 1)
                )
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Button { isOn.wrappedValue.toggle() } label: {
                MiniSwitch(isOn: isOn.wrappedValue)
            }
            .buttonStyle(.plain)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 13)).foregroundStyle(CodexTheme.textPrimary).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
        }
    }

    private func cardContainer<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.sidebarBackground))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    private func infoCardRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(CodexTheme.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 13, design: value.contains("/") ? .monospaced : .default))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func linkRow(_ label: String, icon: String, url: String) -> some View {
        Button { model.openExternalURL(url) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12)).foregroundStyle(CodexTheme.textSecondary).frame(width: 18)
                Text(label).font(.system(size: 13)).foregroundStyle(CodexTheme.textPrimary)
                Spacer(minLength: 16)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
            .codexHover(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(CodexTheme.textSecondary)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CodexTheme.pillBackground))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    private func pillButton(_ title: String, icon: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(destructive ? CodexTheme.errorForeground : CodexTheme.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(CodexTheme.pillBackground))
            .codexHover()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
