import SwiftUI

struct MainContentView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            // Translucent dark base: a behind-window vibrancy tinted near-black.
            // Keeps the page reading "dark black" while giving the Liquid Glass
            // chrome (composer, cards, banners) something to refract — over a
            // fully opaque fill, glass just looks flat grey.
            VisualEffectView(material: .underWindowBackground)
                .overlay(CodexTheme.mainBackground.opacity(0.82))
                .ignoresSafeArea()

            // Living, state-aware ambient field (drifting glow orbs + starfield)
            // that intensifies while the AI is responding. Sits over the dark
            // base, under the page content + Liquid Glass chrome.
            if model.preferences.ambientBackgroundEnabled {
                AmbientBackgroundView(active: model.isRunning)
            }

            if model.isSplitViewVisible && model.activePage != .settings {
                SplitWorkspaceView()
                    .codexPage("splitWorkspace")
            } else {
                switch model.activePage {
                case .home:
                    HomeView()
                        .codexPage("home")
                case .chat:
                    ChatView()
                        .codexChatPage("chat")
                case .search:
                    SearchPageView()
                        .codexUtilityPage("search")
                case .plugins:
                    PluginsView()
                        .codexUtilityPage("plugins")
                case .automations:
                    AutomationsView()
                        .codexUtilityPage("automations")
                case .settings:
                    SettingsView()
                        .codexPage("settings")
                case .projectContext:
                    ProjectContextEditor()
                        .codexPage("projectContext")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if showsFloatingWindowControls {
                windowControls
            }
        }
        .clipped()
        .animation(pageAnimation, value: model.activePage)
    }

    private var showsFloatingWindowControls: Bool {
        model.activePage != .chat || model.isSplitViewVisible
    }

    private var pageAnimation: Animation? {
        guard !model.preferences.reduceMotion else { return nil }
        return model.activePage == .chat ? CodexMotion.chatStartSpring : CodexMotion.pageSpring
    }

    private var windowControls: some View {
        HStack(spacing: 2) {
            topBarButton("rectangle.split.2x1", help: model.isSplitViewVisible ? "Add split pane" : "Open split view") {
                model.openSplitView()
            }
            topBarButton("macwindow", help: "Open chat in a new window") {
                openWindow(id: "chat-popout")
            }
        }
        // Sit clear of the window's rounded top-right corner (radius ~16) so the
        // trailing icon isn't clipped by the curve.
        .padding(.trailing, 16)
        .padding(.top, 12)
    }

    private func topBarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 26, height: 26)
                .codexHover(cornerRadius: 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
