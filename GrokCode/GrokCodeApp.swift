import SwiftUI

@main
struct GrokCodeApp: App {
    @State private var appModel = AppViewModel()
    @State private var menuController = CodexMenuController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(menuController)
                .frame(minWidth: 1000, minHeight: 700)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { appModel.startNewChat() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Cycle Permission Mode") { appModel.cyclePermissionMode() }
                    .keyboardShortcut("m", modifiers: [.shift, .command])
            }
        }
        #endif

        // Popped-out chat window — shares the same view model, so it mirrors
        // the conversation live.
        WindowGroup("Chat", id: "chat-popout") {
            ChatView()
                .environment(appModel)
                .environment(menuController)
                .frame(minWidth: 560, minHeight: 480)
                .background(CodexTheme.mainBackground)
                .codexMenuHost()
        }
        #if os(macOS)
        .defaultSize(width: 820, height: 720)
        #endif
    }
}