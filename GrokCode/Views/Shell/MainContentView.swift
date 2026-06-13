import SwiftUI

struct MainContentView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            CodexTheme.mainBackground

            switch model.activePage {
            case .home:
                HomeView()
                    .codexPage("home")
            case .chat:
                ChatView()
                    .codexPage("chat")
            case .search:
                SearchPageView()
                    .codexPage("search")
            case .plugins:
                FeaturePlaceholderView(
                    title: "Plugins",
                    subtitle: "Browse and manage Grok plugins, MCP servers, and skills.",
                    symbol: "puzzlepiece.extension"
                )
                .codexPage("plugins")
            case .automations:
                FeaturePlaceholderView(
                    title: "Automations",
                    subtitle: "Schedule recurring Grok tasks for your projects.",
                    symbol: "gearshape.2"
                )
                .codexPage("automations")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { windowControls }
        .clipped()
        .animation(CodexMotion.pageSpring, value: model.activePage)
    }

    private var windowControls: some View {
        HStack(spacing: 2) {
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
