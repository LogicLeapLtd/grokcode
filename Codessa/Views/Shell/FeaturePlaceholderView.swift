import SwiftUI

/// A generic "coming soon" / empty-feature placeholder (icon + title + subtitle).
///
/// - Note: Currently **unused** — no call sites reference it as of the #40 hygiene
///   audit. Intentionally retained (not deleted) because another lane may wire it
///   into a not-yet-built page. If it's still orphaned after integration, it's a
///   safe candidate for removal.
/// - Accessibility: the `symbol` here is decorative; callers should ensure the
///   surrounding `title`/`subtitle` text carries the meaning for VoiceOver.
struct FeaturePlaceholderView: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(CodexTheme.textSecondary)
                .codexStaggeredAppear(index: 0)

            Text(title)
                .font(CodexTheme.headlineFont)
                .foregroundStyle(CodexTheme.textPrimary)
                .codexStaggeredAppear(index: 1)

            Text(subtitle)
                .font(CodexTheme.bodyFont)
                .foregroundStyle(CodexTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .codexStaggeredAppear(index: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}