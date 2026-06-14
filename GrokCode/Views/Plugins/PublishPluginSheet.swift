import SwiftUI
import AppKit

/// In-app publishing for GrokCode's *own* plugin marketplace. The user fills in
/// a plugin's metadata + launch config, hits **Publish**, and the entry is saved
/// to their local published store (`MarketplaceService` via
/// `AppViewModel.publishPlugin`). After publishing, a success state offers two
/// follow-ups: copy the manifest-entry JSON (to open a `grokcode-marketplace`
/// PR) and open the marketplace repo on GitHub.
///
/// Presented from `PluginsView` via `.sheet(isPresented:)`. Like
/// `AutomationEditorSheet`, the sheet is its own window, so it carries its own
/// `CodexMenuController` + `.codexMenuHost()` — otherwise the custom Type
/// dropdown would render on the main window's host, behind the sheet.
struct PublishPluginSheet: View {
    /// Persists the entry to the published store, shows a toast, etc. Returns the
    /// built entry so the success state can render its manifest JSON.
    let onPublish: (MarketplaceEntry) -> Void
    let onClose: () -> Void

    /// The marketplace repo opened from the success state ("Open marketplace
    /// repo") and where a manifest-entry PR would be filed.
    static let repoURL = URL(string: "https://github.com/logicleaplabs/grokcode-marketplace")!

    // MARK: Form state

    @State private var name = ""
    @State private var detail = ""
    @State private var icon = "puzzlepiece.extension"
    @State private var kind: PluginKind = .mcpServer
    @State private var command = ""
    @State private var argsText = ""
    @State private var url = ""
    @State private var author = ""
    @State private var homepage = ""

    /// Once published, the sheet swaps the form for a success panel keyed off the
    /// published entry (so we can render/copy its manifest JSON).
    @State private var publishedEntry: MarketplaceEntry?
    @State private var didCopyManifest = false

    @FocusState private var nameFocused: Bool

    /// The sheet is its own window, so it needs its own menu host — otherwise the
    /// Type dropdown renders on the main window's host, behind the sheet.
    @State private var menuController = CodexMenuController(installsKeyboardMonitor: false)

    // MARK: Derived

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDetail: String { detail.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCommand: String { command.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// MCP servers may launch as stdio (command) or remote (url); every other
    /// kind is command/script-shaped, so it only shows the command field.
    private var usesURL: Bool { kind == .mcpServer }

    private var tint: Color {
        Color(red: PluginSource.builtin.tint.red,
              green: PluginSource.builtin.tint.green,
              blue: PluginSource.builtin.tint.blue)
    }

    /// First failed validation rule, or `nil` when savable. Mirrors the contract:
    /// name + description + at least a command or a url.
    private var validationMessage: String? {
        if trimmedName.isEmpty { return "Add a name." }
        if trimmedDetail.isEmpty { return "Add a description." }
        if trimmedCommand.isEmpty && trimmedURL.isEmpty {
            return usesURL ? "Add a command or a server URL." : "Add a command."
        }
        return nil
    }

    private var canPublish: Bool { validationMessage == nil }

    /// Parse the args field on whitespace/newlines into a clean argument vector.
    private var parsedArgs: [String] {
        argsText
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    /// Build the entry from the current form. Command/url are only carried when
    /// non-empty so a remote server doesn't ship an empty `command` and vice versa.
    private func buildEntry() -> MarketplaceEntry {
        MarketplaceEntry(
            name: trimmedName,
            detail: trimmedDetail,
            iconSystemName: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : icon.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            command: trimmedCommand.isEmpty ? nil : trimmedCommand,
            args: trimmedCommand.isEmpty ? [] : parsedArgs,
            url: trimmedURL.isEmpty ? nil : trimmedURL,
            env: [:],
            author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : author.trimmingCharacters(in: .whitespacesAndNewlines),
            homepage: homepage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(CodexTheme.divider)

            ScrollView {
                if let entry = publishedEntry {
                    successPanel(entry)
                        .padding(20)
                } else {
                    formFields
                        .padding(20)
                }
            }
            .frame(maxHeight: 440)

            Divider().background(CodexTheme.divider)
            footer
        }
        .frame(width: 560)
        .background(CodexTheme.mainBackground)
        .codexMenuHost()
        .environment(menuController)
        .onAppear {
            if publishedEntry == nil {
                DispatchQueue.main.async { nameFocused = true }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: publishedEntry == nil ? "paperplane" : "checkmark.seal.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(publishedEntry == nil ? tint : CodexTheme.accentOrange)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((publishedEntry == nil ? tint : CodexTheme.accentOrange).opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(publishedEntry == nil ? "Publish a plugin" : "Published")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                Text(publishedEntry == nil
                     ? "Add your plugin to the GrokCode marketplace."
                     : "It's now in your catalog. Share it with the community below.")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 26, height: 26)
                    .codexHover(cornerRadius: 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Form

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            field("Name") {
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($nameFocused)
                    .placeholderOverlay("Context7", visible: name.isEmpty, font: .system(size: 14))
                    .padding(10)
                    .background(inputBackground)
            }

            field("Description") {
                TextField("", text: $detail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .placeholderOverlay("Up-to-date code docs for any library",
                                        visible: detail.isEmpty, font: .system(size: 14))
                    .padding(10)
                    .background(inputBackground)
            }

            HStack(alignment: .top, spacing: 14) {
                field("Icon") {
                    HStack(spacing: 10) {
                        Image(systemName: iconPreviewName)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(tint)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(tint.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                            )
                        TextField("", text: $icon)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .placeholderOverlay("sf.symbol.name", visible: icon.isEmpty,
                                                font: .system(size: 13, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(inputBackground)
                    }
                }

                field("Type") {
                    menuPicker(label: kind.label, systemImage: kind.symbol) { close in
                        CodexMenuContainer {
                            ForEach(PluginKind.allCases) { option in
                                CodexMenuItem(
                                    title: option.label,
                                    systemImage: option.symbol,
                                    isSelected: option == kind
                                ) {
                                    kind = option; close()
                                }
                            }
                        }
                    }
                }
            }

            // stdio (command + args) and/or remote (url) depending on type.
            field(usesURL ? "Command (stdio)" : "Command") {
                TextField("", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .placeholderOverlay("npx", visible: command.isEmpty,
                                        font: .system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(inputBackground)
            }

            field("Arguments") {
                TextField("", text: $argsText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .placeholderOverlay("-y @upstash/context7-mcp", visible: argsText.isEmpty,
                                        font: .system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(inputBackground)
            }

            if usesURL {
                field("Server URL (remote)") {
                    TextField("", text: $url)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .placeholderOverlay("https://mcp.example.com/sse", visible: url.isEmpty,
                                            font: .system(size: 13, design: .monospaced))
                        .padding(10)
                        .background(inputBackground)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                field("Author") {
                    TextField("", text: $author)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .placeholderOverlay("your-handle", visible: author.isEmpty, font: .system(size: 14))
                        .padding(10)
                        .background(inputBackground)
                }
                field("Homepage") {
                    TextField("", text: $homepage)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .placeholderOverlay("https://…", visible: homepage.isEmpty, font: .system(size: 14))
                        .padding(10)
                        .background(inputBackground)
                }
            }
        }
    }

    /// Use the typed SF Symbol if it resolves to a real symbol; otherwise show a
    /// neutral placeholder so the preview tile never renders blank/broken.
    private var iconPreviewName: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil else {
            return "questionmark.square.dashed"
        }
        return trimmed
    }

    // MARK: Success panel

    private func successPanel(_ entry: MarketplaceEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preview row of the just-published plugin.
            HStack(spacing: 12) {
                Image(systemName: entry.iconSystemName ?? entry.kind.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(CodexTheme.accentOrange)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.accentOrange.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CodexTheme.textPrimary)
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(CodexTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodexTheme.sidebarBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CodexTheme.divider, lineWidth: 1)
            )

            Text("Want it in the public marketplace? Copy the manifest entry and open a pull request on the GrokCode marketplace repo.")
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // The manifest JSON, monospaced, so the user can eyeball it before
            // copying. Rendered by MarketplaceService for a stable, sorted diff.
            ScrollView(.vertical) {
                Text(MarketplaceService.shared.manifestEntryJSON(for: entry))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CodexTheme.composerBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button(action: copyManifest) {
                    HStack(spacing: 6) {
                        Image(systemName: didCopyManifest ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                        Text(didCopyManifest ? "Copied" : "Copy manifest entry")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(CodexTheme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.pillBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(CodexTheme.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 9)

                Button(action: openRepo) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 12, weight: .medium))
                        Text("Open marketplace repo")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(CodexTheme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.pillBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(CodexTheme.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 9)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if publishedEntry == nil, let validationMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11, weight: .regular))
                    Text(validationMessage)
                        .font(.system(size: 12))
                }
                .foregroundStyle(CodexTheme.textTertiary)
            }
            Spacer()

            if publishedEntry == nil {
                Button(action: onClose) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CodexTheme.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(CodexTheme.pillBackground)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 9)

                Button(action: publish) {
                    Text("Publish")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(canPublish ? CodexTheme.sendButtonActiveBackground : CodexTheme.sendButtonBackground)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 9)
                .disabled(!canPublish)
            } else {
                Button(action: onClose) {
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(CodexTheme.sendButtonActiveBackground)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(CodexPressableStyle())
                .codexHoverOverlay(cornerRadius: 9)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Reusable field chrome (matches AutomationEditorSheet)

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CodexTheme.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(CodexTheme.composerBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
            )
    }

    private func menuPicker<Menu: View>(
        label: String,
        systemImage: String,
        @ViewBuilder menu: @escaping (_ close: @escaping () -> Void) -> Menu
    ) -> some View {
        CodexMenuTrigger(minWidth: 220, highlightOnHover: false) { isOpen in
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textSecondary)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CodexTheme.composerBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isOpen ? CodexTheme.textTertiary : CodexTheme.composerBorder, lineWidth: 1)
            )
        } menu: { close in
            menu(close)
        }
    }

    // MARK: Actions

    private func publish() {
        guard canPublish else { return }
        let entry = buildEntry()
        onPublish(entry)           // persists + toasts (closes nothing here)
        withAnimation(CodexMotion.quickSpring) { publishedEntry = entry }
    }

    private func copyManifest() {
        guard let entry = publishedEntry else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MarketplaceService.shared.manifestEntryJSON(for: entry), forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { didCopyManifest = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { didCopyManifest = false }
            }
        }
    }

    private func openRepo() {
        NSWorkspace.shared.open(Self.repoURL)
    }
}
