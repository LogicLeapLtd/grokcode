import SwiftUI

// MARK: - Controller

/// Drives a single app-wide custom dropdown overlay so we never fall back to
/// native NSMenu chrome. A trigger registers its global frame and a content
/// builder; the host (installed once at the app root) renders the floating card.
@MainActor
@Observable
final class CodexMenuController {
    struct Active: Identifiable {
        let id: UUID
        var anchor: CGRect            // trigger frame in global coordinates
        var content: AnyView
        var minWidth: CGFloat
        var edge: VerticalEdge        // .bottom = open downward, .top = upward
    }

    var active: Active?

    func toggle(id: UUID, anchor: CGRect, minWidth: CGFloat, edge: VerticalEdge,
                @ViewBuilder content: () -> some View) {
        if active?.id == id {
            active = nil
        } else {
            active = Active(id: id, anchor: anchor, content: AnyView(content()),
                            minWidth: minWidth, edge: edge)
        }
    }

    func close() { active = nil }
}

// MARK: - Host

private struct MenuSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct CodexMenuHost: ViewModifier {
    @Environment(CodexMenuController.self) private var controller
    @State private var cardSize: CGSize = .zero

    func body(content: Content) -> some View {
        content.overlay {
            if let active = controller.active {
                GeometryReader { geo in
                    let host = geo.frame(in: .global)
                    let gap: CGFloat = 6
                    let x = min(max(8, active.anchor.minX - host.minX),
                                geo.size.width - cardSize.width - 8)
                    let y: CGFloat = {
                        if active.edge == .bottom {
                            return active.anchor.maxY - host.minY + gap
                        } else {
                            return active.anchor.minY - host.minY - cardSize.height - gap
                        }
                    }()

                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.0001)
                            .contentShape(Rectangle())
                            .onTapGesture { controller.close() }

                        active.content
                            .frame(minWidth: active.minWidth, alignment: .leading)
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(key: MenuSizeKey.self, value: g.size)
                                }
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(CodexTheme.menuBackground)
                                    .shadow(color: CodexTheme.menuShadow, radius: 16, y: 6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(CodexTheme.menuBorder, lineWidth: 1)
                            )
                            .fixedSize()
                            .opacity(cardSize == .zero ? 0 : 1)
                            .offset(x: x, y: max(8, y))
                            .onPreferenceChange(MenuSizeKey.self) { cardSize = $0 }
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: controller.active?.id) { _, _ in cardSize = .zero }
    }
}

extension View {
    func codexMenuHost() -> some View { modifier(CodexMenuHost()) }
}

// MARK: - Trigger

struct CodexMenuTrigger<Label: View, Menu: View>: View {
    @Environment(CodexMenuController.self) private var controller
    @State private var id = UUID()
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    var minWidth: CGFloat = 220
    var edge: VerticalEdge = .bottom
    var highlightOnHover: Bool = true
    @ViewBuilder var label: (_ isOpen: Bool) -> Label
    @ViewBuilder var menu: (_ close: @escaping () -> Void) -> Menu

    private var isOpen: Bool { controller.active?.id == id }

    var body: some View {
        Button {
            controller.toggle(id: id, anchor: frame, minWidth: minWidth, edge: edge) {
                menu({ controller.close() })
            }
        } label: {
            label(isOpen)
                .padding(.horizontal, highlightOnHover ? 8 : 0)
                .padding(.vertical, highlightOnHover ? 5 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(highlightOnHover && (isOpen || hovering) ? CodexTheme.hoverBackground : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, f in frame = f }
            }
        )
    }
}

// MARK: - Menu content building blocks

struct CodexMenuContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 1) { content }
            .padding(5)
    }
}

struct CodexMenuSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(CodexTheme.textTertiary)
            .padding(.horizontal, 9)
            .padding(.top, 7)
            .padding(.bottom, 3)
    }
}

struct CodexMenuItem: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var isSelected: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(isDestructive ? CodexTheme.errorForeground : CodexTheme.textSecondary)
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(isDestructive ? CodexTheme.errorForeground : CodexTheme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(CodexTheme.textTertiary)
                    }
                }
                Spacer(minLength: 16)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? CodexTheme.hoverBackground : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CodexMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(CodexTheme.divider)
            .frame(height: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }
}

// MARK: - Generic hover highlight for list rows / buttons

struct CodexHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 8
    var color: Color = CodexTheme.hoverBackground
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? color : .clear)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Adds a Codex-style hover background. Place on the padded row content.
    func codexHover(cornerRadius: CGFloat = 8, color: Color = CodexTheme.hoverBackground) -> some View {
        modifier(CodexHoverHighlight(cornerRadius: cornerRadius, color: color))
    }
}
