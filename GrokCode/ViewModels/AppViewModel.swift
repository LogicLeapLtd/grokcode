import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
    var projects: [Project] = []
    var sessions: [GrokSession] = []
    var models: [GrokModelOption] = []
    var selectedProject: Project?
    var selectedModel: GrokModelOption?
    var permissionMode: PermissionMode = .fullAccess
    var effortLevel: EffortLevel = .medium
    var messages: [ChatMessage] = []
    var promptText = ""
    var isRunning = false
    var errorMessage: String?
    var activePage: MainPage = .home
    var activeSidebarSection: SidebarSection?
    var showSettings = false
    var searchQuery = ""
    var projectRoots: [URL] = []
    var activeSessionId: String?
    var grokAvailable = false
    var pendingHooks: [PendingHook] = []
    var trustedHookIDs: Set<String> = []
    var showHooksReview = false
    var sidebarProjectSearch = ""
    var sidebarStatusFilter: SidebarStatusFilter = .all
    var sidebarGroupBy: SidebarGroupBy = .project
    var sidebarSort: SidebarSort = .lastActive
    var pinnedProjectPaths: Set<String> = []
    var archivedProjectPaths: Set<String> = []
    /// Plugins discovered from local tool configs (grok/claude/codex/cursor),
    /// with `isInstalled` reflecting the persisted installed set.
    var importablePlugins: [Plugin] = []
    /// Plugins the user has imported/installed (persisted full blobs).
    var installedPlugins: [Plugin] = []
    /// User-defined automations (saved grok prompts + simple schedules).
    var automations: [Automation] = []
    /// Live filter text for the Plugins page search box.
    var pluginSearchQuery = ""
    /// When true, project rows collapse to just their names (the collapse
    /// toggle in the Projects header); otherwise every project auto-expands its
    /// chats, Codex-style.
    var projectsCollapsed = false
    /// Live filter text for the composer's project picker.
    var projectPickerQuery = ""
    /// "Don't work in a project" — run with the home directory as cwd.
    var workWithoutProject = false
    /// Codex "Pursue goal" — append grok's self-verification loop (--check).
    var pursueGoal = false
    /// The most recent app the user was in before GrokCode (for "Attach …").
    var lastActiveApp: NSRunningApplication?

    /// Codex "Plan mode" toggle in the + menu, mapped onto the permission mode.
    var isPlanMode: Bool {
        get { permissionMode == .plan }
        set { permissionMode = newValue ? .plan : .fullAccess }
    }

    private let grok = GrokCLIService.shared
    /// Set when the user taps Stop so the resulting termination is treated as a
    /// graceful cancel (no error surfaced, queue not auto-advanced).
    private var didUserCancel = false
    /// The model the current grok session was started with. grok locks a session
    /// to one model's agent, so switching models mid-session requires a new one.
    private var sessionModelId: String?
    private let discovery = ProjectDiscovery()
    private let hooksService = HooksService()
    private let sessionIndex = SessionIndexService()
    private let pluginImport = PluginImportService()
    private let automationService = AutomationService()
    private let rootsKey = "grokcode.projectRoots"
    private let selectedProjectPathKey = "grokcode.selectedProjectPath"
    private let workWithoutProjectKey = "grokcode.workWithoutProject"
    private let sidebarFilterKey = "grokcode.sidebarStatusFilter"
    private let sidebarGroupByKey = "grokcode.sidebarGroupBy"
    private let sidebarSortKey = "grokcode.sidebarSort"
    private let pinnedProjectsKey = "grokcode.pinnedProjects"
    private let archivedProjectsKey = "grokcode.archivedProjects"

    func bootstrap() async {
        grokAvailable = grok.isAvailable
        restoreDefaults()
        trustedHookIDs = hooksService.loadTrustedIDs()
        refreshHooks()
        projects = discovery.discoverProjects(in: projectRoots)
        attachThreadsToProjects()

        if UserDefaults.standard.bool(forKey: workWithoutProjectKey) {
            // Last session was "Don't work in a project" — restore that.
            workWithoutProject = true
            selectedProject = nil
        } else if selectedProject == nil {
            if let savedPath = UserDefaults.standard.string(forKey: selectedProjectPathKey) {
                selectedProject = projects.first { $0.path.path == savedPath }
            }
            selectedProject = selectedProject ?? projects.first
        }

        do {
            models = try await grok.listModels()
            if selectedModel == nil {
                if let savedId = UserDefaults.standard.string(forKey: "grokcode.defaultModel"),
                   let saved = models.first(where: { $0.id == savedId }) {
                    selectedModel = saved
                } else {
                    selectedModel = models.first(where: \.isDefault) ?? models.first
                }
            }
            sessions = try await grok.listSessions()
            attachThreadsToProjects()
            refreshProjects()
        } catch {
            errorMessage = error.localizedDescription
            if models.isEmpty {
                models = [
                    GrokModelOption(id: "grok-composer-2.5-fast", isDefault: true),
                    GrokModelOption(id: "grok-build", isDefault: false),
                ]
                selectedModel = models.first
            }
        }

        refreshPlugins()
        loadAutomations()
        automationService.startScheduler { [weak self] dueIDs in
            self?.runDueAutomations(dueIDs)
        }

        runSmokeTestIfRequested()
    }

    /// Developer-only end-to-end smoke hook used to prove the streaming chat
    /// loop without simulating keystrokes. Activated by environment variables:
    ///   GROKCODE_SMOKE_PROMPT  — the prompt to auto-send on launch
    ///   GROKCODE_SMOKE_MODEL   — optional model id (default: selected/default)
    ///   GROKCODE_SMOKE_EFFORT  — optional effort level (default: current)
    /// Always runs in Plan mode against this repo when available, so it can
    /// never modify files. No-op when the variable is unset.
    private func runSmokeTestIfRequested() {
        let env = ProcessInfo.processInfo.environment

        if let g = env["GROKCODE_SMOKE_GROUPBY"], let gb = SidebarGroupBy(rawValue: g) {
            sidebarGroupBy = gb
        }

        // Page navigation for visual QA (independent of the prompt hook).
        if let page = env["GROKCODE_SMOKE_PAGE"] {
            switch page {
            case "search": navigateTo(.search)
            case "plugins": navigateTo(.plugins)
            case "automations": navigateTo(.automations)
            case "settings": openSettings()
            case "hooks": openHooksReview()
            default: break
            }
        }

        guard let prompt = env["GROKCODE_SMOKE_PROMPT"], !prompt.isEmpty else { return }

        if let safe = projects.first(where: { $0.name == "GrokCodeGUI" }) {
            selectedProject = safe
        }
        if let modelId = env["GROKCODE_SMOKE_MODEL"],
           let match = models.first(where: { $0.id == modelId }) {
            selectedModel = match
        }
        // Force an arbitrary (possibly invalid) model id to exercise the error path.
        if let forced = env["GROKCODE_SMOKE_FORCE_MODEL"] {
            selectedModel = GrokModelOption(id: forced, isDefault: false)
        }
        if let effortRaw = env["GROKCODE_SMOKE_EFFORT"],
           let effort = EffortLevel(rawValue: effortRaw) {
            effortLevel = effort
        }
        permissionMode = .plan
        promptText = prompt
        submit()

        // Optional: submit a second prompt mid-run to prove queue/steering.
        if let queued = env["GROKCODE_SMOKE_QUEUE"], !queued.isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.promptText = queued
                self?.submit()
            }
        }
    }

    func refreshProjects() {
        projects = discovery.discoverProjects(in: projectRoots)
        attachThreadsToProjects()
        if let selected = selectedProject,
           let updated = projects.first(where: { $0.path == selected.path }) {
            selectedProject = updated
        }
    }

    func selectProject(_ project: Project) {
        selectedProject = project
        workWithoutProject = false
        UserDefaults.standard.set(project.path.path, forKey: selectedProjectPathKey)
        UserDefaults.standard.set(false, forKey: workWithoutProjectKey)
        messages = []
        activeSessionId = nil
        sessionModelId = nil
        errorMessage = nil
        navigateTo(messages.isEmpty ? .home : .chat)
    }

    /// Codex "Don't work in a project" — clear the project; runs use the home dir.
    func clearProjectSelection() {
        selectedProject = nil
        workWithoutProject = true
        UserDefaults.standard.set(true, forKey: workWithoutProjectKey)
        messages = []
        activeSessionId = nil
        sessionModelId = nil
        errorMessage = nil
        navigateTo(.home)
    }

    /// Projects filtered by the picker's live query.
    var pickerProjects: [Project] {
        let q = projectPickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    func navigateTo(_ page: MainPage) {
        activePage = page
        switch page {
        case .home, .chat:
            activeSidebarSection = nil
        case .search:
            activeSidebarSection = .search
        case .plugins:
            activeSidebarSection = .plugins
        case .automations:
            activeSidebarSection = .automations
        }
    }

    func openSettings() {
        showSettings = true
    }

    func closeSettings() {
        showSettings = false
    }

    func openHooksReview() {
        showHooksReview = true
    }

    func closeHooksReview() {
        showHooksReview = false
    }

    func selectThread(_ thread: ProjectThread, in project: Project) {
        selectedProject = project
        UserDefaults.standard.set(project.path.path, forKey: selectedProjectPathKey)
        activeSessionId = thread.id
        sessionModelId = nil   // unknown which model this thread used
        errorMessage = nil
        navigateTo(.chat)
    }

    func startNewChat() {
        messages = []
        activeSessionId = nil
        sessionModelId = nil
        promptText = ""
        errorMessage = nil
        navigateTo(.home)
    }

    /// Number of follow-ups the user has queued mid-run.
    var queuedCount: Int { messages.lazy.filter(\.isQueued).count }

    /// Primary entry point from the composer (Return / send button). When idle
    /// it starts a run; while a run is in flight it enqueues the message as a
    /// pending bubble that auto-sends when the current run finishes (Codex-style
    /// queue/steering).
    func submit() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (selectedProject != nil || workWithoutProject), selectedModel != nil else { return }
        promptText = ""

        if isRunning {
            messages.append(ChatMessage(role: .user, text: trimmed, isQueued: true))
            if activePage != .chat { navigateTo(.chat) }
        } else {
            messages.append(ChatMessage(role: .user, text: trimmed))
            Task { await runPrompt(userText: trimmed) }
        }
    }

    private func runPrompt(userText: String, retriedNewSession: Bool = false) async {
        guard let model = selectedModel else { return }
        let cwd: URL
        if let project = selectedProject {
            cwd = project.path
        } else if workWithoutProject {
            // NEVER point grok at the home dir — it would scan Photos/iCloud/etc.
            // and trigger macOS privacy prompts. Use an isolated, empty scratch.
            cwd = Self.noProjectScratchDirectory()
        } else {
            return
        }

        // grok locks a session to one model's agent. If the user switched models
        // since this session started, begin a fresh session so it doesn't error.
        if let sid = activeSessionId, let started = sessionModelId, started != model.id, sid == activeSessionId {
            activeSessionId = nil
        }

        errorMessage = nil
        didUserCancel = false
        isRunning = true

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, text: "", isStreaming: true))

        if activePage != .chat {
            navigateTo(.chat)
        }

        do {
            let sessionId = try await grok.streamPrompt(
                userText,
                cwd: cwd,
                model: model.id,
                permissionMode: permissionMode,
                effort: effortLevel,
                check: pursueGoal,
                sessionId: activeSessionId
            ) { event in
                Task { @MainActor [weak self] in
                    self?.handleStreamEvent(event, assistantId: assistantId)
                }
            }

            if let sessionId {
                activeSessionId = sessionId
            }
            sessionModelId = model.id

            if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[index].isStreaming = false
                // An empty answer with no error is unusual — note it rather
                // than leaving a blank bubble.
                if messages[index].text.isEmpty && messages[index].reasoning.isEmpty {
                    messages[index].errorText = "Grok returned an empty response."
                }
            }

            sessions = (try? await grok.listSessions()) ?? sessions
            attachThreadsToProjects()
        } catch {
            let message = error.localizedDescription
            let lower = message.lowercased()
            // Any failure to resume the session (incompatible model agent, the
            // session expired / was never persisted, etc.) → retry once fresh.
            let needsNewSession = activeSessionId != nil && (
                message.contains("MODEL_SWITCH_INCOMPATIBLE_AGENT")
                || lower.contains("start a new session")
                || lower.contains("session does not exist")
                || lower.contains("session not found")
                || lower.contains("couldn't create session")
                || lower.contains("could not create session")
            )

            if !didUserCancel && needsNewSession && !retriedNewSession {
                // The resumed session is unusable — drop it and retry once as a
                // brand-new conversation so the message still goes through.
                messages.removeAll { $0.id == assistantId }
                activeSessionId = nil
                sessionModelId = nil
                isRunning = false
                await runPrompt(userText: userText, retriedNewSession: true)
                return
            }

            if didUserCancel {
                // Graceful stop — finalize the bubble, keep partial output.
                if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[index].isStreaming = false
                    if messages[index].text.isEmpty && messages[index].reasoning.isEmpty {
                        messages.remove(at: index)
                    }
                }
            } else {
                // Surface the failure inline on the assistant bubble.
                if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[index].isStreaming = false
                    messages[index].errorText = message
                } else {
                    messages.append(ChatMessage(role: .assistant, text: "", errorText: message))
                }
                errorMessage = message
            }
        }

        isRunning = false
        if didUserCancel {
            didUserCancel = false
        } else {
            dequeueNext()
        }
    }

    /// Pull the oldest queued follow-up (if any) and send it.
    private func dequeueNext() {
        guard !isRunning, let index = messages.firstIndex(where: { $0.isQueued }) else { return }
        let text = messages[index].text
        messages[index].isQueued = false
        Task { await runPrompt(userText: text) }
    }

    func attachFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Attach"

        guard panel.runModal() == .OK else { return }

        let paths = panel.urls.map(\.path)
        guard !paths.isEmpty else { return }
        appendAttachment(paths.map { "[\($0)]" }.joined(separator: " "))
    }

    /// Codex "Attach <app>" — grab a screenshot and attach it to the prompt.
    func attachActiveApp() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok_attach_\(UUID().uuidString).png")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", url.path]
        do {
            try proc.run()
            proc.waitUntilExit()
            if FileManager.default.fileExists(atPath: url.path) {
                appendAttachment("[\(url.path)]")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendAttachment(_ text: String) {
        if promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            promptText = text
        } else {
            promptText += " " + text
        }
    }

    private func setupActiveAppObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                self?.lastActiveApp = app
            }
        }
    }

    /// ⇧⌘M — step through the permission modes (Codex/Claude-style shortcut).
    func cyclePermissionMode() {
        let all = PermissionMode.allCases
        if let i = all.firstIndex(of: permissionMode) {
            permissionMode = all[(i + 1) % all.count]
        }
    }

    func cancelRun() {
        didUserCancel = true
        grok.cancel()
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[index].isStreaming = false
        }
    }

    func addProjectRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !projectRoots.contains(standardized) else { return }
        projectRoots.append(standardized)
        saveRoots()
        refreshProjects()
    }

    func removeProjectRoot(_ url: URL) {
        projectRoots.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        saveRoots()
        refreshProjects()
    }

    /// Persist the current model / permission / effort as the launch defaults.
    func persistDefaults() {
        let d = UserDefaults.standard
        d.set(selectedModel?.id, forKey: "grokcode.defaultModel")
        d.set(permissionMode.rawValue, forKey: "grokcode.defaultPermission")
        d.set(effortLevel.rawValue, forKey: "grokcode.defaultEffort")
    }

    private func restoreDefaults() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "grokcode.defaultPermission"),
           let mode = PermissionMode(rawValue: raw) { permissionMode = mode }
        if let raw = d.string(forKey: "grokcode.defaultEffort"),
           let effort = EffortLevel(rawValue: raw) { effortLevel = effort }
    }

    func addProjectFromPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to scan for projects."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addProjectRoot(url)
    }

    func togglePinProject(_ project: Project) {
        let path = project.path.path
        if pinnedProjectPaths.contains(path) {
            pinnedProjectPaths.remove(path)
        } else {
            pinnedProjectPaths.insert(path)
        }
        saveSidebarPreferences()
    }

    func isPinned(_ project: Project) -> Bool {
        pinnedProjectPaths.contains(project.path.path)
    }

    func archiveProject(_ project: Project) {
        archivedProjectPaths.insert(project.path.path)
        pinnedProjectPaths.remove(project.path.path)
        saveSidebarPreferences()
    }

    /// Codex "Archive all chats" — archive every currently-active project.
    func archiveAllProjects() {
        for project in projects where !archivedProjectPaths.contains(project.path.path) {
            archivedProjectPaths.insert(project.path.path)
        }
        pinnedProjectPaths.removeAll()
        saveSidebarPreferences()
    }

    func toggleProjectsCollapsed() {
        projectsCollapsed.toggle()
        UserDefaults.standard.set(projectsCollapsed, forKey: "grokcode.projectsCollapsed")
    }

    var sidebarProjectGroups: [SidebarProjectGroup] {
        let active = sortedSidebarProjects(includeArchived: false)
        let archived = sortedSidebarProjects(includeArchived: true)
            .filter { archivedProjectPaths.contains($0.path.path) }

        switch sidebarGroupBy {
        case .flatList:
            return []
        case .project:
            var groups: [SidebarProjectGroup] = []
            if !active.isEmpty {
                groups.append(SidebarProjectGroup(id: "active", title: "", projects: active))
            }
            if !archived.isEmpty {
                groups.append(SidebarProjectGroup(id: "archive", title: "Archive", projects: archived))
            }
            return groups
        case .rootFolder:
            // "Recent projects": a single flat list ordered by most-recent activity.
            let recent = active.sorted {
                ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast)
            }
            var groups: [SidebarProjectGroup] = []
            if !recent.isEmpty {
                groups.append(SidebarProjectGroup(id: "active", title: "", projects: recent))
            }
            if !archived.isEmpty {
                groups.append(SidebarProjectGroup(id: "archive", title: "Archive", projects: archived))
            }
            return groups
        }
    }

    var sidebarFlatThreads: [SidebarFlatThread] {
        guard sidebarGroupBy == .flatList else { return [] }

        let indexed = sessionIndex.loadIndexedSessions()
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path.standardizedFileURL.path, $0) })
        let query = sidebarProjectSearch.trimmingCharacters(in: .whitespacesAndNewlines)

        return indexed.compactMap { session in
            let projectPath = session.cwd.standardizedFileURL.path
            guard let project = projectByPath[projectPath]
                ?? projects.first(where: { projectPath.hasPrefix($0.path.standardizedFileURL.path + "/") || projectPath == $0.path.standardizedFileURL.path })
            else { return nil }

            if archivedProjectPaths.contains(project.path.path) { return nil }

            switch sidebarStatusFilter {
            case .all: break
            case .withChats: break
            case .noChats: return nil
            case .pinnedOnly:
                guard pinnedProjectPaths.contains(project.path.path) else { return nil }
            }

            if !query.isEmpty {
                let matches = project.name.localizedCaseInsensitiveContains(query)
                    || session.title.localizedCaseInsensitiveContains(query)
                guard matches else { return nil }
            }

            return SidebarFlatThread(
                id: session.id,
                title: session.title,
                ageLabel: relativeAge(from: session.lastActive),
                project: project
            )
        }
    }

    func trustAllHooks() {
        trustedHookIDs.formUnion(pendingHooks.map(\.id))
        hooksService.saveTrustedIDs(trustedHookIDs)
        refreshHooks()
    }

    func trustHook(_ hook: PendingHook) {
        trustedHookIDs.insert(hook.id)
        hooksService.saveTrustedIDs(trustedHookIDs)
        refreshHooks()
    }

    func refreshHooks() {
        pendingHooks = hooksService.loadPendingHooks(trusted: trustedHookIDs)
    }

    // MARK: - Plugins

    /// Reload the installed set and re-scan local tool configs for importable
    /// plugins. Cheap, synchronous, safe to call on appear / from a Rescan button.
    func refreshPlugins() {
        installedPlugins = pluginImport.installedPlugins()
        importablePlugins = pluginImport.discoverImportable()
    }

    /// Add a plugin to the installed set, then refresh both lists.
    func installPlugin(_ plugin: Plugin) {
        pluginImport.install(plugin)
        refreshPlugins()
    }

    /// Remove a plugin from the installed set, then refresh both lists.
    func removePlugin(_ plugin: Plugin) {
        pluginImport.remove(plugin)
        refreshPlugins()
    }

    /// Installed plugins, surfaced in the composer's "+ → Plugins" flyout.
    var activePlugins: [Plugin] { installedPlugins }

    // MARK: - Automations

    /// Load persisted automations and recompute the scheduler's snapshot.
    func loadAutomations() {
        automations = automationService.load()
        automationService.reschedule(with: automations)
    }

    func addAutomation(_ automation: Automation) {
        automationService.add(automation)
        loadAutomations()
    }

    func updateAutomation(_ automation: Automation) {
        automationService.update(automation)
        loadAutomations()
    }

    func deleteAutomation(_ automation: Automation) {
        automationService.delete(automation)
        loadAutomations()
    }

    /// Flip an automation's enabled flag, persist, and reschedule.
    func toggleAutomation(_ automation: Automation) {
        var copy = automation
        copy.enabled.toggle()
        automationService.update(copy)
        loadAutomations()
    }

    /// Run an automation now (headless via grok). Stamps `lastRun` on success and
    /// refreshes the list. Failures are surfaced on `errorMessage`.
    func runAutomation(_ automation: Automation) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.automationService.runNow(automation, using: self.grok)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.loadAutomations()
        }
    }

    /// Scheduler callback: run every automation whose trigger just elapsed.
    private func runDueAutomations(_ ids: [UUID]) {
        let due = automations.filter { ids.contains($0.id) }
        for automation in due {
            runAutomation(automation)
        }
    }

    var filteredProjects: [Project] {
        guard activePage == .search, !searchQuery.isEmpty else { return projects }
        return projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
            || $0.path.path.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var filteredSessions: [GrokSession] {
        guard !searchQuery.isEmpty else { return sessions }
        return sessions.filter {
            $0.summary.localizedCaseInsensitiveContains(searchQuery)
            || $0.id.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private func handleStreamEvent(_ event: GrokStreamEvent, assistantId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantId }) else { return }

        switch event.type {
        case "thought":
            if let data = event.data {
                messages[index].reasoning += data
            }
        case "text":
            if let data = event.data {
                messages[index].text += data
            }
        case "end":
            messages[index].isStreaming = false
            if let sessionId = event.sessionId {
                activeSessionId = sessionId
            }
        default:
            break
        }
    }

    /// An isolated, empty working directory for "Don't work in a project" runs,
    /// so grok never touches the user's home folder / protected files.
    static func noProjectScratchDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GrokCode/no-project-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Current git branch for a project. Checks the folder itself, and — for
    /// projects whose repo lives in a subdirectory (e.g. GrokCodeGUI/GrokCode) —
    /// the immediate subfolders too. Handles `.git` dirs and `.git` pointer files.
    static func gitBranch(for path: URL) -> String? {
        if let branch = branch(atGit: path.appendingPathComponent(".git")) { return branch }
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(
            at: path, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        for sub in subs.prefix(24) {
            if (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               let branch = branch(atGit: sub.appendingPathComponent(".git")) {
                return branch
            }
        }
        return nil
    }

    private static func branch(atGit gitPath: URL) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: gitPath.path, isDirectory: &isDir) else { return nil }
        let headURL: URL
        if isDir.boolValue {
            headURL = gitPath.appendingPathComponent("HEAD")
        } else {
            // `.git` is a pointer file: "gitdir: <path>"
            guard let content = try? String(contentsOf: gitPath, encoding: .utf8),
                  let line = content.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") })
            else { return nil }
            let dir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            headURL = URL(fileURLWithPath: dir, relativeTo: gitPath.deletingLastPathComponent())
                .appendingPathComponent("HEAD")
        }
        guard let raw = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private func attachThreadsToProjects() {
        let indexed = sessionIndex.loadIndexedSessions()

        for index in projects.indices {
            let path = projects[index].path
            let threads = sessionIndex.threads(for: path, in: indexed)
            projects[index].threads = threads
            projects[index].gitBranch = Self.gitBranch(for: path)
            projects[index].lastActiveAt = indexed
                .filter {
                    let projectPath = path.standardizedFileURL.path
                    let sessionPath = $0.cwd.standardizedFileURL.path
                    return sessionPath == projectPath || sessionPath.hasPrefix(projectPath + "/")
                }
                .map(\.lastActive)
                .max()

            if projects[index].createdAt == nil {
                projects[index].createdAt = (try? path.resourceValues(forKeys: [.creationDateKey]).creationDate)
            }
        }

        if let selected = selectedProject,
           let idx = projects.firstIndex(where: { $0.id == selected.id }) {
            selectedProject = projects[idx]
        }
    }

    private func sortedSidebarProjects(includeArchived: Bool) -> [Project] {
        var result = projects

        if includeArchived {
            result = result.filter { archivedProjectPaths.contains($0.path.path) }
        } else {
            result = result.filter { !archivedProjectPaths.contains($0.path.path) }
        }

        let query = sidebarProjectSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { project in
                project.name.localizedCaseInsensitiveContains(query)
                    || project.path.path.localizedCaseInsensitiveContains(query)
                    || project.threads.contains { $0.title.localizedCaseInsensitiveContains(query) }
            }
        }

        switch sidebarStatusFilter {
        case .all: break
        case .withChats: result = result.filter { !$0.threads.isEmpty }
        case .noChats: result = result.filter { $0.threads.isEmpty }
        case .pinnedOnly: result = result.filter { pinnedProjectPaths.contains($0.path.path) }
        }

        switch sidebarSort {
        case .lastActive:
            result.sort {
                let lhs = $0.lastActiveAt ?? .distantPast
                let rhs = $1.lastActiveAt ?? .distantPast
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs > rhs
            }
        case .nameAZ:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .created:
            result.sort {
                let lhs = $0.createdAt ?? .distantFuture
                let rhs = $1.createdAt ?? .distantFuture
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs < rhs
            }
        }

        let pinned = result.filter { pinnedProjectPaths.contains($0.path.path) }
        let unpinned = result.filter { !pinnedProjectPaths.contains($0.path.path) }
        return pinned + unpinned
    }

    private func groupedByRoot(_ projects: [Project]) -> [SidebarProjectGroup] {
        let grouped = Dictionary(grouping: projects) { project in
            rootFolderName(for: project.path)
        }

        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { key in
            SidebarProjectGroup(
                id: key,
                title: key,
                projects: grouped[key] ?? []
            )
        }
    }

    private func rootFolderName(for path: URL) -> String {
        let normalized = path.standardizedFileURL.path
        for root in projectRoots {
            let rootPath = root.standardizedFileURL.path
            if normalized.hasPrefix(rootPath + "/") || normalized == rootPath {
                return root.lastPathComponent
            }
        }
        return path.deletingLastPathComponent().lastPathComponent
    }

    private func loadSidebarPreferences() {
        if let raw = UserDefaults.standard.string(forKey: sidebarFilterKey),
           let filter = SidebarStatusFilter(rawValue: raw) {
            sidebarStatusFilter = filter
        }
        if let raw = UserDefaults.standard.string(forKey: sidebarGroupByKey),
           let groupBy = SidebarGroupBy(rawValue: raw) {
            sidebarGroupBy = groupBy
        }
        if let raw = UserDefaults.standard.string(forKey: sidebarSortKey),
           let sort = SidebarSort(rawValue: raw) {
            sidebarSort = sort
        }
        if let pinned = UserDefaults.standard.array(forKey: pinnedProjectsKey) as? [String] {
            pinnedProjectPaths = Set(pinned)
        }
        if let archived = UserDefaults.standard.array(forKey: archivedProjectsKey) as? [String] {
            archivedProjectPaths = Set(archived)
        }
        projectsCollapsed = UserDefaults.standard.bool(forKey: "grokcode.projectsCollapsed")
    }

    private func saveSidebarPreferences() {
        UserDefaults.standard.set(sidebarStatusFilter.rawValue, forKey: sidebarFilterKey)
        UserDefaults.standard.set(sidebarGroupBy.rawValue, forKey: sidebarGroupByKey)
        UserDefaults.standard.set(sidebarSort.rawValue, forKey: sidebarSortKey)
        UserDefaults.standard.set(Array(pinnedProjectPaths), forKey: pinnedProjectsKey)
        UserDefaults.standard.set(Array(archivedProjectPaths), forKey: archivedProjectsKey)
    }

    private func relativeAge(from date: Date?) -> String {
        guard let date else { return "" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        return "\(weeks)w"
    }

    private func loadRoots() {
        if let data = UserDefaults.standard.data(forKey: rootsKey),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            projectRoots = paths.map { URL(fileURLWithPath: $0) }
        } else {
            projectRoots = discovery.defaultRoots()
        }
    }

    private func saveRoots() {
        let paths = projectRoots.map(\.path)
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: rootsKey)
        }
    }

    init() {
        loadRoots()
        loadSidebarPreferences()
        setupActiveAppObserver()
    }
}

extension AppViewModel {
    func persistSidebarPreferences() {
        saveSidebarPreferences()
    }
}