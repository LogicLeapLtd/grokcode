import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var model
    @EnvironmentObject private var update: UpdateService

    private let titlebarControlsTopInset: CGFloat = 1

    /// License/trial gate. Owned here as a `@StateObject` so its lifetime matches
    /// the primary window and its published state drives the paywall/banner.
    @StateObject private var license = LicenseManager()

    /// Local build handoff watcher. Future Codex/Claude sessions drop a built
    /// app into Application Support; the running canonical app offers it here.
    @StateObject private var localBuildUpdate = LocalBuildUpdateService()

    @State private var showLaunchMascot = true

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
                        if model.activePage == .settings {
                            // Settings owns its own navigation column, so replace
                            // the app sidebar instead of mounting two sidebars.
                            mainContentColumn
                        } else {
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

                                mainContentColumn
                            }
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
                // Quietly check for a newer release in the background. If one is
                // found, show a small bottom-right prompt instead of popping the
                // full dialog uninvited.
                localBuildUpdate.startWatching()
                update.checkInBackgroundIfEnabled()
            }
            .onChange(of: license.isInLimitedMode) { _, limited in
                if limited, model.activePage == .automations {
                    model.navigateTo(.home)
                }
            }

            windowTitlebarControls
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea(.container, edges: .top)
                .zIndex(20)

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

            // Software-update dialog. A download/install is in flight-safe: the
            // backdrop tap only dismisses when we're not mid-install.
            AnimatedModal(isPresented: update.isDialogPresented, onDismiss: { dismissUpdateDialog() }) {
                UpdateDialog()
                    .environmentObject(update)
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
        .overlay {
            if showLaunchMascot && model.preferences.showLaunchMascot {
                LaunchMascotOverlay {
                    showLaunchMascot = false
                }
                .transition(.opacity)
                    .zIndex(400)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            bottomRightUpdatePrompts
                .padding(.trailing, 22)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(350)
        }
        .animation(model.preferences.reduceMotion ? nil : CodexMotion.modalSpring, value: model.commandPaletteOpen)
        .animation(model.preferences.reduceMotion ? nil : CodexMotion.modalSpring, value: model.onboardingOpen)
        .animation(model.preferences.reduceMotion ? nil : .easeOut(duration: 0.18), value: model.fullScreenImagePath)
        .animation(model.preferences.reduceMotion ? nil : .easeOut(duration: 0.22), value: showLaunchMascot)
        .animation(model.preferences.reduceMotion ? nil : CodexMotion.modalSpring, value: update.isDialogPresented)
        .animation(CodexMotion.quickSpring, value: update.updateAvailableInBackground)
        .animation(CodexMotion.quickSpring, value: localBuildUpdate.hasPromptableBuild)
        .environmentObject(license)
        .environmentObject(update)
        .codexMenuHost()
        .focusEffectDisabled()
        .background(WindowConfigurator())
        .preferredColorScheme(model.appearance.colorScheme)
    }

    /// Backdrop-tap / dismiss handler for the update dialog. Ignored while an
    /// install is running so a stray click can't abandon the swap-and-relaunch.
    private func dismissUpdateDialog() {
        if case .installing = update.phase { return }
        update.isDialogPresented = false
    }

    @ViewBuilder
    private var bottomRightUpdatePrompts: some View {
        if localBuildUpdate.hasPromptableBuild {
            localBuildPromptToast
        } else if update.updateAvailableInBackground && !update.isDialogPresented {
            releaseUpdatePromptToast
        }
    }

    private var localBuildPromptToast: some View {
        HStack(spacing: 10) {
            Image(systemName: localBuildUpdate.isInstalling ? "arrow.triangle.2.circlepath.circle.fill" : "shippingbox.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(localBuildUpdate.isInstalling ? "Installing update" : "New build ready")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text(localBuildUpdate.pendingBuild?.versionLabel ?? "Installing and relaunching")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
            }

            if localBuildUpdate.isInstalling {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
            } else {
                Button { localBuildUpdate.installAndRelaunch() } label: {
                    Text("Update & Relaunch")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CodexTheme.sendButtonActiveBackground)
                        )
                }
                .buttonStyle(.plain)

                Button { localBuildUpdate.snoozeCurrent() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(CodexTheme.pillBackground))
                }
                .buttonStyle(.plain)
                .help("Dismiss this local build")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder.opacity(0.82), lineWidth: 1)
        )
        .shadow(color: CodexTheme.shadowColor.opacity(0.30), radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help("Install local Codessa build")
    }

    private var releaseUpdatePromptToast: some View {
        Button { update.presentDialog() } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CodexTheme.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    Text("Install the latest Codessa build")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(CodexTheme.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CodexTheme.composerBorder.opacity(0.82), lineWidth: 1)
            )
            .shadow(color: CodexTheme.shadowColor.opacity(0.30), radius: 18, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open software update")
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

    private var mainContentColumn: some View {
        // Page column runs the full height of the window.
        VStack(spacing: 0) {
            MainContentView()
        }
        .layoutPriority(1)
        // Pull the column up into the transparent title-bar strip so the page
        // content sits flush at the very top instead of leaving a dead ~28pt gap
        // beneath the title bar. Traffic-light buttons live over the sidebar, so
        // the page column's top edge is free.
        .ignoresSafeArea(.container, edges: .top)
    }

    private var windowTitlebarControls: some View {
        // A compact trio (collapse · back · forward) that sits immediately to the
        // right of the macOS traffic-light buttons, top-left over the sidebar
        // glass, vertically aligned with the native stoplights. `spacing: 2`
        // matches the app's other icon clusters (MainContentView window controls,
        // the Projects header bar); `leading: 74` clears the green stoplight
        // (~x20–68) with a hair of breathing room.
        HStack(spacing: 2) {
            titlebarButton(
                "sidebar.left",
                help: model.sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"
            ) {
                model.toggleSidebarCollapsed()
            }

            titlebarButton("arrow.left", help: "Back", isEnabled: model.canNavigateBack) {
                model.navigateBack()
            }

            titlebarButton("arrow.right", help: "Forward", isEnabled: model.canNavigateForward) {
                model.navigateForward()
            }
        }
        .background(NonDraggableRegion())
        .padding(.leading, 74)
        .padding(.top, titlebarControlsTopInset)
    }

    private func titlebarButton(_ symbol: String,
                                help: String,
                                isEnabled: Bool = true,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 26, height: 26)
                .codexHover(cornerRadius: 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .help(help)
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
            windowWidth < 1_200
        case .plugins, .automations, .projectContext:
            windowWidth < 1_030
        case .home, .chat, .search:
            windowWidth < 880
        }
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}
