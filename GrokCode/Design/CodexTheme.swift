import SwiftUI

// Sourced from /Applications/Codex.app (app.asar CSS tokens + live screenshot)
enum CodexTheme {
    static let sidebarBackground = Color(red: 0.992, green: 0.992, blue: 0.991)       // ~white, matches Codex
    static let mainBackground = Color.white
    static let composerShellBackground = Color(red: 0.941, green: 0.941, blue: 0.941)
    static let composerBackground = Color.white
    static let composerBorder = Color(red: 0.82, green: 0.82, blue: 0.82)
    static let composerShellBorder = Color(red: 0.84, green: 0.84, blue: 0.84)
    static let composerShellHighlight = Color(red: 1.0, green: 1.0, blue: 1.0)
    static let divider = Color(red: 0.90, green: 0.90, blue: 0.90)
    static let textPrimary = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let textSecondary = Color(red: 0.42, green: 0.42, blue: 0.42)
    static let textTertiary = Color(red: 0.58, green: 0.58, blue: 0.58)
    static let pillBackground = Color(red: 0.92, green: 0.92, blue: 0.92)
    static let pillBackgroundPressed = Color(red: 0.86, green: 0.86, blue: 0.86)
    static let modalBackdrop = Color(red: 0.94, green: 0.94, blue: 0.94)
    static let navHighlight = Color(red: 0.90, green: 0.90, blue: 0.90)
    static let shadowColor = Color(red: 0.75, green: 0.75, blue: 0.75)
    static let accentOrange = Color(red: 0.92, green: 0.45, blue: 0.18)                // Full access
    static let sendButtonBackground = Color(red: 0.90, green: 0.90, blue: 0.90)
    static let sendButtonForeground = Color(red: 0.55, green: 0.55, blue: 0.55)
    static let sendButtonActiveBackground = Color(red: 0.15, green: 0.15, blue: 0.15)
    static let sendButtonActiveForeground = Color.white

    static let hoverBackground = Color(red: 0.93, green: 0.93, blue: 0.93)
    static let menuBackground = Color(red: 0.99, green: 0.99, blue: 0.99)
    static let menuBorder = Color(red: 0.86, green: 0.86, blue: 0.86)
    static let menuShadow = Color.black.opacity(0.16)

    static let userBubbleBackground = Color(red: 0.945, green: 0.945, blue: 0.945)   // #F1F1F1
    static let errorForeground = Color(red: 0.70, green: 0.18, blue: 0.13)
    static let errorBackground = Color(red: 0.99, green: 0.94, blue: 0.93)
    static let errorBorder = Color(red: 0.92, green: 0.80, blue: 0.78)

    static let sidebarWidth: CGFloat = 240
    static let composerMaxWidth: CGFloat = 640
    static let composerRadius: CGFloat = 24
    static let composerInnerRadius: CGFloat = 12

    static let headlineFont = Font.system(size: 28, weight: .semibold, design: .default)
    static let bodyFont = Font.system(size: 15, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular)
    static let smallFont = Font.system(size: 11, weight: .regular)
}