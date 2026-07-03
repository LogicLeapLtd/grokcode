import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(AppViewModel.self) private var model

    private var chatTitle: String {
        if let firstUser = model.messages.first(where: { $0.role == .user })?.text,
           !firstUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(firstUser.prefix(72))
        }
        return "New chat"
    }

    /// Settled turns that would actually land in an export — mirrors the filter
    /// in `ChatExportService.markdown` (skips streaming, queued, and empty
    /// turns). The export control only enables when this is non-empty so we
    /// never offer to copy/save an empty document.
    private var hasExportableMessages: Bool {
        model.messages.contains { message in
            !message.isStreaming && !message.isQueued
                && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Distance (pt) from the very bottom of the scroll content. 0 = pinned to
    /// the latest message. Drives both the autoscroll gate and the
    /// scroll-to-bottom button's visibility (#11).
    @State private var distanceFromBottom: CGFloat = 0
    /// Once the content overflows we know scrolling is possible; below this the
    /// button must never appear (short threads).
    @State private var isScrollable = false
    /// Measured transcript height, used by the custom scroll thumb.
    @State private var contentHeight: CGFloat = 0

    /// Show the floating "jump to latest" button once the user has scrolled up
    /// past roughly one screenful's worth of slack.
    private var showScrollToBottom: Bool {
        isScrollable && distanceFromBottom > 120
    }

    /// Autoscroll only stays pinned while the user is already near the bottom,
    /// so reading scrollback isn't yanked away mid-stream.
    private var isNearBottom: Bool {
        distanceFromBottom < 80
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(model.messages) { message in
                                MessageBlock(
                                    message: message,
                                    onRetry: { model.retryLast() },
                                    onResend: { newText in
                                        model.editAndResend(messageID: message.id, newText: newText)
                                    }
                                )
                                .id(message.id)
                            }
                            Color.clear.frame(height: 1).id("bottom-anchor")
                        }
                        .padding(.horizontal, 48)
                        .padding(.vertical, 28)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        // Report content bottom (maxY) in the scroll space; the
                        // viewport height comes from the outer GeometryReader.
                        .background(
                            GeometryReader { content in
                                let maxY = content.frame(in: .named(ChatScrollSpace)).maxY
                                Color.clear
                                    .preference(key: ChatContentMaxYKey.self, value: maxY)
                                    .preference(key: ChatContentHeightKey.self, value: content.size.height)
                            }
                        )
                    }
                    .scrollIndicators(.hidden)
                    .background(ChatScrollViewConfigurator())
                    .coordinateSpace(name: ChatScrollSpace)
                    .onPreferenceChange(ChatContentMaxYKey.self) { maxY in
                        // Distance the content extends past the viewport bottom.
                        distanceFromBottom = max(0, maxY - viewport.size.height)
                    }
                    .onPreferenceChange(ChatContentHeightKey.self) { height in
                        contentHeight = height
                        isScrollable = height > viewport.size.height + 1
                    }
                    .onChange(of: model.messages.count) { _, _ in
                        // A brand-new turn always pulls focus to the bottom.
                        withAnimation(CodexMotion.quickSpring) { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                    }
                    // Follow streaming output instantly (no per-token animation =
                    // smooth) — but only while the reader is already near the
                    // bottom, so scrolling up to read isn't fought (#11).
                    .onChange(of: model.messages.last?.text) { _, _ in
                        if isNearBottom { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                    }
                    .onChange(of: model.messages.last?.reasoning) { _, _ in
                        if isNearBottom { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        ScrollToBottomButton {
                            withAnimation(CodexMotion.quickSpring) {
                                proxy.scrollTo("bottom-anchor", anchor: .bottom)
                            }
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 16)
                        .opacity(showScrollToBottom ? 1 : 0)
                        .scaleEffect(showScrollToBottom ? 1 : 0.85)
                        .allowsHitTesting(showScrollToBottom)
                        .animation(CodexMotion.quickSpring, value: showScrollToBottom)
                    }
                    .overlay(alignment: .trailing) {
                        ChatSlimScrollbar(
                            distanceFromBottom: distanceFromBottom,
                            contentHeight: contentHeight,
                            viewportHeight: viewport.size.height
                        )
                        .padding(.trailing, 7)
                    }
                }
            }

            PromptComposer()
                .padding(.horizontal, 48)
                .padding(.vertical, 20)
                .frame(maxWidth: CodexTheme.composerMaxWidth + 96)
                .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chatTitle)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
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

            exportControl
        }
        .padding(.leading, 24)
        // Reserve room on the right for the global window-popout control that
        // floats at the top-trailing corner (see MainContentView.windowControls),
        // so "Export" no longer sits underneath it.
        .padding(.trailing, 52)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CodexTheme.divider).frame(height: 1)
        }
    }

    // MARK: - Export / share

    /// Trailing-side "Export" control: a custom CodexMenu offering markdown
    /// copy-to-clipboard and save-to-file. Disabled (dimmed, non-interactive)
    /// until the conversation has at least one settled, non-empty turn.
    private var exportControl: some View {
        CodexMenuTrigger(minWidth: 220, edge: .bottom) { isOpen in
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
                Text("Export")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isOpen ? CodexTheme.textPrimary : CodexTheme.textSecondary)
        } menu: { close in
            CodexMenuContainer {
                CodexMenuSectionHeader(title: "Export chat")
                CodexMenuItem(title: "Copy as Markdown", systemImage: "doc.on.doc") {
                    copyMarkdown()
                    close()
                }
                CodexMenuItem(title: "Save as Markdown…", systemImage: "arrow.down.doc") {
                    close()
                    saveMarkdown()
                }
            }
        }
        .disabled(!hasExportableMessages)
        .opacity(hasExportableMessages ? 1 : 0.4)
        .help(hasExportableMessages ? "Export this chat" : "Nothing to export yet")
    }

    private func copyMarkdown() {
        let markdown = ChatExportService.markdown(from: model.messages, title: chatTitle)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func saveMarkdown() {
        let markdown = ChatExportService.markdown(from: model.messages, title: chatTitle)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ChatExportService.filename(for: chatTitle)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.title = "Export Chat"
        panel.prompt = "Export"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }
}

private struct MessageBlock: View {
    let message: ChatMessage
    var onRetry: () -> Void = {}
    var onResend: (String) -> Void = { _ in }

    var body: some View {
        switch message.role {
        case .user:
            UserMessageBlock(message: message, onResend: onResend)
        default:
            AssistantMessageBlock(message: message, onRetry: onRetry)
        }
    }
}

// MARK: - User

private struct UserMessageBlock: View {
    let message: ChatMessage
    var onResend: (String) -> Void = { _ in }

    @Environment(AppViewModel.self) private var model
    @State private var hovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    /// Editing is only offered on settled, non-queued user turns while idle —
    /// resending rewrites history, which a live run can't absorb.
    private var canEdit: Bool {
        !message.isQueued && !model.isRunning
    }

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            if isEditing {
                editor
            } else {
                bubble
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onHover { hovering = $0 }
    }

    // MARK: Display bubble (with hover "Edit" affordance, #8)

    private var bubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Attached files render as chips above the text (image chips show a
            // hover preview and open full screen on click).
            if !message.attachments.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(message.attachments, id: \.self) { path in
                        AttachmentChipView(path: path)
                    }
                }
                .padding(.bottom, message.text.isEmpty ? 0 : 2)
            }

            if !message.text.isEmpty {
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
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture { if canEdit { beginEditing() } }
            }

            if canEdit {
                Button(action: beginEditing) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil").font(.system(size: 10, weight: .medium))
                        Text("Edit").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .codexHover(cornerRadius: 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
        }
    }

    // MARK: Inline editor

    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("", text: $draft, axis: .vertical)
                .font(CodexTheme.bodyFont)
                .foregroundStyle(CodexTheme.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...12)
                .multilineTextAlignment(.leading)
                .focused($editorFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 520, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CodexTheme.composerBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(CodexTheme.composerShellBorder, lineWidth: 1)
                )
                .onKeyPress(.return, phases: .down) { press in
                    // Match the composer's send-on-return preference.
                    let hasSendModifier = press.modifiers.contains(.command) || press.modifiers.contains(.shift)
                    let shouldSend = model.sendOnReturn
                        ? !press.modifiers.contains(.shift)
                        : hasSendModifier
                    guard shouldSend else { return .ignored }
                    commitEdit()
                    return .handled
                }
                .onKeyPress(.escape) {
                    cancelEdit()
                    return .handled
                }

            HStack(spacing: 8) {
                editButton("Cancel", filled: false, action: cancelEdit)
                editButton("Send", filled: true) { commitEdit() }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func editButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? CodexTheme.sendButtonActiveForeground : CodexTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(filled ? CodexTheme.sendButtonActiveBackground : CodexTheme.pillBackground)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle(scale: 0.96))
    }

    private func beginEditing() {
        draft = message.text
        isEditing = true
        editorFocused = true
    }

    private func cancelEdit() {
        isEditing = false
        editorFocused = false
    }

    private func commitEdit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isEditing = false
        editorFocused = false
        onResend(trimmed)
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

            // Live tool calls (reads / edits / commands) grok made this turn,
            // surfaced above the answer in arrival order — each row expands to
            // its diff/output. See `ToolCallList`.
            if !message.toolCalls.isEmpty {
                ToolCallList(toolCalls: message.toolCalls)
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

// MARK: - Tool calls (live read / edit / execute visibility)

/// Visual identity for a tool-call `kind`: an SF Symbol plus an accent color
/// used to tint the icon badge. Keeps each action type instantly recognisable
/// while staying calm against the transcript.
private struct ToolKindStyle {
    let icon: String
    let tint: Color
    let verb: String

    static func forKind(_ kind: String) -> ToolKindStyle {
        switch kind {
        case "edit":
            ToolKindStyle(icon: "pencil.line", tint: Color(red: 0.40, green: 0.78, blue: 0.52), verb: "Edited")
        case "execute":
            ToolKindStyle(icon: "terminal", tint: Color(red: 0.45, green: 0.62, blue: 0.95), verb: "Ran")
        case "read":
            ToolKindStyle(icon: "doc.text", tint: Color(red: 0.62, green: 0.66, blue: 0.74), verb: "Read")
        case "search":
            ToolKindStyle(icon: "magnifyingglass", tint: Color(red: 0.74, green: 0.56, blue: 0.95), verb: "Searched")
        default:
            ToolKindStyle(icon: "wrench.and.screwdriver", tint: Color(red: 0.95, green: 0.62, blue: 0.36), verb: "")
        }
    }
}

/// Vertical stack of the assistant turn's tool-call rows, in arrival order.
/// Rendered above the answer text so the reader sees grok working
/// (reading/editing files, running commands) Codex-style. A faint rail threads
/// the icon badges so the calls read as one continuous sequence of steps.
private struct ToolCallList: View {
    let toolCalls: [ToolCallEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(toolCalls.enumerated()), id: \.element.id) { index, call in
                ToolCallRow(
                    call: call,
                    isFirst: index == 0,
                    isLast: index == toolCalls.count - 1
                )
            }
        }
        .padding(.vertical, 4)
    }
}

/// One compact, expandable tool-call row: a tinted kind badge threaded onto a
/// connecting rail, the title, and a soft running/done status. Tapping reveals
/// the detail (diff / command + output) in a monospaced card beneath.
private struct ToolCallRow: View {
    let call: ToolCallEntry
    var isFirst: Bool = false
    var isLast: Bool = false

    @State private var expanded = false
    @State private var hovering = false

    private var style: ToolKindStyle { ToolKindStyle.forKind(call.kind) }

    private var hasDetail: Bool {
        !call.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if expanded, hasDetail {
                detailCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Header row (rail · badge · title · status · chevron)

    private var header: some View {
        Button {
            guard hasDetail else { return }
            withAnimation(CodexMotion.expandSpring) { expanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                badge

                Text(call.title.isEmpty ? "Working…" : call.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(hovering ? CodexTheme.textPrimary : CodexTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                statusIndicator

                // Disclosure chevron — only meaningful when expandable, and it
                // fades in on hover to keep the resting state clean.
                if hasDetail {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .opacity(hovering || expanded ? 1 : 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering || expanded ? CodexTheme.pillBackground.opacity(0.6) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!hasDetail)
        .onHover { hovering = $0 }
    }

    /// Tinted rounded badge threaded onto a hairline rail that connects the row
    /// above and below, so a sequence of calls reads as a single timeline.
    private var badge: some View {
        ZStack {
            // Connecting rail behind the badge.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(CodexTheme.divider)
                    .frame(width: 1.5)
                    .opacity(isFirst ? 0 : 1)
                Rectangle()
                    .fill(CodexTheme.divider)
                    .frame(width: 1.5)
                    .opacity(isLast ? 0 : 1)
            }

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(style.tint.opacity(0.16))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(style.tint.opacity(0.30), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: style.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(style.tint)
                )
        }
        .frame(width: 24)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch call.status {
        case .running:
            HStack(spacing: 6) {
                ThinkingDots(color: style.tint, size: 4)
                Text("Running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(style.tint.opacity(0.12))
            )
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(red: 0.40, green: 0.78, blue: 0.52))
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(Color(red: 0.40, green: 0.78, blue: 0.52).opacity(0.14))
                )
        }
    }

    // MARK: Expanded detail (diff / command + output)

    private var detailCard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(CodeHighlighter.diffAttributed(call.detail))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CodexTheme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CodexTheme.composerBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.leading, 34)
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

// MARK: - Scroll-to-bottom (#11)

/// Floating round button that jumps the transcript to the latest message. Shown
/// only while the user has scrolled up; see `ChatView.showScrollToBottom`.
private struct ScrollToBottomButton: View {
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(CodexTheme.composerBackground)
                        .overlay(Circle().strokeBorder(CodexTheme.divider, lineWidth: 1))
                        .shadow(color: CodexTheme.shadowColor, radius: 5, y: 2)
                )
                .codexHoverOverlay(cornerRadius: 16)
        }
        .buttonStyle(CodexPressableStyle(scale: 0.9))
        .help("Scroll to latest")
    }
}

private struct ChatSlimScrollbar: View {
    let distanceFromBottom: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    var body: some View {
        let maxScroll = max(contentHeight - viewportHeight, 1)
        let offsetFromTop = maxScroll - min(max(distanceFromBottom, 0), maxScroll)
        let progress = min(max(offsetFromTop / maxScroll, 0), 1)
        let thumbHeight = max(34, viewportHeight * min(viewportHeight / max(contentHeight, 1), 1))
        let travel = max(viewportHeight - thumbHeight, 0)
        let isVisible = contentHeight > viewportHeight + 6

        Capsule(style: .continuous)
            .fill(CodexTheme.textTertiary.opacity(0.30))
            .frame(width: 3, height: thumbHeight)
            .offset(y: progress * travel)
            .frame(width: 8, height: viewportHeight, alignment: .top)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: progress)
            .animation(CodexMotion.quickSpring, value: isVisible)
    }
}

private struct ChatScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { ScrollChrome.hideNativeScrollers(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { ScrollChrome.hideNativeScrollers(from: nsView) }
    }
}

/// Coordinate space the transcript reports content geometry in (#11).
private let ChatScrollSpace = "chatScroll"

/// The content's bottom edge (maxY) in the scroll coordinate space. Compared
/// against the viewport height to derive distance-from-bottom.
private struct ChatContentMaxYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Total content height, used to decide whether scrolling is even possible
/// (suppresses the button on short threads).
private struct ChatContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
