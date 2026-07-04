import SwiftUI
import AppKit

/// Translucent vibrancy backing (NSVisualEffectView). On macOS Tahoe the
/// `.sidebar` material renders as Liquid Glass, sampling the desktop/content
/// behind the window — used for the semi-transparent sidebar.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Makes the host window non-opaque (so behind-window vibrancy shows through)
/// AND extends the content under the title bar so there's no transparent/dead
/// strip at the top.
/// A transparent backing whose NSView reports `mouseDownCanMoveWindow = false`,
/// so controls placed in the macOS title-bar drag region (e.g. the sidebar
/// collapse toggle sitting up by the traffic lights) receive clicks instead of
/// the window starting a drag on mouse-down. Apply via `.background(...)`.
struct NonDraggableRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { _NonDraggableNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class _NonDraggableNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            Self.applyChrome(to: window)

            // Entering native fullscreen resets isOpaque/backgroundColor/
            // titlebarAppearsTransparent on the window, which is what leaves
            // an opaque system bar across the top. Reapply once the
            // transition completes.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                guard let window else { return }
                Self.applyChrome(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func applyChrome(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0.035, green: 0.035, blue: 0.040, alpha: 1)
                : NSColor(srgbRed: 0.985, green: 0.985, blue: 0.982, alpha: 1)
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Draw content under the title bar so the sidebar glass / main pane
        // fill the whole window — no invisible top strip.
        window.styleMask.insert(.fullSizeContentView)
    }
}
