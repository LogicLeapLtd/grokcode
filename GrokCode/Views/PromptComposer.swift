import SwiftUI

struct PromptComposer: View {
    @Environment(AppViewModel.self) private var model
    @FocusState private var isFocused: Bool

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

            VStack(alignment: .leading, spacing: 0) {
                inputArea
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                toolbarRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                projectRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            .background(CodexTheme.composerBackground)
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
        .clipShape(RoundedRectangle(cornerRadius: CodexTheme.composerRadius, style: .continuous))
        .shadow(color: CodexTheme.shadowColor, radius: 3, y: 2)
        .animation(CodexMotion.panelSpring, value: model.pendingHooks.count)
        .animation(CodexMotion.panelSpring, value: model.grokAvailable)
        .onAppear { isFocused = true }
    }

    private var inputArea: some View {
        // While a run is in flight, Codex keeps the field live so you can queue
        // a follow-up; the placeholder hints at that.
        TextField(model.isRunning ? "Queue a follow-up…" : "Do anything", text: Binding(
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
            if press.modifiers.contains(.shift) { return .ignored }
            let trimmed = model.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .ignored }
            model.submit()
            return .handled
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            Button { model.attachFiles() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(CodexPressableStyle(scale: 0.92))

            permissionMenu

            Spacer(minLength: 12)

            modelEffortMenu
            sendButton
        }
    }

    private var permissionMenu: some View {
        CodexMenuTrigger(minWidth: 260, edge: .top) { _ in
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
                CodexMenuSectionHeader(title: "Permission mode")
                ForEach(PermissionMode.allCases) { mode in
                    CodexMenuItem(
                        title: mode.label,
                        subtitle: mode.detail,
                        isSelected: model.permissionMode == mode
                    ) { model.permissionMode = mode; close() }
                }
            }
        }
    }

    // Codex-style combined control: "<Model> <Effort> ⌄" with one dropdown.
    // Effort/reasoning is only meaningful for reasoning models (grok-4), so it
    // is only shown when such a model is selected.
    private var modelEffortMenu: some View {
        CodexMenuTrigger(minWidth: 260, edge: .top) { _ in
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
        CodexMenuTrigger(minWidth: 240, edge: .top) { _ in
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(CodexTheme.textTertiary)
                Text(model.selectedProject?.name ?? "Select project")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        } menu: { close in
            CodexMenuContainer {
                CodexMenuSectionHeader(title: "Project")
                ForEach(model.projects) { project in
                    CodexMenuItem(
                        title: project.name,
                        systemImage: "folder",
                        isSelected: model.selectedProject?.id == project.id
                    ) { model.selectProject(project); close() }
                }
                CodexMenuDivider()
                CodexMenuItem(title: "Add folder…", systemImage: "plus") {
                    close(); model.addProjectFromPicker()
                }
            }
        }
    }
}

private extension AppViewModel {
    var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}