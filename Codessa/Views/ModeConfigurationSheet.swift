import SwiftUI

struct ModeConfigurationSheet: View {
    private static let customModelSentinel = "__custom_model__"

    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draftModes: [AgentModeProfile] = []
    @State private var selectedModeID = AgentModeProfile.planID

    private var selectedIndex: Int? {
        draftModes.firstIndex { $0.id == selectedModeID }
    }

    private var providerOptions: [AgentProvider] {
        var providers = AgentProvider.known
        for status in model.providerStatuses where !providers.contains(where: { $0.id == status.provider.id }) {
            providers.append(status.provider)
        }
        return providers
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                detailPane
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .background(CodexTheme.mainBackground)
        .onAppear {
            draftModes = model.agentModes
            selectedModeID = model.activeAgentModeID
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CodexTheme.pillBackground.opacity(0.44)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Modes")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text("Set the instructions, permissions, and model route each mode uses.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CodexTheme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(spacing: 8) {
            ForEach(draftModes) { mode in
                modeSidebarRow(mode)
            }

            Spacer(minLength: 12)

            Button {
                let mode = AgentModeProfile(
                    id: "custom-" + UUID().uuidString,
                    name: "Custom mode",
                    kind: .execute,
                    permissionMode: .auto,
                    executionRoute: ModeModelRoute(selection: .inheritParent),
                    isBuiltIn: false
                )
                draftModes.append(mode)
                selectedModeID = mode.id
            } label: {
                Label("Add mode", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CodexTheme.textSecondary)
            .codexHover(cornerRadius: 8)
        }
        .padding(12)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private func modeSidebarRow(_ mode: AgentModeProfile) -> some View {
        let selected = selectedModeID == mode.id

        return Button {
            selectedModeID = mode.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(selected ? CodexTheme.pillBackground.opacity(0.62) : .clear))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.name)
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .lineLimit(1)
                        if mode.isBuiltIn {
                            Text("Built-in")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(CodexTheme.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.44)))
                        }
                    }
                    Text(mode.kind.label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(CodexTheme.textTertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? CodexTheme.navHighlight : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let index = selectedIndex {
            ScrollView {
                modeDetail($draftModes[index])
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        } else {
            Text("Select a mode")
                .font(CodexTheme.bodyFont)
                .foregroundStyle(CodexTheme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func modeDetail(_ mode: Binding<AgentModeProfile>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            overviewCard(mode)

            routeCard(
                title: mode.wrappedValue.kind == .plan ? "Planning model" : "Execution model",
                subtitle: mode.wrappedValue.kind == .plan
                    ? "Used while drafting the plan."
                    : "Used for normal execution in this mode.",
                route: mode.wrappedValue.kind == .plan ? mode.planningRoute : mode.executionRoute
            )

            if mode.wrappedValue.kind == .plan {
                routeCard(
                    title: "After approval",
                    subtitle: "Used for the next turn when a rendered plan is approved.",
                    route: mode.executionRoute
                )
            }

            instructionCard(mode)
        }
    }

    private func overviewCard(_ mode: Binding<AgentModeProfile>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.wrappedValue.kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(CodexTheme.pillBackground.opacity(0.48)))

                VStack(alignment: .leading, spacing: 8) {
                    if mode.wrappedValue.isBuiltIn {
                        Text(mode.wrappedValue.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CodexTheme.textPrimary)
                    } else {
                        TextField("Mode name", text: mode.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CodexTheme.textPrimary)
                    }

                    HStack(spacing: 8) {
                        if mode.wrappedValue.isBuiltIn {
                            readOnlyChip(mode.wrappedValue.kind.label, icon: "lock.fill")
                        } else {
                            Picker("Type", selection: mode.kind) {
                                ForEach(AgentModeKind.allCases) { kind in
                                    Text(kind.label).tag(kind)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        Picker("Permission", selection: mode.permissionMode) {
                            ForEach(PermissionMode.allCases) { permission in
                                Text(permission.label).tag(permission)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }

                Spacer(minLength: 0)
            }

            if !mode.wrappedValue.isBuiltIn {
                Button(role: .destructive) {
                    draftModes.removeAll { $0.id == mode.wrappedValue.id }
                    selectedModeID = draftModes.first?.id ?? AgentModeProfile.executeID
                } label: {
                    Label("Delete mode", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .modeCard()
    }

    private func routeCard(title: String, subtitle: String, route: Binding<ModeModelRoute>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(CodexTheme.textTertiary)
                }
                Spacer(minLength: 0)
                Text(route.wrappedValue.usesParentModel ? "Inherited" : "Specific")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.48)))
            }

            HStack(spacing: 8) {
                routeChoice(
                    "Inherit chat model",
                    "Use the model selected in the composer.",
                    selected: route.wrappedValue.selection == .inheritParent
                ) {
                    route.wrappedValue.selection = .inheritParent
                }

                routeChoice(
                    "Specific route",
                    "Choose provider and model for this mode.",
                    selected: route.wrappedValue.selection == .explicit
                ) {
                    route.wrappedValue.selection = .explicit
                }
            }

            if route.wrappedValue.selection == .explicit {
                HStack(spacing: 10) {
                    Picker("Provider", selection: Binding<String>(
                        get: { route.wrappedValue.providerID },
                        set: { providerID in
                            route.wrappedValue.providerID = providerID
                            if let first = model.modelOptions(for: providerID).first {
                                route.wrappedValue.modelID = first.id
                            } else {
                                route.wrappedValue.modelID = ""
                            }
                        }
                    )) {
                        ForEach(providerOptions) { provider in
                            Text(provider.shortName).tag(provider.id)
                        }
                    }
                    .frame(width: 170)

                    modelPicker(route)
                }
            }
        }
        .modeCard()
    }

    @ViewBuilder
    private func modelPicker(_ route: Binding<ModeModelRoute>) -> some View {
        let options = model.modelOptions(for: route.wrappedValue.providerID)
        let selectedModelID = route.wrappedValue.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownIDs = Set(options.map(\.id))
        let isCustom = selectedModelID.isEmpty || !knownIDs.contains(selectedModelID)

        HStack(spacing: 10) {
            Picker("Model", selection: Binding(
                get: { isCustom ? Self.customModelSentinel : selectedModelID },
                set: { value in
                    if value == Self.customModelSentinel {
                        route.wrappedValue.modelID = ""
                    } else {
                        route.wrappedValue.modelID = value
                    }
                }
            )) {
                ForEach(options) { option in
                    Text(option.displayName).tag(option.id)
                }
                Divider()
                Text("Custom…").tag(Self.customModelSentinel)
            }
            .frame(width: isCustom ? 170 : 260)

            if isCustom {
                TextField("Custom model id", text: route.modelID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CodexTheme.composerBackground.opacity(0.68))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(CodexTheme.divider, lineWidth: 1)
                    )
            }
        }
    }

    private func routeChoice(_ title: String, _ subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? CodexTheme.accent : CodexTheme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? CodexTheme.navHighlight.opacity(0.85) : CodexTheme.composerBackground.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? CodexTheme.textTertiary.opacity(0.28) : CodexTheme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func instructionCard(_ mode: Binding<AgentModeProfile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Locked instructions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                }

                Text(mode.wrappedValue.lockedInstructions)
                    .font(.system(size: 12.5))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.composerBackground.opacity(0.52))
                    )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Additional instructions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: mode.customInstructions)
                        .font(.system(size: 12.5))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 94)

                    if mode.wrappedValue.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add optional instructions for this mode.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(CodexTheme.composerBackground.opacity(0.52))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(CodexTheme.divider, lineWidth: 1)
                )
            }
        }
        .modeCard()
    }

    private func readOnlyChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(CodexTheme.pillBackground.opacity(0.48)))
    }

    private var footer: some View {
        HStack {
            Button("Reset built-ins") {
                draftModes = AgentModeProfile.defaults
                selectedModeID = AgentModeProfile.executeID
            }
            .buttonStyle(.plain)
            .foregroundStyle(CodexTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .codexHover(cornerRadius: 7)

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Save") {
                for mode in draftModes {
                    model.upsertAgentMode(mode)
                }
                for mode in model.agentModes where !draftModes.contains(where: { $0.id == mode.id }) {
                    model.deleteAgentMode(mode.id)
                }
                model.selectAgentMode(selectedModeID)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private extension View {
    func modeCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodexTheme.pillBackground.opacity(0.24))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CodexTheme.divider.opacity(0.9), lineWidth: 1)
            )
    }
}
