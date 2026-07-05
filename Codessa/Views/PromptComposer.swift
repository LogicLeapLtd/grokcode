import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PromptComposer: View {
    @Environment(AppViewModel.self) private var model
    @FocusState private var isFocused: Bool
    /// Highlights the composer while a file drag hovers over it (#13).
    @State private var isDropTargeted = false

    // MARK: Inline completions (slash commands + @file mentions)

    /// Bounded file index for `@` mentions, rebuilt when the project changes.
    @State private var fileIndex: [ComposerFileMatch] = []
    /// The project path the current `fileIndex` was built for (dedupes rescans).
    @State private var indexedProjectPath: String?
    /// Highlighted row in the open completion menu (arrow-key navigation).
    @State private var completionSelection = 0
    /// When `/model` is chosen, the menu expands into an inline model picker
    /// instead of navigating away (kept in-lane — no AppViewModel state needed).
    @State private var showingInlineModelPicker = false
    @State private var isProjectRowHovered = false
    @State private var showingModeConfiguration = false
    private let projectPickerControlMaxWidth: CGFloat = 188
    private let projectPickerMenuWidth: CGFloat = 240
    private let projectPickerNameMaxWidth: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.pendingHooks.isEmpty {
                HooksBanner()
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    .transition(CodexMotion.bannerTransition)
            } else if !model.grokAvailable {
                GrokMissingBanner()
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    .transition(CodexMotion.bannerTransition)
            }

            VStack(alignment: .leading, spacing: 0) {
                if !model.composerAttachments.isEmpty {
                    AttachmentRow(
                        attachments: model.composerAttachments,
                        onRemove: { model.removeComposerAttachment($0) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .transition(CodexMotion.bannerTransition)
                }

                inputArea
                    .padding(.horizontal, 18)
                    .padding(.top, 17)
                    .padding(.bottom, 8)

                toolbarRow
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
            }

            contextStrip
                .overlay(alignment: .top) {
                    contextDividerLine
                }
        }
        // Liquid Glass composer shell (macOS 26+); solid fallback otherwise.
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous),
            fallback: CodexTheme.composerShellBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous)
                .strokeBorder(CodexTheme.textTertiary.opacity(0.28), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous)
                .strokeBorder(CodexTheme.composerShellHighlight, lineWidth: 1)
                .padding(1)
                .allowsHitTesting(false)
        }
        // Drag-and-drop file highlight (#13).
        .overlay {
            RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous)
                .strokeBorder(CodexTheme.accentOrange, lineWidth: 1.5)
                .opacity(isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        // Focus ring: cool and restrained so it reads as input focus rather than
        // competing with the ambient canvas or the permission/status accents.
        .overlay {
            RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous)
                .strokeBorder(CodexTheme.textTertiary.opacity(0.36), lineWidth: 1)
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous))
        .shadow(color: CodexTheme.shadowColor, radius: 3, y: 2)
        .shadow(color: CodexTheme.shadowColor.opacity(isFocused ? 0.10 : 0),
                radius: isFocused ? 10 : 0)
        .animation(CodexMotion.panelSpring, value: isFocused)
        // The slash / @-mention completion menu floats ABOVE the whole composer.
        // It's attached here — after `.clipShape` — so it is neither clipped by
        // the composer shell nor drawn under the toolbar controls.
        .overlay(alignment: .topLeading) { completionMenuOverlay }
        // Drop files anywhere on the composer to attach them (#13).
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            model.handleComposerDrop(providers)
        }
        .sheet(isPresented: $showingModeConfiguration) {
            ModeConfigurationSheet()
                .environment(model)
        }
        .animation(CodexMotion.panelSpring, value: model.pendingHooks.count)
        .animation(CodexMotion.panelSpring, value: model.grokAvailable)
        .animation(CodexMotion.quickSpring, value: model.composerAttachments)
        .animation(CodexMotion.quickSpring, value: isDropTargeted)
        .onAppear { isFocused = true }
    }

    private var contextDividerLine: some View {
        Rectangle()
            .fill(CodexTheme.divider.opacity(0.42))
            .frame(height: 1)
    }

    // MARK: - Inline completion model

    /// What the composer is completing right now, derived from the prompt text.
    /// Suppressed entirely while a run is in flight (the field is for queuing a
    /// follow-up then, not issuing commands).
    private var activeCompletion: ComposerCompletion {
        guard !model.isRunning else { return .none }
        return ComposerCompletion.detect(in: model.promptText)
    }

    /// The slash commands matching the current "/query" (empty when not slashing).
    private var slashMatches: [SlashCommand] {
        if case let .slash(query) = activeCompletion { return SlashCommand.matching(query) }
        return []
    }

    /// The file matches for the current "@query" (empty when not mentioning).
    private var fileMatches: [ComposerFileMatch] {
        if case let .file(query) = activeCompletion {
            return ComposerFileIndex.matches(query, in: fileIndex)
        }
        return []
    }

    /// Whether a completion menu is currently on screen.
    private var completionMenuVisible: Bool {
        switch activeCompletion {
        case .slash:
            return showingInlineModelPicker ? !model.models.isEmpty : !slashMatches.isEmpty
        case .file:
            return !fileMatches.isEmpty
        case .none:
            return false
        }
    }

    private var inputArea: some View {
        // While a run is in flight, Codex keeps the field live so you can queue
        // a follow-up; the placeholder hints at that.
        TextField("", text: Binding(
            get: { model.promptText },
            set: { model.promptText = $0 }
        ), axis: .vertical)
        .font(CodexTheme.composerInputFont)
        .foregroundStyle(CodexTheme.textPrimary)
        .textFieldStyle(.plain)
        .lineLimit(1...8)
        .frame(minHeight: 24, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .focused($isFocused)
        // Keep the completion menu's highlighted row & inline-picker state sane
        // as the query changes underneath it.
        .onChange(of: model.promptText) { _, _ in
            completionSelection = 0
            // Leaving slash context (e.g. text cleared / a space typed) closes
            // the inline model picker.
            if case .slash = activeCompletion {} else { showingInlineModelPicker = false }
        }
        .task(id: model.selectedProject?.path.path) { await rebuildFileIndexIfNeeded() }
        // Arrow / Tab / Return navigation for the completion menu. These run
        // BEFORE the send-on-return handler below, so when the menu is open
        // Return accepts a completion instead of sending.
        .onKeyPress(.upArrow) { moveCompletionSelection(-1) }
        .onKeyPress(.downArrow) { moveCompletionSelection(1) }
        .onKeyPress(.tab) { acceptHighlightedCompletion() }
        .onKeyPress(.return, phases: .down) { press in
            let shift = press.modifiers.contains(.shift)
            let command = press.modifiers.contains(.command)
            // When the completion menu is open, a plain Return accepts the
            // highlighted row. ⇧/⌘ bypass it (newline / send).
            if completionMenuVisible, !shift, !command {
                return acceptHighlightedCompletion()
            }
            // ⇧-Return is always a newline — never sends. Returning .ignored
            // lets the vertical TextField insert the line break itself.
            if shift { return .ignored }
            // ⌘-Return always sends; a plain Return sends only when the
            // send-on-return preference is enabled (#13 / Settings).
            guard command || model.sendOnReturn else { return .ignored }
            let trimmed = model.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .ignored }
            model.submit()
            return .handled
        }
        .onKeyPress(.escape) {
            // An open completion menu swallows Esc first (just dismiss it).
            if completionMenuVisible {
                if showingInlineModelPicker { showingInlineModelPicker = false }
                else { dismissCompletionMenu() }
                return .handled
            }
            // Esc stops an in-flight run (menus, when open, swallow Esc first).
            if model.isRunning { model.cancelRun(); return .handled }
            return .ignored
        }
        // Cmd-V of an image or file URL attaches it (#13). Declaring only
        // image/file types means a plain-text paste isn't intercepted and still
        // lands in the field as usual.
        .onPasteCommand(of: [.image, .fileURL]) { _ in
            model.handleComposerPaste()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .placeholderOverlay(model.isRunning ? "Queue a follow-up…" : "Do anything",
                            visible: model.promptText.isEmpty,
                            alignment: .topLeading,
                            font: CodexTheme.composerInputFont)
        // NOTE: the completion menu is intentionally NOT overlaid here. The
        // composer clips its content (rounded shell) and the toolbar row draws
        // over this field, so a menu anchored to the field was both clipped and
        // covered by the permission/model controls. It's rendered on the root
        // composer view instead (see `completionMenuOverlay`).
    }

    // MARK: - Completion menu surface

    /// The completion menu pinned above the composer's top edge. Uses an
    /// alignment guide so the card's BOTTOM rests on the composer's TOP (i.e. it
    /// opens upward), with a small gap. Rendered on the root composer view so it
    /// escapes the shell's clip and sits above the toolbar in z-order.
    @ViewBuilder
    private var completionMenuOverlay: some View {
        completionMenu
            .alignmentGuide(.top) { d in d[.bottom] }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .offset(y: -6)
            .animation(.easeOut(duration: 0.12), value: completionMenuVisible)
            .animation(.easeOut(duration: 0.10), value: completionSelection)
            .animation(.easeOut(duration: 0.12), value: showingInlineModelPicker)
    }

    @ViewBuilder
    private var completionMenu: some View {
        if completionMenuVisible {
            completionCard {
                switch activeCompletion {
                case .slash:
                    if showingInlineModelPicker {
                        inlineModelRows
                    } else {
                        slashRows
                    }
                case .file:
                    fileRows
                case .none:
                    EmptyView()
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// The floating card chrome, matched to `CodexMenu`'s host styling.
    private func completionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 1) { content() }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodexTheme.menuBackground)
                    .shadow(color: CodexTheme.menuShadow, radius: 16, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CodexTheme.menuBorder, lineWidth: 1)
            )
            .fixedSize(horizontal: false, vertical: true)
    }

    private var slashRows: some View {
        let matches = slashMatches
        return ForEach(Array(matches.enumerated()), id: \.element.id) { idx, cmd in
            CompletionRow(
                title: cmd.title,
                subtitle: cmd.subtitle,
                systemImage: cmd.systemImage,
                isHighlighted: idx == clampedSelection(matches.count)
            ) { runSlashCommand(cmd) }
            .onHover { if $0 { completionSelection = idx } }
        }
    }

    @ViewBuilder
    private var inlineModelRows: some View {
        CodexMenuSectionHeader(title: "Model")
        ForEach(Array(model.models.enumerated()), id: \.element.id) { idx, option in
            CompletionRow(
                title: option.displayName,
                subtitle: option.providerName,
                providerLogoId: option.providerId,
                isHighlighted: idx == clampedSelection(model.models.count),
                isSelected: model.selectedModel == option
            ) {
                model.selectModel(option)
                showingInlineModelPicker = false
                clearSlashText()
            }
            .onHover { if $0 { completionSelection = idx } }
        }
    }

    private var fileRows: some View {
        let matches = fileMatches
        return ForEach(Array(matches.enumerated()), id: \.element.id) { idx, match in
            CompletionRow(
                title: match.relativePath.isEmpty ? match.fileName : match.relativePath,
                subtitle: nil,
                systemImage: match.iconSystemName,
                isHighlighted: idx == clampedSelection(matches.count)
            ) { insertFileMention(match) }
            .onHover { if $0 { completionSelection = idx } }
        }
    }

    // MARK: - Completion logic

    /// Number of rows in the currently-open menu, used to clamp navigation.
    private var completionRowCount: Int {
        switch activeCompletion {
        case .slash: return showingInlineModelPicker ? model.models.count : slashMatches.count
        case .file: return fileMatches.count
        case .none: return 0
        }
    }

    /// `completionSelection` clamped to a valid index for `count` rows.
    private func clampedSelection(_ count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, completionSelection), count - 1)
    }

    /// Move the highlight by `delta`, wrapping. Swallows the key only when the
    /// menu is open so arrow keys behave normally in plain text.
    private func moveCompletionSelection(_ delta: Int) -> KeyPress.Result {
        guard completionMenuVisible, completionRowCount > 0 else { return .ignored }
        let count = completionRowCount
        completionSelection = ((clampedSelection(count) + delta) % count + count) % count
        return .handled
    }

    /// Run the highlighted row's action. Returns `.handled` when a menu was open.
    private func acceptHighlightedCompletion() -> KeyPress.Result {
        guard completionMenuVisible else { return .ignored }
        let idx = clampedSelection(completionRowCount)
        switch activeCompletion {
        case .slash:
            if showingInlineModelPicker {
                let options = model.models
                guard options.indices.contains(idx) else { return .handled }
                let option = options[idx]
                model.selectModel(option)
                showingInlineModelPicker = false
                clearSlashText()
            } else {
                let matches = slashMatches
                guard matches.indices.contains(idx) else { return .handled }
                runSlashCommand(matches[idx])
            }
        case .file:
            let matches = fileMatches
            guard matches.indices.contains(idx) else { return .handled }
            insertFileMention(matches[idx])
        case .none:
            return .ignored
        }
        return .handled
    }

    /// Execute a slash command. Navigation commands clear the slash first; the
    /// inline-model command flips the menu into a model picker in place.
    private func runSlashCommand(_ cmd: SlashCommand) {
        completionSelection = 0
        switch cmd.kind {
        case .navigation:
            clearSlashText()
            switch cmd.id {
            case "new":         model.startNewChat()
            case "search":      model.navigateTo(.search)
            case "plugins":     model.navigateTo(.plugins)
            case "automations": model.navigateTo(.automations)
            case "settings":    model.navigateTo(.settings)
            default: break
            }
        case .action:
            switch cmd.id {
            case "clear":
                model.promptText = ""
            case "plan":
                model.isPlanMode.toggle()
                clearSlashText()
            default:
                clearSlashText()
            }
        case .inlineModel:
            // Stay in slash context, but render the model picker rows.
            showingInlineModelPicker = true
            completionSelection = max(0, model.models.firstIndex { $0 == model.selectedModel } ?? 0)
        }
    }

    /// Replace the trailing `@query` token with the file's `[<path>]` attachment
    /// token — the exact bracket format the composer already parses into chips.
    private func insertFileMention(_ match: ComposerFileMatch) {
        guard let atIndex = model.promptText.lastIndex(of: "@") else { return }
        let token = "[\(match.absolutePath)]"
        var text = model.promptText
        text.replaceSubrange(atIndex..., with: token + " ")
        model.promptText = text
        completionSelection = 0
    }

    /// Clear the whole prompt when it's purely the slash command being run
    /// (navigation/plan), so the field is empty after we jump away.
    private func clearSlashText() {
        if case .slash = ComposerCompletion.detect(in: model.promptText) {
            model.promptText = ""
        }
        showingInlineModelPicker = false
        completionSelection = 0
    }

    /// Force the menu shut (Esc with no inline picker open): drop the lone slash.
    private func dismissCompletionMenu() {
        if case .slash = activeCompletion { model.promptText = "" }
        showingInlineModelPicker = false
        completionSelection = 0
    }

    /// (Re)build the `@`-mention file index for the selected project, off-main.
    /// Skipped when there's no project or the index is already current.
    private func rebuildFileIndexIfNeeded() async {
        guard let root = model.selectedProject?.path else {
            fileIndex = []
            indexedProjectPath = nil
            return
        }
        let path = root.standardizedFileURL.path
        guard path != indexedProjectPath else { return }
        let scanned = await Task.detached(priority: .utility) {
            ComposerFileIndex.scan(root: root)
        }.value
        fileIndex = scanned
        indexedProjectPath = path
    }

    private var toolbarRow: some View {
        // Group the glass controls so adjacent surfaces blend fluidly (the
        // canonical Liquid Glass treatment); plain HStack on older systems.
        if #available(macOS 26.0, *) {
            return AnyView(
                GlassEffectContainer(spacing: 7) {
                    HStack(spacing: 7) {
                        addMenu
                        modeMenu
                        if showsSeparatePermissionMenu {
                            permissionMenu
                        }
                        Spacer(minLength: 10)
                        modelEffortMenu
                        if model.selectedModel?.reasoningDescriptor != nil {
                            reasoningMenu
                        }
                        sendButton
                    }
                }
            )
        } else {
            return AnyView(
                HStack(spacing: 7) {
                    addMenu
                    modeMenu
                    // Plan agent-mode already locks permissions to read-only, so
                    // showing a second "Plan mode" permission pill is redundant.
                    if showsSeparatePermissionMenu {
                        permissionMenu
                    }
                    Spacer(minLength: 10)
                    modelEffortMenu
                    if model.selectedModel?.reasoningDescriptor != nil {
                        reasoningMenu
                    }
                    sendButton
                }
            )
        }
    }

    private var showsSeparatePermissionMenu: Bool {
        model.activeAgentMode.kind != .plan
    }

    private var addMenu: some View {
        CodexMenuTrigger(minWidth: 260, edge: .top, highlightOnHover: false,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "add") { _ in
            ComposerIconControl(systemImage: "plus")
        } menu: { close in
            CodexMenuContainer {
                CodexMenuItem(title: "Add photos & files", systemImage: "paperclip") {
                    close(); model.attachFiles()
                }
                if let app = model.lastActiveApp {
                    attachAppRow(app, close: close)
                }

                CodexMenuDivider()

                // Plan is a first-class control via the always-visible mode pill
                // (and the ⇧⌘M permission menu), so a third "Plan mode" toggle here
                // was redundant — removed to stop Plan showing up three times.
                CodexMenuToggle(
                    title: "Pursue goal",
                    systemImage: "scope",
                    isOn: Binding(get: { model.pursueGoal }, set: { model.pursueGoal = $0 })
                )

                CodexMenuDivider()

                pluginsFlyout(close: close)
            }
        }
    }

    private var modeMenu: some View {
        CodexMenuTrigger(minWidth: 300, edge: .top, highlightOnHover: false,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "mode") { _ in
            HStack(spacing: 7) {
                Image(systemName: model.activeAgentMode.kind.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textSecondary)
                Text(model.activeAgentMode.name)
                    .font(CodexTheme.composerLabelFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .composerControlCapsule(accented: model.activeAgentMode.kind == .plan)
        } menu: { close in
            CodexMenuContainer {
                CodexMenuSectionHeader(title: "Mode")
                ForEach(model.agentModes) { mode in
                    CodexMenuItem(
                        title: mode.name,
                        subtitle: mode.routeSummary,
                        systemImage: mode.kind.symbol,
                        isSelected: model.activeAgentModeID == mode.id
                    ) {
                        model.selectAgentMode(mode.id)
                        close()
                    }
                }

                if let note = model.activeModeRuntimeNote {
                    CodexMenuDivider()
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }

                CodexMenuDivider()

                CodexMenuItem(title: "Configure modes…", systemImage: "slider.horizontal.3") {
                    close()
                    showingModeConfiguration = true
                }
            }
        }
    }

    /// The "+ → Plugins" flyout: lists installed plugins (icon + name), or a
    /// muted "No active plugins" row, and always a bottom "Manage plugins" item
    /// that jumps to the Plugins page.
    private func pluginsFlyout(close: @escaping () -> Void) -> some View {
        CodexFlyoutItem(title: "Plugins", systemImage: "puzzlepiece.extension") {
            let active = model.installedPlugins
            if active.isEmpty {
                Text("No active plugins")
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(active) { plugin in
                    CodexMenuItem(title: plugin.displayName, systemImage: plugin.iconSystemName) {
                        close(); model.navigateTo(.plugins)
                    }
                }
            }

            CodexMenuDivider()

            CodexMenuItem(title: "Manage plugins", systemImage: "slider.horizontal.3") {
                close(); model.navigateTo(.plugins)
            }
        }
    }

    private func attachAppRow(_ app: NSRunningApplication, close: @escaping () -> Void) -> some View {
        Button { close(); model.attachActiveApp() } label: {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 16)
                }
                Text("Attach \(app.localizedName ?? "app")")
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .codexHover(cornerRadius: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var permissionMenu: some View {
        CodexMenuTrigger(minWidth: 260, edge: .top, highlightOnHover: false,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "permission") { _ in
            HStack(spacing: 6) {
                if model.permissionMode == .fullAccess {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexTheme.accentOrange)
                }
                Text(model.permissionMode.label)
                    .font(CodexTheme.composerLabelFont)
                    .foregroundStyle(model.permissionMode == .fullAccess ? CodexTheme.accentOrange : CodexTheme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .composerControlCapsule(accented: model.permissionMode == .fullAccess)
        } menu: { close in
            CodexMenuContainer {
                CodexMenuSectionHeader(title: "Mode", keys: ["⇧", "⌘", "M"])
                ForEach(Array(PermissionMode.allCases.enumerated()), id: \.element) { idx, mode in
                    CodexMenuItem(
                        title: mode.label,
                        subtitle: mode.detail,
                        systemImage: mode.symbol,
                        isSelected: model.permissionMode == mode,
                        shortcut: "\(idx + 1)"
                    ) { model.applyPermissionMode(mode); close() }
                }
            }
        }
    }

    // Codex-style combined control: "<Provider · Model> <Option> ⌄".
    private var modelEffortMenu: some View {
        CodexMenuTrigger(minWidth: 320, edge: .top, maxHeight: 380, highlightOnHover: false,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "model") { _ in
            HStack(spacing: 7) {
                ProviderLogo(
                    providerId: model.selectedModel?.providerId ?? AgentProvider.codex.id,
                    size: 16,
                    foreground: CodexTheme.textSecondary
                )
                Text(model.selectedModel?.displayName ?? "Model")
                    .font(CodexTheme.composerLabelFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .composerControlCapsule()
        } menu: { close in
            // Reasoning now lives in its own dropdown, so exclude it here and
            // keep this menu to the model list plus any other provider options.
            let reasoningDescriptorID = model.selectedModel?.reasoningDescriptor?.id
            let optionDescriptors = (model.selectedModel?.optionDescriptors ?? [])
                .filter { $0.id != reasoningDescriptorID }
            CodexMenuContainer {
                // The provider/model list scrolls inside a capped region so the
                // menu can't balloon to fill the whole window when it opens
                // upward. The reasoning selector below stays pinned and visible.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.providerStatuses.filter { !$0.models.isEmpty }) { status in
                            CodexMenuSectionHeader(title: status.provider.shortName)
                            ForEach(status.models) { option in
                                ModelMenuItem(
                                    option: option,
                                    isSelected: model.selectedModel?.providerId == option.providerId && model.selectedModel?.id == option.id
                                ) {
                                    withAnimation(CodexMotion.panelSpring) {
                                        model.selectModel(option)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)

                if !optionDescriptors.isEmpty {
                    providerOptionMenuSections(optionDescriptors, close: close)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
            .animation(CodexMotion.panelSpring, value: optionDescriptors)
        }
    }

    // Standalone reasoning-effort control, separate from the model picker.
    @ViewBuilder
    private var reasoningMenu: some View {
        if let descriptor = model.selectedModel?.reasoningDescriptor {
            let selectedValue = model.selectedOptionValue(for: descriptor)
            let selectedTitle = descriptor.choices
                .first(where: { $0.id == selectedValue })?.title ?? descriptor.title
            CodexMenuTrigger(minWidth: 220, edge: .top, highlightOnHover: false,
                             autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "reasoning") { _ in
                HStack(spacing: 7) {
                    Image(systemName: "brain")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textSecondary)
                    Text(selectedTitle)
                        .font(CodexTheme.composerLabelFont)
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                .fixedSize(horizontal: true, vertical: false)
                .composerControlCapsule()
            } menu: { close in
                CodexMenuContainer {
                    CodexMenuSectionHeader(title: descriptor.title)
                    ForEach(descriptor.choices) { choice in
                        CodexMenuItem(
                            title: choice.title,
                            isSelected: selectedValue == choice.id
                        ) {
                            model.setSelectedOptionValue(choice.id, for: descriptor)
                            close()
                        }
                    }
                }
            }
        }
    }

    private func providerOptionMenuSections(_ descriptors: [ProviderOptionDescriptor], close: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(descriptors) { descriptor in
                CodexMenuDivider()
                CodexMenuSectionHeader(title: descriptor.title)
                if descriptor.kind == .readOnly, let detail = descriptor.detail {
                    Text(detail)
                        .font(CodexTheme.sans(11))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 9)
                        .padding(.bottom, 3)
                }
                HStack(spacing: 6) {
                    ForEach(descriptor.choices) { choice in
                        ProviderOptionChoicePill(
                            title: choice.title,
                            isSelected: model.selectedOptionValue(for: descriptor) == choice.id
                        ) {
                            model.setSelectedOptionValue(choice.id, for: descriptor)
                            close()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 5)
            }
        }
    }

    private var sendButton: some View {
        let isActive = model.isRunning || model.canSend

        return Button {
            if model.isRunning {
                model.cancelRun()
            } else {
                model.submit()
            }
        } label: {
            Image(systemName: model.isRunning ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? CodexTheme.sendButtonActiveForeground : CodexTheme.sendButtonForeground)
                .frame(width: 30, height: 30)
                .liquidGlass(
                    in: Circle(),
                    interactive: true,
                    tint: isActive ? CodexTheme.sendButtonActiveBackground : nil,
                    fallback: isActive ? CodexTheme.sendButtonActiveBackground : CodexTheme.sendButtonBackground
                )
                .codexHoverOverlay(Circle(), enabled: isActive)
        }
        .buttonStyle(CodexPressableStyle(scale: 0.92))
        .disabled(!model.isRunning && !model.canSend)
        .animation(CodexMotion.quickSpring, value: model.isRunning)
        .animation(CodexMotion.quickSpring, value: model.canSend)
    }

    private var contextStrip: some View {
        HStack(spacing: 8) {
            projectRow

            Spacer(minLength: 8)

            if model.isPlanMode {
                ComposerStatusChip(systemImage: "list.bullet.clipboard", title: "Plan")
            }
            if model.pursueGoal {
                ComposerStatusChip(systemImage: "scope", title: "Goal")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodexTheme.composerShellBackground.opacity(0.34))
    }

    private var showsProjectClearButton: Bool {
        isProjectRowHovered && !model.workWithoutProject && model.selectedProject != nil
    }

    private var projectRow: some View {
        ZStack(alignment: .trailing) {
            CodexMenuTrigger(minWidth: projectPickerMenuWidth, maxWidth: projectPickerMenuWidth, edge: .top, highlightOnHover: false,
                             autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "project") { _ in
                HStack(spacing: 8) {
                    Image(systemName: model.workWithoutProject ? "folder.badge.minus" : "folder")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(CodexTheme.pillBackground.opacity(0.46))
                        )
                    Text(model.workWithoutProject ? "No project" : (model.selectedProject?.name ?? "Select project"))
                        .font(CodexTheme.composerMetaFont.weight(.semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: projectPickerNameMaxWidth, alignment: .leading)
                    if !model.workWithoutProject, let branch = model.selectedProject?.gitBranch {
                        branchChip(branch)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(width: 20, height: 20)
                        .opacity(showsProjectClearButton ? 0 : 1)
                }
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(CodexTheme.composerBackground.opacity(0.58))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(CodexTheme.textTertiary.opacity(0.16), lineWidth: 0.75)
                )
                .codexHoverOverlay(Capsule(style: .continuous))
                .shadow(color: CodexTheme.shadowColor.opacity(0.06), radius: 5, y: 1)
                .contentShape(Capsule(style: .continuous))
            } menu: { close in
                CodexMenuContainer {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(CodexTheme.textTertiary)
                        TextField("", text: Binding(
                            get: { model.projectPickerQuery },
                            set: { model.projectPickerQuery = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .placeholderOverlay("Search projects", visible: model.projectPickerQuery.isEmpty)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)

                    CodexMenuDivider()

                    ForEach(model.pickerProjects.prefix(8)) { project in
                        CodexMenuItem(
                            title: project.name,
                            systemImage: "folder",
                            isSelected: !model.workWithoutProject && model.selectedProject?.id == project.id
                        ) { model.selectProject(project); model.projectPickerQuery = ""; close() }
                    }

                    CodexMenuDivider()

                    // Per-project context editor — only meaningful with a project
                    // selected (it edits that project's AGENTS.md / GROK.md).
                    if !model.workWithoutProject, let selected = model.selectedProject {
                        CodexMenuItem(title: "Edit project context", systemImage: "doc.text") {
                            close(); model.openProjectContext(for: selected)
                        }
                    }

                    CodexMenuItem(title: "Add new project", systemImage: "folder.badge.plus") {
                        close(); model.addProjectFromPicker()
                    }
                    CodexMenuItem(
                        title: "Don't work in a project",
                        systemImage: "folder.badge.minus",
                        isSelected: model.workWithoutProject
                    ) { model.clearProjectSelection(); model.projectPickerQuery = ""; close() }
                }
            }

            if showsProjectClearButton {
                Button {
                    model.clearProjectSelection()
                    model.projectPickerQuery = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(CodexTheme.pillBackground.opacity(0.56)))
                        .overlay(Circle().strokeBorder(CodexTheme.textTertiary.opacity(0.20), lineWidth: 0.75))
                        .codexHoverOverlay(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(CodexPressableStyle(scale: 0.9))
                .padding(.trailing, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .help("Deselect project")
                .zIndex(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: projectPickerControlMaxWidth, alignment: .leading)
        .onHover { hovering in
            withAnimation(CodexMotion.quickSpring) {
                isProjectRowHovered = hovering
            }
        }
        .animation(CodexMotion.quickSpring, value: showsProjectClearButton)
    }

    private func branchChip(_ branch: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .medium))
            Text(branch)
                .font(CodexTheme.technicalLabelFont)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(CodexTheme.textTertiary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: 150)
        .background(Capsule(style: .continuous).fill(CodexTheme.pillBackground.opacity(0.40)))
    }
}

private struct ComposerIconControl: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CodexTheme.textSecondary)
            .frame(width: 30, height: 30)
            .liquidGlass(in: Circle(),
                         interactive: true,
                         fallback: CodexTheme.pillBackground.opacity(0.7))
            .overlay(
                Circle()
                    .strokeBorder(CodexTheme.composerBorder.opacity(0.58), lineWidth: 0.75)
            )
            .codexHoverOverlay(cornerRadius: 15)
            .contentShape(Rectangle())
    }
}

private struct ComposerStatusChip: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(CodexTheme.composerMetaFont.weight(.semibold))
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.36)))
        .overlay(Capsule().strokeBorder(CodexTheme.textTertiary.opacity(0.22), lineWidth: 0.75))
    }
}

private extension View {
    func composerControlCapsule(accented: Bool = false) -> some View {
        self
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .liquidGlass(in: Capsule(), interactive: true, fallback: CodexTheme.pillBackground.opacity(0.68))
            .overlay(
                Capsule()
                    .strokeBorder(
                        accented ? CodexTheme.accentOrange.opacity(0.44) : CodexTheme.textTertiary.opacity(0.24),
                        lineWidth: 0.75
                    )
            )
            .codexHoverOverlay(Capsule())
    }
}

private extension AppViewModel {
    var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasComposerAttachments
    }
}

// MARK: - Completion menu row

/// A single row in the inline slash/@-mention completion menu. Mirrors
/// `CodexMenuItem`'s look, but takes an externally-driven `isHighlighted` so the
/// keyboard (arrow keys) and hover can both steer the selection.
private struct CompletionRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var providerLogoId: String? = nil
    var isHighlighted: Bool = false
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let providerLogoId {
                    ProviderLogo(providerId: providerLogoId, size: 16, foreground: CodexTheme.textSecondary)
                        .frame(width: 16, height: 16)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(CodexTheme.composerMetaFont)
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(CodexTheme.smallFont)
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 16)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHighlighted ? CodexTheme.hoverBackground : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderOptionChoicePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    private var fill: Color {
        if isSelected { return CodexTheme.accent.opacity(0.16) }
        if hovering { return CodexTheme.hoverBackground }
        return CodexTheme.pillBackground.opacity(0.48)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CodexTheme.sans(11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? CodexTheme.accent : CodexTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(minWidth: 42)
                .background(
                    Capsule(style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? CodexTheme.accent.opacity(0.42) : CodexTheme.divider.opacity(0.45), lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Composer attachments (#13)

/// Horizontal, wrapping-friendly row of attachment chips shown above the input
/// whenever the prompt carries `[<path>]` attachment tokens.
private struct AttachmentRow: View {
    let attachments: [ComposerAttachment]
    var onRemove: (ComposerAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChipView(path: attachment.path) { onRemove(attachment) }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
