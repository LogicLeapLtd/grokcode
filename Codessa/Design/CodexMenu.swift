import SwiftUI
import AppKit

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
        var content: () -> AnyView    // rebuilt every host render so it stays live
        var minWidth: CGFloat
        var edge: VerticalEdge        // .bottom = open downward, .top = upward
    }

    var active: Active?

    /// Single-key shortcuts (e.g. "1"…"4") for the menu that's currently open,
    /// mapped to that row's action. `CodexMenuItem` registers/unregisters these
    /// while it's on screen so pressing the key activates the row instead of
    /// leaking the keystroke into a focused text field behind the menu.
    private var shortcuts: [String: () -> Void] = [:]
    private var keyMonitor: Any?

    /// `installsKeyboardMonitor` is false for short-lived controllers hosted
    /// inside a sheet (which only need menu rendering, not global key capture).
    init(installsKeyboardMonitor: Bool = true) {
        guard installsKeyboardMonitor else { return }
        let handler: @Sendable (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleKeyDown(event) }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func toggle<V: View>(id: UUID, anchor: CGRect, minWidth: CGFloat, edge: VerticalEdge,
                         @ViewBuilder content: @escaping () -> V) {
        if active?.id == id {
            active = nil
        } else {
            active = Active(id: id, anchor: anchor, content: { AnyView(content()) },
                            minWidth: minWidth, edge: edge)
        }
    }

    func close() { active = nil }

    func registerShortcut(_ key: String, _ action: @escaping () -> Void) {
        shortcuts[key] = action
    }

    func unregisterShortcut(_ key: String) {
        shortcuts.removeValue(forKey: key)
    }

    /// Returns `nil` to swallow the keystroke (handled), or the event to let it
    /// continue to the responder chain. Only acts while a menu is open.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard active != nil else { return event }
        if event.keyCode == 53 {                 // Escape closes the open menu
            close()
            return nil
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty,
              let key = event.charactersIgnoringModifiers, !key.isEmpty,
              let action = shortcuts[key]
        else { return event }
        action()
        return nil
    }
}

// MARK: - Host

private struct CodexMenuHost: ViewModifier {
    @Environment(CodexMenuController.self) private var controller
    /// Last-measured height of the open card, used to decide which way the menu
    /// should open and how tall it may be before it has to scroll.
    @State private var cardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay {
            if let active = controller.active {
                GeometryReader { geo in
                    let host = geo.frame(in: .global)
                    let gap: CGFloat = 6
                    // Clamp left edge so the card stays on-screen (estimate width via minWidth).
                    let x = min(max(8, active.anchor.minX - host.minX),
                                max(8, geo.size.width - active.minWidth - 8))
                    let topSpace = max(0, active.anchor.minY - host.minY - gap)     // room above anchor
                    let bottomSpace = max(0, host.maxY - active.anchor.maxY - gap)  // room below anchor
                    let belowY = active.anchor.maxY - host.minY + gap              // just below anchor
                    // Honour the requested edge while it fits; otherwise flip to
                    // whichever side has more room so the card never runs
                    // off-screen (the bug on the new-chat page).
                    let needed = cardHeight + gap
                    let openUp: Bool = {
                        switch active.edge {
                        case .top:    return topSpace >= needed || topSpace >= bottomSpace
                        case .bottom: return !(bottomSpace >= needed || bottomSpace >= topSpace)
                        }
                    }()

                    ZStack(alignment: .topLeading) {
                        // Dismiss layer — taps outside the card close the menu.
                        Color.black.opacity(0.0001)
                            .contentShape(Rectangle())
                            .onTapGesture { controller.close() }

                        // Card positioned with only the card itself hittable, so
                        // outside taps fall through to the dismiss layer above.
                        if openUp {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                clampedCard(active, maxHeight: topSpace)
                            }
                            .frame(height: topSpace, alignment: .bottomLeading)
                            .offset(x: x)
                        } else {
                            clampedCard(active, maxHeight: bottomSpace)
                                .offset(x: x, y: belowY)
                        }
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: controller.active?.id)
    }

    /// The menu card, measured (to drive edge selection) and — only when it
    /// genuinely overflows the room on its side — wrapped in a ScrollView and
    /// height-capped so it can't run off-screen. When it fits it renders plainly
    /// so its drop shadow isn't clipped by the scroll container.
    @ViewBuilder
    private func clampedCard(_ active: CodexMenuController.Active, maxHeight: CGFloat) -> some View {
        let measured = card(active)
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { cardHeight = g.size.height }
                        .onChange(of: g.size.height) { _, h in cardHeight = h }
                }
            )
        if maxHeight > 0, cardHeight > maxHeight {
            ScrollView(.vertical, showsIndicators: false) { measured }
                .frame(height: maxHeight)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            measured
        }
    }

    private func card(_ active: CodexMenuController.Active) -> some View {
        active.content()
            .frame(minWidth: active.minWidth, alignment: .leading)
            .fixedSize()
            .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                         fallback: CodexTheme.menuBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CodexTheme.menuBorder, lineWidth: 1)
            )
            .shadow(color: CodexTheme.menuShadow, radius: 16, y: 6)
            .animation(CodexMotion.panelSpring, value: cardHeight)
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
    /// Dev/QA only: open this menu automatically shortly after appearing.
    var autoOpen: Bool = false
    @ViewBuilder var label: (_ isOpen: Bool) -> Label
    @ViewBuilder var menu: (_ close: @escaping () -> Void) -> Menu

    private var isOpen: Bool { controller.active?.id == id }

    private func open() {
        controller.toggle(id: id, anchor: frame, minWidth: minWidth, edge: edge) {
            menu({ controller.close() })
        }
    }

    var body: some View {
        Button { open() } label: {
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
                    .onAppear {
                        frame = geo.frame(in: .global)
                        if autoOpen {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if controller.active == nil { open() }
                            }
                        }
                    }
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
    /// Optional keyboard-shortcut chips shown on the right (e.g. ["⇧","⌘","M"]).
    var keys: [String]? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
            if let keys {
                Spacer(minLength: 12)
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(RoundedRectangle(cornerRadius: 4).fill(CodexTheme.pillBackground))
                }
            }
        }
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
    /// Optional keyboard-shortcut hint shown on the right (e.g. "1"). When set,
    /// the key activates this row while the menu is open.
    var shortcut: String? = nil
    let action: () -> Void

    @State private var hovering = false
    @Environment(CodexMenuController.self) private var menuController

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
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(minWidth: 12)
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
        .onAppear { if let shortcut { menuController.registerShortcut(shortcut, action) } }
        .onDisappear { if let shortcut { menuController.unregisterShortcut(shortcut) } }
    }
}

/// A menu row that reveals a flyout submenu to its right on hover (Codex-style
/// "Organize sidebar ›" / "Sort by ›").
struct CodexFlyoutItem<Sub: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var submenu: () -> Sub

    @State private var rowHover = false
    @State private var subHover = false
    @State private var open = false
    @State private var rowWidth: CGFloat = 220
    @State private var closeWork: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 16)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textPrimary)
            Spacer(minLength: 16)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(open ? CodexTheme.hoverBackground : .clear)
        )
        .contentShape(Rectangle())
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { rowWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in rowWidth = w }
            }
        )
        .onHover { h in rowHover = h; recompute() }
        .overlay(alignment: .topLeading) {
            if open {
                // A transparent leading bridge overlaps the parent row so the
                // hover never drops into a dead gap on the way to the submenu.
                HStack(spacing: 0) {
                    Color.clear.frame(width: 12)
                    CodexMenuContainer { submenu() }
                        .frame(minWidth: 190, alignment: .leading)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                     fallback: CodexTheme.menuBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(CodexTheme.menuBorder, lineWidth: 1)
                        )
                        .shadow(color: CodexTheme.menuShadow, radius: 16, y: 6)
                }
                .fixedSize()
                .contentShape(Rectangle())
                .onHover { h in subHover = h; recompute() }
                .offset(x: rowWidth - 10, y: -6)
                .transition(.opacity)
            }
        }
    }

    private func recompute() {
        closeWork?.cancel()
        if rowHover || subHover {
            open = true
        } else {
            let work = DispatchWorkItem {
                if !rowHover && !subHover { open = false }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
        }
    }
}

/// A menu row with a trailing switch (Codex "Plan mode" / "Pursue goal").
struct CodexMenuToggle: View {
    let title: String
    var systemImage: String? = nil
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 16)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer(minLength: 16)
                MiniSwitch(isOn: isOn)
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

struct MiniSwitch: View {
    let isOn: Bool
    var body: some View {
        Capsule()
            // On → accent green; off → a neutral track that reads in both
            // appearances (the old hard-coded light grey + white knob rendered as
            // an invisible "white oval" in dark mode).
            .fill(isOn ? CodexTheme.switchOnTrack : CodexTheme.switchOffTrack)
            .frame(width: 32, height: 19)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(CodexTheme.switchKnob)
                    .frame(width: 15, height: 15)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            }
            .overlay(
                Capsule().strokeBorder(CodexTheme.switchBorder, lineWidth: 1)
            )
            .animation(CodexMotion.quickSpring, value: isOn)
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
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? color : .clear)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    /// Adds a Codex-style hover background. Place on the padded row content.
    func codexHover(cornerRadius: CGFloat = 8, color: Color = CodexTheme.hoverBackground) -> some View {
        modifier(CodexHoverHighlight(cornerRadius: cornerRadius, color: color))
    }

    /// Draws a placeholder string over an empty input. Native `.plain`
    /// TextField prompts don't render reliably on this macOS build, so every
    /// search / text input uses this explicit overlay instead. Apply it to the
    /// bare `TextField` (before any outer padding) so the placeholder lines up
    /// with where the text cursor sits.
    func placeholderOverlay(
        _ text: String,
        visible: Bool,
        alignment: Alignment = .leading,
        font: Font = .system(size: 13)
    ) -> some View {
        overlay(alignment: alignment) {
            if visible {
                Text(text)
                    .font(font)
                    .foregroundStyle(CodexTheme.textTertiary)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
    }

    /// Hover darkening drawn ON TOP (clipped to the shape) — for buttons that
    /// already have an opaque fill, where a behind-background wouldn't show.
    /// Apply to the Button itself (after .buttonStyle) so onHover fires reliably.
    func codexHoverOverlay(cornerRadius: CGFloat = 8) -> some View {
        modifier(CodexHoverOverlay(cornerRadius: cornerRadius))
    }
}

struct CodexHoverOverlay: ViewModifier {
    var cornerRadius: CGFloat = 8
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    // Adaptive tint (darkens in light mode, lightens in dark) so
                    // hover feedback is visible on dark secondary pills too.
                    .fill(hovering ? CodexTheme.hoverBackground : Color.clear)
                    .allowsHitTesting(false)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Same idea as `CodexHoverOverlay`, but for controls whose own shape isn't a
/// rounded rectangle (capsule pills, circular buttons). The Liquid Glass
/// fallback fill (pre-macOS 26) is a static color with no built-in hover
/// feedback, so controls using it need this applied explicitly.
struct CodexHoverOverlayShape<S: Shape>: ViewModifier {
    var shape: S
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                shape
                    .fill(hovering ? CodexTheme.hoverBackground : Color.clear)
                    .allowsHitTesting(false)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    /// Hover darkening clipped to an arbitrary `Shape` (e.g. `Capsule()`,
    /// `Circle()`) — for controls whose own background is already opaque and
    /// isn't a rounded rectangle.
    func codexHoverOverlay<S: Shape>(_ shape: S) -> some View {
        modifier(CodexHoverOverlayShape(shape: shape))
    }
}
