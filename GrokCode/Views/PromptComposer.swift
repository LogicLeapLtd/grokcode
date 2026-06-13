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

            // White input area (prompt + toolbar).
            VStack(alignment: .leading, spacing: 0) {
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
                    TextField("Search projects", text: Binding(
                        get: { model.projectPickerQuery },
                        set: { model.projectPickerQuery = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
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