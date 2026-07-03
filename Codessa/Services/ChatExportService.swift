import Foundation

/// Renders a conversation to clean Markdown for "Export chat" / copy-as-markdown
/// flows. Pure, stateless — every surface (chat header menu, ⌘K palette, etc.)
/// calls the same `markdown(from:title:)` so exports stay consistent.
enum ChatExportService {
    /// Render `messages` as a Markdown document titled `title`.
    ///
    /// - User turns become a `## You` section, assistant turns a `## Grok`
    ///   section (matching `ChatMessage.Role.label`); any other role uses its
    ///   own label.
    /// - Only `message.text` is emitted (reasoning traces are intentionally
    ///   omitted from the export).
    /// - Empty, still-streaming, and queued (not-yet-sent) messages are skipped
    ///   so a half-finished turn never lands in the file.
    static func markdown(from messages: [ChatMessage], title: String) -> String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        lines.append("# \(heading.isEmpty ? "Grok chat" : heading)")

        for message in messages {
            // Skip in-flight / queued turns and anything with no body text.
            guard !message.isStreaming, !message.isQueued else { continue }
            let body = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            lines.append("")
            lines.append("## \(message.role.label)")
            lines.append("")
            lines.append(body)
        }

        // Trailing newline so the file ends cleanly.
        return lines.joined(separator: "\n") + "\n"
    }

    /// A filesystem-safe `.md` filename derived from `title`. Collapses
    /// whitespace to hyphens, strips characters illegal in file names, and falls
    /// back to a generic name when the title is empty.
    static func filename(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "grok-chat" : trimmed

        // Replace path separators / illegal characters, collapse whitespace runs.
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var slug = base
            .components(separatedBy: illegal)
            .joined(separator: "-")
        slug = slug
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        // Collapse any accidental double hyphens and trim edge hyphens.
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-."))

        let safe = slug.isEmpty ? "grok-chat" : slug
        return "\(safe).md"
    }
}
