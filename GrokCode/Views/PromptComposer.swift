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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.pendingHooks.isEmpty {
                HooksBanner()
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .transition(CodexMotion.bannerTransition)
            } else if !model.grokAvailable {
                GrokMissingBanner()
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .transition(CodexMotion.bannerTransition)
            }

            // White input area (attachments + prompt + toolbar).
            VStack(alignment: .leading, spacing: 0) {
                if !model.composerAttachments.isEmpty {
                    AttachmentRow(
                        attachments: model.composerAttachments,
                        onRemove: { model.removeComposerAttachment($0) }
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .transition(CodexMotion.bannerTransition)
                }

                inputArea
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                toolbarRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            .background(CodexTheme.composerBackground)

            // Gray footer holding the project/folder selector (Codex-style).
            projectRow
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CodexTheme.composerShellBackground)
        }
        .background(
            RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous)
                .fill(CodexTheme.composerShellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous)
                .strokeBorder(CodexTheme.composerShellBorder, lineWidth: 1)
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
                .strokeBorder(CodexTheme.accentOrange, lineWidth: 2)
                .opacity(isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous))
        .shadow(color: CodexTheme.shadowColor, radius: 3, y: 2)
        // Drop files anywhere on the composer to attach them (#13).
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            model.handleComposerDrop(providers)
        }
        .animation(CodexMotion.panelSpring, value: model.pendingHooks.count)
        .animation(CodexMotion.panelSpring, value: model.grokAvailable)
        .animation(CodexMotion.quickSpring, value: model.composerAttachments)
        .animation(CodexMotion.quickSpring, value: isDropTargeted)
        .onAppear { isFocused = true }
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
        .font(CodexTheme.bodyFont)
        .foregroundStyle(CodexTheme.textPrimary)
        .textFieldStyle(.plain)
        .lineLimit(1...8)
        .frame(minHeight: 22, alignment: .topLeading)
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
            // When the completion menu is open, plain Return accepts the
            // highlighted row rather than sending the message.
            if completionMenuVisible, !press.modifiers.contains(.shift) {
                return acceptHighlightedCompletion()
            }
            // Respect the send-on-return preference (#13 / Settings):
            //  • sendOnReturn:  plain Return sends; ⇧-Return inserts a newline.
            //  • !sendOnReturn: plain Return inserts a newline; ⌘/⇧-Return sends.
            let hasSendModifier = press.modifiers.contains(.command) || press.modifiers.contains(.shift)
            let shouldSend = model.sendOnReturn
                ? !press.modifiers.contains(.shift)
                : hasSendModifier
            guard shouldSend else { return .ignored }
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
                            font: CodexTheme.bodyFont)
        // Completion menu floats above the field (Codex-styled card). The
        // `.bottom → .top` alignment guide flips it to sit above the anchor.
        .overlay(alignment: .bottomLeading) {
            completionMenu
                .alignmentGuide(.bottom) { d in d[.top] }
                .offset(y: -6)
                .animation(.easeOut(duration: 0.12), value: completionMenuVisible)
                .animation(.easeOut(duration: 0.10), value: completionSelection)
                .animation(.easeOut(duration: 0.12), value: showingInlineModelPicker)
        }
    }

    // MARK: - Completion menu surface

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
                subtitle: option.isReasoningModel ? "Reasoning" : "Fast",
                systemImage: option.isReasoningModel ? "brain" : "bolt",
                isHighlighted: idx == clampedSelection(model.models.count),
                isSelected: model.selectedModel == option
            ) {
                model.selectedModel = option
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
                model.selectedModel = option
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
        HStack(spacing: 8) {
            addMenu

            permissionMenu

            Spacer(minLength: 12)

            modelEffortMenu
            sendButton
        }
    }

    private var addMenu: some View {
        CodexMenuTrigger(minWidth: 260, edge: .top, highlightOnHover: false,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "add") { _ in
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 28, height: 28)
                .codexHover(cornerRadius: 8)
                .contentShape(Rectangle())
        } menu: { close in
            CodexMenuContainer {
                CodexMenuItem(title: "Add photos & files", systemImage: "paperclip") {
                    close(); model.attachFiles()
                }
                if let app = model.lastActiveApp {
                    attachAppRow(app, close: close)
                }

                CodexMenuDivider()

                CodexMenuToggle(
                    title: "Plan mode",
                    systemImage: "list.bullet.clipboard",
                    isOn: Binding(get: { model.isPlanMode }, set: { model.isPlanMode = $0 })
                )
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
        CodexMenuTrigger(minWidth: 260, edge: .top,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "permission") { _ in
            HStack(spacing: 4) {
                if model.permissionMode == .fullAccess {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexTheme.accentOrange)
                }
                Text(model.permissionMode.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.permissionMode == .fullAccess ? CodexTheme.accentOrange : CodexTheme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
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
                    ) { model.permissionMode = mode; close() }
                }
            }
        }
    }

    // Codex-style combined control: "<Model> <Effort> ⌄" with one dropdown.
    // Effort/reasoning is only meaningful for reasoning models (grok-4), so it
    // is only shown when such a model is selected.
    private var modelEffortMenu: some View {
        CodexMenuTrigger(minWidth: 260, edge: .top,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "model") { _ in
            HStack(spacing: 5) {
                Text(model.selectedModel?.displayName ?? "Model")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                if model.selectedModel?.isReasoningModel == true {
                    Text(model.effortLevel.label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        } menu: { close in
            CodexMenuContainer {
                CodexMenuSectionHeader(title: "Model")
                ForEach(model.models) { option in
                    CodexMenuItem(
                        title: option.displayName,
                        subtitle: option.isReasoningModel ? "Reasoning" : "Fast",
                        isSelected: model.selectedModel == option
                    ) { model.selectedModel = option }   // keep open so effort can appear
                }

                if model.selectedModel?.isReasoningModel == true {
                    CodexMenuDivider()
                    CodexMenuSectionHeader(title: "Reasoning effort")
                    ForEach(EffortLevel.allCases) { level in
                        CodexMenuItem(
                            title: level.label,
                            isSelected: model.effortLevel == level
                        ) { model.effortLevel = level; close() }
                    }
                }
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
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isActive ? CodexTheme.sendButtonActiveBackground : CodexTheme.sendButtonBackground)
                )
        }
        .buttonStyle(CodexPressableStyle(scale: 0.92))
        .disabled(!model.isRunning && !model.canSend)
        .animation(CodexMotion.quickSpring, value: model.isRunning)
        .animation(CodexMotion.quickSpring, value: model.canSend)
    }

    private var projectRow: some View {
        CodexMenuTrigger(minWidth: 280, edge: .top, highlightOnHover: false,
                         autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENMENU"] == "project") { _ in
            HStack(spacing: 6) {
                Image(systemName: model.workWithoutProject ? "folder.badge.minus" : "folder")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(CodexTheme.textTertiary)
                Text(model.workWithoutProject ? "No project" : (model.selectedProject?.name ?? "Select project"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                if !model.workWithoutProject, let branch = model.selectedProject?.gitBranch {
                    branchChip(branch)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexTheme.pillBackground)
            )
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
    }

    private func branchChip(_ branch: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .medium))
            Text(branch)
                .font(.system(size: 11, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(CodexTheme.textTertiary)
    }
}

private extension AppViewModel {
    var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    var isHighlighted: Bool = false
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
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
                    AttachmentChip(attachment: attachment) { onRemove(attachment) }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// A single attachment chip: thumbnail (for images) or a glyph, the file name,
/// and a hover-revealed remove button.
private struct AttachmentChip: View {
    let attachment: ComposerAttachment
    var onRemove: () -> Void

    @State private var hovering = false
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 7) {
            leading
            Text(attachment.fileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.5)
            .help("Remove attachment")
        }
        .padding(.leading, attachment.isImage && thumbnail != nil ? 4 : 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(CodexTheme.pillBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(CodexTheme.composerShellBorder, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .help(attachment.path)
        .task(id: attachment.path) { await loadThumbnailIfNeeded() }
    }

    @ViewBuilder
    private var leading: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: attachment.iconSystemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 18, height: 18)
        }
    }

    /// Lazily build a small thumbnail for image attachments. The raw bytes are
    /// read off the main actor (Data is Sendable); the `NSImage` itself is
    /// constructed back on the main actor to stay concurrency-clean.
    private func loadThumbnailIfNeeded() async {
        guard attachment.isImage, thumbnail == nil else { return }
        let path = attachment.path
        let data = await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: URL(fileURLWithPath: path))
        }.value
        guard let data, let image = NSImage(data: data) else { return }
        thumbnail = image
    }
}