import SwiftUI
import AppKit

struct ChatView: View {
    @Environment(AppViewModel.self) private var model

    private var chatTitle: String {
        if let firstUser = model.messages.first(where: { $0.role == .user })?.text,
           !firstUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(firstUser.prefix(72))
        }
        return "New chat"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(model.messages) { message in
                            MessageBlock(message: message, onRetry: { model.retryLast() })
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom-anchor")
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation(CodexMotion.quickSpring) { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                }
                // Follow streaming output instantly (no per-token animation = smooth).
                .onChange(of: model.messages.last?.text) { _, _ in
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
                .onChange(of: model.messages.last?.reasoning) { _, _ in
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
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

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chatTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                if let project = model.selectedProject {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(CodexTheme.textTertiary)
                        Text(project.name)
                            .font(.system(size: 12))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                        if let branch = project.gitBranch {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(CodexTheme.textTertiary)
                            Text(branch)
                                .font(.system(size: 11))
                                .foregroundStyle(CodexTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CodexTheme.mainBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CodexTheme.divider).frame(height: 1)
        }
    }
}

private struct MessageBlock: View {
    let message: ChatMessage
    var onRetry: () -> Void = {}

    var body: some View {
        switch message.role {
        case .user:
            UserMessageBlock(message: message)
        default:
            AssistantMessageBlock(message: message, onRetry: onRetry)
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
                            .background(Capsule().fill(CodexTheme.pillBackground))
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
    var onRetry: () -> Void = {}
    @State private var hovering = false

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
                MarkdownText(text: message.text)
                    .textSelection(.enabled)
            }

            if let errorText = message.errorText {
                ErrorBlock(text: errorText, onRetry: onRetry)
            }

            // Hover-revealed actions under a finished answer.
            if !message.text.isEmpty && !message.isStreaming {
                AssistantActions(text: message.text, onRegenerate: onRetry)
                    .opacity(hovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: hovering)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering = $0 }
    }
}

/// Copy / Regenerate row shown under a completed assistant answer.
private struct AssistantActions: View {
    let text: String
    var onRegenerate: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 2) {
            actionButton(copied ? "checkmark" : "doc.on.doc", copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                withAnimation(CodexMotion.quickSpring) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            }
            actionButton("arrow.clockwise", "Regenerate", action: onRegenerate)
        }
        .padding(.top, 2)
    }

    private func actionButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(CodexTheme.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .codexHover(cornerRadius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reasoning ("Thinking") disclosure

private struct ReasoningBlock: View {
    let reasoning: String
    let isStreaming: Bool

    @State private var manualExpanded: Bool?
    @State private var start = Date()
    @State private var elapsed: Int?
    private var isExpanded: Bool { manualExpanded ?? isStreaming }

    private var label: String {
        if isStreaming { return "Thinking…" }
        if let elapsed { return "Thought for \(elapsed)s" }
        return "Thought process"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(CodexMotion.expandSpring) { manualExpanded = !isExpanded }
            } label: {
                HStack(spacing: 6) {
                    if isStreaming {
                        ThinkingDots(color: CodexTheme.textSecondary, size: 4)
                    } else {
                        Image(systemName: "brain")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CodexTheme.textTertiary)
                    }
                    Text(label)
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
                MarkdownText(text: reasoning, font: .system(size: 13.5), color: CodexTheme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CodexTheme.divider)
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { start = Date() }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming, elapsed == nil {
                elapsed = max(1, Int(Date().timeIntervalSince(start)))
            }
        }
    }
}

// MARK: - Thinking indicator (no output yet)

private struct ThinkingIndicator: View {
    @State private var start = Date()

    var body: some View {
        HStack(spacing: 8) {
            ThinkingDots(color: CodexTheme.textSecondary, size: 6)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secs = Int(context.date.timeIntervalSince(start))
                Text(secs >= 3 ? "Thinking… \(secs)s" : "Thinking…")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .contentTransition(.numericText())
            }
        }
        .onAppear { start = Date() }
    }
}

private struct ThinkingDots: View {
    var color: Color
    var size: CGFloat = 6
    @State private var animating = false

    var body: some View {
        HStack(spacing: size * 0.55) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .opacity(animating ? 1.0 : 0.25)
                    .scaleEffect(animating ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Error

private struct ErrorBlock: View {
    let text: String
    var onRetry: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Button(action: onRetry) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                    Text("Retry").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(CodexTheme.errorForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(CodexTheme.errorBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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
