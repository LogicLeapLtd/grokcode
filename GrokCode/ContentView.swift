import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        ZStack {
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
            .ignoresSafeArea(.container, edges: .top)   // fill under the title bar
            .task { await model.bootstrap() }

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