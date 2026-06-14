import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PromptComposer: View {
    @Environment(AppViewModel.self) private var model
    @FocusState private var isFocused: Bool
    /// Highlights the composer while a file drag hovers over it (#13).
    @State private var isDropTargeted = false

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
        .onKeyPress(.return, phases: .down) { press in
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