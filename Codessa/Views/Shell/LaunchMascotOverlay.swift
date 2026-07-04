import SwiftUI

struct LaunchMascotOverlay: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entered = false
    @State private var sparksLit = false
    @State private var floating = false
    @State private var wink = false
    @State private var exiting = false
    @State private var finished = false

    var body: some View {
        ZStack {
            launchBackdrop

            VStack(spacing: 18) {
                CodessaMascotMark(
                    entered: entered,
                    sparksLit: sparksLit,
                    floating: floating,
                    wink: wink,
                    reduceMotion: reduceMotion
                )
                .frame(width: 192, height: 152)

                VStack(spacing: 5) {
                    Text("Codessa")
                        .font(CodexTheme.serif(31, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)

                    HStack(spacing: 7) {
                        Text(">")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(CodexTheme.accent)
                        Text("ready")
                            .font(CodexTheme.sans(12, weight: .medium))
                            .foregroundStyle(CodexTheme.textSecondary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CodexTheme.composerBackground.opacity(0.74))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(CodexTheme.composerBorder.opacity(0.58), lineWidth: 1)
                    )
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered && !reduceMotion ? 0 : 6)
                    .animation(.easeOut(duration: 0.32).delay(0.18), value: entered)
                }
            }
            .opacity(exiting ? 0 : (entered ? 1 : 0))
            .scaleEffect(reduceMotion ? 1 : (exiting ? 0.97 : (entered ? 1 : 0.88)))
            .offset(y: reduceMotion ? 0 : (exiting ? -8 : (entered ? 0 : 18)))
            .animation(LaunchMascotMotion.arrive, value: entered)
            .animation(.easeInOut(duration: 0.24), value: exiting)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codessa ready")
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
            sparksLit = true
        }

        guard !reduceMotion else {
            try? await Task.sleep(nanoseconds: 850_000_000)
            dismissNow()
            return
        }

        withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
            floating = true
        }

        try? await Task.sleep(nanoseconds: 620_000_000)
        withAnimation(.easeInOut(duration: 0.10)) {
            wink = true
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.easeInOut(duration: 0.14)) {
            wink = false
        }

        try? await Task.sleep(nanoseconds: 1_050_000_000)
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

private struct CodessaMascotMark: View {
    var entered: Bool
    var sparksLit: Bool
    var floating: Bool
    var wink: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                LaunchSpark(index: index, lit: sparksLit, drifting: floating && !reduceMotion)
            }

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .strokeBorder(CodexTheme.accent.opacity(0.18), lineWidth: 1)
                .frame(width: entered ? 142 : 82, height: entered ? 110 : 72)
                .scaleEffect(floating && !reduceMotion ? 1.05 : 0.97)
                .opacity(entered ? 1 : 0)
                .animation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true), value: floating)

            mascotBody
                .scaleEffect(entered ? 1 : 0.72)
                .offset(y: reduceMotion ? 0 : (floating ? -5 : 3))
                .rotationEffect(.degrees(reduceMotion ? 0 : (entered ? -1.2 : -8)))
                .animation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true), value: floating)
        }
    }

    private var mascotBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            CodexTheme.composerBackground,
                            CodexTheme.composerShellBackground,
                            CodexTheme.accentDeep.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 88)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.58),
                                    CodexTheme.composerBorder.opacity(0.76),
                                    CodexTheme.accent.opacity(0.44)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.35
                        )
                )
                .shadow(color: CodexTheme.accent.opacity(0.22), radius: 28, y: 12)
                .shadow(color: CodexTheme.shadowColor.opacity(0.36), radius: 20, y: 14)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CodexTheme.accent.opacity(0.68))
                        .frame(width: 7, height: 7)
                    Circle()
                        .fill(CodexTheme.focusAccent.opacity(0.78))
                        .frame(width: 7, height: 7)
                    Capsule(style: .continuous)
                        .fill(CodexTheme.textTertiary.opacity(0.22))
                        .frame(width: 28, height: 6)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 17)
                .padding(.top, 14)

                Spacer(minLength: 0)

                HStack(spacing: 16) {
                    MascotEye(isWinking: false)
                    MascotEye(isWinking: wink)
                }
                .padding(.bottom, 8)

                HStack(spacing: 5) {
                    Text(">")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundStyle(CodexTheme.accent)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(CodexTheme.textPrimary.opacity(floating && !reduceMotion ? 0.46 : 0.9))
                        .frame(width: 11, height: 16)
                }
                .padding(.bottom, 13)
            }
            .frame(width: 112, height: 88)

            Text("</>")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(CodexTheme.accent.opacity(0.76))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.32), lineWidth: 1)
                )
                .offset(x: 34, y: -44)
                .rotationEffect(.degrees(5))
        }
    }
}

private struct MascotEye: View {
    var isWinking: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(CodexTheme.textPrimary.opacity(0.88))
            .frame(width: 12, height: isWinking ? 3 : 11)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(isWinking ? 0 : 0.82))
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: 2.5, y: 2.3)
            }
    }
}

private struct LaunchSpark: View {
    let index: Int
    var lit: Bool
    var drifting: Bool

    var body: some View {
        let angle = (Double(index) / 8.0) * 360.0
        let radians = angle * .pi / 180.0
        let x = CGFloat(cos(radians)) * (lit ? 78 : 30)
        let y = CGFloat(sin(radians)) * (lit ? 52 : 22)
        let long = index.isMultiple(of: 2)

        Capsule(style: .continuous)
            .fill(sparkFill)
            .frame(width: long ? 18 : 7, height: 3.5)
            .rotationEffect(.degrees(angle + (drifting ? 15 : -8)))
            .offset(x: x, y: y + (drifting ? CGFloat(index % 3 - 1) * 4 : 0))
            .scaleEffect(lit ? 1 : 0.35)
            .opacity(lit ? (long ? 0.86 : 0.62) : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(Double(index) * 0.035), value: lit)
            .animation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true), value: drifting)
    }

    private var sparkFill: some ShapeStyle {
        if index.isMultiple(of: 3) {
            return AnyShapeStyle(CodexTheme.focusAccent)
        }
        if index.isMultiple(of: 2) {
            return AnyShapeStyle(CodexTheme.accent)
        }
        return AnyShapeStyle(CodexTheme.textTertiary.opacity(0.72))
    }
}
