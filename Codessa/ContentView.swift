import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var model

    /// License/trial gate. Owned here as a `@StateObject` so its lifetime matches
    /// the primary window and its published state drives the paywall/banner.
    @StateObject private var license = LicenseManager()
    @State private var commandKeyPressed = false

    var body: some View {
        ZStack {
            windowBackdrop

            // The main app shell, wrapped in license-aware animation hooks. Trial
            // and limited-mode states live in the page banner so the app remains
            // usable instead of forcing a blocking license prompt.
            LicenseGateView(license: license) {
                GeometryReader { proxy in
                    let compactSidebar = shouldForceCompactSidebar(windowWidth: proxy.size.width)
                    let sidebarWidth = compactSidebar || model.sidebarCollapsed
                        ? model.collapsedSidebarWidth
                        : model.sidebarWidth

                    ZStack(alignment: .topLeading) {
                        sidebarTitlebarBackdrop(width: sidebarWidth)

                        HStack(spacing: 0) {
                            SidebarView(
                                limitedMode: license.isInLimitedMode,
                                forceCollapsed: compactSidebar
                            )
                            .layoutPriority(2)
                            .zIndex(1)

                            Rectangle()
                                .fill(CodexTheme.divider)
                                .frame(width: 1)
                                .zIndex(2)

                            // License banner sits at the top of the PAGE column only, so
                            // the sidebar runs the full height of the window.
                            VStack(spacing: 0) {
                                if license.isInTrial || license.isInLimitedMode {
                                    TrialBanner(license: license)
                                        .transition(CodexMotion.bannerTransition)
                                }
                                MainContentView()
                            }
                            .layoutPriority(1)
                            // Pull the column up into the transparent title-bar strip so the
                            // trial banner sits flush at the very top instead of leaving a
                            // dead ~28pt gap beneath the title bar. Traffic-light buttons
                            // live over the sidebar, so the page column's top edge is free.
                            .ignoresSafeArea(.container, edges: .top)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                }
            }
            .task {
                await model.bootstrap()
                // Start the trial timer / re-validate any stored license after
                // the app has bootstrapped, so onboarding wins the initial
                // surface and license state settles into the non-blocking banner.
                license.bootstrap()
            }
            .onChange(of: license.isInLimitedMode) { _, limited in
                if limited, model.activePage == .automations {
                    model.navigateTo(.home)
                }
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
        .overlay {
            if let path = model.fullScreenImagePath {
                FullScreenImageOverlay(path: path) { model.fullScreenImagePath = nil }
                    .zIndex(300)
            }
        }
        .animation(CodexMotion.modalSpring, value: model.commandPaletteOpen)
        .animation(CodexMotion.modalSpring, value: model.onboardingOpen)
        .animation(.easeOut(duration: 0.18), value: model.fullScreenImagePath)
        .environment(\.commandKeyPressed, commandKeyPressed)
        .codexMenuHost()
        .focusEffectDisabled()
        .background(CommandKeyObserver(isPressed: $commandKeyPressed))
        .background(WindowConfigurator())
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var windowBackdrop: some View {
        VisualEffectView(material: .underWindowBackground)
            .overlay(CodexTheme.mainBackground.opacity(0.92))
            .overlay(
                LinearGradient(
                    colors: [
                        CodexTheme.sidebarBackground.opacity(0.20),
                        CodexTheme.mainBackground.opacity(0.28)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .ignoresSafeArea()
    }

    private func sidebarTitlebarBackdrop(width: Double) -> some View {
        VisualEffectView(material: .sidebar)
            .overlay(CodexTheme.glassTint)
            .frame(width: width + 1)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
    }

    private func shouldForceCompactSidebar(windowWidth: CGFloat) -> Bool {
        switch model.activePage {
        case .settings:
            windowWidth < 1_260
        case .plugins, .automations, .projectDetail, .projectContext:
            windowWidth < 1_080
        case .home, .chat, .search:
            windowWidth < 920
        }
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}
