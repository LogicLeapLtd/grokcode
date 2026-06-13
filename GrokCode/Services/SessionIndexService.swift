import Foundation

struct IndexedSession: Hashable {
    let id: String
    let cwd: URL
    let title: String
    let lastActive: Date
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
                    ageLabel: relativeAge(from: session.lastActive)
                )
            }
    }

    private func parseSummary(at url: URL) -> IndexedSession? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any],
              let id = info["id"] as? String,
              let cwdPath = info["cwd"] as? String else { return nil }

        let title = (json["generated_title"] as? String)
            ?? (json["session_summary"] as? String)
            ?? "Untitled chat"

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? "Untitled chat" : trimmedTitle

        let lastActive = parseDate(json["last_active_at"] as? String)
            ?? parseDate(json["updated_at"] as? String)
            ?? parseDate(json["created_at"] as? String)
            ?? .distantPast

        return IndexedSession(
            id: id,
            cwd: URL(fileURLWithPath: cwdPath).standardizedFileURL,
            title: displayTitle,
            lastActive: lastActive
        )
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func relativeAge(from date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d" }
        return "\(days / 7)w"
    }
}