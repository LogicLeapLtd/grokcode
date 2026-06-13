import SwiftUI

struct ChatView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            MessageBlock(message: message)
                                .id(message.id)
                                .codexStaggeredAppear(index: min(index, 8))
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .animation(CodexMotion.panelSpring, value: model.messages.count)
                }
                .onChange(of: model.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: model.messages.last?.text) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: model.messages.last?.reasoning) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            PromptComposer()
                .padding(.horizontal, 48)
                .padding(.vertical, 20)
                .frame(maxWidth: CodexTheme.composerMaxWidth + 96)
                .frame(maxWidth: .infinity)
                .background(CodexTheme.mainBackground)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = model.messages.last {
            withAnimation(CodexMotion.quickSpring) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct MessageBlock: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            UserMessageBlock(message: message)
        default:
            AssistantMessageBlock(message: message)
        }
    }
}

// MARK: - User

private struct UserMessageBlock: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.text)
                .font(CodexTheme.bodyFont)
                .foregroundStyle(CodexTheme.textPrimary)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CodexTheme.userBubbleBackground)
                )
                .overlay(alignment: .topTrailing) {
                    if message.isQueued {
                        Text("Queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(CodexTheme.pillBackground)
                            )
                            .offset(x: 4, y: -8)
                    }
                }
                .opacity(message.isQueued ? 0.7 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Assistant

private struct AssistantMessageBlock: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.reasoning.isEmpty {
                ReasoningBlock(
                    reasoning: message.reasoning,
                    isStreaming: message.isStreaming && message.text.isEmpty
                )
            }

            if message.isAwaitingFirstToken {
                ThinkingIndicator()
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(CodexTheme.bodyFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(CodexMotion.quickSpring, value: message.text.count)
            }

            if let errorText = message.errorText {
                ErrorBlock(text: errorText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reasoning ("Thinking") disclosure

private struct ReasoningBlock: View {
    let reasoning: String
    let isStreaming: Bool

    /// nil = follow the default (expanded while actively reasoning, collapsed
    /// once the answer starts); non-nil = user override.
    @State private var manualExpanded: Bool?

    private var isExpanded: Bool { manualExpanded ?? isStreaming }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(CodexMotion.expandSpring) {
                    manualExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    if isStreaming {
                        ThinkingDots(color: CodexTheme.textSecondary, size: 4)
                    } else {
                        Image(systemName: "brain")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CodexTheme.textTertiary)
                    }
                    Text(isStreaming ? "Thinking…" : "Thought process")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexTheme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(reasoning)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CodexTheme.divider)
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Thinking indicator (no reasoning yet)

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ThinkingDots(color: CodexTheme.textSecondary, size: 6)
            Text("Thinking…")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(CodexTheme.textSecondary)
        }
    }
}

private struct ThinkingDots: View {
    var color: Color
    var size: CGFloat = 6
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .opacity(opacity(for: i))
            }
        }
        .onAppear { phase = 1 }
        .animation(
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
            value: phase
        )
    }

    private func opacity(for index: Int) -> Double {
        // Stagger the three dots so they shimmer in sequence.
        let base = 0.35
        let lit = 1.0
        let active = Int((phase * 3).rounded()) % 3
        return index == active ? lit : base
    }
}

// MARK: - Error

private struct ErrorBlock: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.errorForeground)
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(CodexTheme.errorForeground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTheme.errorBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.errorBorder, lineWidth: 1)
        )
    }
}
