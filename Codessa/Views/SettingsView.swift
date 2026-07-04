import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Full-page Settings surface (routed via `MainPage.settings`). Modeled on the
/// ChatGPT Codex desktop layout: a grouped left nav (Personal / Integrations /
/// Coding / Archived) with "Back to app" + a settings search, and a scrolling
/// content pane. Every page maps to a real Codessa feature — styled with
/// CodexTheme tokens and the custom menu engine. Transient state (MCP list,
/// storage size, toast, confirmations, nav search) is held here as `@State`.
struct SettingsView: View {
    @Environment(AppViewModel.self) private var model
    @EnvironmentObject private var update: UpdateService
    @State private var section: Section = .general
    @State private var navQuery = ""

    // Transient, view-local state (no new AppViewModel stored props).
    @State private var mcpServers: [MCPServerInfo] = []
    @State private var mcpLoading = false
    @State private var storageInfo: SessionStorageInfo?
    @State private var toast: String?
    @State private var toastWork: DispatchWorkItem?
    @State private var confirmingClear = false

    /// Nav groups, mirroring Codex's settings sidebar sections.
    enum NavGroup: String, CaseIterable, Identifiable {
        case personal = "Personal"
        case integrations = "Integrations"
        case coding = "Coding"
        case archived = "Archived"
        var id: String { rawValue }
    }

    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        case personalization = "Personalization"
        case shortcuts = "Keyboard shortcuts"
        case mcp = "MCP servers"
        case hooks = "Hooks"
        case cli = "Grok CLI"
        case data = "Data"
        case archived = "Archived chats"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .appearance: "circle.lefthalf.filled"
            case .personalization: "person.crop.circle"
            case .shortcuts: "keyboard"
            case .mcp: "puzzlepiece.extension"
            case .hooks: "bolt.horizontal"
            case .cli: "terminal"
            case .data: "externaldrive"
            case .archived: "archivebox"
            case .about: "info.circle"
            }
        }

        /// The nav group this page lives under, or nil for the standalone footer
        /// item (About).
        var group: NavGroup? {
            switch self {
            case .general, .appearance, .personalization, .shortcuts: .personal
            case .mcp: .integrations
            case .hooks, .cli, .data: .coding
            case .archived: .archived
            case .about: nil
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(CodexTheme.divider).frame(width: 1)
            content
        }
        .frame(maxWidth: Self.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private static let navWidth: CGFloat = 220
    private static let contentMaxWidth: CGFloat = 680
    private static let labelColumnWidth: CGFloat = 250
    private static let controlColumnWidth: CGFloat = 260
    private static let pageMaxWidth: CGFloat = navWidth + 1 + contentMaxWidth + 64

    // MARK: - Section nav

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            backButton
            searchField

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if navQuery.isEmpty {
                        ForEach(NavGroup.allCases) { group in
                            let items = Section.allCases.filter { $0.group == group }
                            if !items.isEmpty {
                                groupHeader(group.rawValue)
                                ForEach(items) { navRow($0) }
                            }
                        }
                        Rectangle().fill(CodexTheme.divider)
                            .frame(height: 1).padding(.horizontal, 8).padding(.vertical, 8)
                        navRow(.about)
                    } else {
                        let matches = Section.allCases.filter {
                            $0.rawValue.localizedCaseInsensitiveContains(navQuery)
                        }
                        if matches.isEmpty {
                            Text("No matches")
                                .font(.system(size: 12))
                                .foregroundStyle(CodexTheme.textTertiary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        } else {
                            ForEach(matches) { navRow($0) }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.never)
        }
        .padding(8)
        .padding(.top, 20)
        .frame(width: Self.navWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .overlay(CodexTheme.mainBackground.opacity(0.28))
    }

    private var backButton: some View {
        Button {
            // Return to wherever the user was before opening Settings; only fall
            // back to Home if that was a chat with no live conversation.
            let target = model.pageBeforeSettings
            model.navigateTo(target == .chat && model.messages.isEmpty ? .home : target)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.left").font(.system(size: 12, weight: .medium))
                Text("Back to app").font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .codexHover(cornerRadius: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(CodexTheme.textTertiary)
            TextField("", text: $navQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textPrimary)
                .placeholderOverlay("Search settings…", visible: navQuery.isEmpty)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodexTheme.composerBackground.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(CodexTheme.textTertiary)
            .kerning(0.4)
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
    }

    private func navRow(_ item: Section) -> some View {
        Button { withAnimation(CodexMotion.quickSpring) { section = item } } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(section == item ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                    .frame(width: 18)
                Text(item.rawValue)
                    .font(.system(size: 13, weight: section == item ? .medium : .regular))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
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

    // MARK: - Content pane

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch section {
                    case .general: generalSection
                    case .appearance: appearanceSection
                    case .personalization: personalizationSection
                    case .shortcuts: shortcutsSection
                    case .mcp: mcpSection
                    case .hooks: hooksSection
                    case .cli: cliSection
                    case .data: dataSection
                    case .archived: archivedSection
                    case .about: aboutSection
                    }
                }
                .codexPage("settings-\(section.rawValue)")
            }
            .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 40)
        }
        .background(CodexTheme.mainBackground.opacity(0.18))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { toastBanner }
        // The project-context editor is now a full page (`.projectContext`), opened
        // via `model.openProjectContext(for:)` — no sheet needed here.
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("General")

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

            settingsDivider

            toggleRow("Send on Return",
                      "When on, Return sends and ⇧Return makes a newline. When off, it's reversed.",
                      isOn: Binding(get: { model.sendOnReturn }, set: { model.sendOnReturn = $0 }))
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Appearance")

            settingRow("Theme", "Match the system, or force light / dark.") {
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

            settingsDivider

            settingRow("Sidebar grouping", "How chats are organised in the sidebar.") {
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
            .frame(maxWidth: 600, alignment: .leading)

            settingsDivider

            toggleRow("Start collapsed",
                      "Launch with the sidebar collapsed to icons.",
                      isOn: Binding(get: { model.sidebarCollapsed }, set: { model.sidebarCollapsed = $0 }))

            toggleRow("Collapsible groups",
                      "Show chevrons so project and branch headers can collapse and expand their chats.",
                      isOn: Binding(get: { model.collapsibleGroupsEnabled },
                                    set: { model.collapsibleGroupsEnabled = $0 }))
        }
    }

    // MARK: - Personalization

    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Personalization")

            Text("Give Grok extra context for a project. Codessa loads each project's \(model.projectContextFileName) on every run in that project — use it for house style, architecture notes, and standing instructions.")
                .font(.system(size: 12)).foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let project = model.selectedProject {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project context")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                        Text("Edit \(project.name)'s \(model.projectContextFileName).")
                            .font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    pillButton("Edit context", icon: "square.and.pencil") {
                        model.openProjectContext(for: project)
                    }
                }
            } else {
                cardContainer {
                    Text("Select a project to edit its context file.")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - MCP servers

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("MCP servers")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Servers")
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
            if section == .mcp, mcpServers.isEmpty { reloadMCP() }
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

            settingsDivider

            toggleRow("Warm Grok session",
                      "Keep a Grok agent running in the background so MCP boots once and follow-up prompts stream instantly.",
                      isOn: Binding(get: { model.warmSessionEnabled }, set: { model.warmSessionEnabled = $0 }))

            Text("If the CLI isn't detected, install it or run `grok login` in a terminal to authenticate.")
                .font(.system(size: 12)).foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Archived chats

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Archived chats")

            let archived = model.archivedProjects
            if archived.isEmpty {
                cardContainer {
                    Text("No archived projects.")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 12)
                }
            } else {
                cardContainer {
                    VStack(spacing: 0) {
                        ForEach(Array(archived.enumerated()), id: \.element.id) { index, project in
                            if index > 0 {
                                Rectangle().fill(CodexTheme.divider).frame(height: 1)
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "archivebox")
                                    .font(.system(size: 12))
                                    .foregroundStyle(CodexTheme.textTertiary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(CodexTheme.textPrimary)
                                    Text(project.path.path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(CodexTheme.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 12)
                                pillButton("Unarchive", icon: "tray.and.arrow.up") {
                                    model.unarchiveProject(project)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                        }
                    }
                }
            }

            Text("Archived projects are hidden from the sidebar. Unarchive one to bring it back.")
                .font(.system(size: 12)).foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Keyboard shortcuts

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Keyboard shortcuts")

            Text("Every shortcut available in Codessa. These work whenever the app is focused.")
                .font(.system(size: 12)).foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
        ("Command palette", ["⌘", "K"]),
        ("Send message", ["⌘", "⏎"]),
        ("Newline in composer", ["⇧", "⏎"]),
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
                    Text("Codessa")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
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

            updateCard

            toggleRow("Check for updates automatically",
                      "Quietly check for a newer version each time Codessa launches.",
                      isOn: $update.automaticallyChecksOnLaunch)

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

    /// Update status + action card in About. Opens the full update dialog, and
    /// surfaces the "development build → install to /Applications" hint inline so
    /// the fix for the drifting Dock shortcut is discoverable from Settings too.
    private var updateCard: some View {
        cardContainer {
            HStack(spacing: 12) {
                Image(systemName: update.updateAvailableInBackground ? "arrow.down.circle.fill" : "checkmark.seal")
                    .font(.system(size: 18))
                    .foregroundStyle(update.updateAvailableInBackground ? CodexTheme.accent : CodexTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(update.updateAvailableInBackground ? "An update is available" : "Software updates")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text(updateStatusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { update.presentDialog() } label: {
                    Text(update.updateAvailableInBackground ? "Install…" : "Check now")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule(style: .continuous).fill(CodexTheme.sendButtonActiveBackground))
                        .contentShape(Capsule())
                }
                .buttonStyle(CodexPressableStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var updateStatusDetail: String {
        if update.updateAvailableInBackground {
            return "Click to review the changes and install."
        }
        if !update.isRunningFromCanonicalLocation {
            return update.isDevBuild
                ? "Running a development build — check for updates to install it to /Applications and stop re-pinning the Dock."
                : "Running from outside /Applications. Check for updates to install it to a stable location."
        }
        return "You're on version \(update.currentVersion)."
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
            if let refreshed = await model.setMCPServer(server, enabled: !server.enabled) {
                mcpServers = refreshed
            } else {
                // Write failed — keep the optimistic state and tell the user.
                showToast("Couldn't update \(server.name) — check ~/.grok/config.toml")
            }
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
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.bottom, 6)
    }

    private func settingRow<Control: View>(_ title: String, _ subtitle: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                settingsRowLabel(title, subtitle)
                    .frame(width: Self.labelColumnWidth, alignment: .leading)

                control()
                    .frame(width: Self.controlColumnWidth, alignment: .trailing)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(CodexTheme.divider, lineWidth: 1)
                    )
            }
            .frame(maxWidth: 600, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                settingsRowLabel(title, subtitle)

                control()
                    .frame(maxWidth: min(Self.controlColumnWidth, 320), alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(CodexTheme.divider, lineWidth: 1)
                    )
            }
            .frame(maxWidth: 600, alignment: .leading)
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                settingsRowLabel(title, subtitle)
                    .frame(width: Self.labelColumnWidth, alignment: .leading)

                Button { withAnimation(CodexMotion.quickSpring) { isOn.wrappedValue.toggle() } } label: {
                    MiniSwitch(isOn: isOn.wrappedValue)
                }
                .buttonStyle(.plain)
                .frame(width: Self.controlColumnWidth, alignment: .trailing)
            }
            .frame(maxWidth: 600, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                settingsRowLabel(title, subtitle)

                Button { withAnimation(CodexMotion.quickSpring) { isOn.wrappedValue.toggle() } } label: {
                    MiniSwitch(isOn: isOn.wrappedValue)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 600, alignment: .leading)
        }
    }

    private func settingsRowLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(CodexTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: 640, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.sidebarBackground))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(CodexTheme.divider)
            .frame(maxWidth: 600)
            .frame(height: 1)
            .padding(.vertical, 2)
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
