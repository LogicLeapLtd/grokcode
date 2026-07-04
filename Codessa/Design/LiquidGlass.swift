import SwiftUI

// Liquid Glass surfaces (macOS 26 "Tahoe"+). The app is built against the
// macOS 26 SDK, so `glassEffect` is available; we still gate at runtime so the
// binary keeps launching on any earlier system by falling back to a solid
// themed fill.

extension View {
    /// Apply a Liquid Glass background clipped to `shape`, falling back to a solid
    /// `fallback` fill on systems without the Glass API. Use in place of a plain
    /// `.background(shape.fill(color))` on chrome surfaces (cards, the composer
    /// shell, banners) so they read as translucent glass rather than flat grey.
    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        interactive: Bool = false,
        tint: Color? = nil,
        fallback: Color
    ) -> some View {
        if #available(macOS 26.0, *) {
            // Build the Glass value in a closure so these imperative statements
            // aren't parsed as views by the surrounding @ViewBuilder.
            let effect: Glass = {
                var e: Glass = .regular
                if let tint { e = e.tint(tint) }
                if interactive { e = e.interactive() }
                return e
            }()
            self.glassEffect(effect, in: shape)
        } else {
            self.background(shape.fill(fallback))
        }
    }
}
