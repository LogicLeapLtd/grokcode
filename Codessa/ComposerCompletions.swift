import Foundation

// MARK: - Composer completions (slash commands + @file mentions)
//
// Pure, AppViewModel-free logic backing the composer's inline completion menu.
// `PromptComposer` owns the SwiftUI surface; everything here is data + matching
// so it stays cheap, testable, and off the view layer.

// MARK: Fuzzy matching

enum ComposerFuzzy {
    /// Subsequence match with a light relevance score. Returns `nil` when
    /// `query`'s characters don't appear, in order, inside `candidate`.
    ///
    /// Scoring rewards: earlier first match, contiguous runs, and matches at the
    /// start of the string or right after a path separator / word boundary. An
    /// empty query matches everything with a neutral score.
    static func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased())
        guard !c.isEmpty else { return nil }

        var score = 0
        var qi = 0
        var lastMatch = -2
        var prev: Character? = nil

        for (ci, ch) in c.enumerated() {
            if qi < q.count, ch == q[qi] {
                // Contiguous with the previous matched char.
                if lastMatch == ci - 1 { score += 8 } else { score += 1 }
                // Boundary bonus (start, or after a separator / camel hump).
                if ci == 0 { score += 12 }
                else if let p = prev, "/._- ".contains(p) { score += 10 }
                // Earlier overall matches rank higher.
                score += max(0, 6 - ci / 4)
                lastMatch = ci
                qi += 1
            }
            prev = ch
        }
        return qi == q.count ? score : nil
    }

    /// Convenience: does `query` fuzzy-match `candidate` at all?
    static func matches(_ query: String, in candidate: String) -> Bool {
        score(query, in: candidate) != nil
    }
}

// MARK: Slash commands

/// A single "/" command surfaced above the composer. `Kind` tells the composer
/// how to treat the slash text after the action runs.
struct SlashCommand: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Navigates elsewhere — the slash text should be cleared on run.
        case navigation
        /// Mutates composer/session state but leaves the user on the chat.
        case action
        /// Expands an inline picker inside the completion menu (e.g. `/model`).
        case inlineModel
    }

    let id: String          // canonical trigger without the slash, e.g. "new"
    let title: String       // "/new"
    let subtitle: String
    let systemImage: String
    let kind: Kind

    /// All commands, in display order.
    static let all: [SlashCommand] = [
        SlashCommand(id: "new",         title: "/new",         subtitle: "Start a new chat",       systemImage: "square.and.pencil",            kind: .navigation),
        SlashCommand(id: "clear",       title: "/clear",       subtitle: "Clear the composer",     systemImage: "eraser",                       kind: .action),
        SlashCommand(id: "plan",        title: "/plan",        subtitle: "Toggle Plan mode",       systemImage: "list.bullet.clipboard",        kind: .action),
        SlashCommand(id: "model",       title: "/model",       subtitle: "Choose the model",       systemImage: "cpu",                          kind: .inlineModel),
        SlashCommand(id: "search",      title: "/search",      subtitle: "Open Search",            systemImage: "magnifyingglass",              kind: .navigation),
        SlashCommand(id: "plugins",     title: "/plugins",     subtitle: "Open Plugins",           systemImage: "puzzlepiece.extension",        kind: .navigation),
        SlashCommand(id: "automations", title: "/automations", subtitle: "Open Automations",       systemImage: "wand.and.stars",               kind: .navigation),
        SlashCommand(id: "settings",    title: "/settings",    subtitle: "Open Settings",          systemImage: "gearshape",                    kind: .navigation),
    ]

    /// Commands matching the text typed after the leading slash, best first.
    /// An empty query returns all commands in declared order.
    static func matching(_ query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return all }
        return all
            .compactMap { cmd -> (SlashCommand, Int)? in
                guard let s = ComposerFuzzy.score(query, in: cmd.id) else { return nil }
                return (cmd, s)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

// MARK: Active completion detection

/// What, if anything, the composer should be completing right now, derived
/// purely from the prompt text (caret assumed at the end — the composer is a
/// single growing field, so the live token is always the tail).
enum ComposerCompletion: Equatable {
    case none
    /// A "/command" being typed at the very start of the prompt.
    case slash(query: String)
    /// An "@mention" — `query` is the text after the most recent unclosed `@`.
    case file(query: String)

    /// Derive the active completion from the prompt text.
    static func detect(in text: String) -> ComposerCompletion {
        // Slash: only when the WHOLE prompt is a single "/word" (no space yet),
        // so "/" only triggers as a command at the very start of an empty-ish
        // composer — never mid-sentence.
        if text.first == "/", !text.contains(" "), !text.contains("\n") {
            return .slash(query: String(text.dropFirst()))
        }

        // File mention: find the last "@" that begins a fresh token (start of
        // string or preceded by whitespace) with no whitespace after it.
        if let query = trailingMention(in: text) {
            return .file(query: query)
        }
        return .none
    }

    /// The text after the most recent active "@" token, or nil if none is open.
    private static func trailingMention(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        // "@" must start a token: at string start or after whitespace.
        if atIndex > text.startIndex {
            let before = text[text.index(before: atIndex)]
            guard before.isWhitespace else { return nil }
        }
        let after = text[text.index(after: atIndex)...]
        // An open mention has no whitespace yet (still being typed).
        guard !after.contains(where: { $0.isWhitespace }) else { return nil }
        return String(after)
    }
}

// MARK: File index

/// A discovered file under the project root, surfaced in the `@` menu.
struct ComposerFileMatch: Identifiable, Hashable {
    /// Absolute path on disk (used to build the `[<path>]` attachment token).
    let absolutePath: String
    /// Path relative to the project root, for display (e.g. `Views/Foo.swift`).
    let relativePath: String
    var isDirectory: Bool

    var id: String { absolutePath }

    var fileName: String { (relativePath as NSString).lastPathComponent }

    var iconSystemName: String {
        if isDirectory { return "folder" }
        switch (relativePath as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp": return "photo"
        case "pdf": return "doc.richtext"
        case "swift", "py", "js", "ts", "tsx", "jsx", "rb", "go", "rs", "c", "cpp",
             "h", "hpp", "java", "kt", "json", "yml", "yaml", "sh", "rs.in": return "curlybraces"
        case "md", "txt", "rtf": return "doc.text"
        default: return "doc"
        }
    }
}

/// Cheap, bounded recursive scan of a project tree for `@file` autocomplete.
/// Caps depth and total count, and skips heavy/noise directories so listing
/// stays instant even on large repos.
enum ComposerFileIndex {
    /// Directory names never descended into.
    static let skippedDirectories: Set<String> = [
        ".git", "node_modules", "build", ".build", "DerivedData",
        ".next", "dist", "out", ".venv", "venv", "Pods", ".idea",
        ".swiftpm", "__pycache__", ".gradle", "target", "vendor", ".cache",
    ]

    static let maxDepth = 6
    static let maxFiles = 4000

    /// Walk `root` breadth-first, returning matches capped at `maxFiles`. Safe to
    /// call off the main actor (pure Foundation, no shared state).
    static func scan(root: URL) -> [ComposerFileMatch] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var results: [ComposerFileMatch] = []
        // (url, depth) queue for a bounded BFS.
        var queue: [(URL, Int)] = [(root.standardizedFileURL, 0)]
        var head = 0

        while head < queue.count, results.count < maxFiles {
            let (dir, depth) = queue[head]
            head += 1
            guard depth <= maxDepth else { continue }

            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries {
                if results.count >= maxFiles { break }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let name = url.lastPathComponent
                if isDir && skippedDirectories.contains(name) { continue }

                let abs = url.standardizedFileURL.path
                let rel = relative(abs, to: rootPath)
                results.append(ComposerFileMatch(absolutePath: abs, relativePath: rel, isDirectory: isDir))

                if isDir { queue.append((url, depth + 1)) }
            }
        }
        return results
    }

    /// Best matches for `query`, files first then directories, capped for display.
    static func matches(_ query: String, in index: [ComposerFileMatch], limit: Int = 8) -> [ComposerFileMatch] {
        guard !query.isEmpty else {
            // No query yet: show shallow, file-first entries as a starting point.
            return Array(
                index
                    .sorted { lhs, rhs in
                        if lhs.isDirectory != rhs.isDirectory { return !lhs.isDirectory }
                        return lhs.relativePath.count < rhs.relativePath.count
                    }
                    .prefix(limit)
            )
        }
        return index
            .compactMap { match -> (ComposerFileMatch, Int)? in
                // Score against both the file name and the full relative path,
                // taking the better of the two.
                let nameScore = ComposerFuzzy.score(query, in: match.fileName)
                let pathScore = ComposerFuzzy.score(query, in: match.relativePath)
                guard let best = [nameScore, pathScore].compactMap({ $0 }).max() else { return nil }
                return (match, best)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.relativePath.count < rhs.0.relativePath.count
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func relative(_ path: String, to root: String) -> String {
        guard path.hasPrefix(root) else { return path }
        var rel = String(path.dropFirst(root.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel.isEmpty ? (path as NSString).lastPathComponent : rel
    }
}
