import SwiftUI

enum CodexMotion {
    static let pageSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let panelSpring = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let modalSpring = Animation.spring(response: 0.44, dampingFraction: 0.84)
    static let expandSpring = Animation.spring(response: 0.38, dampingFraction: 0.8)
    static let quickSpring = Animation.spring(response: 0.28, dampingFraction: 0.78)
    /// Sidebar collapse/expand. Critically-damped (no overshoot) so the rail edge
    /// never bounces against the main pane while the width animates.
    static let sidebarCollapse = Animation.spring(response: 0.34, dampingFraction: 1.0)
    static let staggerDelay: Double = 0.04

    static var pageTransition: AnyTransition {
        // Content settles in (fade + gentle scale-up + slight rise) rather than
        // sliding horizontally — feels lighter and more deliberate.
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.975, anchor: .center))
                .combined(with: .offset(y: 12)),
            removal: .opacity
                .combined(with: .scale(scale: 1.01, anchor: .center))
        )
    }

    static var modalTransition: AnyTransition {
        .scale(scale: 0.94, anchor: .center)
            .combined(with: .opacity)
            .combined(with: .offset(y: 16))
    }

    static var dropTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    static var bannerTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }
}

struct CodexPageTransition: ViewModifier {
    let identity: String

    func body(content: Content) -> some View {
        content
            .id(identity)
            .transition(CodexMotion.pageTransition)
    }
}

struct CodexAppearAnimation: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                withAnimation(CodexMotion.panelSpring.delay(Double(index) * CodexMotion.staggerDelay)) {
                    appeared = true
                }
            }
    }
}

struct CodexPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        // Press feedback via opacity rather than scaleEffect: a permanent
        // scaleEffect forces layer-backed rasterization that visibly softens
        // text. opacity(1) at rest is a no-op, keeping text crisp.
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(CodexMotion.quickSpring, value: configuration.isPressed)
    }
}

extension View {
    func codexPage(_ identity: String) -> some View {
        modifier(CodexPageTransition(identity: identity))
    }

    func codexStaggeredAppear(index: Int = 0) -> some View {
        modifier(CodexAppearAnimation(index: index))
    }
}