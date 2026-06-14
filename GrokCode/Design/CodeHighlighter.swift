import SwiftUI

// Lightweight, dependency-free syntax + diff highlighter for code surfaces.
//
// `highlight(_:language:)` runs a single forward scan over the source, tagging
// comments, string literals, numbers, keywords and (where cheap) common type
// names with adaptive `CodexTheme` syntax tokens. It is deliberately
// approximate — a tokenizer, not a parser — and ALWAYS degrades to plain text
// rather than crashing or producing garbage on odd input.
//
// `diffAttributed(_:)` colours whole lines for tool detail cards: a `+` prefix
// is treated as an added line, `-` as removed, `$ ` as a shell command.
enum CodeHighlighter {

    /// Above this many characters we skip highlighting entirely and return the
    /// input verbatim — keeps rendering snappy for large pasted blobs.
    private static let maxLength = 20_000

    // MARK: - Public API

    /// Syntax-highlight `code` for the given `language` (case-insensitive,
    /// tolerant of aliases like `ts`, `js`, `sh`). Unknown languages, oversized
    /// input, or any failure return `AttributedString(code)` plain.
    static func highlight(_ code: String, language: String?) -> AttributedString {
        guard !code.isEmpty, code.count <= maxLength else {
            return AttributedString(code)
        }
        guard let lang = LanguageProfile.resolve(language) else {
            return AttributedString(code)
        }
        return tokenize(code, profile: lang)
    }

    /// Colour whole lines for diff/shell detail surfaces.
    static func diffAttributed(_ text: String) -> AttributedString {
        guard !text.isEmpty, text.count <= maxLength else {
            return AttributedString(text)
        }

        var result = AttributedString()
        // Preserve the original line structure exactly (including a trailing
        // newline) by splitting on "\n" and re-joining with coloured newlines.
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            var segment = AttributedString(line)
            if let color = diffColor(for: line) {
                segment.foregroundColor = color
            }
            result.append(segment)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    // MARK: - Diff line classification

    private static func diffColor(for line: String) -> Color? {
        // Inspect the first non-leading-marker character. Diff markers live at
        // column 0; we deliberately do NOT trim, so indentation is untouched.
        guard let first = line.first else { return nil }
        switch first {
        case "+":
            return CodexTheme.syntaxDiffAdded
        case "-":
            return CodexTheme.syntaxDiffRemoved
        case "$":
            // Treat "$ " (shell prompt) as a command line.
            if line.count >= 2 {
                let second = line[line.index(after: line.startIndex)]
                if second == " " { return CodexTheme.accentOrange }
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Tokenizer

    private static func tokenize(_ code: String, profile: LanguageProfile) -> AttributedString {
        var result = AttributedString()
        let scalars = Array(code.unicodeScalars)
        let count = scalars.count
        var i = 0

        // Flush a run of plain (uncoloured) source into the result.
        func appendPlain(_ from: Int, _ to: Int) {
            guard from < to else { return }
            let slice = String(String.UnicodeScalarView(scalars[from..<to]))
            result.append(AttributedString(slice))
        }

        // Append a coloured run [from, to).
        func appendColored(_ from: Int, _ to: Int, _ color: Color) {
            guard from < to else { return }
            let slice = String(String.UnicodeScalarView(scalars[from..<to]))
            var seg = AttributedString(slice)
            seg.foregroundColor = color
            result.append(seg)
        }

        var plainStart = 0

        while i < count {
            let c = scalars[i]

            // --- Line comments (e.g. //, #) ---
            if let marker = profile.lineComment, matches(scalars, i, marker) {
                appendPlain(plainStart, i)
                var j = i + marker.count
                while j < count && scalars[j] != "\n" { j += 1 }
                appendColored(i, j, CodexTheme.syntaxComment)
                i = j
                plainStart = i
                continue
            }

            // --- Block comments (e.g. /* ... */) ---
            if let (open, close) = profile.blockComment, matches(scalars, i, open) {
                appendPlain(plainStart, i)
                var j = i + open.count
                while j < count && !matches(scalars, j, close) { j += 1 }
                if j < count { j += close.count }       // consume closing marker if present
                appendColored(i, min(j, count), CodexTheme.syntaxComment)
                i = min(j, count)
                plainStart = i
                continue
            }

            // --- String literals ---
            if profile.stringDelimiters.contains(c) {
                appendPlain(plainStart, i)
                let quote = c
                var j = i + 1
                while j < count {
                    let s = scalars[j]
                    if s == "\\" && profile.allowsEscapes {
                        j += 2                            // skip escaped char
                        continue
                    }
                    if s == quote { j += 1; break }
                    // Strings don't span newlines for these simple languages
                    // (except triple-quoted, which we don't special-case) — bail
                    // to avoid swallowing the rest of the file on an unterminated
                    // quote.
                    if s == "\n" { break }
                    j += 1
                }
                appendColored(i, min(j, count), CodexTheme.syntaxString)
                i = min(j, count)
                plainStart = i
                continue
            }

            // --- Numbers ---
            if isDigit(c) && isWordBoundary(scalars, before: i) {
                appendPlain(plainStart, i)
                var j = i + 1
                while j < count && isNumberScalar(scalars[j]) { j += 1 }
                appendColored(i, j, CodexTheme.syntaxNumber)
                i = j
                plainStart = i
                continue
            }

            // --- Identifiers / keywords / types ---
            if isIdentifierStart(c) {
                let wordStart = i
                var j = i + 1
                while j < count && isIdentifierPart(scalars[j]) { j += 1 }
                let word = String(String.UnicodeScalarView(scalars[wordStart..<j]))
                if profile.keywords.contains(word) {
                    appendPlain(plainStart, wordStart)
                    appendColored(wordStart, j, CodexTheme.syntaxKeyword)
                    plainStart = j
                } else if profile.types.contains(word) || looksLikeType(word, profile: profile) {
                    appendPlain(plainStart, wordStart)
                    appendColored(wordStart, j, CodexTheme.syntaxType)
                    plainStart = j
                }
                // else: leave as plain, handled by the next flush
                i = j
                continue
            }

            i += 1
        }

        appendPlain(plainStart, count)
        return result
    }

    // MARK: - Scalar helpers

    /// Does `scalars[i...]` start with the scalars of `marker`?
    private static func matches(_ scalars: [Unicode.Scalar], _ i: Int, _ marker: [Unicode.Scalar]) -> Bool {
        guard i + marker.count <= scalars.count else { return false }
        for k in 0..<marker.count where scalars[i + k] != marker[k] { return false }
        return true
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool {
        s >= "0" && s <= "9"
    }

    /// Accept digits plus the usual numeric-literal punctuation/letters so
    /// things like `0xFF`, `1_000`, `3.14`, `1e9`, `0b10`, `1.0f` stay one run.
    private static func isNumberScalar(_ s: Unicode.Scalar) -> Bool {
        if isDigit(s) { return true }
        switch s {
        case ".", "_", "x", "X", "b", "B", "o", "O", "e", "E",
             "a", "A", "c", "C", "d", "D", "f", "F", "+", "-":
            return true
        default:
            return false
        }
    }

    private static func isIdentifierStart(_ s: Unicode.Scalar) -> Bool {
        (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || s == "_" || s == "$"
    }

    private static func isIdentifierPart(_ s: Unicode.Scalar) -> Bool {
        isIdentifierStart(s) || isDigit(s)
    }

    /// True when the scalar immediately before `i` is not part of an identifier
    /// (so we don't colour the `123` inside `var123` as a number).
    private static func isWordBoundary(_ scalars: [Unicode.Scalar], before i: Int) -> Bool {
        guard i > 0 else { return true }
        return !isIdentifierPart(scalars[i - 1])
    }

    /// Heuristic: a CapitalizedWord in a language that uses type-case is likely
    /// a type. Cheap and language-gated to avoid colouring prose.
    private static func looksLikeType(_ word: String, profile: LanguageProfile) -> Bool {
        guard profile.capitalizedIsType, let first = word.unicodeScalars.first else { return false }
        guard first >= "A" && first <= "Z" else { return false }
        // Require at least one lowercase letter so SHOUTY_CONSTANTS don't qualify.
        return word.unicodeScalars.contains { $0 >= "a" && $0 <= "z" }
    }
}

// MARK: - Language profiles

/// A compact description of a language's lexical surface: comment markers,
/// string delimiters, keyword/type sets. Intentionally small and fast.
private struct LanguageProfile {
    let lineComment: [Unicode.Scalar]?
    let blockComment: ([Unicode.Scalar], [Unicode.Scalar])?
    let stringDelimiters: Set<Unicode.Scalar>
    let allowsEscapes: Bool
    let keywords: Set<String>
    let types: Set<String>
    let capitalizedIsType: Bool

    init(lineComment: String?,
         blockComment: (String, String)?,
         stringDelimiters: Set<Unicode.Scalar>,
         allowsEscapes: Bool,
         keywords: Set<String>,
         types: Set<String> = [],
         capitalizedIsType: Bool = false) {
        self.lineComment = lineComment.map { Array($0.unicodeScalars) }
        self.blockComment = blockComment.map { (Array($0.0.unicodeScalars), Array($0.1.unicodeScalars)) }
        self.stringDelimiters = stringDelimiters
        self.allowsEscapes = allowsEscapes
        self.keywords = keywords
        self.types = types
        self.capitalizedIsType = capitalizedIsType
    }

    /// Map a free-form language tag to a profile, or `nil` to skip highlighting.
    static func resolve(_ raw: String?) -> LanguageProfile? {
        guard let raw, !raw.isEmpty else { return nil }
        let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch key {
        case "swift":
            return swift
        case "javascript", "js", "jsx", "typescript", "ts", "tsx":
            return javascript
        case "python", "py":
            return python
        case "json", "jsonc":
            return json
        case "bash", "sh", "shell", "zsh", "console", "shell-session":
            return bash
        default:
            return nil
        }
    }

    // MARK: Concrete profiles

    static let swift = LanguageProfile(
        lineComment: "//",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\""],
        allowsEscapes: true,
        keywords: [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
            "func", "import", "init", "inout", "internal", "let", "open", "operator",
            "private", "precedencegroup", "protocol", "public", "rethrows", "static",
            "struct", "subscript", "typealias", "var", "actor", "async", "await",
            "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
            "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
            "as", "catch", "false", "is", "nil", "self", "Self", "super", "throw",
            "throws", "true", "try", "some", "any", "weak", "unowned", "lazy", "final",
            "override", "mutating", "nonmutating", "convenience", "required", "indirect",
            "dynamic", "optional", "get", "set", "willSet", "didSet"
        ],
        types: [
            "Int", "String", "Double", "Float", "Bool", "Character", "Array", "Dictionary",
            "Set", "Optional", "Any", "AnyObject", "Void", "Result", "Error", "Data"
        ],
        capitalizedIsType: true
    )

    static let javascript = LanguageProfile(
        lineComment: "//",
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"],
        allowsEscapes: true,
        keywords: [
            "abstract", "any", "as", "async", "await", "break", "case", "catch", "class",
            "const", "continue", "debugger", "declare", "default", "delete", "do", "else",
            "enum", "export", "extends", "false", "finally", "for", "from", "function",
            "get", "if", "implements", "import", "in", "instanceof", "interface", "let",
            "namespace", "new", "null", "of", "package", "private", "protected", "public",
            "readonly", "return", "set", "static", "super", "switch", "this", "throw",
            "true", "try", "type", "typeof", "undefined", "var", "void", "while", "with",
            "yield", "keyof", "infer", "satisfies", "override"
        ],
        types: [
            "string", "number", "boolean", "object", "symbol", "bigint", "unknown",
            "never", "Array", "Promise", "Record", "Map", "Set", "Object", "String",
            "Number", "Boolean", "Date", "RegExp", "Error", "JSON", "Math"
        ],
        capitalizedIsType: true
    )

    static let python = LanguageProfile(
        lineComment: "#",
        blockComment: nil,
        stringDelimiters: ["\"", "'"],
        allowsEscapes: true,
        keywords: [
            "False", "None", "True", "and", "as", "assert", "async", "await", "break",
            "class", "continue", "def", "del", "elif", "else", "except", "finally", "for",
            "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
            "or", "pass", "raise", "return", "try", "while", "with", "yield", "match",
            "case", "self", "cls"
        ],
        types: [
            "int", "float", "str", "bool", "bytes", "list", "dict", "tuple", "set",
            "frozenset", "complex", "object", "type", "Any", "Optional", "List", "Dict",
            "Tuple", "Set", "Union", "Callable"
        ],
        capitalizedIsType: false
    )

    static let json = LanguageProfile(
        lineComment: "//",                                // tolerated for jsonc
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\""],
        allowsEscapes: true,
        keywords: ["true", "false", "null"],
        types: [],
        capitalizedIsType: false
    )

    static let bash = LanguageProfile(
        lineComment: "#",
        blockComment: nil,
        stringDelimiters: ["\"", "'"],
        allowsEscapes: true,
        keywords: [
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "select", "while",
            "until", "do", "done", "in", "function", "time", "coproc", "return", "break",
            "continue", "export", "local", "readonly", "declare", "unset", "shift",
            "source", "alias", "echo", "cd", "exit", "set", "eval", "exec", "trap"
        ],
        types: [],
        capitalizedIsType: false
    )
}
