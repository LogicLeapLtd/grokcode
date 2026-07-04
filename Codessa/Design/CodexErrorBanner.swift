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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodexTheme.errorForeground)
                    // Keep the icon pinned to the first line as the text wraps.
                    .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(CodexTheme.errorForeground)
                    .textSelection(.enabled)
                    // Always grow vertically rather than truncate on narrow windows.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if onRetry != nil || onDismiss != nil {
                // A wrapping layout so the actions never get clipped on a
                // narrow viewport — they drop to the next line instead.
                FlowLayout(spacing: 8) {
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

/// Minimal line-wrapping layout: places subviews left-to-right and wraps to a
/// new row when the next one would overflow the proposed width. Used so the
/// banner's action buttons reflow instead of clipping on a narrow viewport.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
