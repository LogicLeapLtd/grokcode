import SwiftUI

/// A sheet for editing a project's agent-context file (its `AGENTS.md` / `GROK.md`
/// — the per-repo instructions Grok loads on every run for that project). Shown
/// when `model.projectContextOpen`; edits `model.projectContextDraft` in place and
/// writes it back via `model.saveProjectContext()` on Save.
///
/// Styled and sized to match `AutomationEditorSheet`: a 540pt-wide card with a
/// header (file name + project name + close), a large monospaced editor, a short
/// helper line, and a Cancel / Save footer. Because a sheet is its own window it
/// carries its own `CodexMenuController` + `.codexMenuHost()` so any custom
/// dropdowns render above the sheet rather than behind it.
struct ProjectContextEditor: View {
    @Environment(AppViewModel.self) private var model

    @FocusState private var editorFocused: Bool

    /// The sheet is its own window, so it needs its own menu host — otherwise the
    /// custom dropdowns render on the main window's host, behind the sheet.
    @State private var menuController = CodexMenuController(installsKeyboardMonitor: false)

    /// The project whose context is being edited (for the header subtitle). Falls
    /// back to the selected project; the file name comes from the view model.
    private var projectName: String {
        model.selectedProject?.name ?? "Project"
    }

    private var fileName: String {
        model.projectContextFileName
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(CodexTheme.divider)

            VStack(alignment: .leading, spacing: 12) {
                Text("Rules and context Grok loads for this project on every run. Saved to \(fileName) at the project root.")
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                editor
            }
            .padding(20)

            Divider().background(CodexTheme.divider)

            footer
        }
        .frame(width: 540)
        .background(CodexTheme.mainBackground)
        .codexMenuHost()
        .environment(menuController)
        .onAppear { DispatchQueue.main.async { editorFocused = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Text(projectName)
                    .font(.system(size: 12))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: cancel) {
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

    // MARK: - Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.projectContextDraft.isEmpty {
                Text("# Project rules\n\nAdd guidance, conventions, and context for this project…")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextEditor(text: Binding(
                get: { model.projectContextDraft },
                set: { model.projectContextDraft = $0 }
            ))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(CodexTheme.textPrimary)
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .padding(6)
            .frame(minHeight: 320)
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(CodexTheme.composerBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(CodexTheme.composerBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(action: cancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.pillBackground)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(cornerRadius: 9)

            Button(action: { model.saveProjectContext() }) {
                Text("Save")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodexTheme.sendButtonActiveForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(CodexTheme.sendButtonActiveBackground)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(CodexPressableStyle())
            .codexHoverOverlay(cornerRadius: 9)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// Dismiss without writing the draft back to disk.
    private func cancel() {
        model.projectContextOpen = false
    }
}
