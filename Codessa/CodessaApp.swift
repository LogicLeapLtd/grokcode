import SwiftUI

@main
struct CodessaApp: App {
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
                Button("Command Palette") { appModel.toggleCommandPalette() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Cycle Permission Mode") { appModel.cyclePermissionMode() }
                    .keyboardShortcut("m", modifiers: [.shift, .command])
            }

            // ⌘, — Settings (conventional Preferences slot).
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appModel.navigateTo(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
            }

            // Navigation shortcuts: ⌘F search, ⌘1..4 for the primary pages.
            CommandGroup(after: .sidebar) {
                Button("Search") { appModel.navigateTo(.search) }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("Home") { appModel.navigateTo(.home) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Search Page") { appModel.navigateTo(.search) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Plugins") { appModel.navigateTo(.plugins) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Automations") { appModel.navigateTo(.automations) }
                    .keyboardShortcut("4", modifiers: .command)
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
                .preferredColorScheme(appModel.appearance.colorScheme)
        }
        #if os(macOS)
        .defaultSize(width: 820, height: 720)
        #endif
    }
}