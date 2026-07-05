import SwiftUI

struct ProviderLogo: View {
    let providerId: String
    var size: CGFloat = 16
    var foreground: Color = CodexTheme.textSecondary

    var body: some View {
        mark
            .frame(width: size, height: size)
            .foregroundStyle(foreground)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        switch ProviderLogoKind(providerId: providerId) {
        case .bundledAsset(let name):
            Image(name)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
        case .gemini:
            GeminiLogoMark()
        case .zai:
            ZAILogoMark()
        case .custom:
            CustomProviderLogoMark()
        }
    }
}

struct ModelMenuItem: View {
    let option: GrokModelOption
    var subtitle: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    @State private var hovering = false

    private var rowFill: Color {
        if isSelected { return CodexTheme.accent.opacity(0.12) }
        if hovering { return CodexTheme.hoverBackground }
        return .clear
    }

    private var titleColor: Color {
        isSelected ? CodexTheme.accent : CodexTheme.textPrimary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ProviderLogo(
                    providerId: option.providerId,
                    size: 16,
                    foreground: isSelected ? CodexTheme.accent : CodexTheme.textSecondary
                )
                .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.displayName)
                        .font(CodexTheme.sans(12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle {
                        Text(subtitle)
                            .font(CodexTheme.sans(11))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                if option.isDefault {
                    Text("Default")
                        .font(CodexTheme.sans(9.5, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CodexTheme.pillBackground.opacity(0.72))
                        )
                }

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CodexTheme.accent)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, subtitle == nil ? 5 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private enum ProviderLogoKind {
    case bundledAsset(String)
    case gemini
    case zai
    case custom

    init(providerId: String) {
        switch providerId {
        case AgentProvider.claude.id:
            self = .bundledAsset("ProviderLogoClaude")
        case AgentProvider.cursor.id:
            self = .bundledAsset("ProviderLogoCursor")
        case AgentProvider.codex.id:
            self = .bundledAsset("ProviderLogoChatGPT")
        case AgentProvider.gemini.id:
            self = .gemini
        case AgentProvider.grok.id:
            self = .bundledAsset("ProviderLogoGrok")
        case AgentProvider.zai.id:
            self = .zai
        default:
            self = .custom
        }
    }
}

private struct GeminiLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let rect = CGRect(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2,
                width: side,
                height: side
            ).insetBy(dx: side * 0.04, dy: side * 0.04)

            GeminiSparkleShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.62, green: 0.43, blue: 0.92),
                            Color(red: 0.86, green: 0.39, blue: 0.63),
                            Color(red: 0.98, green: 0.69, blue: 0.23),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    GeminiSparkleShape()
                        .stroke(.white.opacity(0.24), lineWidth: max(0.45, side * 0.04))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct GeminiSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: center.y),
            control1: CGPoint(x: center.x + width * 0.08, y: rect.minY + height * 0.32),
            control2: CGPoint(x: rect.maxX - width * 0.32, y: center.y - height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - width * 0.32, y: center.y + height * 0.08),
            control2: CGPoint(x: center.x + width * 0.08, y: rect.maxY - height * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: center.y),
            control1: CGPoint(x: center.x - width * 0.08, y: rect.maxY - height * 0.32),
            control2: CGPoint(x: rect.minX + width * 0.32, y: center.y + height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: center.x, y: rect.minY),
            control1: CGPoint(x: rect.minX + width * 0.32, y: center.y - height * 0.08),
            control2: CGPoint(x: center.x - width * 0.08, y: rect.minY + height * 0.32)
        )
        path.closeSubpath()

        return path
    }
}

private struct ZAILogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: width * 0.18, y: height * 0.18))
                path.addLine(to: CGPoint(x: width * 0.82, y: height * 0.18))
                path.addLine(to: CGPoint(x: width * 0.20, y: height * 0.82))
                path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.82))
            }
            .stroke(.foreground, style: StrokeStyle(lineWidth: max(1.8, width * 0.16), lineCap: .round, lineJoin: .round))
        }
    }
}

private struct CustomProviderLogoMark: View {
    var body: some View {
        Circle()
            .stroke(.foreground, lineWidth: 1.5)
            .overlay(
                Circle()
                    .fill(.foreground)
                    .frame(width: 4, height: 4)
            )
    }
}
