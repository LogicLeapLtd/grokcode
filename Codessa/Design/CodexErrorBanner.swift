import SwiftUI

/// The single, consistent way an error is shown to the user — a rounded card with
/// a warning icon, selectable message, and optional Retry / Dismiss actions.
///
/// Used both inline in the chat transcript (`ChatView`) and on the home screen
/// (`HomeView`) so errors never appear as bare red text again.
struct CodexErrorBanner: View {
    let text: String
    /// When non-nil, shows a "Retry" button.
    var onRetry: (() -> Void)?
    /// When non-nil, shows a "Dismiss" button.
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.errorForeground)
                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(CodexTheme.errorForeground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if onRetry != nil || onDismiss != nil {
                HStack(spacing: 8) {
                    if let onRetry {
                        actionButton(title: "Retry", systemImage: "arrow.clockwise", action: onRetry)
                    }
                    if let onDismiss {
                        actionButton(title: "Dismiss", systemImage: "xmark", action: onDismiss)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTheme.errorBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.errorBorder, lineWidth: 1)
        )
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(CodexTheme.errorForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(CodexTheme.errorBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
