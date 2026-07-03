import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Modal wrapper around `HooksReviewContent` (still presented from ContentView
/// via `model.showHooksReview`). The same content is embedded, headerless, in
/// the Settings → Hooks section.
struct HooksReviewView: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HooksReviewContent(showsHeader: true)

            HStack {
                Spacer()
                Button { model.closeHooksReview() } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodexTheme.pillBackground))
                        .codexHover()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560, height: 460)
    }
}

/// Reusable hooks review surface: a list of pending hooks, each with an
/// origin badge and an expandable detail revealing the full command in a
/// monospaced block with a copy button, plus per-hook "Trust" and a guarded
/// "Trust all". Used both in the modal and embedded in Settings.
struct HooksReviewContent: View {
    @Environment(AppViewModel.self) private var model
    var showsHeader: Bool = true

    @State private var expanded: Set<String> = []
    @State private var copied: String?
    @State private var confirmingTrustAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                Text("Review hooks")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(CodexTheme.textPrimary)
            }

            Text("Grok hooks run shell commands when agent events fire. Trust only hooks you recognise.")
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.pendingHooks.isEmpty {
                emptyState
            } else {
                hooksList
                trustAllRow
            }
        }
        .confirmationDialog(
            "Trust all pending hooks?",
            isPresented: $confirmingTrustAll,
            titleVisibility: .visible
        ) {
            Button("Trust all", role: .destructive) { model.trustAllHooks() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks every pending hook as trusted, allowing their shell commands to run on agent events. Only do this if you recognise all of them.")
        }
    }

    // MARK: - List

    private var hooksList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.pendingHooks.enumerated()), id: \.element.id) { index, hook in
                if index > 0 {
                    Rectangle().fill(CodexTheme.divider).frame(height: 1)
                }
                hookRow(hook)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.sidebarBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    private func hookRow(_ hook: PendingHook) -> some View {
        let isOpen = expanded.contains(hook.id)
        let origin = AppViewModel.hookOrigin(for: hook)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(CodexMotion.expandSpring) {
                    if isOpen { expanded.remove(hook.id) } else { expanded.insert(hook.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(hook.event)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CodexTheme.textPrimary)
                            originBadge(origin)
                        }
                        Text(hook.command)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CodexTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    Button { model.trustHook(hook) } label: {
                        Text("Trust")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Capsule().fill(CodexTheme.pillBackground))
                            .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Trust this hook")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                detail(hook)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func detail(_ hook: PendingHook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(hook.fileName) · \(hook.event)")
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
                Spacer()
                Button { copy(hook.command, id: hook.id) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied == hook.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(copied == hook.id ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(CodexTheme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(CodexTheme.pillBackground))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Copy the command")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(hook.command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CodexTheme.mainBackground))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.leading, 20)
    }

    private func originBadge(_ origin: (label: String, symbol: String)) -> some View {
        HStack(spacing: 4) {
            Image(systemName: origin.symbol).font(.system(size: 9, weight: .medium))
            Text(origin.label).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(CodexTheme.textSecondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(CodexTheme.pillBackground))
    }

    private var trustAllRow: some View {
        HStack {
            Text("\(model.pendingHooks.count) pending")
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textTertiary)
            Spacer()
            Button { confirmingTrustAll = true } label: {
                Text("Trust all")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.accentOrange)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(CodexTheme.pillBackground))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Trust every pending hook")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CodexTheme.textTertiary)
            Text("No pending hooks")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
            Text("Every hook in ~/.grok/hooks is trusted.")
                .font(.system(size: 12))
                .foregroundStyle(CodexTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.sidebarBackground))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CodexTheme.divider, lineWidth: 1))
    }

    // MARK: - Actions

    private func copy(_ text: String, id: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copied == id { copied = nil }
        }
    }
}
