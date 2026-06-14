import SwiftUI
import AppKit

// Sourced from /Applications/Codex.app (app.asar CSS tokens + live screenshot).
//
// Every colour token is an *adaptive dynamic colour*: it resolves to the light
// value under the Aqua appearance and to a hand-picked dark value under
// Dark Aqua. This means switching the app (or the system) into dark mode
// retints the entire UI with zero call-site changes — views keep referencing
// `CodexTheme.textPrimary` etc. and get the right shade automatically.
enum CodexTheme {
    // MARK: - Adaptive colour factory

    /// Build a dynamic `Color` that picks `light` or `dark` based on the
    /// effective appearance at draw time. `bestMatch` resolves through the
    /// real appearance stack (including any `.preferredColorScheme` override),
    /// so this tracks the app's chosen appearance, not just the system one.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Convenience for sRGB component colours (0...1).
    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Surfaces

    static let sidebarBackground = dynamic(
        light: rgb(0.992, 0.992, 0.991),                 // ~white, matches Codex
        dark:  rgb(0.110, 0.110, 0.117)                  // #1C1C1E-ish raised panel
    )
    static let mainBackground = dynamic(
        light: rgb(1.0, 1.0, 1.0),
        dark:  rgb(0.075, 0.075, 0.082)                  // near-black canvas
    )
    static let composerShellBackground = dynamic(
        light: rgb(0.941, 0.941, 0.941),
        dark:  rgb(0.145, 0.145, 0.153)
    )
    static let composerBackground = dynamic(
        light: rgb(1.0, 1.0, 1.0),
        dark:  rgb(0.169, 0.169, 0.180)
    )
    static let composerBorder = dynamic(
        light: rgb(0.82, 0.82, 0.82),
        dark:  rgb(0.30, 0.30, 0.32)
    )
    static let composerShellBorder = dynamic(
        light: rgb(0.84, 0.84, 0.84),
        dark:  rgb(0.26, 0.26, 0.28)
    )
    static let composerShellHighlight = dynamic(
        light: rgb(1.0, 1.0, 1.0),
        dark:  rgb(0.27, 0.27, 0.29)
    )
    static let divider = dynamic(
        light: rgb(0.90, 0.90, 0.90),
        dark:  rgb(0.22, 0.22, 0.24)
    )

    // MARK: - Text

    static let textPrimary = dynamic(
        light: rgb(0.09, 0.09, 0.09),
        dark:  rgb(0.94, 0.94, 0.95)
    )
    static let textSecondary = dynamic(
        light: rgb(0.42, 0.42, 0.42),
        dark:  rgb(0.66, 0.66, 0.69)
    )
    static let textTertiary = dynamic(
        light: rgb(0.58, 0.58, 0.58),
        dark:  rgb(0.50, 0.50, 0.53)
    )

    // MARK: - Pills / chrome

    static let pillBackground = dynamic(
        light: rgb(0.92, 0.92, 0.92),
        dark:  rgb(0.20, 0.20, 0.22)
    )
    static let pillBackgroundPressed = dynamic(
        light: rgb(0.86, 0.86, 0.86),
        dark:  rgb(0.27, 0.27, 0.29)
    )
    static let modalBackdrop = dynamic(
        light: rgb(0.94, 0.94, 0.94),
        dark:  rgb(0.10, 0.10, 0.11)
    )

    /// Selection / nav highlight. Light mode *darkens* the translucent sidebar;
    /// dark mode *lightens* it so the active row reads against the dark glass.
    static let navHighlight = dynamic(
        light: rgb(0.0, 0.0, 0.0, 0.085),
        dark:  rgb(1.0, 1.0, 1.0, 0.12)
    )

    static let shadowColor = dynamic(
        light: rgb(0.75, 0.75, 0.75),
        dark:  rgb(0.0, 0.0, 0.0, 0.55)
    )
    static let accentOrange = dynamic(                    // Full access
        light: rgb(0.92, 0.45, 0.18),
        dark:  rgb(0.98, 0.55, 0.28)
    )

    // MARK: - Send button

    static let sendButtonBackground = dynamic(
        light: rgb(0.90, 0.90, 0.90),
        dark:  rgb(0.24, 0.24, 0.26)
    )
    static let sendButtonForeground = dynamic(
        light: rgb(0.55, 0.55, 0.55),
        dark:  rgb(0.60, 0.60, 0.63)
    )
    static let sendButtonActiveBackground = dynamic(
        light: rgb(0.15, 0.15, 0.15),
        dark:  rgb(0.95, 0.95, 0.96)                      // bright pill on dark
    )
    static let sendButtonActiveForeground = dynamic(
        light: rgb(1.0, 1.0, 1.0),
        dark:  rgb(0.09, 0.09, 0.10)                      // dark glyph on bright pill
    )

    // MARK: - Hover / menus

    /// Hover overlay drawn over arbitrary backgrounds. Light darkens, dark lightens.
    static let hoverBackground = dynamic(
        light: rgb(0.0, 0.0, 0.0, 0.055),
        dark:  rgb(1.0, 1.0, 1.0, 0.075)
    )
    static let menuBackground = dynamic(
        light: rgb(0.99, 0.99, 0.99),
        dark:  rgb(0.16, 0.16, 0.17)
    )
    static let menuBorder = dynamic(
        light: rgb(0.86, 0.86, 0.86),
        dark:  rgb(0.30, 0.30, 0.32)
    )
    static let menuShadow = dynamic(
        light: rgb(0.0, 0.0, 0.0, 0.16),
        dark:  rgb(0.0, 0.0, 0.0, 0.55)
    )

    // MARK: - Chat bubble / errors

    static let userBubbleBackground = dynamic(
        light: rgb(0.945, 0.945, 0.945),                 // #F1F1F1
        dark:  rgb(0.18, 0.18, 0.20)
    )
    static let errorForeground = dynamic(
        light: rgb(0.70, 0.18, 0.13),
        dark:  rgb(0.98, 0.55, 0.50)
    )
    static let errorBackground = dynamic(
        light: rgb(0.99, 0.94, 0.93),
        dark:  rgb(0.22, 0.12, 0.11)
    )
    static let errorBorder = dynamic(
        light: rgb(0.92, 0.80, 0.78),
        dark:  rgb(0.42, 0.22, 0.20)
    )

    // MARK: - Glass tint (sidebar vibrancy overlay)

    /// A faint tint laid over the behind-window vibrancy so the sidebar reads as
    /// a panel in both appearances.
    static let glassTint = dynamic(
        light: rgb(1.0, 1.0, 1.0, 0.0),
        dark:  rgb(0.10, 0.10, 0.12, 0.30)
    )

    // MARK: - Metrics & fonts (appearance-independent)

    static let sidebarWidth: CGFloat = 240
    static let composerMaxWidth: CGFloat = 640
    static let composerRadius: CGFloat = 24
    static let composerInnerRadius: CGFloat = 12

    static let headlineFont = Font.system(size: 28, weight: .semibold, design: .default)
    static let bodyFont = Font.system(size: 15, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular)
    static let smallFont = Font.system(size: 11, weight: .regular)
}
