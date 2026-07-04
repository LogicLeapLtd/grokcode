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
        dark:  rgb(0.035, 0.035, 0.040)                  // dark black canvas (header/page/modals)
    )
    static let composerShellBackground = dynamic(
        light: rgb(0.941, 0.941, 0.941),
        dark:  rgb(0.145, 0.145, 0.153)
    )
    static let composerBackground = dynamic(
        light: rgb(1.0, 1.0, 1.0),
        dark:  rgb(0.169, 0.169, 0.180)
    )
    // Border palette: cool, translucent edge colours tuned for the ambient
    // canvas. These replace flat grey hairlines so cards, menus, and the
    // composer feel intentionally lit without becoming neon.
    static let composerBorder = dynamic(
        light: rgb(0.73, 0.78, 0.84),
        dark:  rgb(0.48, 0.56, 0.64, 0.48)
    )
    static let composerShellBorder = dynamic(
        light: rgb(0.76, 0.82, 0.88),
        dark:  rgb(0.40, 0.54, 0.64, 0.58)
    )
    static let composerShellHighlight = dynamic(
        light: rgb(1.0, 1.0, 1.0, 0.78),
        dark:  rgb(0.70, 0.80, 0.88, 0.22)
    )
    static let divider = dynamic(
        light: rgb(0.84, 0.87, 0.91),
        dark:  rgb(0.46, 0.52, 0.60, 0.25)
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

    // MARK: - Toggle switch (MiniSwitch)

    /// "On" track — a clear accent green so an enabled toggle reads instantly in
    /// both appearances (replaces the old near-white capsule that vanished in
    /// dark mode).
    static let switchOnTrack = dynamic(
        light: rgb(0.20, 0.72, 0.36),
        dark:  rgb(0.26, 0.78, 0.42)
    )
    static let switchOffTrack = dynamic(
        light: rgb(0.80, 0.80, 0.82),
        dark:  rgb(0.32, 0.32, 0.35)
    )
    static let switchKnob = dynamic(
        light: rgb(1.0, 1.0, 1.0),
        dark:  rgb(0.97, 0.97, 0.98)
    )
    static let switchBorder = dynamic(
        light: rgb(0.48, 0.58, 0.68, 0.18),
        dark:  rgb(0.62, 0.74, 0.84, 0.20)
    )

    static let shadowColor = dynamic(
        light: rgb(0.75, 0.75, 0.75),
        dark:  rgb(0.0, 0.0, 0.0, 0.55)
    )
    /// Brand accent. Historically an orange ("Full access") — now a midnight
    /// violet so the whole app reads cool/purple. The token name is kept for
    /// source compatibility with its ~30 call sites; prefer `accent` in new code.
    static let accentOrange = dynamic(
        light: rgb(0.42, 0.33, 0.86),                     // #6B54DB — deeper for white bg
        dark:  rgb(0.61, 0.51, 0.95)                      // #9B83F2 — the artifact violet
    )
    /// Preferred alias for the brand accent (points at the same dynamic colour).
    static var accent: Color { accentOrange }
    /// A softer, deeper companion violet for gradients / ambient glows.
    static let accentDeep = dynamic(
        light: rgb(0.30, 0.20, 0.66),
        dark:  rgb(0.36, 0.26, 0.72)                      // #5C42B8-ish
    )
    static let focusAccent = dynamic(
        light: rgb(0.22, 0.47, 0.70),
        dark:  rgb(0.48, 0.68, 0.82)
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
    /// Used for full-width menu/list rows, which sit on a solid card surface
    /// where even a subtle tint reads clearly.
    static let hoverBackground = dynamic(
        light: rgb(0.0, 0.0, 0.0, 0.07),
        dark:  rgb(1.0, 1.0, 1.0, 0.10)
    )
    /// Stronger hover tint for standalone chrome controls (pills, capsules,
    /// icon buttons, circular buttons) whose own fill is already tinted or
    /// opaque — `hoverBackground` alone barely reads on top of those.
    static let controlHoverBackground = dynamic(
        light: rgb(0.0, 0.0, 0.0, 0.12),
        dark:  rgb(1.0, 1.0, 1.0, 0.18)
    )
    /// Border color standalone chrome controls brighten to on hover, paired
    /// with `controlHoverBackground` for a clearer "lit up" state.
    static let controlHoverBorder = dynamic(
        light: rgb(0.0, 0.0, 0.0, 0.30),
        dark:  rgb(1.0, 1.0, 1.0, 0.40)
    )
    static let menuBackground = dynamic(
        light: rgb(0.99, 0.99, 0.99),
        dark:  rgb(0.16, 0.16, 0.17)
    )
    static let menuBorder = dynamic(
        light: rgb(0.76, 0.81, 0.87),
        dark:  rgb(0.46, 0.55, 0.66, 0.52)
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

    // MARK: - Syntax highlighting (code blocks)

    /// Token colours for lightweight code highlighting. Tuned to read clearly
    /// against `composerBackground`/code-card surfaces in both appearances:
    /// comments muted green-grey, strings warm, keywords blue/purple, numbers
    /// teal, types a distinct hue.
    static let syntaxKeyword = dynamic(                   // keywords — blue/purple
        light: rgb(0.50, 0.16, 0.69),
        dark:  rgb(0.78, 0.58, 0.98)
    )
    static let syntaxString = dynamic(                    // string literals — warm
        light: rgb(0.77, 0.31, 0.11),
        dark:  rgb(0.95, 0.62, 0.45)
    )
    static let syntaxComment = dynamic(                   // comments — muted green-grey
        light: rgb(0.36, 0.47, 0.39),
        dark:  rgb(0.50, 0.62, 0.53)
    )
    static let syntaxNumber = dynamic(                    // numeric literals — teal
        light: rgb(0.05, 0.45, 0.50),
        dark:  rgb(0.40, 0.82, 0.84)
    )
    static let syntaxType = dynamic(                      // types — distinct hue (gold/amber)
        light: rgb(0.40, 0.36, 0.05),
        dark:  rgb(0.86, 0.78, 0.42)
    )

    // MARK: - Diff colouring (tool detail cards)

    /// Whole-line diff colours: added lines green, removed lines red. Tuned to
    /// stay legible on the monospaced detail surfaces in both appearances.
    static let syntaxDiffAdded = dynamic(                 // "+" lines — green
        light: rgb(0.13, 0.52, 0.20),
        dark:  rgb(0.46, 0.84, 0.52)
    )
    static let syntaxDiffRemoved = dynamic(              // "-" lines — red
        light: rgb(0.74, 0.20, 0.16),
        dark:  rgb(0.96, 0.52, 0.48)
    )

    // MARK: - Inline code (`code` spans in prose)

    /// Inline `code` spans: a restrained lavender ink on a soft, brand-tinted
    /// fill — replaces the flat medium-grey highlighter block that made
    /// code-dense paragraphs read like a ransom note. Kept low-contrast so a
    /// paragraph peppered with spans stays calm.
    static let inlineCodeText = dynamic(
        light: rgb(0.35, 0.31, 0.49),
        dark:  rgb(0.83, 0.81, 0.94)
    )
    static let inlineCodeBackground = dynamic(
        light: rgb(0.45, 0.42, 0.62, 0.10),
        dark:  rgb(0.70, 0.68, 0.86, 0.13)
    )

    // MARK: - Tool activity (live read / edit / run rows)

    /// Faint panel behind a turn's grouped tool-call rows, so the "work" reads
    /// as one calm block distinct from the prose rather than 20 loose items.
    static let toolPanelBackground = dynamic(
        light: rgb(0.48, 0.50, 0.60, 0.05),
        dark:  rgb(0.62, 0.66, 0.78, 0.05)
    )
    static let toolPanelBorder = dynamic(
        light: rgb(0.80, 0.83, 0.88, 0.70),
        dark:  rgb(0.52, 0.58, 0.66, 0.20)
    )
    /// Quiet success tint for a completed row's check — a soft green, no loud
    /// filled circle, so a long run of finished rows doesn't shout.
    static let toolDoneCheck = dynamic(
        light: rgb(0.30, 0.62, 0.40),
        dark:  rgb(0.50, 0.80, 0.58)
    )

    // MARK: - Glass tint (sidebar vibrancy overlay)

    /// A faint tint laid over the behind-window vibrancy so the sidebar reads as
    /// a panel in both appearances.
    static let glassTint = dynamic(
        light: rgb(1.0, 1.0, 1.0, 0.0),
        dark:  rgb(0.06, 0.06, 0.07, 0.68)
    )

    // MARK: - Metrics & fonts (appearance-independent)

    static let sidebarWidth: CGFloat = 240
    static let composerMaxWidth: CGFloat = 640
    static let composerRadius: CGFloat = 24
    static let composerInnerRadius: CGFloat = 12

    // MARK: - Brand typeface pairing
    //
    // Fraunces (a warm high-contrast serif) carries display / headline moments;
    // Manrope (a geometric-humanist sans, distinct from the ubiquitous SF/Inter
    // defaults) carries body & UI text. Both are bundled and registered at launch
    // (see `BrandFonts`). `Font.custom` falls back to the system face if a family
    // failed to register, so the app never renders blank text.

    /// PostScript family names of the registered brand faces.
    static let serifFamily = "Fraunces"
    static let sansFamily = "Manrope"

    /// Display serif (Fraunces). Maps the requested weight onto the true cut we
    /// bundle (Regular / SemiBold) by PostScript name, rather than synthetic
    /// bolding. Falls back to the system serif if registration failed.
    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black:
            name = "Fraunces-SemiBold"
        default:
            name = "Fraunces-Regular"
        }
        return Font.custom(name, size: size)
    }

    /// UI/body sans (Manrope). Maps onto the bundled Regular / Medium / Bold cuts
    /// by PostScript name. Falls back to the system sans if registration failed.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Manrope-Bold"
        case .semibold, .medium:
            name = "Manrope-Medium"
        default:
            name = "Manrope-Regular"
        }
        return Font.custom(name, size: size)
    }

    // Typography direction: Fraunces for headlines, Manrope for the shell, with
    // monospaced type reserved for genuinely technical values.
    static let headlineFont = serif(28, weight: .semibold)
    static let bodyFont = sans(16)
    static let composerInputFont = sans(18)
    static let composerLabelFont = sans(13, weight: .semibold)
    static let composerMetaFont = sans(12, weight: .medium)
    static let technicalLabelFont = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let captionFont = sans(12)
    static let smallFont = sans(11)
}
