import SwiftUI

/// Opaque modal presentation — no semi-transparent scrim.
struct AnimatedModal<Content: View>: View {
    let isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            if isPresented {
                CodexTheme.modalBackdrop
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)

                content()
                    .transition(.asymmetric(
                        insertion: CodexMotion.modalTransition,
                        removal: .scale(scale: 0.96).combined(with: .opacity).combined(with: .offset(y: -8))
                    ))
            }
        }
        .animation(CodexMotion.modalSpring, value: isPresented)
    }

    private func dismiss() {
        onDismiss()
    }
}