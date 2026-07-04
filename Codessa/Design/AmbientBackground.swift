import SwiftUI

/// A living, state-aware backdrop for the dark canvas pages (Home, Project
/// detail, Chat …). Soft glowing orbs drift slowly behind the content and a
/// faint starfield twinkles over the black. When the AI is responding the whole
/// field intensifies — orbs brighten, drift faster and breathe — then settles
/// back to a calm idle state when the turn finishes.
///
/// Rendered once in `MainContentView` *behind* the page content (over the
/// translucent dark base, under the Liquid Glass chrome) so every page inherits
/// it for free. Honours Reduce Motion by holding a still, dim composition.
struct AmbientBackgroundView: View {
    /// Drives the energy of the field. `true` while a run is in flight.
    var active: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Smoothly ramped 0…1 energy. Animated on `active` changes so the field
    /// eases between calm and energetic rather than snapping.
    @State private var energy: Double = 0

    /// Whether the field should be doing per-frame work at all. The animated
    /// path is mounted *only* while a run is in flight (or during the brief
    /// energy ramp back to calm afterwards). At rest we render a single static
    /// frame, so the full-window `Canvas` + heavy `.blur` are composited once and
    /// cached by Core Animation instead of being recomputed every display refresh.
    /// This is the difference between an idle GPU and a permanently pinned one —
    /// the timeline used to tick (and re-blur the whole window) forever, on every
    /// page, whether or not anything was happening.
    private var isAnimating: Bool {
        !reduceMotion && (active || energy > 0.02)
    }

    var body: some View {
        Group {
            if isAnimating {
                // Cap the field to 30fps: it drifts slowly, so the dropped frames
                // are imperceptible but halve the per-frame Canvas + blur cost —
                // and that cost is now only paid while the AI is responding.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        draw(ctx: &ctx, size: size, time: t, energy: energy)
                    }
                }
            } else {
                // Still composition — no per-frame work, no motion. The blur below
                // is applied once to static content and then cached.
                Canvas { ctx, size in
                    draw(ctx: &ctx, size: size, time: 0, energy: energy)
                }
            }
        }
        // A heavier blur keeps the colour field atmospheric instead of reading
        // as distinct, competing colour blobs behind the work surface.
        .blur(radius: 40)
        .opacity(fieldOpacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { energy = active ? 1 : 0 }
        .onChange(of: active) { _, newValue in
            withAnimation(.easeInOut(duration: 1.1)) { energy = newValue ? 1 : 0 }
        }
    }

    /// The field should support the canvas, not become the UI. Keep it subdued
    /// in dark mode and whisper-faint on light backgrounds.
    private var fieldOpacity: Double {
        colorScheme == .dark ? 0.58 + energy * 0.14 : 0.20 + energy * 0.08
    }

    // MARK: - Drawing

    private func draw(ctx: inout GraphicsContext, size: CGSize, time: Double, energy: Double) {
        drawOrbs(ctx: &ctx, size: size, time: time, energy: energy)
        drawStars(ctx: &ctx, size: size, time: time, energy: energy)
    }

    private func drawOrbs(ctx: inout GraphicsContext, size: CGSize, time: Double, energy: Double) {
        let w = size.width, h = size.height
        // Idle orbs glow softly; energy lifts brightness and drift speed without
        // turning the background into a competing colour wash.
        let speed = 0.035 + energy * 0.045
        let glow = 0.075 + energy * 0.12

        for orb in Self.orbs {
            // Lissajous drift around the orb's home position.
            let dx = sin(time * speed * orb.driftRate + orb.phase) * orb.driftRadius
            let dy = cos(time * speed * orb.driftRate * 0.8 + orb.phase * 1.3) * orb.driftRadius * 0.7
            let cx = orb.home.x * w + dx * w
            let cy = orb.home.y * h + dy * h

            // A slow breathing pulse, deeper while energetic.
            let breathe = 1 + sin(time * (0.5 + energy * 0.7) + orb.phase) * (0.06 + energy * 0.1)
            let radius = orb.radius * min(w, h) * breathe

            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            let core = orb.color.opacity(glow)
            let gradient = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [core, orb.color.opacity(0)]),
                center: CGPoint(x: cx, y: cy),
                startRadius: 0,
                endRadius: radius
            )
            ctx.fill(Path(ellipseIn: rect), with: gradient)
        }
    }

    private func drawStars(ctx: inout GraphicsContext, size: CGSize, time: Double, energy: Double) {
        let w = size.width, h = size.height
        let base = colorScheme == .dark ? 0.22 : 0.0
        guard base > 0 else { return }

        for star in Self.stars {
            // Each star twinkles on its own slow cycle; energy makes them sparkle
            // a touch livelier.
            let twinkle = 0.5 + 0.5 * sin(time * (0.6 + energy * 0.9) * star.rate + star.phase)
            let alpha = base * (0.18 + twinkle * (0.30 + energy * 0.16))
            let r = star.size * (1 + energy * 0.14)
            let rect = CGRect(x: star.pos.x * w - r, y: star.pos.y * h - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
        }
    }

    // MARK: - Field definition (deterministic, no per-frame allocation)

    private struct Orb {
        let home: CGPoint      // unit coords (0…1)
        let radius: CGFloat    // fraction of min(w,h)
        let color: Color
        let phase: Double
        let driftRate: Double
        let driftRadius: Double // fraction of view size
    }

    private struct Star {
        let pos: CGPoint
        let size: CGFloat
        let phase: Double
        let rate: Double
    }

    /// Deep violet depth, with the teal/green cast deliberately removed so the
    /// canvas reads purple-black rather than muddy.
    private static let orbs: [Orb] = [
        Orb(home: CGPoint(x: 0.22, y: 0.28), radius: 0.38,
            color: Color(red: 0.28, green: 0.16, blue: 0.58), phase: 0.0,
            driftRate: 1.0, driftRadius: 0.04),
        Orb(home: CGPoint(x: 0.78, y: 0.22), radius: 0.34,
            color: Color(red: 0.22, green: 0.13, blue: 0.50), phase: 1.7,
            driftRate: 1.3, driftRadius: 0.045),
        Orb(home: CGPoint(x: 0.70, y: 0.74), radius: 0.42,
            color: Color(red: 0.18, green: 0.08, blue: 0.38), phase: 3.1,
            driftRate: 0.85, driftRadius: 0.04),
        Orb(home: CGPoint(x: 0.30, y: 0.80), radius: 0.32,
            color: Color(red: 0.38, green: 0.18, blue: 0.62), phase: 4.4,
            driftRate: 1.15, driftRadius: 0.035),
        Orb(home: CGPoint(x: 0.50, y: 0.50), radius: 0.26,
            color: Color(red: 0.16, green: 0.10, blue: 0.28), phase: 2.2,
            driftRate: 0.7, driftRadius: 0.03),
    ]

    /// Deterministic pseudo-random starfield (hashed, so it's stable across
    /// launches without needing a stored seed).
    private static let stars: [Star] = {
        var result: [Star] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 10_000) / 10_000.0
        }
        for _ in 0..<42 {
            result.append(Star(
                pos: CGPoint(x: next(), y: next()),
                size: 0.6 + next() * 1.1,
                phase: next() * 6.28,
                rate: 0.5 + next() * 1.5
            ))
        }
        return result
    }()
}
