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
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Draw content under the title bar so the sidebar glass / main pane
            // fill the whole window — no invisible top strip.
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
