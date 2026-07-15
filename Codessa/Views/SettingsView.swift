import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(AppViewModel.self) private var model
    @EnvironmentObject private var update: UpdateService

    @State private var section: Section = Section.smokeDefault
    @State private var navQuery = ""
    @State private var mcpServers: [MCPServerInfo] = []
    @State private var mcpLoading = false
    @State private var storageInfo: SessionStorageInfo?
    @State private var toast: String?
    @State private var toastWork: DispatchWorkItem?
    @State private var confirmingClearSessions = false
    @State private var confirmingResetAll = false
    @State private var confirmingRetention = false
    @State private var confirmingEmptyArchive = false
    @State private var confirmingTrustAll = false

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
        case cli = "Coding agents"
        case data = "Data"
        case archived = "Archived chats"
        case about = "About"

        var id: String { rawValue }

        static var smokeDefault: Section {
            let raw = ProcessInfo.processInfo.environment["GROKCODE_SMOKE_SETTINGS_SECTION"] ?? ""
            return Section.allCases.first {
                $0.rawValue.replacingOccurrences(of: " ", with: "").lowercased()
                    == raw.replacingOccurrences(of: " ", with: "").lowercased()
            } ?? .general
        }

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

    private let contentWidth: CGFloat = 920
    private let navWidth: CGFloat = 220

    var body: some View {
        ZStack(alignment: .leading) {
            settingsBackdrop
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(CodexTheme.divider).frame(width: 1)
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task(id: section) {
            if section == .mcp { reloadMCP() }
            if section == .data { storageInfo = await model.loadSessionStorageInfo() }
        }
        .confirmationDialog("Delete all local sessions?", isPresented: $confirmingClearSessions, titleVisibility: .visible) {
            Button("Delete all sessions", role: .destructive) { clearSessions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every conversation stored under ~/.grok/sessions.")
        }
        .confirmationDialog("Reset every setting?", isPresented: $confirmingResetAll, titleVisibility: .visible) {
            Button("Reset all settings", role: .destructive) {
                model.resetPreferencesScope(.all)
                showToast("Reset all expanded settings")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets the expanded Codessa preferences. Existing projects and chats are not deleted.")
        }
        .confirmationDialog("Delete old session files?", isPresented: $confirmingRetention, titleVisibility: .visible) {
            Button("Delete old files", role: .destructive) {
                runRetentionCleanup()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Empty archive?", isPresented: $confirmingEmptyArchive, titleVisibility: .visible) {
            Button("Unarchive everything", role: .destructive) {
                model.emptyArchive()
                showToast("Archive emptied")
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Trust all pending hooks?", isPresented: $confirmingTrustAll, titleVisibility: .visible) {
            Button("Trust all", role: .destructive) {
                model.trustAllHooks()
                showToast("Trusted all pending hooks")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This lets every pending hook command run when its event fires.")
        }
    }

    private var settingsBackdrop: some View {
        ZStack {
            CodexTheme.mainBackground
            LinearGradient(
                colors: [CodexTheme.mainBackground.opacity(0.98), CodexTheme.sidebarBackground.opacity(0.62), CodexTheme.mainBackground.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if model.preferences.ambientBackgroundEnabled {
                LinearGradient(
                    colors: [CodexTheme.accentDeep.opacity(0.10), Color.clear, CodexTheme.focusAccent.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                let target = model.pageBeforeSettings
                model.navigateTo(target == .chat && model.messages.isEmpty ? .home : target)
            } label: {
                Label("Back to app", systemImage: "arrow.left")
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .codexHover(cornerRadius: 7)
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
                TextField("", text: $navQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .placeholderOverlay("Search settings…", visible: navQuery.isEmpty)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(CodexTheme.mainBackground.opacity(0.38)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CodexTheme.divider.opacity(0.78), lineWidth: 1))
            .padding(.bottom, 4)

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
                        Rectangle().fill(CodexTheme.divider).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 8)
                        navRow(.about)
                    } else {
                        ForEach(Section.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(navQuery) }) { navRow($0) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(8)
        .padding(.top, 24)
        .frame(width: navWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffectView(material: .sidebar).overlay(CodexTheme.sidebarBackground.opacity(0.30)))
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(CodexTheme.textTertiary)
            .kerning(0.4)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }

    private func navRow(_ item: Section) -> some View {
        Button {
            withAnimation(CodexMotion.quickSpring) { section = item }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: section == item ? .semibold : .regular))
                    .foregroundStyle(section == item ? CodexTheme.accent : CodexTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(section == item ? CodexTheme.accent.opacity(0.14) : .clear))
                Text(item.rawValue)
                    .font(.system(size: 13, weight: section == item ? .medium : .regular))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(section == item ? CodexTheme.navHighlight.opacity(0.92) : .clear))
            .overlay(alignment: .leading) {
                if section == item {
                    RoundedRectangle(cornerRadius: 1.5).fill(CodexTheme.accent.opacity(0.82)).frame(width: 3, height: 18).padding(.leading, 2)
                }
            }
            .codexHover(cornerRadius: 7)
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title(section.rawValue, icon: section.icon)
                Group {
                    switch section {
                    case .general: generalPage
                    case .appearance: appearancePage
                    case .personalization: personalizationPage
                    case .shortcuts: shortcutsPage
                    case .mcp: mcpPage
                    case .hooks: hooksPage
                    case .cli: cliPage
                    case .data: dataPage
                    case .archived: archivedPage
                    case .about: aboutPage
                    }
                }
                .codexPage("settings-\(section.rawValue)")
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 44)
            .padding(.top, 62)
            .padding(.bottom, 52)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { toastBanner }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricGrid([
                ("Model", model.selectedModel?.providerMenuName ?? "Model", "cpu"),
                ("Permission", model.permissionMode.label, "lock.shield"),
                ("Project", model.defaultProjectLabel, "folder"),
                ("Queue", model.preferences.allowFollowupQueue ? "On" : "Off", "text.badge.plus"),
            ])

            settingsCard("Defaults", "Startup and new-chat defaults.") {
                menuRow("Default model", "Used for new chats.", value: model.selectedModel?.providerMenuName ?? "Model") {
                    ForEach(Array(model.providerStatuses.enumerated()), id: \.element.id) { index, status in
                        if index > 0 { Divider() }
                        Text(status.provider.shortName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if status.models.isEmpty {
                            Button("No models available") {}
                                .disabled(true)
                        } else {
                            ForEach(status.models) { option in
                                Button(option.displayName) { model.selectModel(option) }
                            }
                        }
                    }
                }
                menuRow("Reasoning effort", "Only applies to reasoning models.", value: model.effortLevel.label) {
                    ForEach(EffortLevel.allCases) { level in
                        Button(level.label) { model.effortLevel = level; model.persistDefaults() }
                    }
                }
                menuRow("Permission mode", "How much the selected provider can do without asking.", value: model.permissionMode.label) {
                    ForEach(PermissionMode.allCases) { mode in
                        Button(mode.label) { model.permissionMode = mode; model.persistDefaults() }
                    }
                }
                menuRow("Default project", "Where new chats start.", value: model.defaultProjectLabel) {
                    Button("Don't work in a project") { model.setDefaultProject(nil) }
                    ForEach(model.projects) { project in
                        Button(project.name) { model.setDefaultProject(project) }
                    }
                }
                enumPicker("Launch page", selection: pref(\.launchPage), cases: AppPreferences.LaunchPage.allCases)
                enumPicker("New chat location", selection: pref(\.defaultNewChatLocation), cases: AppPreferences.NewChatLocation.allCases)
                toggle("Restore last page", "Use the last stable page when launch page allows it.", pref(\.restoreLastPage))
                toggle("Open split view on launch", "Start with split workspace visible.", pref(\.openSplitViewOnLaunch))
                toggle("Show launch mascot", "Display the launch overlay on startup.", pref(\.showLaunchMascot))
            }

            settingsCard("Composer Behaviour", "Controls that affect real chat sending.") {
                toggle("Send on Return", "Return sends; Shift-Return inserts a newline.", Binding(get: { model.sendOnReturn }, set: { model.sendOnReturn = $0 }))
                toggle("Allow follow-up queue", "Queue messages while a run is already streaming.", pref(\.allowFollowupQueue))
                toggle("Default pursue goal", "Enable self-checking by default.", pref(\.defaultPursueGoal))
                toggle("Default plan mode", "Start future sessions in plan permission mode.", pref(\.defaultPlanMode))
                toggle("Keep composer draft", "Leave sent text in the composer when clear-after-send is off.", pref(\.keepComposerDraft))
                toggle("Clear composer after send", "Clear typed text after successful submit.", pref(\.clearComposerAfterSend))
                enumPicker("Attachment behaviour", selection: pref(\.defaultAttachmentBehavior), cases: AppPreferences.AttachmentBehavior.allCases)
                toggle("Confirm stop-running", "Ask before cancelling an in-flight run.", pref(\.confirmStopRunning))
                toggle("Confirm destructive actions", "Require confirmation for local deletes and resets.", pref(\.confirmDestructiveActions))
            }

            actionGrid([
                action("Start new chat", "plus.bubble") { model.startNewChat() },
                action("Apply plan default now", "doc.text") { model.permissionMode = .plan },
                action("Apply pursue default now", "checkmark.seal") { model.pursueGoal = model.preferences.defaultPursueGoal },
                action("Reset General", "arrow.counterclockwise") { model.resetPreferencesScope(.general); showToast("Reset General settings") },
            ])
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            appearancePreview
            settingsCard("Theme", "Visual choices that apply immediately.") {
                enumPicker("Theme", selection: Binding(get: { model.appearance }, set: { model.appearance = $0 }), cases: AppAppearance.allCases)
                enumPicker("Accent", selection: pref(\.accent), cases: AppPreferences.Accent.allCases)
                enumPicker("Message density", selection: pref(\.messageDensity), cases: AppPreferences.Density.allCases)
                enumPicker("Bubble style", selection: pref(\.bubbleStyle), cases: AppPreferences.BubbleStyle.allCases)
                enumPicker("Tool calls", selection: pref(\.toolCallStyle), cases: AppPreferences.ToolCallStyle.allCases)
                toggle("High contrast", "Strengthen borders and text contrast.", pref(\.highContrast))
                toggle("Window vibrancy", "Keep translucent macOS materials enabled.", pref(\.vibrancyEnabled))
                toggle("Ambient background", "Show the animated background field.", pref(\.ambientBackgroundEnabled))
                toggle("Reduce motion", "Disable page and modal animations.", pref(\.reduceMotion))
                toggle("Show timestamps", "Show timestamps beside chat messages.", pref(\.showTimestamps))
            }
            settingsCard("Typography and Code", "Font and code rendering preferences.") {
                slider("Animation speed", value: pref(\.animationSpeed), range: 0.5...1.5, suffix: "x")
                slider("UI font size", value: pref(\.uiFontSize), range: 11...16, suffix: "pt")
                slider("Chat font size", value: pref(\.chatFontSize), range: 12...18, suffix: "pt")
                slider("Code font size", value: pref(\.codeFontSize), range: 10...16, suffix: "pt")
                toggle("Wrap code", "Wrap long code lines in previews.", pref(\.wrapCode))
                toggle("Code line numbers", "Show line numbers in code previews.", pref(\.showCodeLineNumbers))
            }
            settingsCard("Sidebar", "Existing sidebar preferences surfaced in one place.") {
                enumPicker("Sidebar grouping", selection: Binding(get: { model.sidebarGroupBy }, set: { model.sidebarGroupBy = $0; model.persistSidebarPreferences() }), cases: SidebarGroupBy.allCases)
                enumPicker("Sidebar sort", selection: Binding(get: { model.sidebarSort }, set: { model.sidebarSort = $0; model.persistSidebarPreferences() }), cases: SidebarSort.allCases)
                slider("Sidebar width", value: Binding(get: { model.sidebarWidth }, set: { model.sidebarWidth = $0 }), range: 240...340, suffix: "pt")
                toggle("Start collapsed", "Launch with the sidebar collapsed to icons.", Binding(get: { model.sidebarCollapsed }, set: { model.sidebarCollapsed = $0 }))
                toggle("Collapsible groups", "Project and branch headers can expand/collapse.", Binding(get: { model.collapsibleGroupsEnabled }, set: { model.collapsibleGroupsEnabled = $0 }))
            }
            actionGrid([
                action("Reset Appearance", "arrow.counterclockwise") { model.resetPreferencesScope(.appearance); showToast("Reset Appearance settings") },
                action("Collapse sidebar", "sidebar.left") { model.sidebarCollapsed = true },
                action("Expand sidebar", "sidebar.right") { model.sidebarCollapsed = false },
                action("Use system theme", "circle.lefthalf.filled") { model.appearance = .system },
            ])
        }
    }

    private var personalizationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricGrid([
                ("Context", model.preferences.contextEnabled ? "Enabled" : "Off", "doc.text"),
                ("Language", model.preferences.languagePreference.label, "textformat"),
                ("Tone", model.preferences.tonePreset.label, "slider.horizontal.3"),
                ("Rules", "\(personalizationRuleCount)", "checklist"),
            ])
            settingsCard("Project Context", "Real project context file controls.") {
                enumPicker("Context file policy", selection: pref(\.contextFilePolicy), cases: AppPreferences.ContextFilePolicy.allCases)
                toggle("Use context file", "Include project-context awareness in outgoing prompts.", pref(\.contextEnabled))
                toggle("Include project rules", "Mention project context in the preference prefix.", pref(\.includeProjectRules))
                infoRow("Selected file", model.projectContextFileName)
                actionRow("Edit context", "Open the full context editor.", "square.and.pencil") {
                    if let project = model.selectedProject { model.openProjectContext(for: project) }
                }
                actionRow("Reveal context file", "Show the file in Finder.", "folder") { model.revealCurrentProjectContext() }
            }
            settingsCard("Writing Preferences", "Applied as a compact prefix to prompts.") {
                enumPicker("Language", selection: pref(\.languagePreference), cases: AppPreferences.LanguagePreference.allCases)
                enumPicker("Response length", selection: pref(\.responseLength), cases: AppPreferences.ResponseLength.allCases)
                enumPicker("Explanation depth", selection: pref(\.explanationDepth), cases: AppPreferences.ExplanationDepth.allCases)
                enumPicker("Tone preset", selection: pref(\.tonePreset), cases: AppPreferences.TonePreset.allCases)
                toggle("British English", "Prefer UK spelling and phrasing.", pref(\.preferBritishEnglish))
                toggle("Avoid em dashes", "Prefer commas or shorter sentences.", pref(\.avoidEmDashes))
                toggle("Preserve wording", "Do not stylistically rewrite user-approved wording.", pref(\.preserveUserWording))
                toggle("Draft-only messaging", "Do not send external messages without approval.", pref(\.draftOnlyMessaging))
                toggle("Show plans by default", "Offer concise plans for substantial work.", pref(\.showPlansByDefault))
                toggle("Ask before assumptions", "Ask before high-impact assumptions.", pref(\.askBeforeAssumptions))
                toggle("Include style rules", "Attach these rules to outgoing prompts.", pref(\.includeStyleRules))
            }
            actionGrid([
                action("Copy active prefix", "doc.on.doc") { model.copyToClipboard(model.personalizationPrefix()) },
                action("Export preferences", "square.and.arrow.up") { model.exportPreferences(completion: showToast) },
                action("Import preferences", "square.and.arrow.down") { model.importPreferences(completion: showToast) },
                action("Reset Personalization", "arrow.counterclockwise") { model.resetPreferencesScope(.personalization); showToast("Reset Personalization settings") },
            ])
        }
    }

    private var shortcutsPage: some View {
        let filtered = shortcutItems.filter {
            model.preferences.shortcutSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(model.preferences.shortcutSearch)
        }
        return VStack(alignment: .leading, spacing: 16) {
            settingsCard("Shortcut System", "Editable labels are persisted; built-in command shortcuts remain active.") {
                enumPicker("Preset", selection: pref(\.shortcutPreset), cases: AppPreferences.ShortcutPreset.allCases)
                toggle("Enable custom shortcut map", "Use saved shortcut labels for display and conflict checks.", pref(\.shortcutsEnabled))
                textFieldRow("Search shortcuts", text: pref(\.shortcutSearch))
                infoRow("Configured shortcuts", "\(model.preferences.customShortcuts.count)")
                actionRow("Detect conflicts", "Scan duplicate shortcut labels.", "exclamationmark.triangle") {
                    showToast(shortcutConflictSummary)
                }
            }
            settingsCard("Shortcuts", "Click a key label to cycle through useful defaults.") {
                ForEach(filtered) { item in
                    shortcutRow(item)
                }
            }
            actionGrid([
                action("Reset shortcuts", "arrow.counterclockwise") { model.resetPreferencesScope(.shortcuts); showToast("Reset shortcuts") },
                action("Export shortcuts", "square.and.arrow.up") { model.exportPreferences(completion: showToast) },
                action("Import shortcuts", "square.and.arrow.down") { model.importPreferences(completion: showToast) },
                action("Copy conflicts", "doc.on.doc") { model.copyToClipboard(shortcutConflictSummary) },
            ])
        }
    }

    private var mcpPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricGrid([
                ("Servers", "\(mcpServers.count)", "server.rack"),
                ("Enabled", "\(mcpServers.filter(\.enabled).count)", "checkmark.circle"),
                ("Disabled", "\(mcpServers.filter { !$0.enabled }.count)", "pause.circle"),
                ("Reload", mcpLoading ? "Loading" : "Ready", "arrow.clockwise"),
            ])
            settingsCard("Controls", "Real MCP list and config actions.") {
                textFieldRow("Search servers", text: pref(\.mcpSearch))
                enumPicker("Filter", selection: pref(\.mcpFilter), cases: AppPreferences.ServerFilter.allCases)
                enumPicker("Sort", selection: pref(\.mcpSort), cases: AppPreferences.ServerSort.allCases)
                toggle("Show details", "Show command/URL detail under each server.", pref(\.mcpShowDetails))
                toggle("Show env keys", "Expose environment-key summary when available.", pref(\.mcpShowEnvKeys))
                toggle("Confirm writes", "Require care around MCP config writes.", pref(\.mcpRequireWriteConfirmation))
                actionRow("Reload", "Run `grok mcp list` again.", "arrow.clockwise") { reloadMCP() }
                actionRow("Reveal config", "Show ~/.grok/config.toml in Finder.", "folder") { model.revealInFinder(model.grokConfigURL) }
                actionRow("Open config", "Open the TOML config in the default editor.", "doc.text") { model.openFileOrFolder(model.grokConfigURL) }
                actionRow("Copy debug info", "Copy server list and config path.", "doc.on.doc") { copyMCPDebug() }
            }
            settingsCard("Servers", "Toggle enabled state in the real Grok config.") {
                if filteredMCPServers.isEmpty {
                    emptyLine("No MCP servers match the current filters.")
                } else {
                    ForEach(filteredMCPServers) { server in
                        mcpRow(server)
                    }
                }
            }
            actionGrid([
                action("Add from marketplace", "plus.app") { model.navigateTo(.plugins) },
                action("Refresh plugins", "arrow.triangle.2.circlepath") { model.refreshPlugins(); showToast("Refreshed plugins") },
                action("Reset MCP page", "arrow.counterclockwise") { model.resetPreferencesScope(.mcp); showToast("Reset MCP filters") },
                action("Copy config path", "doc.on.doc") { model.copyToClipboard(model.grokConfigURL.path) },
            ])
        }
    }

    private var hooksPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricGrid([
                ("Pending", "\(model.pendingHooks.count)", "bolt.badge.clock"),
                ("Trusted", "\(model.trustedHookIDs.count)", "checkmark.shield"),
                ("Filter", model.preferences.hookFilter.label, "line.3.horizontal.decrease"),
                ("View", model.preferences.hookCompactView ? "Compact" : "Detailed", "rectangle.compress.vertical"),
            ])
            settingsCard("Filters", "Control the hook review surface.") {
                textFieldRow("Search hooks", text: pref(\.hookSearch))
                enumPicker("Hook filter", selection: pref(\.hookFilter), cases: AppPreferences.HookFilter.allCases)
                toggle("Compact view", "Reduce row height for long hook lists.", pref(\.hookCompactView))
                toggle("Show command preview", "Show command snippets in rows.", pref(\.hookShowCommandPreview))
                toggle("Confirm trust all", "Require confirmation before trusting every hook.", pref(\.hookRequireTrustAllConfirmation))
                actionRow("Refresh hooks", "Reload hooks from disk.", "arrow.clockwise") { model.refreshHooks(); showToast("Hooks refreshed") }
                actionRow("Open hooks review", "Show the modal review surface.", "shield.lefthalf.filled") { model.openHooksReview() }
                actionRow("Trust all pending", "Approve every pending hook.", "checkmark.shield") {
                    if model.preferences.hookRequireTrustAllConfirmation { confirmingTrustAll = true } else { model.trustAllHooks() }
                }
            }
            settingsCard("Pending hooks", "Each action mutates real trusted-hook state.") {
                if filteredHooks.isEmpty {
                    emptyLine("No hooks match the current filters.")
                } else {
                    ForEach(filteredHooks, id: \.id) { hook in
                        hookRow(hook)
                    }
                }
            }
            actionGrid([
                action("Copy pending count", "doc.on.doc") { model.copyToClipboard("\(model.pendingHooks.count)") },
                action("Reset hook filters", "arrow.counterclockwise") { model.resetPreferencesScope(.hooks); showToast("Reset hook filters") },
                action("Copy trusted IDs", "number") { model.copyToClipboard(model.trustedHookIDs.sorted().joined(separator: "\n")) },
                action("Open hooks folder", "folder") { model.openFileOrFolder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/hooks")) },
            ])
        }
    }

    private var cliPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricGrid([
                ("Codex", model.codexProviderStatus?.installed == true ? "Detected" : "Missing", "terminal"),
                ("Models", "\(model.models.count)", "cpu"),
                ("Provider", model.selectedProvider.shortName, "switch.2"),
                ("Account", model.codexProviderStatus?.authStatus.label ?? "Unknown", "person.crop.circle"),
            ])
            settingsCard("ChatGPT Codex", "Primary local CLI and account setup.") {
                infoRow("Status", model.codexProviderStatus?.message ?? "Codex status is unavailable.")
                infoRow("Resolved path", model.codexProviderStatus?.binaryPath ?? "Not found")
                actionRow("Copy setup command", model.codexSetupCommand, "doc.on.doc") { model.copyCodexSetupCommand(); showToast("Copied Codex setup command") }
                actionRow("Open Codex CLI docs", "Install, sign in, and learn the Codex CLI.", "book") { model.openCodexDocs() }
                actionRow("Refresh CLI status", "Re-check Codex and optional providers.", "arrow.clockwise") { model.refreshCLIStatus(); showToast("CLI status refreshed") }
            }
            settingsCard("Optional Grok runtime", "Legacy warm-session controls for chats that explicitly select Grok.") {
                infoRow("Resolved path", model.grokBinaryPath)
                textFieldRow("Binary override", text: pref(\.grokBinaryOverride))
                toggle("Warm Grok session", "Keep a long-lived agent process ready.", Binding(get: { model.warmSessionEnabled }, set: { model.warmSessionEnabled = $0 }))
                toggle("Force one-shot mode", "Disable warm-session behaviour for future sends.", pref(\.forceOneShotMode))
                slider("Inactivity timeout", value: pref(\.inactivityTimeoutSeconds), range: 60...420, suffix: "s")
                slider("Session list limit", value: Binding(get: { Double(model.preferences.defaultSessionLimit) }, set: { model.preferences.defaultSessionLimit = Int($0) }), range: 10...100, suffix: "")
                actionRow("Run grok login", "Open Terminal with `grok login`.", "person.badge.key") { model.runGrokLogin() }
                actionRow("Refresh CLI status", "Re-check binary and providers.", "arrow.clockwise") { model.refreshCLIStatus(); showToast("CLI status refreshed") }
                actionRow("Refresh models", "Run the real model list call.", "cpu") { model.refreshModelsNow(completion: showToast) }
            }
            settingsCard("Providers", "Selection persists through ProviderRegistry.") {
                ForEach(model.providerStatuses) { status in
                    providerRow(status)
                }
                actionRow("Add custom provider", "Choose a local executable.", "plus") { model.addCustomProvider() }
            }
            actionGrid([
                action("Copy binary path", "doc.on.doc") { model.copyToClipboard(model.grokBinaryPath) },
                action("Reveal binary", "folder") { model.revealInFinder(URL(fileURLWithPath: model.grokBinaryPath)) },
                action("Copy diagnostics", "stethoscope") { model.copyDiagnostics(); showToast("Copied diagnostics") },
                action("Reset CLI settings", "arrow.counterclockwise") { model.resetPreferencesScope(.cli); showToast("Reset CLI settings") },
            ])
        }
    }

    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricGrid([
                ("Local sessions", storageInfo.map { "\($0.count)" } ?? "- -", "bubble.left.and.bubble.right"),
                ("On disk", storageInfo?.sizeLabel ?? "Calculating", "externaldrive"),
                ("Retention", "\(Int(model.preferences.retentionDays))d", "calendar"),
                ("Auto-clean", model.preferences.autoCleanOnLaunch ? "On" : "Off", "sparkles"),
            ])
            settingsCard("Storage", "Real local session and diagnostics actions.") {
                infoRow("Sessions folder", "~/.grok/sessions")
                slider("Retention days", value: pref(\.retentionDays), range: 7...365, suffix: "d")
                toggle("Auto-clean on launch", "Delete old session files on launch.", pref(\.autoCleanOnLaunch))
                toggle("Export before delete", "Keep this reminder enabled around destructive actions.", pref(\.exportBeforeDelete))
                toggle("Settings in diagnostics", "Include preferences in copied diagnostics.", pref(\.includeSettingsInDiagnostics))
                toggle("System info in diagnostics", "Include OS and bundle details.", pref(\.includeSystemInfoInDiagnostics))
                actionRow("Refresh storage", "Recompute storage size.", "arrow.clockwise") {
                    Task { storageInfo = await model.loadSessionStorageInfo(); showToast("Storage refreshed") }
                }
                actionRow("Reveal sessions", "Open the local sessions folder.", "folder") { model.openFileOrFolder(model.grokSessionsURL) }
                actionRow("Export sessions", "Write every summary to JSON.", "square.and.arrow.up") { exportSessions() }
                actionRow("Clear sessions", "Delete all local Grok sessions.", "trash") { confirmingClearSessions = true }
            }
            settingsCard("Maintenance", "Cleanup and settings import/export.") {
                actionRow("Run retention cleanup", "Delete session files older than the threshold.", "calendar.badge.minus") { confirmingRetention = true }
                actionRow("Clear temp attachments", "Delete Codessa temporary screenshot attachments.", "trash") {
                    model.clearTemporaryAttachments(completion: showToast)
                }
                actionRow("Reveal temp folder", "Open the temp attachment location.", "folder") { model.openFileOrFolder(model.grokTempAttachmentsURL) }
                actionRow("Export settings", "Write settings JSON.", "square.and.arrow.up") { model.exportPreferences(completion: showToast) }
                actionRow("Import settings", "Load settings JSON.", "square.and.arrow.down") { model.importPreferences(completion: showToast) }
                actionRow("Copy diagnostics", "Copy app diagnostics to clipboard.", "stethoscope") { model.copyDiagnostics(); showToast("Copied diagnostics") }
                actionRow("Open app support", "Open the app support folder.", "folder") { model.openFileOrFolder(model.appSupportURL) }
                actionRow("Clear pending chat", "Remove the optimistic New chat placeholder.", "bubble.left") { model.clearPendingChatPlaceholder(); showToast("Cleared pending chat placeholder") }
            }
            actionGrid([
                action("Reset Data settings", "arrow.counterclockwise") { model.resetPreferencesScope(.data); showToast("Reset Data settings") },
                action("Reset all settings", "exclamationmark.triangle") { confirmingResetAll = true },
                action("Copy sessions path", "doc.on.doc") { model.copyToClipboard(model.grokSessionsURL.path) },
                action("Refresh projects", "folder.badge.gearshape") { model.refreshProjects(); showToast("Projects refreshed") },
            ])
        }
    }

    private var archivedPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricGrid([
                ("Archived", "\(model.archivedProjects.count)", "archivebox"),
                ("Pinned safe", model.preferences.keepPinnedUnarchived ? "On" : "Off", "pin"),
                ("Auto archive", model.preferences.autoArchiveInactiveProjects ? "On" : "Off", "timer"),
                ("Candidates", "\(archiveCandidates.count)", "tray"),
            ])
            settingsCard("Archive Rules", "Filtering and automatic archive preferences.") {
                textFieldRow("Search archive", text: pref(\.archiveSearch))
                enumPicker("Sort", selection: pref(\.archiveSort), cases: AppPreferences.ArchiveSort.allCases)
                enumPicker("Filter", selection: pref(\.archiveFilter), cases: AppPreferences.ArchiveFilter.allCases)
                toggle("Keep pinned unarchived", "Do not archive pinned projects.", pref(\.keepPinnedUnarchived))
                toggle("Auto-archive inactive", "Enable the inactive-project candidate rule.", pref(\.autoArchiveInactiveProjects))
                slider("Inactive threshold", value: pref(\.archiveInactiveDays), range: 14...180, suffix: "d")
                actionRow("Archive selected project", "Archive the current project if allowed.", "archivebox") {
                    model.archiveSelectedProjectIfAllowed()
                    showToast("Archive rule applied")
                }
                actionRow("Preview candidates", "Count projects matching the inactive rule.", "eye") { showToast("\(archiveCandidates.count) archive candidate(s)") }
            }
            settingsCard("Archived Projects", "Restore or inspect hidden projects.") {
                if filteredArchivedProjects.isEmpty {
                    emptyLine("No archived projects match the current filters.")
                } else {
                    ForEach(filteredArchivedProjects) { project in
                        archivedProjectRow(project)
                    }
                }
            }
            actionGrid([
                action("Restore all", "tray.and.arrow.up") { model.restoreAllArchivedProjects(); showToast("Restored archived projects") },
                action("Empty archive", "trash") { confirmingEmptyArchive = true },
                action("Export archive list", "square.and.arrow.up") { model.exportArchiveList(completion: showToast) },
                action("Reset Archive settings", "arrow.counterclockwise") { model.resetPreferencesScope(.archive); showToast("Reset Archive settings") },
            ])
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon).resizable().frame(width: 58, height: 58)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codessa")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("Version \(AppViewModel.appVersionString)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(CodexTheme.textSecondary)
                    Text("A native macOS workspace for ChatGPT Codex.")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
            }
            .settingsCardChrome()

            updateCard

            settingsCard("App and System", "Useful support and local app details.") {
                infoRow("Bundle ID", Bundle.main.bundleIdentifier ?? "co.codessa.Codessa")
                infoRow("Install path", Bundle.main.bundlePath)
                infoRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                toggle("Check for updates automatically", "Quietly check on launch.", $update.automaticallyChecksOnLaunch)
                actionRow("Check for updates", "Open the update dialog.", "arrow.down.circle") { update.presentDialog() }
                actionRow("Copy version", "Copy version and build.", "doc.on.doc") { model.copyToClipboard(AppViewModel.appVersionString) }
                actionRow("Copy system info", "Copy OS and bundle details.", "desktopcomputer") { model.copySystemInfo(); showToast("Copied system info") }
                actionRow("Reveal app in Finder", "Show the running app bundle.", "folder") { model.revealInFinder(Bundle.main.bundleURL) }
                actionRow("Reset onboarding", "Show onboarding again.", "sparkles") { model.resetOnboarding(); showToast("Onboarding reset") }
            }

            settingsCard("Links and Support", "Every button opens or copies a real resource.") {
                linkRow("GitHub repository", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/LogicLeapLtd/grokcode")
                linkRow("Codex CLI docs", icon: "book", url: AgentProvider.codex.docsURL)
                linkRow("Report an issue", icon: "exclamationmark.bubble", url: "https://github.com/LogicLeapLtd/grokcode/issues/new")
                linkRow("Release notes", icon: "doc.text", url: "https://github.com/LogicLeapLtd/grokcode/releases")
                linkRow("Privacy", icon: "hand.raised", url: "https://github.com/LogicLeapLtd/grokcode")
                linkRow("Terms", icon: "checkmark.seal", url: "https://github.com/LogicLeapLtd/grokcode")
                actionRow("Copy diagnostics", "Copy support diagnostics.", "stethoscope") { model.copyDiagnostics(); showToast("Copied diagnostics") }
                actionRow("Open config folder", "Open ~/.grok.", "folder") { model.openFileOrFolder(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")) }
            }

            actionGrid([
                action("Reset all settings", "exclamationmark.triangle") { confirmingResetAll = true },
                action("Copy bundle ID", "doc.on.doc") { model.copyToClipboard(Bundle.main.bundleIdentifier ?? "co.codessa.Codessa") },
                action("Open support email", "envelope") { model.openExternalURL("mailto:support@logicleap.co.uk?subject=Codessa%20support") },
                action("Copy app path", "doc.on.doc") { model.copyToClipboard(Bundle.main.bundlePath) },
            ])
        }
    }

    private var updateCard: some View {
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
            }
            Spacer()
            pillButton(update.updateAvailableInBackground ? "Install…" : "Check now", icon: "arrow.down.circle") {
                update.presentDialog()
            }
        }
        .settingsCardChrome()
    }

    private var updateStatusDetail: String {
        if update.updateAvailableInBackground { return "Click to review the changes and install." }
        if !update.isRunningFromCanonicalLocation { return "Running outside /Applications; update can install to a stable location." }
        return "You're on version \(update.currentVersion)."
    }

    private var appearancePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Preview")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat message")
                        .font(.system(size: model.preferences.chatFontSize))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("Tool calls: \(model.preferences.toolCallStyle.label) · Density: \(model.preferences.messageDensity.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.preferences.showCodeLineNumbers ? "1  let answer = 42" : "let answer = 42")
                    Text(model.preferences.showCodeLineNumbers ? "2  print(answer)" : "print(answer)")
                }
                .font(.system(size: model.preferences.codeFontSize, design: .monospaced))
                .foregroundStyle(CodexTheme.textSecondary)
                .padding(10)
                .frame(width: 230, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(CodexTheme.mainBackground.opacity(0.55)))
            }
        }
        .settingsCardChrome()
    }

    private var personalizationRuleCount: Int {
        [
            model.preferences.preferBritishEnglish,
            model.preferences.avoidEmDashes,
            model.preferences.preserveUserWording,
            model.preferences.draftOnlyMessaging,
            model.preferences.showPlansByDefault,
            model.preferences.askBeforeAssumptions,
            model.preferences.includeStyleRules,
            model.preferences.includeProjectRules,
        ].filter { $0 }.count
    }

    private var shortcutConflictSummary: String {
        let values = model.preferences.customShortcuts.values
        let duplicates = Dictionary(grouping: values, by: { $0 }).filter { !$0.key.isEmpty && $0.value.count > 1 }
        if duplicates.isEmpty { return "No shortcut label conflicts." }
        return duplicates.map { "\($0.key): \($0.value.count) uses" }.sorted().joined(separator: "\n")
    }

    private var filteredMCPServers: [MCPServerInfo] {
        var rows = mcpServers
        let query = model.preferences.mcpSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
        }
        switch model.preferences.mcpFilter {
        case .all: break
        case .enabled: rows = rows.filter(\.enabled)
        case .disabled: rows = rows.filter { !$0.enabled }
        }
        switch model.preferences.mcpSort {
        case .name: rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .status: rows.sort { ($0.enabled ? 0 : 1, $0.name) < ($1.enabled ? 0 : 1, $1.name) }
        case .detail: rows.sort { $0.detail.localizedCaseInsensitiveCompare($1.detail) == .orderedAscending }
        }
        return rows
    }

    private var filteredHooks: [PendingHook] {
        var rows = model.pendingHooks
        let query = model.preferences.hookSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter { $0.event.localizedCaseInsensitiveContains(query) || $0.command.localizedCaseInsensitiveContains(query) || $0.fileName.localizedCaseInsensitiveContains(query) }
        }
        return rows
    }

    private var archiveCandidates: [Project] {
        let threshold = Int(model.preferences.archiveInactiveDays)
        guard model.preferences.autoArchiveInactiveProjects else { return [] }
        return model.projects.filter { project in
            if model.preferences.keepPinnedUnarchived, model.isPinned(project) { return false }
            guard let latest = project.lastActiveAt else { return true }
            let days = Calendar.current.dateComponents([.day], from: latest, to: Date()).day ?? 0
            return days >= threshold
        }
    }

    private var filteredArchivedProjects: [Project] {
        var rows = model.archivedProjects
        let query = model.preferences.archiveSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.path.path.localizedCaseInsensitiveContains(query) }
        }
        switch model.preferences.archiveFilter {
        case .all: break
        case .hasChats: rows = rows.filter { !$0.threads.isEmpty }
        case .empty: rows = rows.filter { $0.threads.isEmpty }
        }
        switch model.preferences.archiveSort {
        case .name: rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .chats: rows.sort { $0.threads.count > $1.threads.count }
        case .path: rows.sort { $0.path.path.localizedCaseInsensitiveCompare($1.path.path) == .orderedAscending }
        }
        return rows
    }

    private var shortcutItems: [ShortcutSettingItem] {
        [
            .init(id: "newChat", name: "New chat", defaultKeys: "⌘N"),
            .init(id: "commandPalette", name: "Command palette", defaultKeys: "⌘K"),
            .init(id: "search", name: "Search", defaultKeys: "⌘F"),
            .init(id: "settings", name: "Settings", defaultKeys: "⌘,"),
            .init(id: "home", name: "Home", defaultKeys: "⌘1"),
            .init(id: "plugins", name: "Plugins", defaultKeys: "⌘3"),
            .init(id: "automations", name: "Automations", defaultKeys: "⌘4"),
            .init(id: "split", name: "Open split view", defaultKeys: "⌥⌘S"),
            .init(id: "newWindow", name: "Open chat window", defaultKeys: "⇧⌘N"),
            .init(id: "stop", name: "Stop run", defaultKeys: "Esc"),
            .init(id: "cyclePermission", name: "Cycle permission", defaultKeys: "⇧⌘M"),
            .init(id: "attachFiles", name: "Attach files", defaultKeys: "⌘O"),
            .init(id: "attachApp", name: "Attach active app", defaultKeys: "⇧⌘A"),
            .init(id: "send", name: "Send", defaultKeys: "⌘⏎"),
            .init(id: "newline", name: "New line", defaultKeys: "⇧⏎"),
            .init(id: "focusComposer", name: "Focus composer", defaultKeys: "⌘L"),
            .init(id: "back", name: "Back", defaultKeys: "⌘["),
            .init(id: "forward", name: "Forward", defaultKeys: "⌘]"),
            .init(id: "openSelected", name: "Open selected chat", defaultKeys: "⏎"),
            .init(id: "closeModal", name: "Close modal", defaultKeys: "Esc"),
        ]
    }

    private func title(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(CodexTheme.accent.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CodexTheme.accent.opacity(0.22), lineWidth: 1))
            Text(text)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexTheme.textPrimary)
        }
        .padding(.bottom, 4)
    }

    private func settingsCard<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(CodexTheme.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
            }
            VStack(spacing: 0) {
                content()
            }
        }
        .settingsCardChrome()
    }

    private func metricGrid(_ metrics: [(String, String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 9) {
                    Image(systemName: item.2).font(.system(size: 13)).foregroundStyle(CodexTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.system(size: 10, weight: .medium)).foregroundStyle(CodexTheme.textTertiary)
                        Text(item.1).font(.system(size: 13, weight: .semibold)).foregroundStyle(CodexTheme.textPrimary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(CodexTheme.composerBackground.opacity(0.42)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CodexTheme.divider.opacity(0.56), lineWidth: 1))
            }
        }
    }

    private func toggle(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            rowLabel(title, subtitle)
            Spacer()
            Button { binding.wrappedValue.toggle() } label: { MiniSwitch(isOn: binding.wrappedValue) }
                .buttonStyle(.plain)
        }
        .rowPadding()
    }

    private func enumPicker<T: CaseIterable & Identifiable>(_ title: String, selection: Binding<T>, cases: T.AllCases) -> some View where T: Hashable, T.AllCases: RandomAccessCollection {
        menuRow(title, "", value: label(for: selection.wrappedValue)) {
            ForEach(cases) { option in
                Button(label(for: option)) { selection.wrappedValue = option }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue))\(suffix)").font(.system(size: 12, design: .monospaced)).foregroundStyle(CodexTheme.textSecondary)
            }
            Slider(value: value, in: range)
        }
        .rowPadding()
    }

    private func textFieldRow(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            rowLabel(title, "")
            Spacer()
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .frame(width: 260, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(CodexTheme.mainBackground.opacity(0.46)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(CodexTheme.divider, lineWidth: 1))
        }
        .rowPadding()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13)).foregroundStyle(CodexTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: value.contains("/") || value.contains("~") ? .monospaced : .default))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .rowPadding()
    }

    private func actionRow(_ title: String, _ subtitle: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(CodexTheme.textSecondary).frame(width: 18)
                rowLabel(title, subtitle)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CodexTheme.textTertiary)
            }
            .rowPadding()
            .contentShape(Rectangle())
            .codexHover(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }

    private func menuRow<MenuContent: View>(_ title: String, _ subtitle: String, value: String, @ViewBuilder menu: () -> MenuContent) -> some View {
        HStack(spacing: 12) {
            rowLabel(title, subtitle)
            Spacer()
            Menu {
                menu()
            } label: {
                HStack {
                    Text(value).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10)
                .frame(minWidth: 230, idealWidth: 250)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(CodexTheme.mainBackground.opacity(0.46)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(CodexTheme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .rowPadding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
            }
        }
    }

    private func actionGrid(_ actions: [SettingsAction]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(actions) { item in
                Button(action: item.action) {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon).font(.system(size: 12, weight: .medium))
                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(CodexTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(CodexTheme.pillBackground))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CodexTheme.divider.opacity(0.72), lineWidth: 1))
                    .codexHover(cornerRadius: 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func action(_ title: String, _ icon: String, action: @escaping () -> Void) -> SettingsAction {
        SettingsAction(title: title, icon: icon, action: action)
    }

    private func mcpRow(_ server: MCPServerInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: server.enabled ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(server.enabled ? Color.green : CodexTheme.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                if model.preferences.mcpShowDetails {
                    Text(server.detail.isEmpty ? "-" : server.detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(CodexTheme.textTertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            pillButton("Copy", icon: "doc.on.doc") { model.copyToClipboard("\(server.name): \(server.detail)") }
            Button { toggleMCP(server) } label: { MiniSwitch(isOn: server.enabled) }.buttonStyle(.plain)
        }
        .rowPadding()
    }

    private func hookRow(_ hook: PendingHook) -> some View {
        HStack(spacing: 10) {
            Image(systemName: AppViewModel.hookOrigin(for: hook).symbol).foregroundStyle(CodexTheme.textSecondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(hook.event).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                if model.preferences.hookShowCommandPreview {
                    Text(hook.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(CodexTheme.textTertiary).lineLimit(model.preferences.hookCompactView ? 1 : 2).truncationMode(.middle)
                }
            }
            Spacer()
            pillButton("Copy", icon: "doc.on.doc") { model.copyToClipboard(hook.command) }
            pillButton("Trust", icon: "checkmark.shield") { model.trustHook(hook) }
        }
        .rowPadding()
    }

    private func providerRow(_ status: ProviderStatus) -> some View {
        HStack(spacing: 10) {
            Text(status.provider.monogram)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CodexTheme.textPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(CodexTheme.pillBackground))
            VStack(alignment: .leading, spacing: 2) {
                Text(status.provider.name).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                Text(status.binaryPath ?? status.provider.installCommand).font(.system(size: 11, design: .monospaced)).foregroundStyle(CodexTheme.textTertiary).lineLimit(1).truncationMode(.middle)
                Text("\(status.runtimeState.label) · \(status.authStatus.label) · \(status.models.count) model\(status.models.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(status.runtimeState == .ready ? CodexTheme.textSecondary : CodexTheme.textTertiary)
                    .lineLimit(1)
                if let message = status.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if status.provider.isCustom {
                pillButton("Remove", icon: "minus.circle") { model.removeCustomProvider(status.provider) }
            }
            pillButton(model.selectedProviderId == status.provider.id ? "Selected" : "Select", icon: "checkmark") { model.selectProvider(status.provider.id) }
            pillButton("Docs", icon: "book") { model.openProviderDocs(status.provider) }
        }
        .rowPadding()
    }

    private func shortcutRow(_ item: ShortcutSettingItem) -> some View {
        let value = model.preferences.customShortcuts[item.id] ?? item.defaultKeys
        return HStack(spacing: 12) {
            rowLabel(item.name, "Default: \(item.defaultKeys)")
            Spacer()
            Button {
                var copy = model.preferences
                copy.customShortcuts[item.id] = nextShortcut(after: value, fallback: item.defaultKeys)
                model.preferences = copy
            } label: {
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 70, minHeight: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(CodexTheme.pillBackground))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(CodexTheme.divider, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .rowPadding()
    }

    private func archivedProjectRow(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox").foregroundStyle(CodexTheme.textSecondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                Text(project.path.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(CodexTheme.textTertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            pillButton("Copy", icon: "doc.on.doc") { model.copyToClipboard(project.path.path) }
            pillButton("Reveal", icon: "folder") { model.revealInFinder(project.path) }
            pillButton("Restore", icon: "tray.and.arrow.up") { model.unarchiveProject(project) }
        }
        .rowPadding()
    }

    private func linkRow(_ label: String, icon: String, url: String) -> some View {
        actionRow(label, url, icon) { model.openExternalURL(url) }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(CodexTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowPadding()
    }

    private func pillButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(CodexTheme.pillBackground))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pref<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { model.preferences[keyPath: keyPath] },
            set: { model.preferences[keyPath: keyPath] = $0 }
        )
    }

    private func label<T>(for value: T) -> String {
        if let v = value as? AppAppearance { return v.label }
        if let v = value as? SidebarGroupBy { return v.label }
        if let v = value as? SidebarSort { return v.label }
        if let v = value as? AppPreferences.LaunchPage { return v.label }
        if let v = value as? AppPreferences.NewChatLocation { return v.label }
        if let v = value as? AppPreferences.AttachmentBehavior { return v.label }
        if let v = value as? AppPreferences.Accent { return v.label }
        if let v = value as? AppPreferences.Density { return v.label }
        if let v = value as? AppPreferences.BubbleStyle { return v.label }
        if let v = value as? AppPreferences.ToolCallStyle { return v.label }
        if let v = value as? AppPreferences.ContextFilePolicy { return v.label }
        if let v = value as? AppPreferences.LanguagePreference { return v.label }
        if let v = value as? AppPreferences.ResponseLength { return v.label }
        if let v = value as? AppPreferences.ExplanationDepth { return v.label }
        if let v = value as? AppPreferences.TonePreset { return v.label }
        if let v = value as? AppPreferences.ShortcutPreset { return v.label }
        if let v = value as? AppPreferences.ServerFilter { return v.label }
        if let v = value as? AppPreferences.ServerSort { return v.label }
        if let v = value as? AppPreferences.HookFilter { return v.label }
        if let v = value as? AppPreferences.ArchiveSort { return v.label }
        if let v = value as? AppPreferences.ArchiveFilter { return v.label }
        return String(describing: value)
    }

    private func nextShortcut(after value: String, fallback: String) -> String {
        let options = [fallback, "⌥" + fallback, "⇧" + fallback, "Disabled"]
        guard let index = options.firstIndex(of: value) else { return options.first ?? fallback }
        return options[(index + 1) % options.count]
    }

    private func reloadMCP() {
        mcpLoading = true
        Task {
            mcpServers = await model.loadMCPServers()
            mcpLoading = false
            showToast("Loaded \(mcpServers.count) MCP server\(mcpServers.count == 1 ? "" : "s")")
        }
    }

    private func toggleMCP(_ server: MCPServerInfo) {
        if let index = mcpServers.firstIndex(of: server) {
            mcpServers[index] = MCPServerInfo(name: server.name, detail: server.detail, enabled: !server.enabled)
        }
        Task {
            if let refreshed = await model.setMCPServer(server, enabled: !server.enabled) {
                mcpServers = refreshed
                showToast("\(server.name) \(server.enabled ? "disabled" : "enabled")")
            } else {
                showToast("Couldn't update \(server.name)")
            }
        }
    }

    private func copyMCPDebug() {
        let text = filteredMCPServers.map { "\($0.enabled ? "on" : "off") \($0.name): \($0.detail)" }.joined(separator: "\n")
        model.copyToClipboard("Config: \(model.grokConfigURL.path)\n\(text)")
        showToast("Copied MCP debug info")
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

    private func runRetentionCleanup() {
        model.runRetentionCleanup(days: Int(model.preferences.retentionDays)) { message, info in
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

    @ViewBuilder
    private var toastBanner: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(CodexTheme.menuBackground).shadow(color: CodexTheme.menuShadow, radius: 12, y: 4))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CodexTheme.menuBorder, lineWidth: 1))
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct SettingsAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let action: () -> Void
}

private struct ShortcutSettingItem: Identifiable {
    let id: String
    let name: String
    let defaultKeys: String
}

private struct SettingsCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodexTheme.composerBackground.opacity(0.34)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CodexTheme.divider.opacity(0.56), lineWidth: 1))
            .shadow(color: CodexTheme.shadowColor.opacity(0.08), radius: 9, y: 3)
    }
}

private extension View {
    func settingsCardChrome() -> some View {
        modifier(SettingsCardChrome())
    }

    func rowPadding() -> some View {
        self
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CodexTheme.divider.opacity(0.45)).frame(height: 1)
            }
    }
}
