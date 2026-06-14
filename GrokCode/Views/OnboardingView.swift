import SwiftUI
import AppKit

/// First-run onboarding overlay (shared contract). Presented from `ContentView`
/// over a dimmed backdrop whenever `model.onboardingOpen` is true. A single
/// centred card — not a long wizard — that gets the user from a cold install to
/// a working setup in one view:
///   1. Warm welcome with the GrokCode identity (chevron prompt + orange
///      block-cursor motif recreated in SwiftUI).
///   2. Grok CLI status — a green check when detected, or an amber "Not found"
///      row with a "Run grok login" button + install hint.
///   3. "Add a project folder" (NSOpenPanel → `model.addProjectRoot`), showing
///      how many roots are configured.
///   4. A default-model picker (`CodexMenuTrigger` over `model.models`).
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
                .frame(width: 520)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(CodexTheme.mainBackground)
                        .shadow(color: CodexTheme.shadowColor, radius: 32, y: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
                )
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

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            Divider().background(CodexTheme.divider)

            VStack(alignment: .leading, spacing: 18) {
                grokStatusStep
                projectStep
                modelStep
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Divider().background(CodexTheme.divider)
            footer
        }
    }

    // MARK: - Header (identity + welcome)

    private var header: some View {
        VStack(spacing: 16) {
            ChevronPromptMark()

            VStack(spacing: 7) {
                Text("Welcome to GrokCode")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)

                Text("A native macOS home for the Grok CLI — plan, build, and ship across your projects from one clean surface.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
    }

    // MARK: - Step 1 · Grok CLI status

    @ViewBuilder
    private var grokStatusStep: some View {
        if model.grokAvailable {
            OnboardingStep(number: 1, title: "Grok CLI") {
                HStack(spacing: 9) {
                    StatusGlyph(systemImage: "checkmark.seal.fill", tint: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grok CLI detected")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(CodexTheme.textPrimary)
                        Text(model.grokBinaryPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(stepCardBackground)
            }
        } else {
            OnboardingStep(number: 1, title: "Grok CLI") {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 9) {
                        StatusGlyph(systemImage: "exclamationmark.triangle.fill",
                                    tint: CodexTheme.accentOrange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Grok CLI not found")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(CodexTheme.textPrimary)
                            Text("Install it, then sign in — GrokCode drives the local `grok` command.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(CodexTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(model.grokInstallCommand)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(CodexTheme.composerShellBackground)
                        )

                    HStack(spacing: 8) {
                        Button { model.runGrokLogin() } label: {
                            primaryPillLabel("Run grok login", systemImage: "terminal")
                        }
                        .buttonStyle(CodexPressableStyle())
                        .codexHoverOverlay(cornerRadius: 8)

                        Button { model.openGrokDocs() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "book")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Install docs")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(CodexTheme.textPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(CodexTheme.pillBackground)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CodexPressableStyle())
                        .codexHoverOverlay(cornerRadius: 8)

                        Spacer(minLength: 0)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(CodexTheme.errorBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(CodexTheme.errorBorder, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Step 2 · Add a project folder

    private var projectStep: some View {
        OnboardingStep(number: 2, title: "Your projects") {
            HStack(spacing: 11) {
                StatusGlyph(
                    systemImage: model.projectRoots.isEmpty ? "folder.badge.plus" : "folder.fill",
                    tint: model.projectRoots.isEmpty ? CodexTheme.textSecondary : .green
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectRootsTitle)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("Point GrokCode at a folder of repos — it scans for projects automatically.")
                        .font(.system(size: 11.5))
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
            .padding(11)
            .background(stepCardBackground)
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

    // MARK: - Step 3 · Default model

    private var modelStep: some View {
        OnboardingStep(number: 3, title: "Default model") {
            HStack(spacing: 11) {
                StatusGlyph(systemImage: "cpu", tint: CodexTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick a model to start with")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("You can switch any time from the composer.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(CodexTheme.textSecondary)
                }
                Spacer(minLength: 8)
                modelPicker
            }
            .padding(11)
            .background(stepCardBackground)
        }
    }

    private var modelLabel: String {
        model.selectedModel?.menuName
            ?? model.models.first?.menuName
            ?? "Select a model"
    }

    private var modelPicker: some View {
        CodexMenuTrigger(minWidth: 240, edge: .top, highlightOnHover: false) { isOpen in
            HStack(spacing: 8) {
                Image(systemName: (model.selectedModel?.isReasoningModel ?? false) ? "brain" : "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
                Text(modelLabel)
                    .font(.system(size: 13))
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
                    .strokeBorder(isOpen ? CodexTheme.textTertiary : CodexTheme.composerBorder, lineWidth: 1)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { model.completeOnboarding() } label: {
                HStack(spacing: 6) {
                    Text("Get started")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CodexTheme.sendButtonActiveBackground)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(cornerRadius: 10)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Shared bits

    private func primaryPillLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
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

    private var stepCardBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(CodexTheme.composerBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
            )
    }
}

// MARK: - Numbered step wrapper

private struct OnboardingStep<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(CodexTheme.pillBackground)
                    )
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .kerning(0.5)
                Spacer(minLength: 0)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

// MARK: - Identity mark (chevron prompt + orange block-cursor)

/// Recreates the GrokCode identity in SwiftUI: a terminal-style chevron prompt
/// (`›`) followed by a softly blinking orange block cursor, sat inside a rounded
/// "tile" so it reads as a brand mark rather than a stray glyph.
private struct ChevronPromptMark: View {
    @State private var cursorOn = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CodexTheme.textPrimary)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CodexTheme.accentOrange)
                .frame(width: 13, height: 26)
                .opacity(cursorOn ? 1 : 0.18)
                .shadow(color: CodexTheme.accentOrange.opacity(cursorOn ? 0.5 : 0), radius: 8)
        }
        .frame(width: 76, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CodexTheme.composerShellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                cursorOn = false
            }
        }
    }
}
