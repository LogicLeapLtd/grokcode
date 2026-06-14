import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var model

    /// License/trial gate. Owned here as a `@StateObject` so its lifetime matches
    /// the primary window and its published state drives the paywall/banner.
    @StateObject private var license = LicenseManager()

    var body: some View {
        ZStack {
            // The main app shell, wrapped in the license gate. The gate shows a
            // trial-countdown banner during the trial and a hard paywall once it
            // elapses without a valid license. It wraps ONLY the shell — the
            // onboarding/command-palette overlays below sit at a higher zIndex so
            // first-run onboarding is never blocked by the paywall (gate AFTER the
            // user has seen the app's value).
            LicenseGateView(license: license) {
                HStack(spacing: 0) {
                    SidebarView()
                        .zIndex(1)

                    Rectangle()
                        .fill(CodexTheme.divider)
                        .frame(width: 1)
                        .zIndex(2)

                    MainContentView()
                        .layoutPriority(1)
                }
            }
            .ignoresSafeArea(.container, edges: .top)   // fill under the title bar
            .task {
                await model.bootstrap()
                // Start the trial timer / re-validate any stored license after the
                // app has bootstrapped, so onboarding (gated on first run) wins the
                // initial surface and the paywall only ever appears behind it.
                license.bootstrap()
            }

            AnimatedModal(isPresented: model.showHooksReview, onDismiss: { model.closeHooksReview() }) {
                HooksReviewView()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CodexTheme.mainBackground)
                            .shadow(color: CodexTheme.shadowColor, radius: 24, y: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
                    )
            }
        }
        .overlay {
            if model.commandPaletteOpen {
                CommandPalette()
                    .zIndex(100)
            }
        }
        .overlay {
            if model.onboardingOpen {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .animation(CodexMotion.modalSpring, value: model.commandPaletteOpen)
        .animation(CodexMotion.modalSpring, value: model.onboardingOpen)
        .codexMenuHost()
        .focusEffectDisabled()
        .background(WindowConfigurator())
        .preferredColorScheme(model.appearance.colorScheme)
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}