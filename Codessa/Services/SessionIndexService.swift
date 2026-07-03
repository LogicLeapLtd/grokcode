import Foundation

/// Whether a session is an ordinary chat or a subagent spawned by another chat.
enum SessionKind: String, Hashable {
    case normal
    case subagent
}

struct IndexedSession: Hashable {
    let id: String
    let cwd: URL
    let title: String
    let lastActive: Date
    /// Git branch resolved from `cwd`, when the folder is a repo (#26). Optional.
    var branch: String?
    /// Normal chat vs. subagent session (from `session_kind` in summary.json).
    var kind: SessionKind = .normal
    /// The agent type for a subagent (from `agent_name`), e.g. "Explore". Optional.
    var agentName: String?
    /// For subagents, the id of the chat that spawned it. Resolved by scanning the
    /// parent's `updates.jsonl` for the `subagent_spawned` event that names this
    /// session as its `child_session_id`. nil for ordinary chats (and for any
    /// subagent whose parent can't be found).
    var parentSessionId: String?
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

        // Keep each session's on-disk directory alongside it so we can resolve
        // subagent → parent links from the parents' `updates.jsonl` without a
        // second full directory walk.
        var entries: [(session: IndexedSession, dir: URL)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "summary.json" else { continue }
            guard let session = parseSummary(at: fileURL) else { continue }
            entries.append((session, fileURL.deletingLastPathComponent()))
        }

        let parentBySubagent = resolveSubagentParents(in: entries)

        var sessions = entries.map(\.session)
        for index in sessions.indices where sessions[index].kind == .subagent {
            sessions[index].parentSessionId = parentBySubagent[sessions[index].id]
        }

        return sessions.sorted { $0.lastActive > $1.lastActive }
    }

    /// Build a `[subagentId: parentSessionId]` map by scanning the `updates.jsonl`
    /// of candidate parent chats for `subagent_spawned` events. A parent always
    /// shares the subagent's `cwd` (and so its encoded-cwd directory), so we only
    /// scan sessions that live in a directory which actually contains a subagent —
    /// keeping the scan to the handful of projects that used subagents, not the
    /// whole history. No-op (and zero file reads) when there are no subagents.
    private func resolveSubagentParents(
        in entries: [(session: IndexedSession, dir: URL)]
    ) -> [String: String] {
        let subagentIds = Set(entries.filter { $0.session.kind == .subagent }.map { $0.session.id })
        guard !subagentIds.isEmpty else { return [:] }

        // Encoded-cwd directories (one level up from a session folder) that hold a
        // subagent — only these can hold its parent.
        let cwdDirsWithSubagents = Set(entries
            .filter { $0.session.kind == .subagent }
            .map { $0.dir.deletingLastPathComponent().path })

        let sessionIdByDir = Dictionary(
            entries.map { ($0.dir.path, $0.session.id) },
            uniquingKeysWith: { first, _ in first }
        )

        var map: [String: String] = [:]
        for entry in entries where entry.session.kind != .subagent {
            guard cwdDirsWithSubagents.contains(entry.dir.deletingLastPathComponent().path) else { continue }
            let updatesURL = entry.dir.appendingPathComponent("updates.jsonl")
            guard let raw = try? String(contentsOf: updatesURL, encoding: .utf8),
                  raw.contains("subagent_spawned") else { continue }

            let parentId = sessionIdByDir[entry.dir.path] ?? entry.session.id
            for line in raw.split(whereSeparator: \.isNewline) {
                guard line.contains("child_session_id"),
                      let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let params = obj["params"] as? [String: Any],
                      let update = params["update"] as? [String: Any],
                      (update["sessionUpdate"] as? String) == "subagent_spawned",
                      let childId = update["child_session_id"] as? String,
                      subagentIds.contains(childId) else { continue }
                map[childId] = parentId
            }
        }
        return map
    }

    func threads(
        for projectPath: URL, in sessions: [IndexedSession], branch: String? = nil, limit: Int = 12
    ) -> [ProjectThread] {
        let normalizedProject = projectPath.standardizedFileURL.path

        // The project's git branch, used for the "By project → branch" grouping
        // (#25) and per-row chips (#24) when an individual session predates
        // branch tracking. Callers that already resolved it (AppViewModel keeps
        // it on the project) pass it in so we don't re-read `.git/HEAD` from
        // disk a second time; otherwise resolve it here.
        let projectBranch = branch ?? AppViewModel.gitBranch(for: projectPath)

        let projectSessions = sessions.filter { session in
            let sessionPath = session.cwd.standardizedFileURL.path
            return sessionPath == normalizedProject
                || sessionPath.hasPrefix(normalizedProject + "/")
        }

        func makeThread(_ session: IndexedSession, subThreads: [ProjectThread] = []) -> ProjectThread {
            ProjectThread(
                id: session.id,
                title: session.title,
                ageLabel: relativeAge(from: session.lastActive),
                branch: session.branch ?? projectBranch,
                isSubagent: session.kind == .subagent,
                agentName: session.agentName,
                subThreads: subThreads
            )
        }

        // Bucket subagents by the parent that spawned them, keeping spawn order
        // (oldest-first) so nested rows read top-to-bottom as they were launched.
        let normalIds = Set(projectSessions.filter { $0.kind != .subagent }.map(\.id))
        var childrenByParent: [String: [IndexedSession]] = [:]
        for session in projectSessions where session.kind == .subagent {
            if let parentId = session.parentSessionId, normalIds.contains(parentId) {
                childrenByParent[parentId, default: []].append(session)
            }
        }
        for parentId in childrenByParent.keys {
            childrenByParent[parentId]?.sort { $0.lastActive < $1.lastActive }
        }

        // Walk sessions newest-first, nesting each chat's subagents beneath it.
        // A subagent whose parent isn't in this project (e.g. trimmed away) is
        // surfaced at the top level so it's never silently dropped.
        var topLevel: [ProjectThread] = []
        for session in projectSessions {
            if session.kind == .subagent {
                if let parentId = session.parentSessionId, normalIds.contains(parentId) {
                    continue   // rendered nested under its parent
                }
                topLevel.append(makeThread(session))   // orphan → top level
            } else {
                let children = (childrenByParent[session.id] ?? []).map { makeThread($0) }
                topLevel.append(makeThread(session, subThreads: children))
            }
        }

        return Array(topLevel.prefix(limit))
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

        let kind: SessionKind = (json["session_kind"] as? String) == "subagent" ? .subagent : .normal
        let agentName = (json["agent_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return IndexedSession(
            id: id,
            cwd: URL(fileURLWithPath: cwdPath).standardizedFileURL,
            title: displayTitle,
            lastActive: lastActive,
            branch: nil,
            kind: kind,
            agentName: (agentName?.isEmpty == false) ? agentName : nil
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

    // MARK: - Transcript loading (open a past chat)

    /// Locate the on-disk folder for a session id by matching `info.id` inside
    /// each `summary.json`. Returns the directory that also holds `updates.jsonl`.
    func sessionDirectory(for sessionId: String) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "summary.json" else { continue }
            if let data = try? Data(contentsOf: fileURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let info = json["info"] as? [String: Any],
               (info["id"] as? String) == sessionId {
                return fileURL.deletingLastPathComponent()
            }
        }
        return nil
    }

    /// Reconstruct a session's conversation from its `updates.jsonl` so a past
    /// chat opens populated. Walks the streamed events (user/agent message &
    /// thought chunks, tool calls) and rebuilds the `[ChatMessage]` the chat view
    /// renders. Returns nil if the session folder / file can't be found.
    func loadMessages(for sessionId: String) -> [ChatMessage]? {
        guard let dir = sessionDirectory(for: sessionId) else { return nil }
        let updatesURL = dir.appendingPathComponent("updates.jsonl")
        guard let raw = try? String(contentsOf: updatesURL, encoding: .utf8) else { return nil }

        var messages: [ChatMessage] = []
        var assistant: ChatMessage?
        func flushAssistant() {
            if let a = assistant, !(a.text.isEmpty && a.reasoning.isEmpty && a.toolCalls.isEmpty) {
                messages.append(a)
            }
            assistant = nil
        }

        for line in raw.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let params = obj["params"] as? [String: Any],
                  let update = params["update"] as? [String: Any],
                  let kind = update["sessionUpdate"] as? String else { continue }

            switch kind {
            case "user_message_chunk":
                let text = Self.chunkText(update)
                flushAssistant()
                if let last = messages.indices.last, messages[last].role == .user {
                    messages[last].text += text
                } else if !text.isEmpty {
                    messages.append(ChatMessage(role: .user, text: text))
                }
            case "agent_thought_chunk":
                if assistant == nil { assistant = ChatMessage(role: .assistant, text: "") }
                assistant?.reasoning += Self.chunkText(update)
            case "agent_message_chunk":
                if assistant == nil { assistant = ChatMessage(role: .assistant, text: "") }
                assistant?.text += Self.chunkText(update)
            case "tool_call", "tool_call_update":
                if assistant == nil { assistant = ChatMessage(role: .assistant, text: "") }
                if var a = assistant, let info = Self.toolInfo(update) {
                    if let i = a.toolCalls.firstIndex(where: { $0.id == info.id }) {
                        if !info.title.isEmpty { a.toolCalls[i].title = info.title }
                        if !info.kind.isEmpty { a.toolCalls[i].kind = info.kind }
                        if !info.detail.isEmpty { a.toolCalls[i].detail = info.detail }
                        a.toolCalls[i].status = .done
                    } else {
                        a.toolCalls.append(ToolCallEntry(
                            id: info.id, title: info.title, kind: info.kind,
                            detail: info.detail, status: .done))
                    }
                    assistant = a
                }
            default:
                continue
            }
        }
        flushAssistant()

        // Lift inline `[<path>]` attachment tokens out of past user turns into the
        // structured `attachments` field, so history renders chips (with image
        // preview / fullscreen) instead of raw bracketed paths.
        for index in messages.indices where messages[index].role == .user {
            let (clean, paths) = Self.splitAttachments(from: messages[index].text)
            if !paths.isEmpty {
                messages[index].text = clean
                messages[index].attachments = paths
            }
        }
        return messages
    }

    /// Strip `[<absolute-path>]` attachment tokens from `text`, returning the
    /// cleaned text plus the extracted paths (in order).
    static func splitAttachments(from text: String) -> (text: String, paths: [String]) {
        let pattern = "\\[/[^\\]]+\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, []) }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, []) }
        let paths = matches.map { String(ns.substring(with: $0.range).dropFirst().dropLast()) }
        var cleaned = text
        for match in matches.reversed() {
            if let r = Range(match.range, in: cleaned) { cleaned.removeSubrange(r) }
        }
        cleaned = cleaned
            .replacingOccurrences(of: "\n+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, paths)
    }

    /// Text from an update's `content`, whether a single object or an array.
    private static func chunkText(_ update: [String: Any]) -> String {
        if let content = update["content"] as? [String: Any], let t = content["text"] as? String {
            return t
        }
        if let parts = update["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    /// Reconstruct a tool row from a `tool_call` / `tool_call_update` event,
    /// mirroring the live `GrokAgentSession` mapping.
    private static func toolInfo(_ update: [String: Any]) -> (id: String, title: String, kind: String, detail: String)? {
        guard let id = update["toolCallId"] as? String else { return nil }
        let title = (update["title"] as? String) ?? ""
        let kind = (update["kind"] as? String) ?? ""
        var parts: [String] = []
        if let rawInput = update["rawInput"] as? [String: Any] {
            if let command = rawInput["command"] as? String, !command.isEmpty {
                parts.append("$ " + command)
            } else if let command = rawInput["command"] as? [String], !command.isEmpty {
                parts.append("$ " + command.joined(separator: " "))
            }
        }
        if let content = update["content"] as? [[String: Any]] {
            for item in content {
                switch item["type"] as? String {
                case "diff":
                    let newText = item["newText"] as? String ?? ""
                    let oldText = item["oldText"] as? String
                    if let oldText, !oldText.isEmpty { parts.append("- " + oldText) }
                    if !newText.isEmpty { parts.append("+ " + newText) }
                case "content":
                    if let inner = item["content"] as? [String: Any],
                       let t = inner["text"] as? String, !t.isEmpty { parts.append(t) }
                default:
                    if let t = item["text"] as? String, !t.isEmpty { parts.append(t) }
                }
            }
        }
        return (id, title, kind, parts.joined(separator: "\n"))
    }
}
