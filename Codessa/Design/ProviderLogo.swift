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
        case .anthropic:
            AnthropicLogoMark()
        case .cursor:
            CursorLogoMark()
        case .openAI:
            OpenAILogoMark()
        case .gemini:
            GeminiLogoMark()
        case .grok:
            GrokLogoMark()
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
    case anthropic
    case cursor
    case openAI
    case gemini
    case grok
    case zai
    case custom

    init(providerId: String) {
        switch providerId {
        case AgentProvider.claude.id:
            self = .anthropic
        case AgentProvider.cursor.id:
            self = .cursor
        case AgentProvider.codex.id:
            self = .openAI
        case AgentProvider.gemini.id:
            self = .gemini
        case AgentProvider.grok.id:
            self = .grok
        case AgentProvider.zai.id:
            self = .zai
        default:
            self = .custom
        }
    }
}

private struct OpenAILogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    Capsule(style: .continuous)
                        .frame(width: side * 0.42, height: max(1.8, side * 0.16))
                        .offset(x: side * 0.19)
                        .rotationEffect(.degrees(Double(index) * 60))
                }
                Circle()
                    .stroke(.foreground, lineWidth: max(1.2, side * 0.08))
                    .frame(width: side * 0.28, height: side * 0.28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct AnthropicLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.50, y: height * 0.08))
                    path.addLine(to: CGPoint(x: width * 0.12, y: height * 0.90))
                    path.addLine(to: CGPoint(x: width * 0.30, y: height * 0.90))
                    path.addLine(to: CGPoint(x: width * 0.40, y: height * 0.66))
                    path.addLine(to: CGPoint(x: width * 0.60, y: height * 0.66))
                    path.addLine(to: CGPoint(x: width * 0.70, y: height * 0.90))
                    path.addLine(to: CGPoint(x: width * 0.88, y: height * 0.90))
                    path.closeSubpath()
                }
                .fill(.foreground)
                RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                    .frame(width: width * 0.24, height: max(1.2, height * 0.10))
                    .offset(y: height * 0.14)
            }
        }
    }
}

private struct CursorLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: width * 0.18, y: height * 0.08))
                path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.48))
                path.addLine(to: CGPoint(x: width * 0.58, y: height * 0.58))
                path.addLine(to: CGPoint(x: width * 0.71, y: height * 0.88))
                path.addLine(to: CGPoint(x: width * 0.55, y: height * 0.94))
                path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.64))
                path.addLine(to: CGPoint(x: width * 0.20, y: height * 0.80))
                path.closeSubpath()
            }
            .fill(.foreground)
        }
    }
}

private struct GeminiLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: width * 0.50, y: height * 0.02))
                path.addQuadCurve(to: CGPoint(x: width * 0.98, y: height * 0.50),
                                  control: CGPoint(x: width * 0.66, y: height * 0.34))
                path.addQuadCurve(to: CGPoint(x: width * 0.50, y: height * 0.98),
                                  control: CGPoint(x: width * 0.66, y: height * 0.66))
                path.addQuadCurve(to: CGPoint(x: width * 0.02, y: height * 0.50),
                                  control: CGPoint(x: width * 0.34, y: height * 0.66))
                path.addQuadCurve(to: CGPoint(x: width * 0.50, y: height * 0.02),
                                  control: CGPoint(x: width * 0.34, y: height * 0.34))
                path.closeSubpath()
            }
            .fill(.foreground)
        }
    }
}

private struct GrokLogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
                    .frame(width: side * 0.82, height: max(2, side * 0.16))
                    .rotationEffect(.degrees(45))
                RoundedRectangle(cornerRadius: side * 0.08, style: .continuous)
                    .frame(width: side * 0.82, height: max(2, side * 0.16))
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
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
