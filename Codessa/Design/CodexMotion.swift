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

/// The app-wide tactile press style. Wired into nearly every button, so its
/// feel *is* the app's feel. A press now dips scale + opacity with a springy
/// settle instead of a flat opacity fade — the control reacts to the finger.
/// The scale is applied ONLY while pressed (rest stays at 1.0), so text is
/// never permanently rasterized/softened. Honours Reduce Motion.
struct CodexPressableStyle: ButtonStyle {
    /// How far the control shrinks at the bottom of a press.
    var scale: CGFloat = 0.955

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, pressedScale: scale)
    }

    private struct PressableLabel: View {
        let configuration: Configuration
        let pressedScale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .scaleEffect(pressed && !reduceMotion ? pressedScale : 1)
                .opacity(pressed ? 0.72 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.1)
                                        : .spring(response: 0.3, dampingFraction: 0.62),
                           value: pressed)
        }
    }
}

/// A prominent accent CTA — filled violet, spring press, a soft accent glow, and
/// a subtle top highlight so it reads as raised. Use for the primary action on a
/// surface (`Button("Save") {}.buttonStyle(CodexProminentButtonStyle())`).
struct CodexProminentButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(CodexTheme.sans(13.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CodexTheme.accent, CodexTheme.accentDeep],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(pressed ? 0.10 : 0))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .shadow(color: CodexTheme.accent.opacity(pressed ? 0.20 : 0.42),
                    radius: pressed ? 5 : 12, y: pressed ? 2 : 5)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.1)
                                    : .spring(response: 0.3, dampingFraction: 0.6),
                       value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A quieter companion to the prominent style — a tinted, bordered surface for
/// secondary actions. Neutral at rest, accent-tinted border on hover-less press.
struct CodexSecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(CodexTheme.sans(13, weight: .medium))
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(CodexTheme.composerBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(pressed ? CodexTheme.accent.opacity(0.7) : CodexTheme.composerBorder,
                                  lineWidth: 1)
            )
            .scaleEffect(pressed && !reduceMotion ? 0.965 : 1)
            .opacity(pressed ? 0.9 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.1)
                                    : .spring(response: 0.3, dampingFraction: 0.62),
                       value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// A focus/emphasis ring in the brand accent — a crisp inner stroke plus a
    /// soft outer halo. Use for keyboard focus or to mark the active control.
    func codexFocusRing(_ visible: Bool, cornerRadius: CGFloat = 10) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(CodexTheme.accent.opacity(visible ? 0.9 : 0), lineWidth: 2)
                .shadow(color: CodexTheme.accent.opacity(visible ? 0.5 : 0), radius: 6)
                .allowsHitTesting(false)
        )
        .animation(CodexMotion.quickSpring, value: visible)
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