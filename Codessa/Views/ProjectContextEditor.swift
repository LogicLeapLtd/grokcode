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

    /// The project whose context is being edited (for the header subtitle). Falls
    /// back to the selected project; the file name comes from the view model.
    private var projectName: String {
        model.selectedProject?.name ?? "Project"
    }

    private var fileName: String {
        model.projectContextFileName
    }

    var body: some View {
        PageScaffold(maxWidth: 820, scrolls: false) {
            header

            Text("Rules and context Grok loads for this project on every run. Saved to \(fileName) at the project root.")
                .font(.system(size: 13))
                .foregroundStyle(CodexTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            editor

            footer
        }
        .onAppear { DispatchQueue.main.async { editorFocused = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: cancel) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodexTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(CodexTheme.pillBackground))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back")

            Image(systemName: "doc.text")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CodexTheme.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(1)
                Text(projectName)
                    .font(.system(size: 13))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
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
            .frame(minHeight: 440)
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
        model.closeProjectContext()
    }
}
