import SwiftUI
import AppKit

/// The in-app updater's modal. Reads `UpdateService` from the environment and
/// renders a state per `UpdateService.Phase`, plus the dev "promote this build to
/// /Applications" affordance when the running build isn't installed at the
/// canonical path.
///
/// Presented from `ContentView` inside an `AnimatedModal`, so it just draws the
/// card; the backdrop + transition come from the host.
struct UpdateDialog: View {
    @EnvironmentObject private var update: UpdateService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
            actions
        }
        .padding(22)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CodexTheme.mainBackground)
                .shadow(color: CodexTheme.shadowColor, radius: 24, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
            }
            Spacer(minLength: 8)
            // Always-available dismiss (except mid-install, where quitting the
            // swap would be unsafe). Guarantees the dialog can be closed from any
            // state, including errors.
            if !isInstalling {
                Button { update.isDialogPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CodexTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(CodexTheme.pillBackground))
                        .contentShape(Circle())
                }
                .buttonStyle(CodexPressableStyle())
                .help("Close")
            }
        }
    }

    private var isInstalling: Bool {
        if case .installing = update.phase { return true }
        return false
    }

    private var title: String {
        switch update.phase {
        case .idle, .checking: return "Checking for updates"
        case .upToDate: return update.isRunningFromCanonicalLocation ? "You're up to date" : "You're up to date"
        case .updateAvailable(let r): return "Update available — \(r.name)"
        case .downloading: return "Downloading update"
        case .installing: return "Installing"
        case .failed: return "Couldn't check for updates"
        }
    }

    private var subtitle: String {
        "Codessa \(update.currentVersion)"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch update.phase {
        case .idle, .checking:
            row(spinner: true, text: "Contacting the release server…")

        case .upToDate:
            VStack(alignment: .leading, spacing: 14) {
                row(icon: "checkmark.circle.fill", tint: CodexTheme.accent,
                    text: "You're running the latest published version.")
                devPromoteNotice
            }

        case .updateAvailable(let release):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    versionPill(update.currentVersion, muted: true)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CodexTheme.textTertiary)
                    versionPill(release.version, muted: false)
                }
                if !release.notes.isEmpty {
                    Text("What's new")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexTheme.textSecondary)
                    ScrollView {
                        Text(renderedNotes(release.notes))
                            .font(.system(size: 12))
                            .foregroundStyle(CodexTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodexTheme.pillBackground))
                }
                if !update.isRunningFromCanonicalLocation {
                    footnote("It'll be installed to \(UpdateService.canonicalInstallURL.path) and relaunched from there, so your Dock shortcut stays put.")
                }
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(CodexTheme.accent)
                Text("\(Int(progress * 100))% downloaded")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
            }

        case .installing:
            row(spinner: true, text: "Installing and relaunching…")

        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                row(icon: "exclamationmark.triangle.fill", tint: CodexTheme.errorForeground, text: message)
                footnote("You can still grab the latest build straight from the releases page.")
            }
        }
    }

    /// Shown in the up-to-date state when the running build isn't at the
    /// canonical install path (a dev build, or run from Downloads).
    @ViewBuilder
    private var devPromoteNotice: some View {
        if !update.isRunningFromCanonicalLocation {
            VStack(alignment: .leading, spacing: 6) {
                Divider().overlay(CodexTheme.divider)
                Text(update.isDevBuild ? "You're running a development build." : "You're running Codessa from outside /Applications.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text("Install it to \(UpdateService.canonicalInstallURL.path) and relaunch so future updates and your Dock shortcut stay put — no more manual reboots or re-pinning.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            switch update.phase {
            case .idle, .checking, .installing:
                EmptyView()

            case .upToDate:
                if !update.isRunningFromCanonicalLocation {
                    secondaryButton("Close") { update.isDialogPresented = false }
                    primaryButton("Install & Relaunch", icon: "arrow.down.app") {
                        update.promoteRunningBuildToApplications()
                    }
                } else {
                    primaryButton("Done", icon: nil) { update.isDialogPresented = false }
                }

            case .updateAvailable(let release):
                secondaryButton("Later") { update.isDialogPresented = false }
                primaryButton("Update Now", icon: "arrow.down.circle") {
                    update.downloadAndInstall(release)
                }

            case .downloading:
                secondaryButton("Cancel") { update.isDialogPresented = false }

            case .failed:
                secondaryButton("Open Releases Page") {
                    NSWorkspace.shared.open(UpdateService.releasesPageURL)
                }
                primaryButton("Retry", icon: "arrow.clockwise") {
                    Task { await update.checkForUpdates(userInitiated: true) }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func row(spinner: Bool = false, icon: String? = nil, tint: Color = CodexTheme.textSecondary, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if spinner {
                ProgressView().controlSize(.small)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(CodexTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func versionPill(_ version: String, muted: Bool) -> some View {
        Text("v\(version)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(muted ? CodexTheme.textSecondary : CodexTheme.sendButtonActiveForeground)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(muted ? CodexTheme.pillBackground : CodexTheme.sendButtonActiveBackground)
            )
    }

    private func primaryButton(_ title: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(CodexTheme.sendButtonActiveForeground)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule(style: .continuous).fill(CodexTheme.sendButtonActiveBackground))
            .contentShape(Capsule())
        }
        .buttonStyle(CodexPressableStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule(style: .continuous).fill(CodexTheme.pillBackground))
                .overlay(Capsule().strokeBorder(CodexTheme.divider, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(CodexPressableStyle())
    }

    /// Best-effort markdown → AttributedString for the release notes, falling
    /// back to the raw text. Keeps headings/lists readable without a full
    /// markdown engine.
    private func renderedNotes(_ raw: String) -> AttributedString {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attributed = try? AttributedString(
            markdown: trimmed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(trimmed)
    }
}
