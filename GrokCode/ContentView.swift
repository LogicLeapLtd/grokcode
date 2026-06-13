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
            .task { await model.bootstrap() }

            AnimatedModal(isPresented: model.showSettings, onDismiss: { model.closeSettings() }) {
                SettingsView()
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
        .codexMenuHost()
        .focusEffectDisabled()
        .background(WindowConfigurator())
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}