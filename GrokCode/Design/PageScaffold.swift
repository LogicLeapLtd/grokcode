import SwiftUI

/// Shared centered page container for every detail surface (Settings, Plugins,
/// Automations, …). Guarantees one max content width + horizontal centering +
/// consistent gutters across the app, so no page sets its own random width.
///
/// The content you pass is laid out in a single leading-aligned column capped at
/// `maxWidth`, and that column is then centered horizontally in the window. The
/// whole thing scrolls vertically and fills the available area against
/// `CodexTheme.mainBackground`.
///
/// Usage:
/// ```swift
/// PageScaffold {
///     SomeHeader()
///     SomeSection()
/// }
/// ```
/// Override metrics only when a surface genuinely needs to (rare):
/// ```swift
/// PageScaffold(maxWidth: 720) { … }
/// ```
struct PageScaffold<Content: View>: View {
    /// Maximum width of the inner content column.
    var maxWidth: CGFloat = 820
    /// Horizontal gutter on each side (also the minimum margin when the window
    /// is narrower than `maxWidth`).
    var horizontalPadding: CGFloat = 40
    /// Padding above the first piece of content.
    var topPadding: CGFloat = 36
    /// Padding below the last piece of content.
    var bottomPadding: CGFloat = 40
    /// Vertical spacing between the items in the content column.
    var spacing: CGFloat = 24
    /// Whether the page scrolls vertically. Pages that manage their own scroll
    /// (or must not scroll) can pass `false`.
    var scrolls: Bool = true

    @ViewBuilder var content: Content

    init(
        maxWidth: CGFloat = 820,
        horizontalPadding: CGFloat = 40,
        topPadding: CGFloat = 36,
        bottomPadding: CGFloat = 40,
        spacing: CGFloat = 24,
        scrolls: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.spacing = spacing
        self.scrolls = scrolls
        self.content = content()
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        // Cap the column, keep it leading-aligned internally …
        .frame(maxWidth: maxWidth, alignment: .leading)
        // … then center that capped column in the available width.
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }

    var body: some View {
        Group {
            if scrolls {
                ScrollView(.vertical, showsIndicators: true) {
                    column
                }
            } else {
                column
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodexTheme.mainBackground)
    }
}

/// Centered empty-state helper for pages with no content yet ("No automations
/// yet", "No plugins", …). Sits centered in the available area rather than
/// pinned to a corner. Drop it inside a `PageScaffold` (or use on its own).
///
/// Usage:
/// ```swift
/// PageEmptyState(
///     systemImage: "bolt.badge.clock",
///     title: "No automations yet",
///     message: "Saved prompts you schedule will appear here."
/// ) {
///     Button("New automation") { … }
/// }
/// ```
struct PageEmptyState<Actions: View>: View {
    var systemImage: String?
    var title: String
    var message: String?
    /// Minimum height so the state reads as centered in a tall page.
    var minHeight: CGFloat = 360
    @ViewBuilder var actions: Actions

    init(
        systemImage: String? = nil,
        title: String,
        message: String? = nil,
        minHeight: CGFloat = 360,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.minHeight = minHeight
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.bottom, 2)
            }

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CodexTheme.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(CodexTheme.bodyFont)
                    .foregroundStyle(CodexTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            let hasActions = Actions.self != EmptyView.self
            if hasActions {
                VStack(spacing: 8) { actions }
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    }
}

extension PageEmptyState where Actions == EmptyView {
    /// Convenience for an empty state with no action buttons.
    init(
        systemImage: String? = nil,
        title: String,
        message: String? = nil,
        minHeight: CGFloat = 360
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            message: message,
            minHeight: minHeight,
            actions: { EmptyView() }
        )
    }
}
