import SwiftUI
import AppKit

struct HomeView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 64).frame(maxHeight: 64)

                    VStack(spacing: 20) {
                        Text(headline)
                            .font(CodexTheme.headlineFont)
                            .foregroundStyle(CodexTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: CodexTheme.composerMaxWidth)
                            .id(headline)
                            .transition(CodexMotion.dropTransition)
                            .codexStaggeredAppear(index: 0)

                        if !model.grokAvailable {
                            GrokInstallGuidanceBanner()
                                .frame(maxWidth: CodexTheme.composerMaxWidth)
                                .codexStaggeredAppear(index: 1)
                        }

                        PromptComposer()
                            .codexStaggeredAppear(index: 2)
                            .frame(maxWidth: CodexTheme.composerMaxWidth)

                        if let error = model.errorMessage {
                            Text(error)
                                .font(CodexTheme.captionFont)
                                .foregroundStyle(CodexTheme.errorForeground)
                                .frame(maxWidth: CodexTheme.composerMaxWidth, alignment: .leading)
                                .transition(CodexMotion.bannerTransition)
                        }

                        quickActionRow
                            .frame(maxWidth: CodexTheme.composerMaxWidth)
                            .codexStaggeredAppear(index: 3)

                        recentChatsSection
                            .frame(maxWidth: CodexTheme.composerMaxWidth)
                            .codexStaggeredAppear(index: 4)
                    }
                    .padding(.horizontal, 48)
                    .animation(CodexMotion.pageSpring, value: model.selectedProject?.id)

                    Spacer(minLength: 48).frame(maxHeight: 48)
                }
                // Fill at least the viewport so the content centres vertically
                // when it's shorter than the window, and scrolls when taller.
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.hidden)
            .background(HomeScrollViewConfigurator())
            // Base provided by MainContentView's translucent dark layer (so glass refracts).
            .animation(CodexMotion.panelSpring, value: model.errorMessage)
            .animation(CodexMotion.panelSpring, value: model.grokAvailable)
        }
    }

    private var headline: String {
        if let project = model.selectedProject {
            return "What should we work on in \(project.name)?"
        }
        return "What should we work on?"
    }

    // MARK: Quick actions (#30)

    private var quickActionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(model.homeQuickActions) { action in
                    QuickActionCard(action: action) { model.runQuickAction(action) }
                }
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 10)
            ], spacing: 10) {
                ForEach(model.homeQuickActions) { action in
                    QuickActionCard(action: action) { model.runQuickAction(action) }
                }
            }
        }
    }

    // MARK: Recent chats (#30)

    @ViewBuilder
    private var recentChatsSection: some View {
        let recents = model.recentHomeChats()
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent chats")
                    .font(CodexTheme.sectionLabelFont)
                    .foregroundStyle(CodexTheme.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                VStack(spacing: 1) {
                    ForEach(recents) { chat in
                        RecentChatRow(chat: chat) { model.openRecentChat(chat) }
                    }
                }
            }
        }
    }
}

private struct HomeScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { ScrollChrome.hideNativeScrollers(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { ScrollChrome.hideNativeScrollers(from: nsView) }
    }
}

// MARK: - Quick-action card

private struct QuickActionCard: View {
    let action: HomeQuickAction
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CodexTheme.pillBackground.opacity(0.48))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(CodexTheme.composerBorder.opacity(0.42), lineWidth: 0.75)
                    )

                Text(action.title)
                    .font(CodexTheme.controlTitleFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            // Liquid Glass card (macOS 26+), with a hover tint over the glass.
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true,
                fallback: CodexTheme.composerBackground
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hovering ? CodexTheme.hoverBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? CodexTheme.focusAccent.opacity(0.62) : CodexTheme.composerBorder.opacity(0.54),
                                  lineWidth: 1)
            )
            .shadow(color: CodexTheme.focusAccent.opacity(hovering ? 0.10 : 0), radius: 10, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CodexPressableStyle())
        .onHover { hovering = $0 }
        .animation(CodexMotion.quickSpring, value: hovering)
    }
}

// MARK: - Recent-chat row

private struct RecentChatRow: View {
    let chat: HomeRecentChat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .frame(width: 18)

                Text(chat.title)
                    .font(CodexTheme.listTitleFont)
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                // One clean, muted trailing label — branch when it differs from
                // the obvious context, otherwise just the age.
                if let branch = chat.branch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(branch)
                            .font(CodexTheme.listMetaFont)
                            .lineLimit(1)
                    }
                    .foregroundStyle(CodexTheme.textTertiary)
                }

                if !chat.ageLabel.isEmpty {
                    Text(chat.ageLabel)
                        .font(CodexTheme.listMetaFont)
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .codexHover(cornerRadius: 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexPressableStyle())
    }
}

struct HooksBanner: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.accentOrange)

            Text("\(model.pendingHooks.count) hook\(model.pendingHooks.count == 1 ? "" : "s") need review before they can run")
                .font(CodexTheme.captionFont)
                .foregroundStyle(CodexTheme.textSecondary)

            Spacer()

            Button("Trust all") { model.trustAllHooks() }
                .buttonStyle(CodexPillButtonStyle())

            Button("Review hooks") { model.openHooksReview() }
                .buttonStyle(CodexPillButtonStyle())
        }
    }
}

/// Compact "Grok CLI not found" warning embedded inside the composer (used by
/// `PromptComposer`). Home shows the richer `GrokInstallGuidanceBanner` instead.
struct GrokMissingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.accentOrange)
            Text("Grok CLI not found at ~/.grok/bin/grok")
                .font(CodexTheme.captionFont)
                .foregroundStyle(CodexTheme.textSecondary)
            Spacer()
        }
    }
}

/// Shown on Home when the Grok CLI isn't installed. Beyond warning, it surfaces
/// the one-line install command (copyable) and a docs link so the user can act
/// without leaving the app (#31).
struct GrokInstallGuidanceBanner: View {
    @Environment(AppViewModel.self) private var model
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexTheme.accentOrange)
                Text("Grok CLI not found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Spacer(minLength: 8)
            }

            Text("Codessa drives the local `grok` command. Install it, then run `grok login`.")
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(model.grokInstallCommand)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.copyGrokInstallCommand()
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didCopy = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(didCopy ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(CodexPillButtonStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexTheme.composerShellBackground)
            )

            HStack(spacing: 8) {
                Button {
                    model.openGrokDocs()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Installation docs")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(CodexPillButtonStyle())
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTheme.errorBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CodexTheme.errorBorder, lineWidth: 1)
        )
        .animation(CodexMotion.quickSpring, value: didCopy)
    }
}

struct CodexPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CodexTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? CodexTheme.pillBackgroundPressed : CodexTheme.pillBackground)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(CodexMotion.quickSpring, value: configuration.isPressed)
    }
}
