import SwiftUI
import AppKit

/// First-run onboarding overlay (shared contract). Presented from `ContentView`
/// over a dimmed backdrop whenever `model.onboardingOpen` is true. A single
/// centred glass card — not a long wizard — that gets the user from a cold
/// install to a working, provider-agnostic setup in one view:
///   1. Warm welcome with the Codessa identity (chevron prompt + violet
///      block-cursor motif recreated in SwiftUI, in Fraunces).
///   2. AI providers — a dock of every supported agent CLI (Claude Code, Codex,
///      Cursor, Gemini, Grok, Z.AI) with per-provider detected/not-detected
///      status rings, plus a "+ Custom" slot. No single provider is the focus.
///   3. "Add a project folder" (NSOpenPanel → `model.addProjectRoot`).
///   4. A default-provider + model picker (`CodexMenuTrigger` over `model.models`).
/// A prominent "Get started" button calls `model.completeOnboarding()`.
///
/// The card lives in its own overlay layer with its own `CodexMenuController`
/// and `.codexMenuHost()`, so the model dropdown renders above the card rather
/// than on the main window's host behind it.
struct OnboardingView: View {
    @Environment(AppViewModel.self) private var model

    /// Dedicated menu host for the in-card model dropdown. No global key monitor —
    /// the overlay is short-lived and only needs menu rendering.
    @State private var menuController = CodexMenuController(installsKeyboardMonitor: false)
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Dimmed backdrop. Tapping outside is intentionally inert — the only
            // way out of onboarding is "Get started" (or skip), so first-run setup
            // is never dismissed by accident.
            CodexTheme.modalBackdrop
                .opacity(0.82)
                .ignoresSafeArea()
                .transition(.opacity)

            card
                .frame(width: 560)
                .background(glassBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.30), .white.opacity(0.13), .white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(appeared ? 1 : 0.96)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
        }
        .codexMenuHost()
        .environment(menuController)
        .onAppear {
            withAnimation(CodexMotion.modalSpring) { appeared = true }
        }
    }

    /// Frosted glass card background: within-window vibrancy + a faint violet
    /// tint + a diagonal specular sheen so the "glass" reads clearly regardless
    /// of what's behind the window.
    private var glassBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            Color.black.opacity(0.22)
            CodexTheme.mainBackground.opacity(0.28)
            CodexTheme.accent.opacity(0.045)
            LinearGradient(
                colors: [.white.opacity(0.075), .clear, .white.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: CodexTheme.shadowColor, radius: 34, y: 14)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            fadeRule
            VStack(spacing: 0) {
                providerStatusStep
                Divider().overlay(CodexTheme.divider.opacity(0.5))
                providerChoiceStep
                Divider().overlay(CodexTheme.divider.opacity(0.5))
                projectStep
                Divider().overlay(CodexTheme.divider.opacity(0.5))
                modelStep
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 6)
            fadeRule
            footer
        }
    }

    private var fadeRule: some View {
        LinearGradient(
            colors: [.clear, CodexTheme.divider, CodexTheme.divider, .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, 30)
    }

    // MARK: - Header (identity + welcome)

    private var header: some View {
        VStack(spacing: 16) {
            ChevronPromptMark()

            VStack(spacing: 8) {
                Text("Welcome to Codessa")
                    .font(CodexTheme.serif(28, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)

                Text("One native macOS home for your AI coding agents — bring Claude Code, Codex, Cursor, Gemini, Grok, Z.AI, or any custom CLI, and ship across every project from one clean surface.")
                    .font(CodexTheme.sans(14))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 42)
        .padding(.top, 36)
        .padding(.bottom, 28)
    }

    // MARK: - Step 1 · AI providers

    private var providerStatusStep: some View {
        OnboardingRow {
            HStack(spacing: 13) {
                StatusGlyph(systemImage: "square.grid.2x2.fill",
                            tint: model.installedProviderCount > 0 ? .green : CodexTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(providerHeadline)
                        .font(CodexTheme.sans(13.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text(providerSubtitle)
                        .font(CodexTheme.sans(12.5))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var providerChoiceStep: some View {
        OnboardingRow {
            HStack(alignment: .top, spacing: 16) {
                StatusGlyph(systemImage: "bolt.horizontal.circle.fill",
                            tint: model.selectedProviderIsWired ? CodexTheme.accent : CodexTheme.textSecondary)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose your starting agent")
                            .font(CodexTheme.sans(13.5, weight: .semibold))
                            .foregroundStyle(CodexTheme.textPrimary)
                        Text("Pick any detected provider now. You can still switch per chat later.")
                            .font(CodexTheme.sans(12.5))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(model.providerStatuses) { status in
                                ProviderDockItem(
                                    status: status,
                                    isSelected: status.provider.id == model.selectedProviderId,
                                    select: { model.selectProvider(status.provider.id) },
                                    setUp: { model.setUpProvider(status.provider) }
                                )
                            }
                            VStack(spacing: 7) {
                                Button(action: { model.addCustomProvider() }) {
                                    ProviderDockGlyph(monogram: "+", installed: false, isCustom: true, isSelected: false)
                                }
                                .buttonStyle(CodexPressableStyle())
                                .help("Add a custom agent CLI")
                                Text("Custom")
                                    .font(CodexTheme.sans(10))
                                    .foregroundStyle(CodexTheme.textTertiary)
                            }
                            .frame(width: 58)
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 2)
                    }

                    if !model.selectedProviderIsWired {
                        Text("Live runs currently route through the Grok engine — \(model.selectedProvider.shortName) is detected and selectable while its adapter lands.")
                            .font(CodexTheme.sans(11))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var providerHeadline: String {
        "Providers — \(model.installedProviderCount) of \(model.totalProviderCount) ready"
    }

    private var providerSubtitle: String {
        let installed = model.installedProviderNames
        switch installed.count {
        case 0:
            return "None detected on your PATH yet — sign in to any, or bring your own custom CLI."
        case 1:
            return "\(installed[0]) detected on your PATH — connect more, or bring your own CLI."
        default:
            let head = installed.prefix(2).joined(separator: " and ")
            return "\(head) detected on your PATH — connect more, or bring your own CLI."
        }
    }

    // MARK: - Step 2 · Add a project folder

    private var projectStep: some View {
        OnboardingRow {
            HStack(spacing: 13) {
                StatusGlyph(
                    systemImage: model.projectRoots.isEmpty ? "folder.badge.plus" : "folder.fill",
                    tint: model.projectRoots.isEmpty ? CodexTheme.textSecondary : .green
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectRootsTitle)
                        .font(CodexTheme.sans(13.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("Point Codessa at a folder of repos — it scans for projects automatically.")
                        .font(CodexTheme.sans(12.5))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: addProjectFolder) {
                    primaryPillLabel(model.projectRoots.isEmpty ? "Add folder" : "Add another",
                                     systemImage: "plus")
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 8)
            }
        }
    }

    private var projectRootsTitle: String {
        switch model.projectRoots.count {
        case 0: return "No project folders yet"
        case 1: return "1 project folder configured"
        default: return "\(model.projectRoots.count) project folders configured"
        }
    }

    /// NSOpenPanel → `model.addProjectRoot` (per the onboarding contract).
    private func addProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to scan for projects."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addProjectRoot(url)
    }

    // MARK: - Step 3 · Default provider + model

    private var modelStep: some View {
        OnboardingRow {
            HStack(spacing: 13) {
                StatusGlyph(systemImage: "cpu", tint: CodexTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick a provider and model to start with")
                        .font(CodexTheme.sans(13.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("You can switch providers or models any time from the composer.")
                        .font(CodexTheme.sans(12.5))
                        .foregroundStyle(CodexTheme.textSecondary)
                }
                Spacer(minLength: 8)
                modelPicker
            }
        }
    }

    private var modelLabel: String {
        let modelName = model.selectedModel?.displayName
            ?? model.models.first?.displayName
            ?? "Select"
        return "\(model.selectedProvider.shortName) · \(modelName)"
    }

    private var modelPicker: some View {
        CodexMenuTrigger(minWidth: 240, edge: .top, highlightOnHover: false) { isOpen in
            HStack(spacing: 8) {
                Image(systemName: (model.selectedModel?.isReasoningModel ?? false) ? "brain" : "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
                Text(modelLabel)
                    .font(CodexTheme.sans(13))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CodexTheme.composerBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isOpen ? CodexTheme.accent : CodexTheme.composerBorder, lineWidth: 1)
            )
        } menu: { close in
            CodexMenuContainer {
                if model.models.isEmpty {
                    CodexMenuItem(title: "No models available", action: {})
                } else {
                    ForEach(model.models) { option in
                        CodexMenuItem(
                            title: option.menuName,
                            subtitle: option.isReasoningModel ? "Reasoning" : nil,
                            systemImage: option.isReasoningModel ? "brain" : "cpu",
                            isSelected: option.id == model.selectedModel?.id
                        ) {
                            model.selectedModel = option
                            close()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button { model.completeOnboarding() } label: {
                Text("Skip for now")
                    .font(CodexTheme.sans(13, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { model.completeOnboarding() } label: {
                HStack(spacing: 6) {
                    Text("Get started")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(CodexProminentButtonStyle(cornerRadius: 11))
        }
        .padding(.horizontal, 34)
        .padding(.top, 18)
        .padding(.bottom, 26)
    }

    // MARK: - Shared bits

    private func primaryPillLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(CodexTheme.sans(12, weight: .medium))
        }
        .foregroundStyle(CodexTheme.sendButtonActiveForeground)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CodexTheme.sendButtonActiveBackground)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Unbordered checklist row

/// A single checklist item — a plain padded row (no bordered card), so the three
/// setup tasks read as a calm list separated by hairlines rather than a stack of
/// boxes.
private struct OnboardingRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 15)
    }
}

// MARK: - Provider dock

/// One provider in the dock: a circular glyph with a status ring (violet when
/// selected, green when installed), a check badge when detected, and a caption.
/// Tap selects; long-press / the badge routes to setup.
private struct ProviderDockItem: View {
    let status: ProviderStatus
    let isSelected: Bool
    let select: () -> Void
    let setUp: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: select) {
                ProviderDockGlyph(
                    monogram: status.provider.monogram,
                    systemImage: Self.symbol(for: status.provider.id),
                    installed: status.installed,
                    isCustom: status.provider.isCustom,
                    isSelected: isSelected
                )
            }
            .buttonStyle(CodexPressableStyle())
            .help(status.installed
                  ? "\(status.provider.name) — detected"
                  : "\(status.provider.name) — not installed")

            Text(status.provider.shortName)
                .font(CodexTheme.sans(9.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? CodexTheme.textSecondary : CodexTheme.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 58)
    }

    /// A distinct SF-Symbol stand-in per provider (real brand marks can be
    /// dropped into the asset catalog later without touching this view).
    static func symbol(for id: String) -> String? {
        switch id {
        case "claude": return "sparkle"
        case "cursor": return "cursorarrow.rays"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "sparkles"
        case "grok": return "bolt.fill"
        case "zai": return "bolt.horizontal.fill"
        default: return nil   // custom → monogram
        }
    }
}

/// The circular glyph itself, shared by provider tiles and the "+ Custom" slot.
private struct ProviderDockGlyph: View {
    var monogram: String
    var systemImage: String? = nil
    var installed: Bool
    var isCustom: Bool
    var isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isCustom ? Color.clear : CodexTheme.composerShellBackground)
                .overlay(
                    Circle().strokeBorder(
                        isCustom
                            ? AnyShapeStyle(CodexTheme.composerBorder)
                            : AnyShapeStyle(ringStyle),
                        style: StrokeStyle(lineWidth: isSelected || installed ? 2 : 1,
                                           dash: isCustom ? [3, 3] : [])
                    )
                )
                .frame(width: 42, height: 42)
                .shadow(color: installed ? Color.green.opacity(0.35) : .clear, radius: 6)

            glyph
                .foregroundStyle(installed || isSelected ? CodexTheme.textPrimary : CodexTheme.textSecondary)

            if installed {
                Circle()
                    .fill(Color.green)
                    .frame(width: 15, height: 15)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color(red: 0.04, green: 0.10, blue: 0.06))
                    )
                    .overlay(Circle().strokeBorder(CodexTheme.mainBackground, lineWidth: 2))
                    .offset(x: 15, y: 15)
            }
        }
        .frame(width: 42, height: 42)
        .opacity(installed || isSelected || isCustom ? 1 : 0.55)
    }

    private var ringStyle: Color {
        if isSelected { return CodexTheme.accent }
        if installed { return .green }
        return CodexTheme.composerBorder
    }

    @ViewBuilder private var glyph: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
        } else {
            Text(monogram)
                .font(CodexTheme.sans(isCustom ? 18 : 12, weight: .bold))
        }
    }
}

// MARK: - Status glyph

private struct StatusGlyph: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

// MARK: - Identity mark (chevron prompt + violet block-cursor)

/// Recreates the Codessa identity in SwiftUI: a terminal-style chevron prompt
/// (`›`) followed by a softly blinking violet block cursor, sat inside a rounded
/// "tile" so it reads as a brand mark rather than a stray glyph.
private struct ChevronPromptMark: View {
    @State private var cursorOn = true

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(CodexTheme.textPrimary)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CodexTheme.accent)
                .frame(width: 11, height: 24)
                .opacity(cursorOn ? 1 : 0.18)
                .shadow(color: CodexTheme.accent.opacity(cursorOn ? 0.55 : 0), radius: 10)
        }
        .frame(width: 68, height: 68)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CodexTheme.accent.opacity(0.18), CodexTheme.composerShellBackground],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                cursorOn = false
            }
        }
    }
}
