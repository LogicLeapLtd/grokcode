import SwiftUI

/// Native command-center surface for creating, scheduling, and running saved
/// agent prompts. The page is intentionally presentational: persistence,
/// scheduling, and run execution stay in `AutomationService` / `AppViewModel`.
struct AutomationsView: View {
    @Environment(AppViewModel.self) private var model

    /// When non-nil, the editor sheet is shown. Create mode can carry a private
    /// draft preset used only to seed the form; persisted data is unchanged.
    @State private var editorMode: EditorMode?

    private enum EditorMode: Identifiable {
        case create(AutomationDraftPreset?)
        case edit(Automation)

        var id: String {
            switch self {
            case .create(let preset): return "create-\(preset?.id ?? "blank")"
            case .edit(let automation): return automation.id.uuidString
            }
        }

        var seed: Automation? {
            if case .edit(let automation) = self { return automation }
            return nil
        }

        var draftPreset: AutomationDraftPreset? {
            if case .create(let preset) = self { return preset }
            return nil
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    private var metrics: AutomationCommandMetrics {
        AutomationCommandMetrics(automations: model.automations)
    }

    var body: some View {
        PageScaffold(maxWidth: 1080, horizontalPadding: 42, topPadding: 42, bottomPadding: 44, spacing: 22) {
            AutomationCommandHeader(metrics: metrics) {
                editorMode = .create(nil)
            }
            .codexStaggeredAppear(index: 0)

            if model.automations.isEmpty {
                AutomationLaunchpad(
                    onCreate: { editorMode = .create(nil) },
                    onPreset: { editorMode = .create($0) }
                )
                .codexStaggeredAppear(index: 1)
            } else {
                automationBoard
                    .codexStaggeredAppear(index: 1)
            }
        }
        .onAppear {
            model.loadAutomations()
            // QA: auto-open the editor so the modal can be captured.
            if ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENEDITOR"] == "1" {
                editorMode = .create(nil)
            }
        }
        .sheet(item: $editorMode) { mode in
            AutomationEditorSheet(
                seed: mode.seed,
                draft: mode.draftPreset,
                projects: model.projects,
                providerStatuses: model.providerStatuses,
                models: model.models,
                defaultProviderId: model.selectedProviderId,
                defaultModelId: model.selectedModel?.id ?? model.models.first?.id ?? "",
                defaultOptionSelections: model.selectedModel.map { model.runOptions(for: $0) } ?? [:],
                onSave: { automation in
                    if mode.isEditing {
                        model.updateAutomation(automation)
                    } else {
                        model.addAutomation(automation)
                    }
                    editorMode = nil
                },
                onCancel: { editorMode = nil }
            )
            .environment(model)
        }
    }

    private var automationBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AutomationBoardHeader(count: model.automations.count) {
                editorMode = .create(nil)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 330, maximum: 520), spacing: 16, alignment: .top)
                ],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(Array(model.automations.enumerated()), id: \.element.id) { index, automation in
                    AutomationCard(
                        automation: automation,
                        onToggle: { model.toggleAutomation(automation) },
                        onRun: { await model.runAutomationNow(automation) },
                        onEdit: { editorMode = .edit(automation) },
                        onDelete: { model.deleteAutomation(automation) }
                    )
                    .codexStaggeredAppear(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Command center header

private struct AutomationCommandHeader: View {
    let metrics: AutomationCommandMetrics
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CodexTheme.accent)
                        Text("Automation command center")
                            .font(CodexTheme.captionFont)
                            .foregroundStyle(CodexTheme.textSecondary)
                    }

                    Text("Automations")
                        .font(CodexTheme.serif(32, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)

                    Text("Build dependable background agents for the work you repeat: checks, digests, release notes, inbox scans, and project rituals.")
                        .font(CodexTheme.sans(14.5))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }

                Spacer(minLength: 16)

                AutomationPrimaryButton(title: "New automation", systemImage: "plus", action: onCreate)
            }

            HStack(spacing: 0) {
                AutomationMetricColumn(
                    title: "Total",
                    value: "\(metrics.total)",
                    detail: metrics.total == 1 ? "saved routine" : "saved routines",
                    systemImage: "square.stack.3d.up"
                )

                AutomationMetricDivider()

                AutomationMetricColumn(
                    title: "Armed",
                    value: "\(metrics.armed)",
                    detail: metrics.armed == 1 ? "scheduled run" : "scheduled runs",
                    systemImage: "bolt.horizontal.circle"
                )

                AutomationMetricDivider()

                AutomationMetricColumn(
                    title: "Next run",
                    value: metrics.nextRun.map(AutomationTimeFormatter.relative) ?? "None",
                    detail: metrics.nextRunName ?? "No schedule armed",
                    systemImage: "calendar.badge.clock"
                )

                AutomationMetricDivider()

                AutomationMetricColumn(
                    title: "Last result",
                    value: metrics.latestRunLabel,
                    detail: metrics.latestRunDetail,
                    systemImage: metrics.latestRunSystemImage,
                    accent: metrics.latestRunAccent
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
        .padding(24)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            interactive: true,
            tint: CodexTheme.accent.opacity(0.055),
            fallback: CodexTheme.composerBackground.opacity(0.84)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CodexTheme.composerShellHighlight.opacity(0.72), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            AutomationHeaderCircuit()
                .padding(.top, 70)
                .padding(.trailing, 28)
                .allowsHitTesting(false)
        }
        .shadow(color: CodexTheme.accentDeep.opacity(0.12), radius: 26, y: 16)
    }
}

private struct AutomationMetricColumn: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var accent: Color = CodexTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent)
                Text(title)
                    .font(CodexTheme.smallFont)
                    .foregroundStyle(CodexTheme.textTertiary)
            }

            Text(value)
                .font(CodexTheme.sans(21, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(CodexTheme.smallFont)
                .foregroundStyle(CodexTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AutomationMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(CodexTheme.divider)
            .frame(width: 1, height: 62)
            .padding(.horizontal, 18)
    }
}

private struct AutomationHeaderCircuit: View {
    private let steps = ["doc.text", "clock", "play.fill", "checkmark"]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, symbol in
                ZStack {
                    Circle()
                        .fill(index == 2 ? CodexTheme.accent.opacity(0.18) : CodexTheme.pillBackground.opacity(0.7))
                        .frame(width: 26, height: 26)
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index == 2 ? CodexTheme.accent : CodexTheme.textSecondary)
                }

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(CodexTheme.accent.opacity(index == 1 ? 0.36 : 0.16))
                        .frame(width: 22, height: 1)
                }
            }
        }
        .padding(9)
        .background(
            Capsule(style: .continuous)
                .fill(CodexTheme.mainBackground.opacity(0.42))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CodexTheme.composerShellHighlight.opacity(0.52), lineWidth: 1)
        )
    }
}

private struct AutomationPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(CodexTheme.controlTitleFont)
            }
            .foregroundStyle(CodexTheme.sendButtonActiveForeground)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CodexTheme.sendButtonActiveBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle())
        .codexHoverOverlay(cornerRadius: 10)
    }
}

// MARK: - Empty launchpad

private struct AutomationLaunchpad: View {
    let onCreate: () -> Void
    let onPreset: (AutomationDraftPreset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 340), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 26) {
                AutomationPipelineScene()
                    .frame(width: 318, height: 188)

                VStack(alignment: .leading, spacing: 12) {
                    Text("No automations yet")
                        .font(CodexTheme.serif(25, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)

                    Text("Turn the work you repeat into calm, scheduled runs. Start blank, or open a template and tune the prompt before saving.")
                        .font(CodexTheme.sans(14))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 500, alignment: .leading)

                    AutomationPrimaryButton(title: "Start blank", systemImage: "plus", action: onCreate)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                tint: CodexTheme.accent.opacity(0.04),
                fallback: CodexTheme.composerBackground.opacity(0.78)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(CodexTheme.divider.opacity(0.86), lineWidth: 1)
            }

            Text("Quick starts")
                .font(CodexTheme.sectionLabelFont)
                .foregroundStyle(CodexTheme.textTertiary)
                .padding(.top, 2)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(AutomationDraftPreset.presets) { preset in
                    AutomationPresetTile(preset: preset) {
                        onPreset(preset)
                    }
                }
            }
        }
    }
}

private struct AutomationPipelineScene: View {
    private let steps: [AutomationPipelineStep] = [
        .init(title: "Prompt", symbol: "text.alignleft"),
        .init(title: "Schedule", symbol: "calendar.badge.clock"),
        .init(title: "Run", symbol: "play.fill"),
        .init(title: "Result", symbol: "checkmark.seal")
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            CodexTheme.accent.opacity(0.18),
                            CodexTheme.accentDeep.opacity(0.08),
                            CodexTheme.mainBackground.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexTheme.accent)
                    Text("agent run loop")
                        .font(CodexTheme.smallFont)
                        .foregroundStyle(CodexTheme.textSecondary)
                }

                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        AutomationPipelineNode(step: step, highlighted: index == 1)

                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(CodexTheme.accent.opacity(index == 1 ? 0.36 : 0.18))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .padding(22)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(CodexTheme.composerShellHighlight.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct AutomationPipelineStep: Identifiable {
    var id: String { title }
    let title: String
    let symbol: String
}

private struct AutomationPipelineNode: View {
    let step: AutomationPipelineStep
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(highlighted ? CodexTheme.sendButtonActiveBackground : CodexTheme.composerBackground.opacity(0.86))
                    .frame(width: 42, height: 42)
                    .shadow(color: highlighted ? CodexTheme.accent.opacity(0.22) : .clear, radius: 12, y: 6)

                Image(systemName: step.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(highlighted ? CodexTheme.sendButtonActiveForeground : CodexTheme.textSecondary)
            }

            Text(step.title)
                .font(CodexTheme.smallFont)
                .foregroundStyle(highlighted ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                .lineLimit(1)
        }
    }
}

private struct AutomationPresetTile: View {
    let preset: AutomationDraftPreset
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: preset.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CodexTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(CodexTheme.accent.opacity(0.12))
                        )

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(preset.title)
                        .font(CodexTheme.controlTitleFont)
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)

                    Text(preset.subtitle)
                        .font(CodexTheme.captionFont)
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CodexTheme.composerBackground.opacity(hovering ? 0.98 : 0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(hovering ? CodexTheme.controlHoverBorder : CodexTheme.divider, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(CodexPressableStyle(scale: 0.975))
        .onHover { hovering = $0 }
        .animation(CodexMotion.quickSpring, value: hovering)
    }
}

// MARK: - Automation board

private struct AutomationBoardHeader: View {
    let count: Int
    let onCreate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Operations board")
                    .font(CodexTheme.sectionLabelFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                Text("\(count) \(count == 1 ? "routine" : "routines") ready to run or schedule.")
                    .font(CodexTheme.captionFont)
                    .foregroundStyle(CodexTheme.textSecondary)
            }

            Spacer(minLength: 12)

            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(CodexTheme.sendButtonActiveBackground))
                    .contentShape(Circle())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(Circle())
            .help("New automation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Automation card

private struct AutomationCard: View {
    let automation: Automation
    let onToggle: () -> Void
    /// Awaitable run that reports success, so the card can drive its inline
    /// running → ✓ / ✗ feedback.
    let onRun: () async -> Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Inline run feedback for #36. `.idle` shows the normal button; `.running`
    /// shows a spinner; `.succeeded` / `.failed` show a transient ✓ / ✗ that
    /// settles back to `.idle`.
    private enum RunState: Equatable {
        case idle, running, succeeded, failed
    }

    @State private var runState: RunState = .idle
    @State private var confirmingDelete = false
    @State private var hovering = false

    private var lastRunLabel: String {
        guard let lastRun = automation.lastRun else { return "Never run" }
        return "Ran " + AutomationTimeFormatter.relative(lastRun)
    }

    private var nextRunLabel: String? {
        guard let next = automation.nextRun() else { return nil }
        return "Next " + AutomationTimeFormatter.relative(next)
    }

    private var status: AutomationCardStatus {
        if !automation.enabled { return .paused }
        if automation.lastRunSucceeded == false { return .attention }
        if automation.isScheduled { return .armed }
        return .manual
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(status.accent.opacity(automation.enabled ? 0.14 : 0.08))
                        .frame(width: 42, height: 42)

                    Image(systemName: automation.iconSystemName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(status.accent)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(automation.displayName)
                        .font(CodexTheme.sans(15.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)

                    AutomationStatusBadge(status: status)
                }

                Spacer(minLength: 12)

                Button(action: onToggle) {
                    MiniSwitch(isOn: automation.enabled)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(automation.enabled ? "Disable" : "Enable")
            }

            promptPreview

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    metaChip(systemImage: automation.scheduleKind.symbol, text: automation.scheduleSummary)
                    metaChip(systemImage: "folder", text: automation.projectLabel)
                }

                HStack(spacing: 8) {
                    metaChip(systemImage: "cpu", text: modelLabel)
                    if let nextRunLabel {
                        metaChip(systemImage: "arrow.triangle.2.circlepath", text: nextRunLabel)
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastRunLabel)
                        .font(CodexTheme.smallFont)
                        .foregroundStyle(CodexTheme.textTertiary)
                }

                if !automation.runHistory.isEmpty {
                    runHistoryTrail
                }

                Spacer(minLength: 0)
            }

            actionRow
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            interactive: true,
            tint: status.accent.opacity(automation.enabled ? 0.045 : 0.02),
            fallback: CodexTheme.composerBackground.opacity(automation.enabled ? 0.84 : 0.58)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(hovering ? CodexTheme.controlHoverBorder.opacity(0.7) : CodexTheme.divider, lineWidth: 1)
        )
        .shadow(color: status.accent.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 22 : 10, y: hovering ? 14 : 6)
        .opacity(automation.enabled ? 1 : 0.74)
        .onHover { hovering = $0 }
        .animation(CodexMotion.quickSpring, value: hovering)
        .confirmationDialog(
            "Delete “\(automation.displayName)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete automation", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved prompt and its schedule. This can’t be undone.")
        }
    }

    private var promptPreview: some View {
        Text(automation.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(CodexTheme.captionFont)
            .foregroundStyle(CodexTheme.textSecondary)
            .lineSpacing(2)
            .lineLimit(3)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodexTheme.toolPanelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CodexTheme.toolPanelBorder, lineWidth: 1)
            )
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            runButton
            Spacer(minLength: 0)
            iconAction("pencil", help: "Edit automation") { onEdit() }
            iconAction("trash", help: "Delete automation", destructive: true) {
                confirmingDelete = true
            }
        }
    }

    // MARK: Run button + state machine

    @ViewBuilder
    private var runButton: some View {
        switch runState {
        case .running:
            runStatusPill {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                Text("Running…")
                    .font(CodexTheme.captionFont)
                    .foregroundStyle(CodexTheme.textSecondary)
            }
        case .succeeded:
            runStatusPill {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.green)
                Text("Done")
                    .font(CodexTheme.captionFont)
                    .foregroundStyle(CodexTheme.textPrimary)
            }
        case .failed:
            runStatusPill {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexTheme.errorForeground)
                Text("Failed")
                    .font(CodexTheme.captionFont)
                    .foregroundStyle(CodexTheme.errorForeground)
            }
        case .idle:
            actionButton("Run now", systemImage: "play.fill", prominent: true) {
                runNow()
            }
        }
    }

    /// Shared chrome for the non-idle run states so the button doesn't resize
    /// jarringly between spinner / ✓ / ✗.
    private func runStatusPill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) {
            content()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(CodexTheme.pillBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(CodexTheme.divider, lineWidth: 1)
        )
        .transition(.opacity)
    }

    private func runNow() {
        guard runState != .running else { return }
        withAnimation(.easeInOut(duration: 0.15)) { runState = .running }
        Task {
            let ok = await onRun()
            withAnimation(.easeInOut(duration: 0.15)) {
                runState = ok ? .succeeded : .failed
            }
            // Settle back to the button after a short beat.
            try? await Task.sleep(nanoseconds: ok ? 1_400_000_000 : 2_200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { runState = .idle }
        }
    }

    // MARK: Run history trail

    private var runHistoryTrail: some View {
        HStack(spacing: 6) {
            ForEach(Array(automation.runHistory.prefix(5))) { run in
                Image(systemName: run.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(run.ok ? Color.green : CodexTheme.errorForeground)
                    .help(runTooltip(run))
            }
        }
    }

    private func runTooltip(_ run: AutomationRun) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return (run.ok ? "Succeeded " : "Failed ") + formatter.string(from: run.date)
    }

    private var modelLabel: String {
        let provider = AgentProvider.known.first { $0.id == automation.providerId }?.shortName ?? automation.providerId
        let model = GrokModelOption(id: automation.modelId, isDefault: false).displayName
        return GrokModelOption.providerScopedName(providerName: provider, modelName: model)
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .regular))
            Text(text)
                .font(CodexTheme.smallFont)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CodexTheme.pillBackground)
        )
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .regular))
                Text(title)
                    .font(CodexTheme.captionFont)
            }
            .foregroundStyle(foreground(prominent: prominent, destructive: destructive))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(background(prominent: prominent))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : CodexTheme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle())
        .codexHoverOverlay(cornerRadius: 9)
    }

    private func foreground(prominent: Bool, destructive: Bool) -> Color {
        if prominent { return CodexTheme.sendButtonActiveForeground }
        if destructive { return CodexTheme.errorForeground }
        return CodexTheme.textPrimary
    }

    private func background(prominent: Bool) -> Color {
        prominent ? CodexTheme.sendButtonActiveBackground : CodexTheme.mainBackground
    }

    private func iconAction(
        _ systemImage: String,
        help: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(destructive ? CodexTheme.errorForeground : CodexTheme.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(CodexTheme.mainBackground.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(CodexTheme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle())
        .codexHoverOverlay(cornerRadius: 9)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct AutomationStatusBadge: View {
    let status: AutomationCardStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.accent)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(CodexTheme.smallFont)
                .foregroundStyle(CodexTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(status.accent.opacity(0.10))
        )
    }
}

private enum AutomationCardStatus {
    case armed, manual, paused, attention

    var label: String {
        switch self {
        case .armed: "Armed"
        case .manual: "Manual"
        case .paused: "Paused"
        case .attention: "Needs review"
        }
    }

    var accent: Color {
        switch self {
        case .armed: CodexTheme.accent
        case .manual: CodexTheme.textTertiary
        case .paused: CodexTheme.textTertiary
        case .attention: CodexTheme.errorForeground
        }
    }
}

// MARK: - Metrics + presets

private struct AutomationCommandMetrics {
    let total: Int
    let armed: Int
    let nextRun: Date?
    let nextRunName: String?
    let latestRun: AutomationRun?
    let latestRunName: String?

    init(automations: [Automation]) {
        total = automations.count
        armed = automations.filter(\.isScheduled).count

        let upcoming = automations.compactMap { automation -> (Automation, Date)? in
            guard let next = automation.nextRun() else { return nil }
            return (automation, next)
        }
        .sorted { $0.1 < $1.1 }
        .first

        nextRun = upcoming?.1
        nextRunName = upcoming?.0.displayName

        let latest = automations.compactMap { automation -> (Automation, AutomationRun)? in
            if let run = automation.runHistory.first {
                return (automation, run)
            }
            if let lastRun = automation.lastRun {
                return (automation, AutomationRun(date: lastRun, ok: true))
            }
            return nil
        }
        .sorted { $0.1.date > $1.1.date }
        .first

        latestRun = latest?.1
        latestRunName = latest?.0.displayName
    }

    var latestRunLabel: String {
        guard let latestRun else { return "None" }
        return latestRun.ok ? "Clean" : "Failed"
    }

    var latestRunDetail: String {
        guard let latestRun else { return "No runs yet" }
        return "\(latestRunName ?? "Automation") · \(AutomationTimeFormatter.relative(latestRun.date))"
    }

    var latestRunSystemImage: String {
        guard let latestRun else { return "circle.dashed" }
        return latestRun.ok ? "checkmark.seal" : "exclamationmark.triangle"
    }

    var latestRunAccent: Color {
        guard let latestRun else { return CodexTheme.textTertiary }
        return latestRun.ok ? Color.green : CodexTheme.errorForeground
    }
}

private struct AutomationDraftPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let name: String
    let prompt: String
    let scheduleKind: AutomationScheduleKind
    let intervalMinutes: Int?
    let timeOfDay: String?

    static let presets: [AutomationDraftPreset] = [
        AutomationDraftPreset(
            id: "manual-release",
            title: "Release note draft",
            subtitle: "Manual run for turning recent work into a clean changelog.",
            symbol: "doc.text.magnifyingglass",
            name: "Release note draft",
            prompt: "Review the latest git changes in this project and draft a concise release note with the important user-facing changes, verification performed, and any remaining risks.",
            scheduleKind: .manual,
            intervalMinutes: nil,
            timeOfDay: nil
        ),
        AutomationDraftPreset(
            id: "interval-health",
            title: "Project health check",
            subtitle: "Runs every 30 minutes while Codessa is open.",
            symbol: "waveform.path.ecg",
            name: "Project health check",
            prompt: "Check the current project for failing tests, dirty git state, build errors, and obvious handoff blockers. Report only concrete issues and the safest next action.",
            scheduleKind: .interval,
            intervalMinutes: 30,
            timeOfDay: nil
        ),
        AutomationDraftPreset(
            id: "daily-brief",
            title: "Morning brief",
            subtitle: "Daily 09:00 scan for priorities and loose ends.",
            symbol: "sunrise",
            name: "Morning project brief",
            prompt: "Prepare a short morning brief for this project: what changed recently, what is unfinished, what deserves attention today, and any risky local or release state.",
            scheduleKind: .daily,
            intervalMinutes: nil,
            timeOfDay: "09:00"
        )
    ]
}

private enum AutomationTimeFormatter {
    nonisolated static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Editor sheet

private struct AutomationEditorSheet: View {
    /// `nil` ⇒ creating a new automation; otherwise editing this one.
    let seed: Automation?
    /// Optional private create-mode draft from the empty-state quick starts.
    let draft: AutomationDraftPreset?
    let projects: [Project]
    let providerStatuses: [ProviderStatus]
    let models: [GrokModelOption]
    let defaultProviderId: String
    let defaultModelId: String
    let defaultOptionSelections: [String: String]
    let onSave: (Automation) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var projectPath: String?          // nil ⇒ Home
    @State private var providerId: String = AgentProvider.grok.id
    @State private var modelId: String = ""
    @State private var optionSelections: [String: String] = [:]
    @State private var scheduleKind: AutomationScheduleKind = .manual
    @State private var intervalMinutes: Int = 30
    @State private var timeOfDay: String = "09:00"
    @State private var enabled: Bool = true

    @FocusState private var nameFocused: Bool

    /// The sheet is its own window, so it needs its own menu host — otherwise
    /// the custom dropdowns render on the main window's host, behind the sheet.
    @State private var menuController = CodexMenuController(installsKeyboardMonitor: false)

    private var isEditing: Bool { seed != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First failed validation rule, or `nil` when the form is savable. Drives the
    /// disabled Save button and the inline footer hint.
    private var validationMessage: String? {
        if trimmedName.isEmpty { return "Add a name." }
        if trimmedName.count > Automation.maxNameLength {
            return "Name is too long (max \(Automation.maxNameLength))."
        }
        if trimmedPrompt.isEmpty { return "Add a prompt." }
        if trimmedPrompt.count > Automation.maxPromptLength {
            return "Prompt is too long (max \(Automation.maxPromptLength))."
        }
        if modelId.isEmpty { return "Pick a model." }
        return nil
    }

    private var canSave: Bool { validationMessage == nil }

    private var projectLabel: String {
        guard let projectPath, !projectPath.isEmpty else { return "Home (no project)" }
        return (projectPath as NSString).lastPathComponent
    }

    private var modelLabel: String {
        currentModels.first(where: { $0.id == modelId })?.providerMenuName
            ?? GrokModelOption.providerScopedName(
                providerName: providerLabel(providerId),
                modelName: modelId.isEmpty ? "Model" : GrokModelOption(id: modelId, isDefault: false).displayName
            )
    }

    private var currentModels: [GrokModelOption] {
        providerStatuses.first { $0.provider.id == providerId }?.models
            ?? (providerId == defaultProviderId ? models : [])
    }

    private func providerLabel(_ id: String) -> String {
        providerStatuses.first { $0.provider.id == id }?.provider.shortName
            ?? AgentProvider.known.first { $0.id == id }?.shortName
            ?? id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit automation" : "New automation")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer()
                Button(action: onCancel) {
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

            Divider().background(CodexTheme.divider)

            VStack(alignment: .leading, spacing: 18) {
                    field("Name", trailing: AnyView(
                        counter(trimmedName.count, limit: Automation.maxNameLength)
                    )) {
                        TextField("", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .focused($nameFocused)
                            .placeholderOverlay("Weekly release notes", visible: name.isEmpty, font: .system(size: 14))
                            .padding(10)
                            .background(inputBackground)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > Automation.maxNameLength {
                                    name = String(newValue.prefix(Automation.maxNameLength))
                                }
                            }
                    }

                    field("Prompt", trailing: AnyView(
                        counter(trimmedPrompt.count, limit: Automation.maxPromptLength)
                    )) {
                        ZStack(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("Describe what Grok should do each run…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CodexTheme.textTertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $prompt)
                                .font(.system(size: 14))
                                .foregroundStyle(CodexTheme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(minHeight: 96)
                                .onChange(of: prompt) { _, newValue in
                                    if newValue.count > Automation.maxPromptLength {
                                        prompt = String(newValue.prefix(Automation.maxPromptLength))
                                    }
                                }
                        }
                        .background(inputBackground)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        field("Project") {
                            menuPicker(label: projectLabel, systemImage: "folder",
                                       autoOpen: ProcessInfo.processInfo.environment["GROKCODE_SMOKE_OPENEDITOR"] == "1") { close in
                                CodexMenuContainer {
                                    CodexMenuItem(
                                        title: "Home (no project)",
                                        systemImage: "house",
                                        isSelected: projectPath == nil
                                    ) {
                                        projectPath = nil; close()
                                    }
                                    if !projects.isEmpty { CodexMenuDivider() }
                                    ForEach(projects) { project in
                                        CodexMenuItem(
                                            title: project.name,
                                            subtitle: project.path.path,
                                            systemImage: "folder",
                                            isSelected: projectPath == project.path.path
                                        ) {
                                            projectPath = project.path.path; close()
                                        }
                                    }
                                }
                            }
                        }

                        field("Model") {
                            menuPicker(label: modelLabel, systemImage: "cpu", providerLogoId: providerId) { close in
                                CodexMenuContainer {
                                    ForEach(providerStatuses) { status in
                                        CodexMenuSectionHeader(title: status.provider.shortName)
                                        ForEach(status.models) { option in
                                            ModelMenuItem(
                                                option: option,
                                                subtitle: option.isReasoningModel ? "Reasoning" : status.runtimeState.label,
                                                isSelected: option.providerId == providerId && option.id == modelId
                                            ) {
                                                providerId = option.providerId
                                                modelId = option.id
                                                seedOptionSelections(for: option)
                                                close()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    field("Schedule") {
                        VStack(alignment: .leading, spacing: 12) {
                            menuPicker(label: scheduleKind.label, systemImage: scheduleKind.symbol) { close in
                                CodexMenuContainer {
                                    ForEach(AutomationScheduleKind.allCases) { kind in
                                        CodexMenuItem(
                                            title: kind.label,
                                            systemImage: kind.symbol,
                                            isSelected: kind == scheduleKind
                                        ) {
                                            scheduleKind = kind; close()
                                        }
                                    }
                                }
                            }

                            scheduleDetailFields
                        }
                    }

                    CodexMenuToggle(title: "Enabled", systemImage: "power", isOn: $enabled)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(CodexTheme.sidebarBackground)
                        )
                }
                .padding(20)

            Divider().background(CodexTheme.divider)

            // Footer
            HStack(spacing: 10) {
                if let validationMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11, weight: .regular))
                        Text(validationMessage)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(CodexTheme.textTertiary)
                }
                Spacer()
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(CodexTheme.pillBackground)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
        .codexHoverOverlay(cornerRadius: 9)

                Button(action: save) {
                    Text(isEditing ? "Save changes" : "Create automation")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(canSave ? CodexTheme.sendButtonActiveBackground : CodexTheme.sendButtonBackground)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
        .codexHoverOverlay(cornerRadius: 9)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 540)
        .background(CodexTheme.mainBackground)
        .codexMenuHost()
        .environment(menuController)
        .onAppear(perform: seedFields)
    }

    // MARK: Schedule detail fields

    @ViewBuilder
    private var scheduleDetailFields: some View {
        switch scheduleKind {
        case .manual:
            Text("Runs only when you tap Run now.")
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textTertiary)
        case .interval:
            HStack(spacing: 10) {
                Text("Every")
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textSecondary)
                menuPicker(label: intervalLabel(intervalMinutes), systemImage: "timer", minWidth: 160) { close in
                    CodexMenuContainer {
                        ForEach(Self.intervalChoices, id: \.self) { minutes in
                            CodexMenuItem(
                                title: intervalLabel(minutes),
                                isSelected: minutes == intervalMinutes
                            ) {
                                intervalMinutes = minutes; close()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        case .daily:
            HStack(spacing: 10) {
                Text("At")
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textSecondary)
                menuPicker(label: timeOfDay, systemImage: "clock", minWidth: 140) { close in
                    CodexMenuContainer {
                        ForEach(Self.timeChoices, id: \.self) { time in
                            CodexMenuItem(title: time, isSelected: time == timeOfDay) {
                                timeOfDay = time; close()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Reusable pieces

    private func field<Content: View>(
        _ title: String,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                if let trailing {
                    Spacer(minLength: 8)
                    trailing
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A right-aligned "count/limit" counter that turns warning-coloured as it
    /// approaches the cap. Only renders once you're within ~15% of the limit so
    /// it stays quiet for short inputs.
    @ViewBuilder
    private func counter(_ count: Int, limit: Int) -> some View {
        let threshold = max(limit - max(limit / 6, 10), 0)
        if count >= threshold {
            Text("\(count)/\(limit)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(count >= limit ? CodexTheme.errorForeground : CodexTheme.textTertiary)
                .monospacedDigit()
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(CodexTheme.composerBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
            )
    }

    private func menuPicker<Menu: View>(
        label: String,
        systemImage: String,
        providerLogoId: String? = nil,
        minWidth: CGFloat = 220,
        autoOpen: Bool = false,
        @ViewBuilder menu: @escaping (_ close: @escaping () -> Void) -> Menu
    ) -> some View {
        CodexMenuTrigger(minWidth: minWidth, highlightOnHover: false, autoOpen: autoOpen) { isOpen in
            HStack(spacing: 8) {
                if let providerLogoId {
                    ProviderLogo(providerId: providerLogoId, size: 16, foreground: CodexTheme.textSecondary)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textSecondary)
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CodexTheme.composerBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isOpen ? CodexTheme.textTertiary : CodexTheme.composerBorder, lineWidth: 1)
            )
        } menu: { close in
            menu(close)
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(minutes) min"
    }

    private static let intervalChoices = [5, 15, 30, 60, 120, 240, 480, 1440]
    private static let timeChoices: [String] = {
        var out: [String] = []
        for hour in 0..<24 {
            out.append(String(format: "%02d:00", hour))
            out.append(String(format: "%02d:30", hour))
        }
        return out
    }()

    // MARK: State seeding + save

    private func seedFields() {
        if let seed {
            name = seed.name
            prompt = seed.prompt
            projectPath = seed.projectPath
            providerId = seed.providerId.isEmpty ? AgentProvider.grok.id : seed.providerId
            modelId = seed.modelId.isEmpty ? defaultModelId : seed.modelId
            optionSelections = seed.optionSelections
            if let option = currentModels.first(where: { $0.id == modelId }) {
                seedOptionSelections(for: option)
            }
            scheduleKind = seed.scheduleKind
            intervalMinutes = seed.intervalMinutes ?? 30
            timeOfDay = seed.timeOfDay ?? "09:00"
            enabled = seed.enabled
        } else {
            providerId = defaultProviderId
            modelId = defaultModelId
            optionSelections = defaultOptionSelections
            if let draft {
                name = draft.name
                prompt = draft.prompt
                scheduleKind = draft.scheduleKind
                intervalMinutes = draft.intervalMinutes ?? 30
                timeOfDay = draft.timeOfDay ?? "09:00"
                enabled = true
            }
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private func seedOptionSelections(for option: GrokModelOption) {
        for descriptor in option.optionDescriptors where optionSelections[descriptor.id] == nil {
            optionSelections[descriptor.id] = descriptor.defaultValue
        }
    }

    private func save() {
        guard canSave else { return }
        let interval: Int? = scheduleKind == .interval ? intervalMinutes : nil
        let time: String? = scheduleKind == .daily ? timeOfDay : nil

        let automation: Automation
        if let seed {
            automation = Automation(
                id: seed.id,
                name: trimmedName,
                prompt: trimmedPrompt,
                projectPath: projectPath,
                providerId: providerId,
                modelId: modelId,
                optionSelections: optionSelections,
                scheduleKind: scheduleKind,
                intervalMinutes: interval,
                timeOfDay: time,
                enabled: enabled,
                lastRun: seed.lastRun,
                createdAt: seed.createdAt,
                runHistory: seed.runHistory          // preserve the run trail on edit
            )
        } else {
            automation = Automation(
                name: trimmedName,
                prompt: trimmedPrompt,
                projectPath: projectPath,
                providerId: providerId,
                modelId: modelId,
                optionSelections: optionSelections,
                scheduleKind: scheduleKind,
                intervalMinutes: interval,
                timeOfDay: time,
                enabled: enabled
            )
        }
        onSave(automation)
    }
}
