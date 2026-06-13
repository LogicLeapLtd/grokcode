import SwiftUI

/// Codex-style Automations page. Big title + subtitle, a "New automation"
/// primary button, an empty state, and a list of automation cards. An inline
/// create/edit form (sheet) lets the user define name, prompt, target project,
/// model, and a manual / interval / daily schedule.
///
/// Reads `AppViewModel` per the contract: `automations`, `addAutomation`,
/// `updateAutomation`, `deleteAutomation`, `runAutomation`, `toggleAutomation`,
/// `projects`, `models`, and `loadAutomations()`.
struct AutomationsView: View {
    @Environment(AppViewModel.self) private var model

    /// When non-nil, the editor sheet is shown. `.create` builds a fresh
    /// automation; `.edit` seeds the form from an existing one.
    @State private var editorMode: EditorMode?

    private enum EditorMode: Identifiable {
        case create
        case edit(Automation)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let automation): return automation.id.uuidString
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if model.automations.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(model.automations.enumerated()), id: \.element.id) { index, automation in
                            AutomationCard(
                                automation: automation,
                                onToggle: { model.toggleAutomation(automation) },
                                onRun: { model.runAutomation(automation) },
                                onEdit: { editorMode = .edit(automation) },
                                onDelete: { model.deleteAutomation(automation) }
                            )
                            .codexStaggeredAppear(index: index)
                        }
                    }
                }
            }
            .padding(48)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.mainBackground)
        .onAppear { model.loadAutomations() }
        .sheet(item: $editorMode) { mode in
            AutomationEditorSheet(
                seed: { if case .edit(let automation) = mode { return automation } else { return nil } }(),
                projects: model.projects,
                models: model.models,
                defaultModelId: model.selectedModel?.id ?? model.models.first?.id ?? "",
                onSave: { automation in
                    if case .edit = mode {
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Automations")
                    .font(CodexTheme.headlineFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                Text("Schedule recurring Grok tasks, or save prompts to run on demand.")
                    .font(CodexTheme.bodyFont)
                    .foregroundStyle(CodexTheme.textSecondary)
            }

            Spacer(minLength: 16)

            Button {
                editorMode = .create
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New automation")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(CodexTheme.sendButtonActiveBackground)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle())
        .codexHoverOverlay(cornerRadius: 9)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(CodexTheme.textSecondary)

            Text("No automations yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)

            Text("Create an automation to run a saved Grok prompt on demand, every few minutes, or once a day.")
                .font(CodexTheme.bodyFont)
                .foregroundStyle(CodexTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button {
                editorMode = .create
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New automation")
                        .font(.system(size: 13, weight: .medium))
                }
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
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CodexTheme.sidebarBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CodexTheme.divider, lineWidth: 1)
        )
    }
}

// MARK: - Automation card

private struct AutomationCard: View {
    let automation: Automation
    let onToggle: () -> Void
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var lastRunLabel: String {
        guard let lastRun = automation.lastRun else { return "Never run" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Ran " + formatter.localizedString(for: lastRun, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: automation.iconSystemName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CodexTheme.pillBackground)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(automation.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                    Text(automation.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button(action: onToggle) {
                    MiniSwitch(isOn: automation.enabled)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(automation.enabled ? "Disable" : "Enable")
            }

            if !automation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(automation.prompt)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                metaChip(systemImage: automation.scheduleKind.symbol, text: automation.scheduleSummary)
                metaChip(systemImage: "folder", text: automation.projectLabel)
                metaChip(systemImage: "cpu", text: modelLabel)

                Spacer(minLength: 8)

                Text(lastRunLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
            }

            HStack(spacing: 8) {
                actionButton("Run now", systemImage: "play.fill", prominent: true) {
                    onRun()
                }
                actionButton("Edit", systemImage: "pencil") { onEdit() }
                Spacer(minLength: 0)
                actionButton("Delete", systemImage: "trash", destructive: true) { onDelete() }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CodexTheme.mainBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CodexTheme.divider, lineWidth: 1)
        )
        .opacity(automation.enabled ? 1 : 0.6)
    }

    private var modelLabel: String {
        GrokModelOption(id: automation.modelId, isDefault: false).displayName
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .regular))
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
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
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(foreground(prominent: prominent, destructive: destructive))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background(prominent: prominent))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
}

// MARK: - Editor sheet

private struct AutomationEditorSheet: View {
    /// `nil` ⇒ creating a new automation; otherwise editing this one.
    let seed: Automation?
    let projects: [Project]
    let models: [GrokModelOption]
    let defaultModelId: String
    let onSave: (Automation) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var projectPath: String?          // nil ⇒ Home
    @State private var modelId: String = ""
    @State private var scheduleKind: AutomationScheduleKind = .manual
    @State private var intervalMinutes: Int = 30
    @State private var timeOfDay: String = "09:00"
    @State private var enabled: Bool = true

    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { seed != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !modelId.isEmpty
    }

    private var projectLabel: String {
        guard let projectPath, !projectPath.isEmpty else { return "Home (no project)" }
        return (projectPath as NSString).lastPathComponent
    }

    private var modelLabel: String {
        models.first(where: { $0.id == modelId })?.menuName
            ?? GrokModelOption(id: modelId, isDefault: false).displayName
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit automation" : "New automation")
                    .font(.system(size: 16, weight: .semibold))
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
                    field("Name") {
                        TextField("Weekly release notes", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .focused($nameFocused)
                            .padding(10)
                            .background(inputBackground)
                    }

                    field("Prompt") {
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
                        }
                        .background(inputBackground)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        field("Project") {
                            menuPicker(label: projectLabel, systemImage: "folder") { close in
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
                            menuPicker(label: modelLabel, systemImage: "cpu") { close in
                                CodexMenuContainer {
                                    ForEach(models) { option in
                                        CodexMenuItem(
                                            title: option.menuName,
                                            systemImage: "cpu",
                                            isSelected: option.id == modelId
                                        ) {
                                            modelId = option.id; close()
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

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        minWidth: CGFloat = 220,
        @ViewBuilder menu: @escaping (_ close: @escaping () -> Void) -> Menu
    ) -> some View {
        CodexMenuTrigger(minWidth: minWidth, highlightOnHover: false) { isOpen in
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
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
            modelId = seed.modelId.isEmpty ? defaultModelId : seed.modelId
            scheduleKind = seed.scheduleKind
            intervalMinutes = seed.intervalMinutes ?? 30
            timeOfDay = seed.timeOfDay ?? "09:00"
            enabled = seed.enabled
        } else {
            modelId = defaultModelId
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let interval: Int? = scheduleKind == .interval ? intervalMinutes : nil
        let time: String? = scheduleKind == .daily ? timeOfDay : nil

        let automation: Automation
        if let seed {
            automation = Automation(
                id: seed.id,
                name: trimmedName,
                prompt: trimmedPrompt,
                projectPath: projectPath,
                modelId: modelId,
                scheduleKind: scheduleKind,
                intervalMinutes: interval,
                timeOfDay: time,
                enabled: enabled,
                lastRun: seed.lastRun,
                createdAt: seed.createdAt
            )
        } else {
            automation = Automation(
                name: trimmedName,
                prompt: trimmedPrompt,
                projectPath: projectPath,
                modelId: modelId,
                scheduleKind: scheduleKind,
                intervalMinutes: interval,
                timeOfDay: time,
                enabled: enabled
            )
        }
        onSave(automation)
    }
}
