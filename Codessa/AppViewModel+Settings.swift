import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Settings lane view-model methods
//
// Everything the rebuilt `SettingsView` needs that isn't already on the shared
// `AppViewModel` contract lives here. Stored properties stay in
// `AppViewModel.swift` (Foundation owns that file) — this extension only adds
// behaviour, and any *transient* UI state (the MCP list, cache size, toasts)
// is held as `@State` in `SettingsView`, fed by the `async` methods below which
// return their results rather than mutating the view model.
//
// The MCP server list is read from `grok mcp list` and toggled by editing
// `~/.grok/config.toml` directly (the CLI has no enable/disable verb), so the
// Settings UI stays fully self-contained and never depends on another lane.

/// One configured MCP server, as surfaced in the Performance section.
struct MCPServerInfo: Identifiable, Hashable {
    /// Server name (the `[mcp_servers.<name>]` key); also the row id.
    var id: String { name }
    let name: String
    /// The launch command / URL summary shown under the name.
    let detail: String
    /// Whether the server is currently enabled (false ⇒ `(disabled)`).
    let enabled: Bool
}

/// On-disk session storage stats for the Data section.
struct SessionStorageInfo: Equatable {
    let bytes: Int64
    let count: Int

    /// Pretty size string, e.g. "436 MB".
    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct SettingsDiagnosticsBundle: Codable {
    let generatedAt: Date
    let appVersion: String
    let grokAvailable: Bool
    let selectedProvider: String
    let projectCount: Int
    let sessionCount: Int
    let preferences: AppPreferences?
    let system: [String: String]
}

extension AppViewModel {

    // MARK: - General: default project

    /// Persist a launch default project (or "no project") so a new chat opens
    /// against it. Reuses the same select path the sidebar uses.
    func setDefaultProject(_ project: Project?) {
        if let project {
            selectProject(project)
        } else {
            clearProjectSelection()
        }
    }

    /// The current "default project" label for the General picker.
    var defaultProjectLabel: String {
        if workWithoutProject { return "Don't work in a project" }
        return selectedProject?.name ?? "Choose a project"
    }

    // MARK: - Performance: MCP servers

    /// Load the configured MCP servers via `grok mcp list`. Runs off the main
    /// actor; returns the parsed list. Safe to call from `.task`/`onAppear`.
    func loadMCPServers() async -> [MCPServerInfo] {
        await Self.mcpBridge.list()
    }

    /// Flip a server's enabled flag in `~/.grok/config.toml`, then return the
    /// reloaded list so the caller can refresh its `@State`.
    /// Returns the reloaded list on success, or nil if the config write failed
    /// (so the UI can keep the optimistic state and surface an error).
    func setMCPServer(_ server: MCPServerInfo, enabled: Bool) async -> [MCPServerInfo]? {
        let ok = await Self.mcpBridge.setEnabled(name: server.name, enabled: enabled)
        guard ok else { return nil }
        return await Self.mcpBridge.list()
    }

    // MARK: - Data: sessions

    /// On-disk size of `~/.grok/sessions` plus the indexed conversation count,
    /// computed off the main actor.
    func loadSessionStorageInfo() async -> SessionStorageInfo {
        await Self.dataBridge.sessionStorageInfo()
    }

    /// Export every indexed session summary to a user-chosen JSON file.
    /// Calls back with a result message and the refreshed storage info.
    func exportSessions(completion: @escaping (String, SessionStorageInfo) -> Void) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "grok-sessions-\(Self.exportDateStamp()).json"
        panel.allowedContentTypes = [.json]
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let ok = await Self.dataBridge.exportSessions(to: url)
            let info = await Self.dataBridge.sessionStorageInfo()
            let message = ok ? "Exported sessions to \(url.lastPathComponent)" : "Couldn't export sessions."
            completion(message, info)
        }
    }

    /// Delete every grok session on disk (after the caller confirms). Clears the
    /// in-memory list, refreshes project threads, and calls back with a result
    /// message + refreshed storage info.
    func clearAllSessions(completion: @escaping (String, SessionStorageInfo) -> Void) {
        Task {
            let ok = await Self.dataBridge.clearSessions()
            if ok {
                sessions = []
                refreshProjects()
            }
            let info = await Self.dataBridge.sessionStorageInfo()
            let message = ok ? "Cleared all local sessions." : "Couldn't clear sessions."
            completion(message, info)
        }
    }

    // MARK: - Grok CLI

    /// Resolved path to the grok binary shown in the CLI section.
    var grokBinaryPath: String {
        Self.resolveGrokPath()
    }

    /// Open a Terminal window running `grok login` so the user can authenticate.
    func runGrokLogin() {
        let path = Self.resolveGrokPath()
        let script = "tell application \"Terminal\"\n\tactivate\n\tdo script \"\(path) login\"\nend tell"
        if let apple = NSAppleScript(source: script) {
            var err: NSDictionary?
            apple.executeAndReturnError(&err)
            if err != nil {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
            }
        }
    }

    // MARK: - About

    /// "1.0 (42)" style version + build string from the bundle.
    static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    func openExternalURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func revealInFinder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func openFileOrFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    var grokConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/config.toml")
    }

    var grokSessionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/sessions")
    }

    var grokTempAttachmentsURL: URL {
        FileManager.default.temporaryDirectory
    }

    var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Codessa", isDirectory: true)
    }

    var currentProjectContextURL: URL? {
        selectedProject.map { projectContext.contextFileURL(for: $0) }
    }

    func revealCurrentProjectContext() {
        guard let url = currentProjectContextURL else { return }
        revealInFinder(url)
    }

    func exportPreferences(completion: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "codessa-settings-\(Self.exportDateStamp()).json"
        panel.allowedContentTypes = [.json]
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder.pretty.encode(preferences)
            try data.write(to: url, options: .atomic)
            completion("Exported settings to \(url.lastPathComponent)")
        } catch {
            completion("Couldn't export settings: \(error.localizedDescription)")
        }
    }

    func importPreferences(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
            completion("Imported settings from \(url.lastPathComponent)")
        } catch {
            completion("Couldn't import settings: \(error.localizedDescription)")
        }
    }

    func copyDiagnostics() {
        let bundle = SettingsDiagnosticsBundle(
            generatedAt: Date(),
            appVersion: Self.appVersionString,
            grokAvailable: grokAvailable,
            selectedProvider: selectedProvider.name,
            projectCount: projects.count,
            sessionCount: sessions.count,
            preferences: preferences.copyDiagnosticsIncludesSettings ? preferences : nil,
            system: [
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "architecture": Self.architectureLabel,
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
                "executable": Bundle.main.executablePath ?? "unknown",
            ]
        )
        if let data = try? JSONEncoder.pretty.encode(bundle),
           let text = String(data: data, encoding: .utf8) {
            copyToClipboard(text)
        }
    }

    func clearTemporaryAttachments(completion: @escaping (String) -> Void) {
        Task {
            let count = await Self.dataBridge.clearTempAttachments()
            completion("Cleared \(count) temporary attachment\(count == 1 ? "" : "s")")
        }
    }

    func runRetentionCleanup(days: Int, completion: @escaping (String, SessionStorageInfo) -> Void) {
        Task {
            let deleted = await Self.dataBridge.deleteSessions(olderThanDays: days)
            let info = await Self.dataBridge.sessionStorageInfo()
            if deleted > 0 {
                sessions = (try? await grok.listSessions(limit: preferences.defaultSessionLimit)) ?? sessions
                refreshSessionSnapshot()
            }
            completion("Deleted \(deleted) old session file\(deleted == 1 ? "" : "s")", info)
        }
    }

    func refreshModelsNow(completion: @escaping (String) -> Void) {
        Task {
            await refreshProviderSnapshots()
            completion("Refreshed \(models.count) \(selectedProvider.shortName) model\(models.count == 1 ? "" : "s")")
        }
    }

    func refreshCLIStatus() {
        grokAvailable = grok.isAvailable
        refreshProviders()
        Task { await refreshProviderSnapshots() }
    }

    func copySystemInfo() {
        copyToClipboard([
            "Codessa \(Self.appVersionString)",
            ProcessInfo.processInfo.operatingSystemVersionString,
            Self.architectureLabel,
            Bundle.main.bundleIdentifier ?? "co.codessa.Codessa",
        ].joined(separator: "\n"))
    }

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.hasOnboardedKey)
        onboardingOpen = true
    }

    func clearPendingChatPlaceholder() {
        pendingChat = nil
    }

    func emptyArchive() {
        archivedProjectPaths.removeAll()
        persistSidebarPreferences()
    }

    func restoreAllArchivedProjects() {
        archivedProjectPaths.removeAll()
        persistSidebarPreferences()
    }

    func archiveSelectedProjectIfAllowed() {
        guard let project = selectedProject else { return }
        if preferences.keepPinnedUnarchived, isPinned(project) { return }
        archiveProject(project)
    }

    func exportArchiveList(completion: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "codessa-archived-projects-\(Self.exportDateStamp()).json"
        panel.allowedContentTypes = [.json]
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rows = archivedProjects.map { ["name": $0.name, "path": $0.path.path, "chats": "\($0.threads.count)"] }
        do {
            let data = try JSONEncoder.pretty.encode(rows)
            try data.write(to: url, options: .atomic)
            completion("Exported archive list to \(url.lastPathComponent)")
        } catch {
            completion("Couldn't export archive list: \(error.localizedDescription)")
        }
    }

    func personalizationPrefix() -> String {
        guard preferences.includeStyleRules || preferences.includeProjectRules else { return "" }
        var rules: [String] = []
        if preferences.includeStyleRules {
            rules.append("Response length: \(preferences.responseLength.label).")
            rules.append("Explanation depth: \(preferences.explanationDepth.label).")
            rules.append("Tone: \(preferences.tonePreset.label).")
            if preferences.preferBritishEnglish { rules.append("Use British English.") }
            if preferences.avoidEmDashes { rules.append("Avoid em dashes.") }
            if preferences.preserveUserWording { rules.append("Preserve user wording exactly when rewriting.") }
            if preferences.draftOnlyMessaging { rules.append("For messages or external communications, draft only unless explicitly approved.") }
            if preferences.showPlansByDefault { rules.append("For substantial work, show a concise plan before broad changes.") }
            if preferences.askBeforeAssumptions { rules.append("Ask before making high-impact assumptions.") }
        }
        if preferences.includeProjectRules, preferences.contextEnabled, let project = selectedProject {
            let file = projectContext.fileName(for: project)
            rules.append("Project context file enabled: \(file).")
        }
        guard !rules.isEmpty else { return "" }
        return "[Codessa user preferences]\n" + rules.map { "- " + $0 }.joined(separator: "\n") + "\n\n"
    }

    // MARK: - Hooks origin (derived, no new stored state)

    /// Where a pending hook came from, inferred from its file name and the
    /// command path. Drives the origin badge in the hooks list.
    static func hookOrigin(for hook: PendingHook) -> (label: String, symbol: String) {
        let lowerFile = hook.fileName.lowercased()
        let lowerCmd = hook.command.lowercased()
        if lowerFile.contains("claude") || lowerCmd.contains("/.claude/") {
            return ("Imported from Claude", "ant")
        }
        if lowerFile.contains("codex") || lowerCmd.contains("/.codex/") {
            return ("Imported from Codex", "chevron.left.forwardslash.chevron.right")
        }
        if lowerFile.contains("cursor") || lowerCmd.contains("/.cursor/") {
            return ("Imported from Cursor", "cursorarrow.rays")
        }
        return ("Local hook", "bolt.horizontal")
    }

    // MARK: - Private helpers

    static func resolveGrokPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let override = UserDefaults.standard.string(forKey: "grokcode.preferences.grokBinaryOverride") ?? ""
        if !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let candidates = [
            "\(home)/.grok/bin/grok",
            "/usr/local/bin/grok",
            "/opt/homebrew/bin/grok",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    private static func exportDateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static var architectureLabel: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static let mcpBridge = MCPConfigBridge()
    private static let dataBridge = SessionDataBridge()
}

// MARK: - Off-main-actor bridges
//
// These shell out / touch the filesystem, so they're `nonisolated` and run on a
// background executor. They never mutate view-model state — the `@MainActor`
// methods above own that.

/// Reads `grok mcp list` and toggles the `enabled` flag in `~/.grok/config.toml`.
private final class MCPConfigBridge: @unchecked Sendable {
    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/config.toml")
    }

    func list() async -> [MCPServerInfo] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.parseList(self.runGrok(["mcp", "list"])))
            }
        }
    }

    func setEnabled(name: String, enabled: Bool) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.writeEnabledFlag(name: name, enabled: enabled))
            }
        }
    }

    // Parses the indented `  name: command... (disabled)?` lines grok prints.
    private func parseList(_ output: String) -> [MCPServerInfo] {
        var servers: [MCPServerInfo] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" ") else { continue }
            var detail = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let disabled = detail.hasSuffix("(disabled)")
            if disabled {
                detail = String(detail.dropLast("(disabled)".count)).trimmingCharacters(in: .whitespaces)
            }
            servers.append(MCPServerInfo(name: name, detail: detail, enabled: !disabled))
        }
        return servers
    }

    private func runGrok(_ args: [String]) -> String {
        let grokPath = AppViewModel.resolveGrokPath()
        guard FileManager.default.isExecutableFile(atPath: grokPath) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: grokPath)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    /// Rewrite the `enabled = …` line inside `[mcp_servers.<name>]`. If the table
    /// exists but has no `enabled` key, insert one right after the header. Leaves
    /// the file untouched if the table can't be found.
    @discardableResult
    private func writeEnabledFlag(name: String, enabled: Bool) -> Bool {
        let url = configURL
        guard let original = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let header = "[mcp_servers.\(name)]"
        var lines = original.components(separatedBy: "\n")
        guard let headerIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == header
        }) else { return false }

        let desired = "enabled = \(enabled)"
        var didEdit = false
        var i = headerIdx + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            // Stop at the next table header (start of a different section).
            if trimmed.hasPrefix("[") { break }
            if trimmed.hasPrefix("enabled") && trimmed.contains("=") {
                lines[i] = desired
                didEdit = true
                break
            }
            i += 1
        }
        if !didEdit {
            lines.insert(desired, at: headerIdx + 1)
        }
        let updated = lines.joined(separator: "\n")
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}

/// Filesystem operations for the Data section (size, export, clear).
private final class SessionDataBridge: @unchecked Sendable {
    private var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/sessions")
    }

    func sessionStorageInfo() async -> SessionStorageInfo {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.computeStorage())
            }
        }
    }

    func exportSessions(to destination: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.writeExport(to: destination))
            }
        }
    }

    func clearSessions() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.deleteSessions())
            }
        }
    }

    func deleteSessions(olderThanDays days: Int) async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.deleteSessions(olderThanDays: days))
            }
        }
    }

    func clearTempAttachments() async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.deleteTempAttachments())
            }
        }
    }

    private func computeStorage() -> SessionStorageInfo {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: []
        ) else { return SessionStorageInfo(bytes: 0, count: 0) }

        var bytes: Int64 = 0
        var summaries = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            if values?.isRegularFile == true {
                bytes += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
            if url.lastPathComponent == "summary.json" { summaries += 1 }
        }
        return SessionStorageInfo(bytes: bytes, count: summaries)
    }

    /// Collect every `summary.json` into a single JSON array and write it.
    private func writeExport(to destination: URL) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }

        var items: [Any] = []
        for case let url as URL in enumerator where url.lastPathComponent == "summary.json" {
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) {
                items.append(json)
            }
        }
        guard let out = try? JSONSerialization.data(
            withJSONObject: items, options: [.prettyPrinted, .sortedKeys]
        ) else { return false }
        return (try? out.write(to: destination, options: .atomic)) != nil
    }

    /// Remove the contents of the sessions directory (but keep the directory).
    private func deleteSessions() -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: sessionsRoot, includingPropertiesForKeys: nil, options: []
        ) else { return false }
        var ok = true
        for entry in entries {
            do { try fm.removeItem(at: entry) } catch { ok = false }
        }
        return ok
    }

    private func deleteSessions(olderThanDays days: Int) -> Int {
        let fm = FileManager.default
        guard days > 0,
              let enumerator = fm.enumerator(
                at: sessionsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else { return 0 }

        let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))
        var deleted = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "summary.json" || url.lastPathComponent == "updates.jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, (values?.contentModificationDate ?? Date()) < cutoff else { continue }
            do {
                try fm.removeItem(at: url)
                deleted += 1
            } catch {
                continue
            }
        }
        return deleted
    }

    private func deleteTempAttachments() -> Int {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let entries = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return 0 }
        var deleted = 0
        for entry in entries {
            let name = entry.lastPathComponent
            guard entry.pathExtension.lowercased() == "png",
                  name.hasPrefix("grok_attach_") || name.hasPrefix("grok_paste_")
            else { continue }
            do {
                try fm.removeItem(at: entry)
                deleted += 1
            } catch {
                continue
            }
        }
        return deleted
    }
}
