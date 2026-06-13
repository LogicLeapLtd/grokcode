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
        TextField("Do anything", text: Binding(
            get: { model.promptText },
            set: { model.promptText = $0 }
        ), axis: .vertical)
        .font(CodexTheme.bodyFont)
        .foregroundStyle(CodexTheme.textPrimary)
        .textFieldStyle(.plain)
        .lineLimit(1...6)
        .frame(minHeight: 24, maxHeight: 120, alignment: .topLeading)
        .focused($isFocused)
        .disabled(model.isRunning)
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.shift) { return .ignored }
            guard !model.isRunning else { return .handled }
            let trimmed = model.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .ignored }
            Task { await model.sendPrompt() }
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

            effortMenu
            modelMenu
            sendButton
        }
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(PermissionMode.allCases) { mode in
                Button(mode.label) { model.permissionMode = mode }
            }
        } label: {
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
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var effortMenu: some View {
        Menu {
            ForEach(EffortLevel.allCases) { level in
                Button(level.label) { model.effortLevel = level }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.effortLevel.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var modelMenu: some View {
        Menu {
            ForEach(model.models) { option in
                Button(option.displayName) { model.selectedModel = option }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.selectedModel?.id ?? "Model")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sendButton: some View {
        let isActive = model.isRunning || model.canSend

        return Button {
            if model.isRunning {
                model.cancelRun()
            } else {
                Task { await model.sendPrompt() }
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
        Menu {
            ForEach(model.projects) { project in
                Button(project.name) { model.selectProject(project) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.selectedProject?.name ?? "Select project")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private extension AppViewModel {
    var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}