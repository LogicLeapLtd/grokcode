import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(AppViewModel.self) private var model
    @State private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case projects = "Projects"
        case cli = "Grok CLI"
        case about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .projects: "folder"
            case .cli: "terminal"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(CodexTheme.divider).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch section {
                    case .general: generalSection
                    case .projects: projectsSection
                    case .cli: cliSection
                    case .about: aboutSection
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620, height: 460)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ForEach(Section.allCases) { item in
                Button { section = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .frame(width: 16)
                        Text(item.rawValue)
                            .font(.system(size: 13))
                            .foregroundStyle(CodexTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(section == item ? CodexTheme.navHighlight : .clear)
                    )
                    .codexHover(cornerRadius: 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button { model.closeSettings() } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CodexTheme.pillBackground)
                    )
                    .codexHover()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(10)
        .frame(width: 180)
        .background(CodexTheme.sidebarBackground)
    }

    // MARK: General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("General")

            settingRow("Default model", "Used when starting a new chat.") {
                CodexMenuTrigger(minWidth: 220) { _ in
                    fieldLabel(model.selectedModel?.displayName ?? "Model")
                } menu: { close in
                    CodexMenuContainer {
                        ForEach(model.models) { option in
                            CodexMenuItem(
                                title: option.displayName,
                                subtitle: option.isReasoningModel ? "Reasoning" : "Fast",
                                isSelected: model.selectedModel == option
                            ) { model.selectedModel = option; model.persistDefaults(); close() }
                        }
                    }
                }
            }

            settingRow("Default permission mode", "How much Grok can do without asking.") {
                CodexMenuTrigger(minWidth: 260) { _ in
                    fieldLabel(model.permissionMode.label)
                } menu: { close in
                    CodexMenuContainer {
                        ForEach(PermissionMode.allCases) { mode in
                            CodexMenuItem(title: mode.label, subtitle: mode.detail,
                                          isSelected: model.permissionMode == mode) {
                                model.permissionMode = mode; model.persistDefaults(); close()
                            }
                        }
                    }
                }
            }

            if model.selectedModel?.isReasoningModel == true {
                settingRow("Reasoning effort", "Only applies to reasoning models (Grok 4).") {
                    CodexMenuTrigger(minWidth: 180) { _ in
                        fieldLabel(model.effortLevel.label)
                    } menu: { close in
                        CodexMenuContainer {
                            ForEach(EffortLevel.allCases) { level in
                                CodexMenuItem(title: level.label, isSelected: model.effortLevel == level) {
                                    model.effortLevel = level; model.persistDefaults(); close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Project roots")
            Text("Folders scanned for git / Xcode / Swift projects.")
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textSecondary)

            VStack(spacing: 0) {
                if model.projectRoots.isEmpty {
                    Text("No folders added yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                ForEach(model.projectRoots, id: \.path) { root in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(CodexTheme.textSecondary)
                        Text(root.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button { model.removeProjectRoot(root) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CodexTheme.textTertiary)
                                .frame(width: 22, height: 22)
                                .codexHover(cornerRadius: 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(CodexTheme.sidebarBackground))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CodexTheme.divider, lineWidth: 1))

            HStack(spacing: 8) {
                pillButton("Add folder…", icon: "plus") { pickFolder() }
                pillButton("Refresh", icon: "arrow.clockwise") { model.refreshProjects() }
            }
        }
    }

    // MARK: CLI

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Grok CLI")
            HStack(spacing: 8) {
                Image(systemName: model.grokAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.grokAvailable ? .green : CodexTheme.accentOrange)
                Text(model.grokAvailable ? "Grok CLI detected" : "Grok CLI not found")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
            }
            infoRow("Expected path", "~/.grok/bin/grok")
            infoRow("Models available", "\(model.models.count)")
            infoRow("Recent sessions", "\(model.sessions.count)")
            Text("If the CLI isn't detected, install it or run `grok login` in a terminal.")
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textSecondary)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("About")
            infoRow("App", "GrokCode")
            infoRow("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            infoRow("A native macOS front-end for the Grok CLI.", "")
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(CodexTheme.textPrimary)
    }

    private func settingRow<Control: View>(_ title: String, _ subtitle: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(CodexTheme.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(CodexTheme.textTertiary)
            }
            Spacer()
            control()
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(CodexTheme.divider, lineWidth: 1)
                )
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 13)).foregroundStyle(CodexTheme.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(CodexTheme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, design: value.contains("/") ? .monospaced : .default))
                .foregroundStyle(CodexTheme.textPrimary)
        }
    }

    private func pillButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(CodexTheme.pillBackground))
            .codexHover()
        }
        .buttonStyle(.plain)
    }

    private func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            model.addProjectRoot(url)
        }
        #endif
    }
}
