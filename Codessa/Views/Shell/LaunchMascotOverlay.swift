import SwiftUI

struct LaunchMascotOverlay: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entered = false
    @State private var exiting = false
    @State private var finished = false
    @State private var bootProgress: CGFloat = 0

    var body: some View {
        ZStack {
            launchBackdrop

            VStack(spacing: 12) {
                SpriteSheetMascotView(isAnimating: entered && !reduceMotion)
                    .frame(width: 238, height: 188)

                VStack(spacing: 5) {
                    Text("Codessa")
                        .font(CodexTheme.serif(31, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)

                    LaunchProgressIndicator(progress: bootProgress, isActive: entered && !exiting)
                        .frame(width: 118, height: 13)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered && !reduceMotion ? 0 : 6)
                        .animation(.easeOut(duration: 0.32).delay(0.12), value: entered)
                }
            }
            .opacity(exiting ? 0 : (entered ? 1 : 0))
            .scaleEffect(reduceMotion ? 1 : (exiting ? 0.97 : (entered ? 1 : 0.88)))
            .offset(y: reduceMotion ? 0 : (exiting ? -8 : (entered ? 0 : 18)))
            .animation(LaunchMascotMotion.arrive, value: entered)
            .animation(.easeInOut(duration: 0.24), value: exiting)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codessa opening")
        .contentShape(Rectangle())
        .onTapGesture { dismissNow() }
        .task { await playIntro() }
    }

    private var launchBackdrop: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            CodexTheme.mainBackground.opacity(0.82)

            LinearGradient(
                colors: [
                    CodexTheme.sidebarBackground.opacity(0.86),
                    CodexTheme.mainBackground.opacity(0.76),
                    CodexTheme.composerShellBackground.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LaunchLineField()
                .opacity(entered ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: entered)

            LinearGradient(
                colors: [.white.opacity(0.18), .clear, CodexTheme.accent.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func playIntro() async {
        guard !finished else { return }

        withAnimation(LaunchMascotMotion.arrive) {
            entered = true
        }

        guard !reduceMotion else {
            bootProgress = 1
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismissNow()
            return
        }

        bootProgress = 0.08
        withAnimation(.easeInOut(duration: 2.72)) {
            bootProgress = 1
        }

        try? await Task.sleep(nanoseconds: 3_100_000_000)
        dismissNow()
    }

    @MainActor
    private func dismissNow() {
        guard !finished else { return }
        finished = true

        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.24)) {
            exiting = true
        }

        Task {
            try? await Task.sleep(nanoseconds: reduceMotion ? 140_000_000 : 260_000_000)
            await MainActor.run {
                onFinished()
            }
        }
    }
}

private enum LaunchMascotMotion {
    static let arrive = Animation.spring(response: 0.52, dampingFraction: 0.74)
}

private struct LaunchProgressIndicator: View {
    var progress: CGFloat
    var isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = max(proxy.size.width * clampedProgress, clampedProgress > 0 ? 8 : 0)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(CodexTheme.composerBackground.opacity(0.58))
                    .frame(height: proxy.size.height)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(CodexTheme.composerBorder.opacity(0.54), lineWidth: 1)
                    )

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                CodexTheme.accent.opacity(0.88),
                                CodexTheme.focusAccent.opacity(0.96),
                                CodexTheme.textPrimary.opacity(0.84)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: proxy.size.height)
                    .shadow(color: CodexTheme.accent.opacity(0.42), radius: 7, x: 0, y: 0)

                if isActive && clampedProgress > 0.12 && clampedProgress < 0.98 {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.58))
                        .frame(width: 16, height: proxy.size.height)
                        .blur(radius: 1.4)
                        .offset(x: max(0, fillWidth - 18))
                        .blendMode(.plusLighter)
                }
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

private struct SpriteSheetMascotView: View {
    var isAnimating: Bool

    @State private var frameIndex = 0
    @State private var frames: [NSImage] = []

    var body: some View {
        Group {
            if frames.indices.contains(frameIndex) {
                Image(nsImage: frames[frameIndex])
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(CodexTheme.accent)
            }
        }
        .accessibilityHidden(true)
        .task {
            loadFramesIfNeeded()
        }
        .task(id: isAnimating) {
            loadFramesIfNeeded()

            guard isAnimating, frames.count > 1 else {
                frameIndex = 0
                return
            }

            frameIndex = 0

            for nextIndex in 1..<frames.count {
                try? await Task.sleep(nanoseconds: 92_000_000)
                guard !Task.isCancelled, !frames.isEmpty else { return }
                frameIndex = nextIndex
            }
        }
    }

    @MainActor
    private func loadFramesIfNeeded() {
        guard frames.isEmpty else { return }
        frames = MascotSpriteFrames.load()
    }
}

private enum MascotSpriteFrames {
    private static let directory = "Assets/Sprites/codessa-mascot-v2-frames"

    static func load() -> [NSImage] {
        (1...32).compactMap { index in
            let name = String(format: "codessa-mascot-v2-%02d", index)
            if let bundled = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: bundled) {
                return image
            }
            if let bundled = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: directory),
               let image = NSImage(contentsOf: bundled) {
                return image
            }

            #if DEBUG
            let sourceURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../../Assets/Sprites/codessa-mascot-v2-frames/\(name).png")
                .standardizedFileURL
            return NSImage(contentsOf: sourceURL)
            #else
            return nil
            #endif
        }
    }
}

private struct LaunchLineField: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                for x in stride(from: -height, through: width, by: 72) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + height * 0.36, y: height))
                }
                for y in stride(from: 0, through: height, by: 86) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y + width * 0.04))
                }
            }
            .stroke(CodexTheme.divider.opacity(0.16), lineWidth: 1)
            .mask(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.58), .black.opacity(0.42), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .allowsHitTesting(false)
    }
}
