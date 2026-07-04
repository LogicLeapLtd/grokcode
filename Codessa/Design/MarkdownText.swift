import SwiftUI
import AppKit

/// Lightweight markdown renderer for chat. Splits text into blocks (fenced code,
/// headings, lists, block-quotes, paragraphs) and renders inline spans
/// (`**bold**`, `*italic*`, `` `code` ``, links) via `AttributedString(markdown:)`.
/// Fenced code blocks become a monospaced card with a copy button. Always falls
/// back to plain text — never throws on malformed input.
struct MarkdownText: View {
    let text: String
    var font: Font = CodexTheme.bodyFont
    var color: Color = CodexTheme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MarkdownParser.blocks(from: text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let s):
            inline(s)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading(let level, let s):
            inline(s, weight: .semibold,
                   size: level <= 1 ? 20 : level == 2 ? 17 : 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•").foregroundStyle(CodexTheme.textTertiary)
                        inline(item).lineSpacing(3)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(idx + 1).").foregroundStyle(CodexTheme.textTertiary)
                            .font(font.monospacedDigit())
                        inline(item).lineSpacing(3)
                    }
                }
            }
        case .quote(let s):
            inline(s, color: CodexTheme.textSecondary)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(CodexTheme.divider).frame(width: 2)
                }
        case .code(let language, let code):
            CodeBlockCard(language: language, code: code)
        }
    }

    /// Render one paragraph of inline markdown, styling `code` spans monospaced.
    private func inline(_ string: String, weight: Font.Weight? = nil,
                        size: CGFloat? = nil, color overrideColor: Color? = nil) -> Text {
        let base = size.map { Font.system(size: $0) } ?? font
        var attr = (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
        // Inline `code` spans: slightly smaller monospaced, tinted ink on a soft
        // brand-tinted fill. Per-run foreground survives the trailing
        // `.foregroundColor` default below (that only colours runs without their
        // own colour), so code stays distinct from body text.
        let codeSize = (size ?? 14) * 0.92
        for run in attr.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attr[run.range].font = .system(size: codeSize, weight: .medium, design: .monospaced)
            attr[run.range].foregroundColor = CodexTheme.inlineCodeText
            attr[run.range].backgroundColor = CodexTheme.inlineCodeBackground
        }
        var text = Text(attr).font(weight.map { base.weight($0) } ?? base)
        text = text.foregroundColor(overrideColor ?? color)
        return text
    }
}

// MARK: - Fenced code block

private struct CodeBlockCard: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CodexTheme.textTertiary)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation(CodexMotion.quickSpring) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(copied ? CodexTheme.textSecondary : CodexTheme.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(CodexTheme.pillBackground)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(code, language: language))
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    }
}

// MARK: - Parser

enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, String)
    case bullets([String])
    case numbered([String])
    case quote(String)
    case code(language: String?, String)
}

enum MarkdownParser {
    static func blocks(from text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[i]); i += 1
                }
                i += 1 // consume closing fence
                blocks.append(.code(language: language.isEmpty ? nil : language,
                                    body.joined(separator: "\n")))
                continue
            }

            // Heading.
            if let hashes = trimmed.firstMatchHeadingLevel {
                flushParagraph()
                let content = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: hashes, content))
                i += 1
                continue
            }

            // Bullet list.
            if trimmed.isBullet {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isBullet {
                    items.append(lines[i].trimmingCharacters(in: .whitespaces).bulletContent)
                    i += 1
                }
                blocks.append(.bullets(items))
                continue
            }

            // Numbered list.
            if trimmed.isNumbered {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isNumbered {
                    items.append(lines[i].trimmingCharacters(in: .whitespaces).numberedContent)
                    i += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            // Block quote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                i += 1
                continue
            }

            // Blank line ends a paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }
}

private extension String {
    var firstMatchHeadingLevel: Int? {
        guard hasPrefix("#") else { return nil }
        let count = prefix(while: { $0 == "#" }).count
        guard count <= 6, dropFirst(count).first == " " else { return nil }
        return count
    }
    var isBullet: Bool {
        hasPrefix("- ") || hasPrefix("* ") || hasPrefix("+ ")
    }
    var bulletContent: String { String(dropFirst(2)) }
    var isNumbered: Bool {
        guard let dot = firstIndex(of: ".") else { return false }
        let num = self[startIndex..<dot]
        return !num.isEmpty && num.allSatisfy(\.isNumber) && index(after: dot) < endIndex && self[index(after: dot)] == " "
    }
    var numberedContent: String {
        guard let dot = firstIndex(of: ".") else { return self }
        return String(self[index(after: dot)...]).trimmingCharacters(in: .whitespaces)
    }
}
