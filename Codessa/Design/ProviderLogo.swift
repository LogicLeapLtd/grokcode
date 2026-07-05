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
            self = .bundledAsset("ProviderLogoGemini")
        case AgentProvider.grok.id:
            self = .bundledAsset("ProviderLogoGrok")
        case AgentProvider.zai.id:
            self = .zai
        default:
            self = .custom
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
