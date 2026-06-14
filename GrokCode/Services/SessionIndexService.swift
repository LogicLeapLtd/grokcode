import Foundation

struct IndexedSession: Hashable {
    let id: String
    let cwd: URL
    let title: String
    let lastActive: Date
    /// Git branch resolved from `cwd`, when the folder is a repo (#26). Optional.
    var branch: String?
}

struct SessionIndexService {
    private let fileManager = FileManager.default
    private let sessionsRoot: URL

    init(sessionsRoot: URL? = nil) {
        let home = fileManager.homeDirectoryForCurrentUser
        self.sessionsRoot = sessionsRoot ?? home.appendingPathComponent(".grok/sessions")
    }

    func loadIndexedSessions() -> [IndexedSession] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sessions: [IndexedSession] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "summary.json" else { continue }
            guard let session = parseSummary(at: fileURL) else { continue }
            sessions.append(session)
        }

        return sessions.sorted { $0.lastActive > $1.lastActive }
    }

    func threads(for projectPath: URL, in sessions: [IndexedSession], limit: Int = 12) -> [ProjectThread] {
        let normalizedProject = projectPath.standardizedFileURL.path

        // Resolve the project's git branch once (rather than per session) so the
        // "By project → branch" grouping (#25) and per-row chips (#24) have a
        // value even when an individual session predates branch tracking.
        let projectBranch = AppViewModel.gitBranch(for: projectPath)

        return sessions
            .filter { session in
                let sessionPath = session.cwd.standardizedFileURL.path
                return sessionPath == normalizedProject
                    || sessionPath.hasPrefix(normalizedProject + "/")
            }
            .prefix(limit)
            .map { session in
                ProjectThread(
                    id: session.id,
                    title: session.title,
                    ageLabel: relativeAge(from: session.lastActive),
                    branch: session.branch ?? projectBranch
                )
            }
    }

    private func parseSummary(at url: URL) -> IndexedSession? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any],
              let id = info["id"] as? String,
              let cwdPath = info["cwd"] as? String else { return nil }

        // Prefer grok's own title; fall back to the session summary; finally fall
        // back to the first user message in the sibling updates.jsonl (#26) so
        // freshly-started chats read as their opening line instead of "Untitled".
        let rawTitle = (json["generated_title"] as? String)
            ?? (json["session_summary"] as? String)
        let trimmedTitle = (rawTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let displayTitle: String
        if trimmedTitle.isEmpty {
            displayTitle = firstUserMessageTitle(besideSummaryAt: url) ?? "Untitled chat"
        } else {
            displayTitle = trimmedTitle
        }

        let lastActive = parseDate(json["last_active_at"] as? String)
            ?? parseDate(json["updated_at"] as? String)
            ?? parseDate(json["created_at"] as? String)
            ?? .distantPast

        return IndexedSession(
            id: id,
            cwd: URL(fileURLWithPath: cwdPath).standardizedFileURL,
            title: displayTitle,
            lastActive: lastActive,
            branch: nil
        )
    }

    /// Read the first `user_message_chunk` text from the `updates.jsonl` that
    /// sits next to a session's `summary.json`, truncated to a sidebar-friendly
    /// length. Returns nil if the file is absent or has no user text yet (#26).
    private func firstUserMessageTitle(besideSummaryAt summaryURL: URL) -> String? {
        let updatesURL = summaryURL.deletingLastPathComponent().appendingPathComponent("updates.jsonl")
        guard let raw = try? String(contentsOf: updatesURL, encoding: .utf8) else { return nil }

        for line in raw.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let params = obj["params"] as? [String: Any],
                  let update = params["update"] as? [String: Any],
                  (update["sessionUpdate"] as? String) == "user_message_chunk" else { continue }

            // `content` is a single text object on this grok build, but tolerate
            // an array of content parts as well.
            if let content = update["content"] as? [String: Any],
               let text = content["text"] as? String {
                return Self.truncatedTitle(text)
            }
            if let parts = update["content"] as? [[String: Any]] {
                let joined = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
                if !joined.isEmpty { return Self.truncatedTitle(joined) }
            }
        }
        return nil
    }

    /// Collapse whitespace and clip to a tidy single-line title.
    private static func truncatedTitle(_ text: String, limit: Int = 60) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "Untitled chat" }
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Capitalised, human relative age (#29): "Today" / "Yesterday" / "3d" / "2w".
    private func relativeAge(from date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d" }
        return "\(days / 7)w"
    }
}
