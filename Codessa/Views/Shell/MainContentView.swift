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
                        .codexPage("chat")
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
        .overlay(alignment: .topTrailing) { windowControls }
        .clipped()
        .animation(model.preferences.reduceMotion ? nil : CodexMotion.pageSpring, value: model.activePage)
    }

    private var windowControls: some View {
        HStack(spacing: 2) {
            topBarButton("rectangle.split.2x1", help: model.isSplitViewVisible ? "Add split pane" : "Open split view") {
                model.openSplitView()
            }
            topBarButton("square.on.square", help: "Open chat in a new window") {
                openWindow(id: "chat-popout")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
