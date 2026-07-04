import AppKit
import Foundation
import Observation
import SwiftUI

/// App-wide appearance preference. `system` follows macOS; `light`/`dark`
/// force a `ColorScheme`, applied at the `ContentView` root.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` for `system` (let SwiftUI inherit the platform appearance).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@Observable
@MainActor
final class AppViewModel {
    var projects: [Project] = []
    var sessions: [GrokSession] = []
    /// Whether the grok CLI session list has been loaded this launch. The list
    /// is loaded lazily on first Search-page open rather than eagerly at
    /// startup, so opening the app never shells out to `grok sessions list`.
    private var didLoadCLISessions = false
    var models: [GrokModelOption] = []
    var selectedProject: Project?
    var selectedModel: GrokModelOption?
    var modelOptionSelections: [String: String] = [:]
    var permissionMode: PermissionMode = .fullAccess
    var effortLevel: EffortLevel = .medium
    var messages: [ChatMessage] = []
    var promptText = ""
    var isRunning = false
    var errorMessage: String?
    var activePage: MainPage = .home
    var splitPanes: [SplitPane] = []
    var activeSplitPaneID: UUID?
    var isApplyingSplitPaneFocus = false
    let maxSplitPaneCount = 8
    private var pageBackStack: [MainPage] = []
    private var pageForwardStack: [MainPage] = []
    private let maxPageHistoryDepth = 50
    /// The page the user was on before opening Settings, so "Back to app" returns
    /// there instead of guessing from whether `messages` happens to be empty.
    var pageBeforeSettings: MainPage = .home
    var activeSidebarSection: SidebarSection?
    var showSettings = false
    var searchQuery = ""
    var projectRoots: [URL] = []
    var activeSessionId: String?
    /// Absolute paths of files staged on the composer, kept SEPARATE from
    /// `promptText` so the raw `[<path>]` token never appears in (and can't be
    /// corrupted by editing) the input. Folded into the sent text on submit.
    var composerAttachmentPaths: [String] = []
    /// When set, the app shows a full-screen image viewer for this path (tapping
    /// an image attachment chip). Cleared by the viewer's close button.
    var fullScreenImagePath: String?
    /// Optimistic "New chat" placeholder shown in the sidebar the instant a new
    /// conversation starts, before grok persists the session. Cleared once the
    /// real session is indexed (see `refreshSessionSnapshot`) or the run fails.
    var pendingChat: PendingChat?
    /// Chats started with "Don't work in a project" — their session `cwd` is the
    /// isolated no-project scratch directory, so `refreshSessionSnapshot` can't
    /// match them to any discovered project. Surfaced instead in the sidebar's
    /// standalone "Chats" section, below the projects list.
    var noProjectThreads: [ProjectThread] = []
    var grokAvailable = false
    /// Detected agent-CLI providers (Claude Code, Codex, Cursor, Gemini, Grok,
    /// Z.AI + any custom), each with install status. Populated by
    /// `refreshProviders()` at bootstrap and after adding a custom provider.
    var providerStatuses: [ProviderStatus] = []
    /// The user's selected provider id (mirrors `ProviderRegistry`). Defaults to
    /// the wired engine (Grok) so the shipping run path is unchanged until the
    /// user picks another provider.
    var selectedProviderId: String = AgentProvider.wiredDefault.id
    /// User-configurable agent modes. Built-ins provide the durable Plan and
    /// Execute lanes; users can add more profiles with their own provider/model
    /// routing and extra instructions.
    var agentModes: [AgentModeProfile] = AgentModeProfile.defaults {
        didSet {
            guard agentModes != oldValue else { return }
            persistAgentModes()
        }
    }
    /// The active mode controls permission, locked instructions, and model route.
    var activeAgentModeID: String = AgentModeProfile.executeID {
        didSet {
            guard activeAgentModeID != oldValue else { return }
            UserDefaults.standard.set(activeAgentModeID, forKey: Self.activeAgentModeKey)
        }
    }
    var pendingHooks: [PendingHook] = []
    var trustedHookIDs: Set<String> = []
    var showHooksReview = false
    var sidebarProjectSearch = ""
    var sidebarStatusFilter: SidebarStatusFilter = .withChats
    var sidebarGroupBy: SidebarGroupBy = .project
    var sidebarSort: SidebarSort = .lastActive
    var pinnedProjectPaths: Set<String> = []
    var archivedProjectPaths: Set<String> = []
    /// Project paths the user has explicitly removed from the sidebar. Unlike
    /// archiving (recoverable from Settings), a removed project is hidden from the
    /// list entirely until it's re-added. Persisted under `grokcode.hiddenProjects`.
    var hiddenProjectPaths: Set<String> = []
    /// Custom display names keyed by `project.path.path`. Renaming a project sets a
    /// label override here — it never touches the folder on disk. Persisted under
    /// `grokcode.projectNameOverrides`.
    var projectNameOverrides: [String: String] = [:]
    /// Per-project sidebar collapse state. Holds the `project.path.path` of every
    /// project the user has individually collapsed. A project is considered
    /// collapsed if it's in this set OR the global `projectsCollapsed` is on.
    /// Persisted under `grokcode.collapsedProjects`.
    var collapsedProjectPaths: Set<String> = []
    /// Every project path ever discovered. Used to seed newly-discovered projects
    /// as collapsed by default without re-collapsing a project the user has since
    /// expanded. Persisted under `grokcode.seenProjectPaths`.
    private var seenProjectPaths: Set<String> = []
    /// The project most recently auto-expanded from a sidebar selection. Cleared
    /// the instant the user manually toggles any project's collapse state, so
    /// manual expand/collapse is never undone by auto-follow behaviour.
    private var autoExpandedProjectPath: String?
    /// Per-branch collapse state for the "By project → branch" grouping. Keys are
    /// "<project path>::<branch or ∅>". Persisted under `grokcode.collapsedBranches`.
    var collapsedBranchKeys: Set<String> = []
    /// Master switch for sidebar collapsibility. When off, project and branch
    /// headers stay expanded and their chevrons are hidden. Persisted under
    /// `grokcode.collapsibleGroups` (default on).
    var collapsibleGroupsEnabled = true {
        didSet {
            guard collapsibleGroupsEnabled != oldValue else { return }
            UserDefaults.standard.set(collapsibleGroupsEnabled, forKey: Self.collapsibleGroupsKey)
        }
    }
    /// Plugins discovered from local tool configs (grok/claude/codex/cursor),
    /// with `isInstalled` reflecting the persisted installed set.
    var importablePlugins: [Plugin] = []
    /// Plugins the user has imported/installed (persisted full blobs).
    var installedPlugins: [Plugin] = []
    /// Community marketplace plugins, loaded from `MarketplaceService` (remote
    /// manifest, cached on disk). Refreshed on appear via `loadCommunityPlugins()`.
    /// `isInstalled` reflects the persisted installed set at load time.
    var communityPlugins: [Plugin] = []
    /// The user's own published plugins (local published store). Surfaced so the
    /// Plugins UI can list "Published by you" and re-open the publish sheet.
    var publishedPlugins: [Plugin] = []
    /// Drives presentation of the in-app "Publish a plugin" sheet on the Plugins
    /// page. Transient — not persisted.
    var publishSheetOpen = false
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
    /// The most recent app the user was in before Codessa (for "Attach …").
    var lastActiveApp: NSRunningApplication?
    /// Durable app-level settings beyond the legacy scalar defaults. This is the
    /// source of truth for the expanded Settings surface, persisted as one
    /// versioned Codable blob while the older keys below stay readable.
    var preferences: AppPreferences = .defaults {
        didSet {
            guard preferences != oldValue else { return }
            UserDefaults.standard.set(preferences.grokBinaryOverride, forKey: Self.grokBinaryOverrideMirrorKey)
            guard let data = try? JSONEncoder().encode(preferences) else { return }
            UserDefaults.standard.set(data, forKey: Self.preferencesKey)
        }
    }

    // MARK: - Appearance & layout preferences (shared contract)

    /// Light / dark / system appearance. Applied via `.preferredColorScheme`
    /// at the `ContentView` root. Persisted under `grokcode.appearance`.
    var appearance: AppAppearance = .system {
        didSet {
            guard appearance != oldValue else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    /// Sidebar width in points. Clamped to `240...340`. Persisted under
    /// `grokcode.sidebarWidth` (default 280).
    var sidebarWidth: Double = 280 {
        didSet {
            let clamped = min(max(sidebarWidth, 240), 340)
            if clamped != sidebarWidth {
                // Re-clamp without re-triggering persistence twice.
                sidebarWidth = clamped
                return
            }
            guard sidebarWidth != oldValue else { return }
            // While actively dragging the resize handle we update width every
            // frame; skip the synchronous UserDefaults write each tick (it's
            // flushed once on drag end) so the drag stays buttery.
            guard !isResizingSidebar else { return }
            UserDefaults.standard.set(sidebarWidth, forKey: Self.sidebarWidthKey)
        }
    }

    /// True only while the user is dragging the resize handle. Suppresses
    /// per-frame width persistence and the implicit width animation so the drag
    /// tracks the cursor 1:1. Transient (never persisted).
    var isResizingSidebar = false

    /// Flush the current sidebar width to disk — called once when a resize drag
    /// ends (per-tick persistence is suppressed via `isResizingSidebar`).
    func commitSidebarWidth() {
        UserDefaults.standard.set(sidebarWidth, forKey: Self.sidebarWidthKey)
    }

    /// Whether the sidebar is collapsed. Persisted under
    /// `grokcode.sidebarCollapsed`.
    var sidebarCollapsed: Bool = false {
        didSet {
            guard sidebarCollapsed != oldValue else { return }
            UserDefaults.standard.set(sidebarCollapsed, forKey: Self.sidebarCollapsedKey)
        }
    }

    /// When true, plain Return in the composer sends; otherwise it inserts a
    /// newline and ⌘/⇧-Return sends. Persisted under `grokcode.sendOnReturn`
    /// (default true).
    var sendOnReturn: Bool = true {
        didSet {
            guard sendOnReturn != oldValue else { return }
            UserDefaults.standard.set(sendOnReturn, forKey: Self.sendOnReturnKey)
        }
    }

    /// Mirrors `GrokCLIService.useWarmSession` (same UserDefaults key) so the
    /// Settings UI can toggle the warm-session optimisation. Default true.
    var warmSessionEnabled: Bool = true {
        didSet {
            guard warmSessionEnabled != oldValue else { return }
            UserDefaults.standard.set(warmSessionEnabled, forKey: Self.warmSessionKey)
        }
    }

    /// Transient feedback string for plugin install/remove (consumed by the
    /// Plugins lane). Not persisted.
    var pluginToast: String?

    /// Codex "Plan mode" toggle in the + menu, mapped onto the permission mode.
    var isPlanMode: Bool {
        get { activeAgentMode.kind == .plan || permissionMode == .plan }
        set { selectAgentMode(newValue ? AgentModeProfile.planID : AgentModeProfile.executeID) }
    }

    var activeAgentMode: AgentModeProfile {
        agentModes.first { $0.id == activeAgentModeID }
            ?? agentModes.first { $0.id == AgentModeProfile.executeID }
            ?? AgentModeProfile.defaults[0]
    }

    var activeModeRouteLabel: String {
        let route = activeAgentMode.activeRoute
        guard !route.usesParentModel else {
            return selectedModel?.displayName ?? "Chat model"
        }
        return modelDisplayName(providerID: route.providerID, modelID: route.modelID)
    }

    /// Friendly, human-readable name for a `providerID`/`modelID` pair. Prefers a
    /// live catalog entry, then falls back to `GrokModelOption`'s formatter so raw
    /// ids like `claude-fable-5` never surface in the UI. The provider is conveyed
    /// separately (logo/section header), so this never prefixes "Provider ·".
    func modelDisplayName(providerID: String, modelID: String) -> String {
        if let option = providerStatuses
            .first(where: { $0.provider.id == providerID })?
            .models.first(where: { $0.id == modelID }) {
            return option.displayName
        }
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Model" }
        return GrokModelOption(id: trimmed, isDefault: false, providerId: providerID).displayName
    }

    var activeModeRuntimeNote: String? {
        let route = activeAgentMode.activeRoute
        guard !route.usesParentModel, route.providerID != AgentProvider.wiredDefault.id else { return nil }
        return "\(providerLabel(for: route.providerID)) is configured for this mode; live streaming still uses the wired Grok adapter until that provider runner lands."
    }

    func selectAgentMode(_ id: String) {
        guard let mode = agentModes.first(where: { $0.id == id }) else { return }
        activeAgentModeID = mode.id
        permissionMode = mode.permissionMode
    }

    func applyPermissionMode(_ mode: PermissionMode) {
        permissionMode = mode
        if mode == .plan {
            activeAgentModeID = AgentModeProfile.planID
        } else if activeAgentMode.kind == .plan {
            activeAgentModeID = AgentModeProfile.executeID
        }
    }

    func upsertAgentMode(_ mode: AgentModeProfile) {
        var next = normalizedAgentModes(agentModes)
        if let index = next.firstIndex(where: { $0.id == mode.id }) {
            next[index] = mode
        } else {
            next.append(mode)
        }
        agentModes = normalizedAgentModes(next)
        if activeAgentModeID == mode.id {
            permissionMode = mode.permissionMode
        }
    }

    func addAgentMode() -> AgentModeProfile {
        let mode = AgentModeProfile(
            id: "custom-" + UUID().uuidString,
            name: "Custom mode",
            kind: .execute,
            permissionMode: .auto,
            executionRoute: ModeModelRoute(selection: .inheritParent),
            customInstructions: "",
            isBuiltIn: false
        )
        agentModes.append(mode)
        selectAgentMode(mode.id)
        return mode
    }

    func deleteAgentMode(_ id: String) {
        guard !AgentModeProfile.defaults.contains(where: { $0.id == id }) else { return }
        agentModes.removeAll { $0.id == id }
        if activeAgentModeID == id {
            selectAgentMode(AgentModeProfile.executeID)
        }
    }

    func resetAgentModes() {
        agentModes = AgentModeProfile.defaults
        selectAgentMode(AgentModeProfile.executeID)
    }

    func providerLabel(for id: String) -> String {
        providerStatuses.first { $0.provider.id == id }?.provider.shortName
            ?? AgentProvider.known.first { $0.id == id }?.shortName
            ?? "Custom"
    }

    /// Whether the ⌘K command palette overlay is presented. Driven by
    /// `toggleCommandPalette()` (⌘K) and dismissed by the palette surface.
    /// Transient — not persisted.
    var commandPaletteOpen = false

    /// ⌘K — show/hide the command palette overlay.
    func toggleCommandPalette() {
        commandPaletteOpen.toggle()
    }

    // MARK: - Onboarding (shared contract)

    /// Drives the first-run onboarding sheet. Set true during `bootstrap()` on a
    /// genuine first launch (the `hasOnboarded` flag unset) — but never during a
    /// GROKCODE_SMOKE_* run, so smoke tests aren't blocked by the sheet. The
    /// smoke hook may instead set it true explicitly to screenshot onboarding.
    var onboardingOpen = false

    /// Mark onboarding complete: persist the flag and dismiss the sheet. Safe to
    /// call more than once.
    func completeOnboarding() {
        // Persist the model / permission / effort picked during onboarding as the
        // launch defaults — previously these were dropped, so the choice was lost.
        persistDefaults()
        UserDefaults.standard.set(true, forKey: Self.hasOnboardedKey)
        onboardingOpen = false
    }

    // MARK: - Project context (shared contract)

    /// Legacy flag retained only for compatibility with any remaining call sites;
    /// the editor is now a full page (`.projectContext`), not a sheet.
    var projectContextOpen = false

    /// The working copy of the context file being edited. Loaded by
    /// `openProjectContext(for:)`, written back by `saveProjectContext()`.
    var projectContextDraft = ""

    /// The project whose context file is currently being edited (so a save writes
    /// back to the right place even if `selectedProject` changes meanwhile).
    private var projectContextEditing: Project?

    /// The page to return to when the context editor closes.
    private var pageBeforeProjectContext: MainPage = .home

    /// Load `project`'s context file into the draft and open the editor page.
    func openProjectContext(for project: Project) {
        projectContextEditing = project
        projectContextDraft = projectContext.read(project)
        pageBeforeProjectContext = (activePage == .projectContext) ? .home : activePage
        navigateTo(.projectContext)
    }

    /// Write the current draft back to the project being edited, then leave the
    /// editor page. No-op (other than closing) if no project is being edited.
    func saveProjectContext() {
        if let project = projectContextEditing {
            projectContext.write(project, projectContextDraft)
        }
        projectContextEditing = nil
        closeProjectContext()
    }

    /// Leave the context editor page without writing (Cancel) and return to wherever
    /// it was opened from.
    func closeProjectContext() {
        projectContextOpen = false
        if activePage == .projectContext {
            navigateTo(pageBeforeProjectContext)
        }
    }

    /// The file name of the context file for the project being edited (or the
    /// selected project), for labelling the editor sheet. Defaults to "AGENTS.md".
    var projectContextFileName: String {
        if let project = projectContextEditing ?? selectedProject {
            return projectContext.fileName(for: project)
        }
        return "AGENTS.md"
    }

    let grok = GrokCLIService.shared
    private let providerRuntime = AgentProviderRuntime.shared
    /// Set when the user taps Stop so the resulting termination is treated as a
    /// graceful cancel (no error surfaced, queue not auto-advanced).
    private var didUserCancel = false
    /// The model the current grok session was started with. grok locks a session
    /// to one model's agent, so switching models mid-session requires a new one.
    private var sessionModelId: String?
    /// One-shot route override set when the user approves a rendered plan. It
    /// lets Plan mode define a distinct "after approval" provider/model without
    /// permanently changing the normal Execute mode.
    private var approvedPlanExecutionRoute: ModeModelRoute?
    private let discovery = ProjectDiscovery()
    private let hooksService = HooksService()
    private let sessionIndex = SessionIndexService()
    private let pluginImport = PluginImportService()
    private let automationService = AutomationService()
    private let marketplace = MarketplaceService.shared
    let projectContext = ProjectContextService()
    private var sessionIndexSnapshot: SessionIndexSnapshot?
    private var sessionSnapshotRefreshTask: Task<Void, Never>?
    private var sessionSnapshotRefreshID = 0
    private var sessionIndexRevision = 0
    private let rootsKey = "grokcode.projectRoots"
    private let selectedProjectPathKey = "grokcode.selectedProjectPath"
    private let workWithoutProjectKey = "grokcode.workWithoutProject"
    private let sidebarFilterKey = "grokcode.sidebarStatusFilter"
    private let sidebarGroupByKey = "grokcode.sidebarGroupBy"
    private let sidebarSortKey = "grokcode.sidebarSort"
    private let pinnedProjectsKey = "grokcode.pinnedProjects"
    private let archivedProjectsKey = "grokcode.archivedProjects"
    private let hiddenProjectsKey = "grokcode.hiddenProjects"
    private let projectNameOverridesKey = "grokcode.projectNameOverrides"
    private let collapsedProjectsKey = "grokcode.collapsedProjects"
    private let seenProjectPathsKey = "grokcode.seenProjectPaths"
    private let collapsedBranchesKey = "grokcode.collapsedBranches"
    // Appearance / layout preference keys (shared contract).
    fileprivate static let appearanceKey = "grokcode.appearance"
    fileprivate static let sidebarWidthKey = "grokcode.sidebarWidth"
    fileprivate static let sidebarCollapsedKey = "grokcode.sidebarCollapsed"
    fileprivate static let sendOnReturnKey = "grokcode.sendOnReturn"
    fileprivate static let warmSessionKey = "grokcode.useWarmSession"   // shared with GrokCLIService
    fileprivate static let collapsibleGroupsKey = "grokcode.collapsibleGroups"
    fileprivate static let preferencesKey = "grokcode.preferences.v1"
    fileprivate static let grokBinaryOverrideMirrorKey = "grokcode.preferences.grokBinaryOverride"
    private static let agentModesKey = "grokcode.agentModes.v1"
    private static let activeAgentModeKey = "grokcode.activeAgentMode"
    private static let activePageKey = "grokcode.activePage"
    /// First-run flag (shared contract). Unset → show onboarding on launch.
    static let hasOnboardedKey = "grokcode.hasOnboarded"

    private func persistAgentModes() {
        guard let data = try? JSONEncoder().encode(agentModes) else { return }
        UserDefaults.standard.set(data, forKey: Self.agentModesKey)
    }

    private func restoreAgentModes() {
        if let data = UserDefaults.standard.data(forKey: Self.agentModesKey),
           let decoded = try? JSONDecoder().decode([AgentModeProfile].self, from: data) {
            agentModes = normalizedAgentModes(decoded)
        } else {
            agentModes = AgentModeProfile.defaults
        }

        if let saved = UserDefaults.standard.string(forKey: Self.activeAgentModeKey),
           agentModes.contains(where: { $0.id == saved }) {
            activeAgentModeID = saved
        } else {
            activeAgentModeID = AgentModeProfile.executeID
        }
        permissionMode = activeAgentMode.permissionMode
    }

    private func normalizedAgentModes(_ modes: [AgentModeProfile]) -> [AgentModeProfile] {
        var byID = Dictionary(uniqueKeysWithValues: modes.map { ($0.id, $0) })
        for builtIn in AgentModeProfile.defaults {
            if var existing = byID[builtIn.id] {
                existing.kind = builtIn.kind
                existing.isBuiltIn = true
                byID[builtIn.id] = existing
            } else {
                byID[builtIn.id] = builtIn
            }
        }

        let builtIns = AgentModeProfile.defaults.compactMap { byID.removeValue(forKey: $0.id) }
        let custom = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return builtIns + custom
    }

    func bootstrap() async {
        grokAvailable = grok.isAvailable
        // Detect every installed agent-CLI provider (Claude Code, Codex, Cursor,
        // Gemini, Grok, Z.AI + custom) and restore the selected one.
        refreshProviders()
        // NOTE: we deliberately do NOT prewarm the `grok agent stdio` session on
        // launch. Prewarming boots the entire MCP server fleet (dozens of
        // subprocesses) the moment the app opens — while the user is still on the
        // home screen and may never send anything — pinning a large amount of
        // idle memory. The warm session is started lazily on the first real send
        // (`GrokCLIService.streamPrompt` → `GrokAgentSession.ensureStarted`), so
        // MCP boots on demand instead of on every launch.
        restoreDefaults()
        await refreshProviderSnapshots()
        trustedHookIDs = hooksService.loadTrustedIDs()
        refreshHooks()
        projects = discovery.discoverProjects(in: projectRoots)
        refreshSessionSnapshot()

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

        syncModelsForSelectedProvider()
        // NOTE: we no longer shell out to `grok sessions list` on launch. That
        // CLI session list only feeds the Search page (the sidebar renders from
        // the on-disk index via `refreshSessionSnapshot()`), so spawning a grok
        // process at startup to "restore previous sessions" is wasted work the
        // user never asked for. It's now loaded lazily the first time the Search
        // page is opened — see `loadCLISessionsIfNeeded()`.

        // Plugins/automations aren't needed for first paint (home/sidebar) — load
        // them concurrently instead of blocking bootstrap (and so the window)
        // on a marketplace network fetch (`loadCommunityPlugins`).
        refreshPlugins()
        refreshPublishedPlugins()
        Task { [weak self] in
            guard let self else { return }
            await self.loadCommunityPlugins()
        }
        loadAutomations()
        automationService.startScheduler { [weak self] dueIDs in
            self?.runDueAutomations(dueIDs)
        }

        // #39 — return the user to the preferred launch page. Runs before the
        // smoke hook so explicit QA overrides still win.
        restorePreferredLaunchPage()

        // First-run onboarding (shared contract): show the sheet when the user
        // has never onboarded — but never during a GROKCODE_SMOKE_* run, so smoke
        // tests aren't blocked. The smoke hook can still open onboarding itself.
        if !UserDefaults.standard.bool(forKey: Self.hasOnboardedKey), !Self.isSmokeRun {
            onboardingOpen = true
        }

        runSmokeTestIfRequested()
        if preferences.openSplitViewOnLaunch, activePage != .settings {
            openSplitView()
        }
    }

    /// True when any GROKCODE_SMOKE_* environment variable is set — used to
    /// suppress first-run onboarding during automated smoke runs.
    private static var isSmokeRun: Bool {
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("GROKCODE_SMOKE_") }
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

        // Warm-session self-test: 3 harmless prompts through the real
        // GrokCLIService → GrokAgentSession path, against the empty scratch dir
        // (full access there is safe — nothing to modify). Logs timing to stderr.
        if env["GROKCODE_SMOKE_WARMTEST"] == "1" {
            runWarmSelfTest()
            return
        }

        // Inject a chat with synthetic tool calls so the ToolCallList renders
        // deterministically for QA (no real grok turn / focus needed).
        if env["GROKCODE_SMOKE_TOOLCALLS"] == "1" {
            var assistant = ChatMessage(role: .assistant,
                text: "This looks like a small Swift package — two source files and a README.")
            assistant.toolCalls = [
                ToolCallEntry(id: "t1", title: "Edit Sources/Foo.swift", kind: "edit",
                              detail: "- let x = 1\n+ let x = 2", status: .done),
                ToolCallEntry(id: "t2", title: "Execute ls -la", kind: "execute",
                              detail: "$ ls -la\nFoo.swift\nBar.swift\nREADME.md", status: .done),
                ToolCallEntry(id: "t3", title: "Read README.md", kind: "read",
                              detail: "", status: .running),
            ]
            messages = [
                ChatMessage(role: .user, text: "List the files and describe this project."),
                assistant,
            ]
            navigateTo(.chat)
            return
        }

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

        // Open the Plugins page with the publish sheet up so QA can screenshot
        // the publish flow deterministically.
        if env["GROKCODE_SMOKE_PUBLISH"] == "1" {
            navigateTo(.plugins)
            publishSheetOpen = true
        }

        // Open the first-run onboarding sheet so QA can screenshot it
        // deterministically (independent of the persisted hasOnboarded flag).
        if env["GROKCODE_SMOKE_ONBOARDING"] == "1" {
            onboardingOpen = true
        }

        // Open the split workspace deterministically for layout QA.
        if env["GROKCODE_SMOKE_SPLIT"] == "1" {
            if activePage == .settings {
                navigateTo(.home)
            }
            openSplitView()
        }

        // Select the first project and open its Project Context editor so QA can
        // screenshot the AGENTS.md / GROK.md editing flow deterministically.
        if env["GROKCODE_SMOKE_PROJECTCONTEXT"] == "1", let first = projects.first {
            selectProject(first)
            openProjectContext(for: first)
        }

        guard let prompt = env["GROKCODE_SMOKE_PROMPT"], !prompt.isEmpty else { return }

        if let safe = projects.first(where: { $0.name == "GrokCodeGUI" }) {
            selectedProject = safe
        }
        if let modelId = env["GROKCODE_SMOKE_MODEL"],
           let match = models.first(where: { $0.id == modelId }) {
            selectModel(match)
        }
        // Force an arbitrary (possibly invalid) model id to exercise the error path.
        if let forced = env["GROKCODE_SMOKE_FORCE_MODEL"] {
            selectedModel = GrokModelOption(
                id: forced,
                isDefault: false,
                providerId: selectedProviderId,
                providerName: selectedProvider.shortName,
                title: forced,
                isCustom: true
            )
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

    /// Dev/QA: drive 3 prompts through the warm session and print timing. Proves
    /// MCP boots once (1st prompt) and 2nd/3rd start fast. stderr only.
    private func runWarmSelfTest() {
        let cwd = Self.noProjectScratchDirectory()
        let model = selectedModel?.id ?? "grok-composer-2.5-fast"
        func log(_ s: String) { FileHandle.standardError.write(Data(("[WARMTEST] " + s + "\n").utf8)) }
        log("starting (model=\(model))")
        Task {
            var sid: String?
            for i in 1...3 {
                let start = Date()
                do {
                    sid = try await GrokCLIService.shared.streamPrompt(
                        "Reply with exactly the word: pong. Do not use any tools.",
                        cwd: cwd, model: model, permissionMode: .fullAccess,
                        effort: .medium, check: false, sessionId: sid) { _ in }
                    log("prompt \(i): \(String(format: "%.2f", Date().timeIntervalSince(start)))s sid=\(sid ?? "nil")")
                } catch {
                    log("prompt \(i) ERROR after \(String(format: "%.2f", Date().timeIntervalSince(start)))s: \(error.localizedDescription)")
                }
            }
            log("DONE")
        }
    }

    func refreshProjects() {
        projects = discovery.discoverProjects(in: projectRoots)
        if let selected = selectedProject,
           let updated = projects.first(where: { $0.path == selected.path }) {
            selectedProject = updated
        }
        collapseNewlyDiscoveredProjects()
        refreshSessionSnapshot()
    }

    /// Projects collapse by default the first time they're ever discovered — a
    /// project the user has since expanded (or manually re-collapsed) is never
    /// touched again, since that only checks paths not yet in `seenProjectPaths`.
    private func collapseNewlyDiscoveredProjects() {
        let currentPaths = Set(projects.map { $0.path.path })
        let newPaths = currentPaths.subtracting(seenProjectPaths)
        guard !newPaths.isEmpty else { return }
        collapsedProjectPaths.formUnion(newPaths)
        seenProjectPaths.formUnion(newPaths)
        UserDefaults.standard.set(Array(seenProjectPaths), forKey: seenProjectPathsKey)
        saveSidebarPreferences()
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
        syncActiveSplitPaneFromCurrentState()
    }

    /// Select a project as working context and reveal its chats in the sidebar,
    /// without routing the main pane to a per-project overview.
    func revealProjectInSidebar(_ project: Project) {
        selectedProject = project
        workWithoutProject = false
        UserDefaults.standard.set(project.path.path, forKey: selectedProjectPathKey)
        UserDefaults.standard.set(false, forKey: workWithoutProjectKey)
        let newPath = project.path.path
        if let prev = autoExpandedProjectPath, prev != newPath {
            collapsedProjectPaths.insert(prev)
        }
        collapsedProjectPaths.remove(newPath)
        autoExpandedProjectPath = newPath
        saveSidebarPreferences()
    }

    /// The "+" affordance on a sidebar project row: select the project and start a
    /// fresh chat in it (lands on Home with the composer ready).
    func startNewChatInProject(_ project: Project) {
        selectedProject = project
        workWithoutProject = false
        UserDefaults.standard.set(project.path.path, forKey: selectedProjectPathKey)
        UserDefaults.standard.set(false, forKey: workWithoutProjectKey)
        messages = []
        activeSessionId = nil
        pendingChat = nil
        sessionModelId = nil
        promptText = ""
        errorMessage = nil
        navigateTo(.home)
        syncActiveSplitPaneFromCurrentState()
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
        syncActiveSplitPaneFromCurrentState()
    }

    /// Projects filtered by the picker's live query.
    var pickerProjects: [Project] {
        let q = projectPickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var canNavigateBack: Bool { !pageBackStack.isEmpty }
    var canNavigateForward: Bool { !pageForwardStack.isEmpty }

    func navigateBack() {
        guard let previous = pageBackStack.popLast() else { return }
        pageForwardStack.append(activePage)
        applyNavigation(to: previous, recordHistory: false)
    }

    func navigateForward() {
        guard let next = pageForwardStack.popLast() else { return }
        pageBackStack.append(activePage)
        applyNavigation(to: next, recordHistory: false)
    }

    func navigateTo(_ page: MainPage) {
        applyNavigation(to: page, recordHistory: true)
    }

    private func applyNavigation(to page: MainPage, recordHistory: Bool) {
        guard page != activePage else { return }
        let previousPage = activePage
        if recordHistory {
            pageBackStack.append(previousPage)
            if pageBackStack.count > maxPageHistoryDepth {
                pageBackStack.removeFirst(pageBackStack.count - maxPageHistoryDepth)
            }
            pageForwardStack.removeAll()
        }
        if page == .settings, previousPage != .settings {
            pageBeforeSettings = previousPage
        }
        activePage = page
        switch page {
        case .home, .chat, .settings, .projectContext:
            activeSidebarSection = nil
        case .search:
            activeSidebarSection = .search
        case .plugins:
            activeSidebarSection = .plugins
        case .automations:
            activeSidebarSection = .automations
        }
        persistActivePage(page)
        if !isApplyingSplitPaneFocus {
            syncActiveSplitPaneFromCurrentState()
        }
    }

    /// Persist the last *stable* landing page (#39). `.chat` is excluded — it
    /// depends on live in-memory messages, so restoring into it on a cold launch
    /// would show an empty conversation; we fall back to `.home` instead.
    private func persistActivePage(_ page: MainPage) {
        // Pages that depend on live in-memory/selection state shouldn't be
        // restored on a cold launch — fall back to Home.
        let transient: Set<MainPage> = [.chat, .projectContext]
        let stored: MainPage = transient.contains(page) ? .home : page
        UserDefaults.standard.set(stored.rawValue, forKey: Self.activePageKey)
    }

    /// Restore the last stable landing page on launch (#39).
    private func restoreActivePage() {
        guard let raw = UserDefaults.standard.string(forKey: Self.activePageKey),
              let page = MainPage(rawValue: raw),
              page != .chat else { return }
        applyNavigation(to: page, recordHistory: false)
    }

    private func restorePreferredLaunchPage() {
        guard preferences.restoreLastPage, preferences.launchPage == .restoreLast else {
            switch preferences.launchPage {
            case .restoreLast: applyNavigation(to: .home, recordHistory: false)
            case .home: applyNavigation(to: .home, recordHistory: false)
            case .search: applyNavigation(to: .search, recordHistory: false)
            case .plugins: applyNavigation(to: .plugins, recordHistory: false)
            case .automations: applyNavigation(to: .automations, recordHistory: false)
            case .settings: applyNavigation(to: .settings, recordHistory: false)
            }
            return
        }
        restoreActivePage()
    }

    func openSettings() {
        // Settings is now a full page (#15) rather than a modal. Keep the modal
        // flag clear and route via the page so existing callers (sidebar gear,
        // smoke hook, ⌘,) all land on the same surface.
        showSettings = false
        navigateTo(.settings)
    }

    func closeSettings() {
        showSettings = false
        if activePage == .settings {
            navigateTo(.home)
        }
    }

    func openHooksReview() {
        showHooksReview = true
    }

    func closeHooksReview() {
        showHooksReview = false
    }

    func selectThread(_ thread: ProjectThread, in project: Project) {
        guard !isRunning else { return }   // don't swap the transcript mid-stream
        selectedProject = project
        UserDefaults.standard.set(project.path.path, forKey: selectedProjectPathKey)
        activeSessionId = thread.id
        sessionModelId = nil   // unknown which model this thread used
        errorMessage = nil
        // Navigate immediately and stream the past conversation in behind it —
        // parsing a long session's updates.jsonl synchronously here used to
        // stall the chat-open transition.
        messages = []
        navigateTo(.chat)
        syncActiveSplitPaneFromCurrentState()
        loadMessagesAsync(for: thread.id)
    }

    /// Open a chat from the sidebar's standalone "Chats" section — a session
    /// started with "Don't work in a project", so unlike `selectThread` there's
    /// no project to attach it to.
    func selectNoProjectThread(_ thread: ProjectThread) {
        guard !isRunning else { return }
        selectedProject = nil
        workWithoutProject = true
        UserDefaults.standard.set(true, forKey: workWithoutProjectKey)
        activeSessionId = thread.id
        sessionModelId = nil
        errorMessage = nil
        messages = []
        navigateTo(.chat)
        syncActiveSplitPaneFromCurrentState()
        loadMessagesAsync(for: thread.id)
    }

    /// Loads a session's transcript off the main actor and applies it only if
    /// the user hasn't already navigated to a different chat in the meantime.
    func loadMessagesAsync(for sessionId: String) {
        let sessionIndex = sessionIndex
        let directoryHint = sessionIndexSnapshot?.sessionDirectoryById[sessionId]
        Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                sessionIndex.loadMessages(for: sessionId, directoryHint: directoryHint)
            }.value
            guard let self, self.activeSessionId == sessionId else { return }
            self.messages = loaded ?? []
            self.syncActiveSplitPaneFromCurrentState()
        }
    }

    func loadMessagesAsync(for sessionId: String, intoSplitPane paneID: UUID) {
        let sessionIndex = sessionIndex
        let directoryHint = sessionIndexSnapshot?.sessionDirectoryById[sessionId]
        Task { [weak self] in
            let loaded = await Task.detached(priority: .userInitiated) {
                sessionIndex.loadMessages(for: sessionId, directoryHint: directoryHint)
            }.value
            guard let self,
                  let index = self.splitPanes.firstIndex(where: { $0.id == paneID })
            else { return }
            self.splitPanes[index].messages = loaded ?? []
            self.splitPanes[index].isLoading = false
            if self.activeSplitPaneID == paneID, self.activeSessionId == sessionId {
                self.messages = loaded ?? []
            }
        }
    }

    /// Rename a no-project thread in-memory (mirrors `renameThread`).
    func renameNoProjectThread(_ thread: ProjectThread, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = noProjectThreads.firstIndex(where: { $0.id == thread.id }) else { return }
        noProjectThreads[index].title = trimmed
        invalidateSidebarCaches()
    }

    /// Remove a no-project thread from the sidebar (in-memory, mirrors `deleteThread`).
    func deleteNoProjectThread(_ thread: ProjectThread) {
        noProjectThreads.removeAll { $0.id == thread.id }
        if activeSessionId == thread.id { startNewChat() }
        invalidateSidebarCaches()
    }

    func startNewChat() {
        messages = []
        activeSessionId = nil
        pendingChat = nil
        sessionModelId = nil
        promptText = ""
        composerAttachmentPaths = []
        errorMessage = nil
        navigateTo(.home)
        syncActiveSplitPaneFromCurrentState()
    }

    /// Number of follow-ups the user has queued mid-run.
    var queuedCount: Int { messages.lazy.filter(\.isQueued).count }

    func approvePresentedPlan(_ plan: PresentedPlan) {
        guard !isRunning else { return }
        let sourceMode = activeAgentMode
        approvedPlanExecutionRoute = sourceMode.kind == .plan ? sourceMode.executionRoute : sourceMode.activeRoute
        selectAgentMode(AgentModeProfile.executeID)

        var text = "Approved. Execute this plan:\n\nTitle: \(plan.title)"
        if !plan.summary.isEmpty {
            text += "\nSummary: \(plan.summary)"
        }
        if !plan.steps.isEmpty {
            text += "\nSteps:\n" + plan.steps.enumerated().map { index, step in
                "\(index + 1). \(step)"
            }.joined(separator: "\n")
        }
        promptText = text
        submit()
    }

    private func resolvedRunModelID(routeOverride: ModeModelRoute? = nil) -> String? {
        resolvedRunModel(routeOverride: routeOverride)?.id
    }

    private func resolvedRunProviderID(routeOverride: ModeModelRoute? = nil) -> String {
        let route = routeOverride ?? activeAgentMode.activeRoute
        return route.usesParentModel ? selectedProviderId : route.providerID
    }

    private func resolvedRunModel(routeOverride: ModeModelRoute? = nil) -> GrokModelOption? {
        let providerID = resolvedRunProviderID(routeOverride: routeOverride)
        let route = routeOverride ?? activeAgentMode.activeRoute
        let explicit = route.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if route.usesParentModel {
            if selectedModel?.providerId == providerID {
                return selectedModel
            }
            return modelOptions(for: providerID).first(where: \.isDefault) ?? modelOptions(for: providerID).first
        }
        if explicit.isEmpty { return modelOptions(for: providerID).first(where: \.isDefault) ?? modelOptions(for: providerID).first }
        return modelOption(providerId: providerID, modelId: explicit)
            ?? GrokModelOption(
                id: explicit,
                isDefault: false,
                providerId: providerID,
                providerName: providerLabel(for: providerID),
                title: explicit,
                isCustom: true
            )
    }

    private func resolvedProviderStatus(routeOverride: ModeModelRoute? = nil) -> ProviderStatus? {
        let providerID = resolvedRunProviderID(routeOverride: routeOverride)
        return providerStatuses.first { $0.provider.id == providerID }
    }

    private func modeInstructionPrefix(routeOverride: ModeModelRoute? = nil) -> String {
        let mode = activeAgentMode
        let route = routeOverride ?? mode.activeRoute
        var lines: [String] = []

        lines.append("[Codessa active mode]")
        lines.append("- Mode: \(mode.name) (\(mode.kind.label)).")
        lines.append("- Permission mode: \(mode.permissionMode.label).")
        if routeOverride != nil {
            lines.append("- Approved plan execution: use the plan profile's after-approval route for this turn.")
        }
        if route.usesParentModel {
            lines.append("- Model route: inherit the selected chat model.")
        } else {
            lines.append("- Configured model route: \(providerLabel(for: route.providerID)) / \(route.modelID).")
        }
        lines.append("- Locked mode instructions: \(mode.lockedInstructions.replacingOccurrences(of: "\n", with: " "))")

        let custom = mode.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append("- User mode instructions: \(custom)")
        }

        return personalizationPrefix() + lines.joined(separator: "\n") + "\n\n"
    }

    /// Primary entry point from the composer (Return / send button). When idle
    /// it starts a run; while a run is in flight it enqueues the message as a
    /// pending bubble that auto-sends when the current run finishes (Codex-style
    /// queue/steering).
    func submit() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = composerAttachmentPaths
        // Allow a send with attachments and no typed text.
        guard !(trimmed.isEmpty && attachments.isEmpty),
              (selectedProject != nil || workWithoutProject),
              resolvedRunModelID() != nil else { return }
        if isRunning, !preferences.allowFollowupQueue {
            errorMessage = "A run is already in progress."
            return
        }
        if preferences.clearComposerAfterSend {
            promptText = ""
        }
        if preferences.defaultAttachmentBehavior == .clearAfterSend {
            composerAttachmentPaths = []
        }

        let sent = Self.composedSendText(trimmed, attachments: attachments)

        if isRunning {
            messages.append(ChatMessage(role: .user, text: trimmed, isQueued: true, attachments: attachments))
            if activePage != .chat { navigateTo(.chat) }
            syncActiveSplitPaneFromCurrentState()
        } else {
            // Brand-new conversation → optimistically surface a "New chat" row in
            // the sidebar right away (it pulses until grok persists the session),
            // rather than waiting for the first reply to make the chat appear.
            if activeSessionId == nil, pendingChat == nil {
                pendingChat = PendingChat(projectPath: selectedProject?.path)
                // Expand the owning project (newly discovered projects start
                // collapsed) so the freshly started chat is actually visible in
                // the sidebar instead of hidden under a collapsed project row.
                if let project = selectedProject {
                    collapsedProjectPaths.remove(project.path.path)
                    autoExpandedProjectPath = project.path.path
                    saveSidebarPreferences()
                }
            }
            messages.append(ChatMessage(role: .user, text: trimmed, attachments: attachments))
            syncActiveSplitPaneFromCurrentState()
            Task { await runPrompt(userText: sent) }
        }
    }

    /// Re-send the most recent user message — backs the error "Retry" button and
    /// the answer "Regenerate" action. Drops a trailing assistant bubble first.
    /// True when there's a prior user turn we can re-send (drives the home
    /// banner's Retry button).
    var canRetryLast: Bool {
        !isRunning && messages.contains { $0.role == .user && !($0.text.isEmpty && $0.attachments.isEmpty) }
    }

    func retryLast() {
        guard !isRunning else { return }
        if messages.last?.role == .assistant {
            messages.removeLast()
        }
        guard let lastUser = messages.last(where: { $0.role == .user }),
              !(lastUser.text.isEmpty && lastUser.attachments.isEmpty) else { return }
        let sent = Self.composedSendText(lastUser.text, attachments: lastUser.attachments)
        Task { await runPrompt(userText: sent) }
    }

    /// Transient failures (rate limiting, a brief network/backend hiccup — the
    /// `EX_TEMPFAIL` family surfaced by `CLIProcessMessage`) are worth retrying
    /// automatically before we ever bother the user with a banner. Detected from
    /// the human-readable message so it works across providers.
    private static func isTransientFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("temporary failure")
            || lower.contains("rate limit")
            || lower.contains("network/backend")
            || lower.contains("unavailable right now")
            || lower.contains("try again in a moment")
    }

    /// How many times we silently retry a transient failure, and the backoff
    /// before each retry.
    private static let maxTransientRetries = 2
    private static func transientBackoff(attempt: Int) -> Duration { .seconds(1.5 * Double(attempt + 1)) }

    private func runPrompt(userText: String, retriedNewSession: Bool = false, transientAttempt: Int = 0) async {
        let routeOverride = approvedPlanExecutionRoute
        approvedPlanExecutionRoute = nil
        guard let runModel = resolvedRunModel(routeOverride: routeOverride),
              let providerStatus = resolvedProviderStatus(routeOverride: routeOverride),
              let binaryPath = providerStatus.binaryPath else {
            errorMessage = "Selected provider is not installed or has no model available."
            return
        }
        let runModelID = runModel.id
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

        let runSessionModelKey = "\(providerStatus.provider.id)::\(runModelID)"

        // Some agent CLIs lock a session to one model/provider. If the user
        // switched since this session started, begin a fresh session.
        if let sid = activeSessionId, let started = sessionModelId, started != runSessionModelKey, sid == activeSessionId {
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
        syncActiveSplitPaneFromCurrentState()

        let effectiveUserText = modeInstructionPrefix(routeOverride: routeOverride) + userText

        do {
            let request = ProviderRunRequest(
                provider: providerStatus.provider,
                binaryPath: binaryPath,
                prompt: effectiveUserText,
                cwd: cwd,
                model: runModel,
                permissionMode: permissionMode,
                options: runOptions(for: runModel),
                check: pursueGoal,
                sessionId: providerStatus.provider.id == AgentProvider.grok.id ? activeSessionId : nil
            )

            // Coalesce the provider's stream onto the main actor. Delivering each
            // chunk with its own `Task { @MainActor }` has no backpressure: a fast
            // (or runaway) stream floods the main actor faster than SwiftUI drains
            // it, pinning the UI and ballooning memory. The coalescer keeps at most
            // one flush in flight and batches everything that arrives in between.
            let coalescer = StreamCoalescer { [weak self] batch in
                self?.applyStreamBatch(batch, assistantId: assistantId)
            }
            let sessionId = try await providerRuntime.streamPrompt(request: request) { event in
                coalescer.enqueue(event)
            }

            if let sessionId {
                activeSessionId = sessionId
            }
            sessionModelId = runSessionModelKey

            if let index = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[index].isStreaming = false
                // An empty answer with no error is unusual — note it rather
                // than leaving a blank bubble.
                if messages[index].text.isEmpty && messages[index].reasoning.isEmpty {
                    messages[index].errorText = "\(providerStatus.provider.shortName) returned an empty response."
                }
            }

            if providerStatus.provider.id == AgentProvider.grok.id {
                sessions = (try? await grok.listSessions()) ?? sessions
                refreshSessionSnapshot()
            }
            syncActiveSplitPaneFromCurrentState()
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

            // Transient hiccup (rate limit / brief network-backend blip): retry a
            // couple of times with backoff so a momentary failure self-heals
            // instead of dumping the "Grok hit a temporary failure" banner on the
            // user. Keep the same session so context is preserved.
            if !didUserCancel && transientAttempt < Self.maxTransientRetries
                && Self.isTransientFailure(message) {
                messages.removeAll { $0.id == assistantId }
                isRunning = false
                try? await Task.sleep(for: Self.transientBackoff(attempt: transientAttempt))
                if didUserCancel { didUserCancel = false; return }
                await runPrompt(userText: userText,
                                retriedNewSession: retriedNewSession,
                                transientAttempt: transientAttempt + 1)
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
        // If the run ended without ever creating a session, drop the optimistic
        // "New chat" placeholder so it doesn't pulse forever. (On success it's
        // already been retired by `refreshSessionSnapshot`.)
        if pendingChat != nil, activeSessionId == nil {
            pendingChat = nil
        }
        if didUserCancel {
            didUserCancel = false
        } else {
            dequeueNext()
        }
        syncActiveSplitPaneFromCurrentState()
    }

    /// Pull the oldest queued follow-up (if any) and send it.
    private func dequeueNext() {
        guard !isRunning, let index = messages.firstIndex(where: { $0.isQueued }) else { return }
        let queued = messages[index]
        messages[index].isQueued = false
        let sent = Self.composedSendText(queued.text, attachments: queued.attachments)
        Task { await runPrompt(userText: sent) }
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
        paths.forEach { appendAttachmentPath($0) }
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
                appendAttachmentPath(url.path)
            }
        } catch {
            errorMessage = error.localizedDescription
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
        providerRuntime.cancel()
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
        d.set(selectedProviderId, forKey: "grokcode.defaultProviderInstanceId")
        if let selectedModel {
            d.set(selectedModel.id, forKey: "grokcode.defaultModel.\(selectedModel.providerId)")
        }
        d.set(modelOptionSelections, forKey: "grokcode.defaultOptionsByInstance")
        d.set(permissionMode.rawValue, forKey: "grokcode.defaultPermission")
        d.set(effortLevel.rawValue, forKey: "grokcode.defaultEffort")
    }

    private func restoreDefaults() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "grokcode.defaultPermission"),
           let mode = PermissionMode(rawValue: raw) { permissionMode = mode }
        if let raw = d.string(forKey: "grokcode.defaultEffort"),
           let effort = EffortLevel(rawValue: raw) { effortLevel = effort }
        if let provider = d.string(forKey: "grokcode.defaultProviderInstanceId") {
            selectedProviderId = provider
        }
        if let options = d.dictionary(forKey: "grokcode.defaultOptionsByInstance") as? [String: String] {
            modelOptionSelections = options
        }
        restoreAgentModes()
        if let collapsed = d.array(forKey: collapsedProjectsKey) as? [String] {
            collapsedProjectPaths = Set(collapsed)
        }
        if preferences.defaultPlanMode {
            selectAgentMode(AgentModeProfile.planID)
        }
        pursueGoal = preferences.defaultPursueGoal
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

    /// Restore an archived project back into the active sidebar list.
    func unarchiveProject(_ project: Project) {
        archivedProjectPaths.remove(project.path.path)
        saveSidebarPreferences()
    }

    // MARK: - Project context-menu actions

    /// Open the project's folder in Finder, selecting it.
    func revealProjectInFinder(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting([project.path])
    }

    /// Remove a project from the sidebar entirely. Non-destructive on disk — the
    /// folder is untouched; it's simply hidden until re-added. If the project is a
    /// top-level scan root, drop the root too so it doesn't immediately reappear.
    func removeProjectFromSidebar(_ project: Project) {
        let path = project.path.path
        hiddenProjectPaths.insert(path)
        pinnedProjectPaths.remove(path)
        if selectedProject?.path.path == path {
            clearProjectSelection()
        }
        saveSidebarPreferences()
        if projectRoots.contains(where: { $0.standardizedFileURL == project.path }) {
            removeProjectRoot(project.path)
        }
    }

    /// Set a custom sidebar display name for a project (label only — never renames
    /// the folder on disk). Passing a blank name clears the override.
    func renameProject(_ project: Project, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = project.path.path
        if trimmed.isEmpty || trimmed == project.path.lastPathComponent {
            projectNameOverrides.removeValue(forKey: path)
        } else {
            projectNameOverrides[path] = trimmed
        }
        saveSidebarPreferences()
    }

    /// Create a permanent git worktree for the project on a new branch, then add
    /// it to the sidebar as its own project. Runs `git` off the main actor;
    /// failures surface on `errorMessage`.
    func createWorktree(for project: Project) {
        let repo = project.path
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                AppViewModel.addGitWorktree(forRepoAt: repo)
            }.value
            await MainActor.run {
                guard let self else { return }
                if let dest = result.url {
                    self.addProjectRoot(dest)
                } else {
                    self.errorMessage = result.error ?? "git worktree add failed."
                }
            }
        }
    }

    /// Runs `git worktree add -b <branch> <dest>` for the given repo, choosing a
    /// non-colliding sibling directory and branch name. Returns the new worktree
    /// URL on success or a human-readable error message on failure.
    private nonisolated static func addGitWorktree(forRepoAt repo: URL) -> (url: URL?, error: String?) {
        let fm = FileManager.default
        // Confirm the folder is inside a git working tree first.
        guard gitBranch(for: repo) != nil else {
            return (nil, "\(repo.lastPathComponent) is not a git repository.")
        }

        let parent = repo.deletingLastPathComponent()
        let base = repo.lastPathComponent
        var index = 1
        var branch = "worktree-\(index)"
        var dest = parent.appendingPathComponent("\(base)-\(branch)")
        while fm.fileExists(atPath: dest.path) {
            index += 1
            branch = "worktree-\(index)"
            dest = parent.appendingPathComponent("\(base)-\(branch)")
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", repo.path, "worktree", "add", "-b", branch, dest.path]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return (nil, "Couldn't run git: \(error.localizedDescription)")
        }
        guard proc.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (nil, output.isEmpty ? "git worktree add failed." : output)
        }
        return (dest.standardizedFileURL, nil)
    }

    /// Projects the user has archived (full blobs, for the Settings "Archived"
    /// page). Ordered by name so the list is stable.
    var archivedProjects: [Project] {
        projects
            .filter { archivedProjectPaths.contains($0.path.path) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Codex "Archive all chats" — archive every currently-active project.
    func archiveAllProjects() {
        for project in projects where !archivedProjectPaths.contains(project.path.path) {
            archivedProjectPaths.insert(project.path.path)
        }
        pinnedProjectPaths.removeAll()
        saveSidebarPreferences()
    }

    /// True when every project is currently collapsed. Drives the header
    /// "collapse/expand all" button's icon and its next action.
    var allProjectsCollapsed: Bool {
        let paths = projects.map { $0.path.path }
        guard !paths.isEmpty else { return projectsCollapsed }
        return paths.allSatisfy { collapsedProjectPaths.contains($0) }
    }

    /// The header "collapse/expand all" control. It is authoritative: collapsing
    /// adds every project to the collapsed set, expanding clears the set — so it
    /// always overrides whatever the user collapsed/expanded individually (the
    /// previous global-flag approach left manually-collapsed rows stuck).
    func toggleProjectsCollapsed() {
        // Authoritative manual action — drop the auto-follow tracker so the next
        // overview open doesn't immediately re-collapse what was just expanded.
        autoExpandedProjectPath = nil
        if allProjectsCollapsed {
            collapsedProjectPaths.removeAll()           // expand all
            projectsCollapsed = false
        } else {
            collapsedProjectPaths = Set(projects.map { $0.path.path })  // collapse all
            projectsCollapsed = true
        }
        UserDefaults.standard.set(projectsCollapsed, forKey: "grokcode.projectsCollapsed")
        saveSidebarPreferences()
    }

    /// Whether a project's chats are hidden in the sidebar — driven solely by the
    /// per-project set so the "all" toggle and individual chevrons stay coherent.
    func isProjectCollapsed(_ project: Project) -> Bool {
        guard collapsibleGroupsEnabled else { return false }
        return collapsedProjectPaths.contains(project.path.path)
    }

    /// Flip a single project's collapse state and persist the per-project set.
    func toggleProjectCollapsed(_ project: Project) {
        // The user took manual control of the tree — stop auto-collapsing the last
        // opened project so their explicit expand/collapse choices stick.
        autoExpandedProjectPath = nil
        let path = project.path.path
        if collapsedProjectPaths.contains(path) {
            collapsedProjectPaths.remove(path)
        } else {
            collapsedProjectPaths.insert(path)
        }
        saveSidebarPreferences()
    }

    /// Expand a single project (used by the double-tap-to-expand gesture).
    func expandProject(_ project: Project) {
        collapsedProjectPaths.remove(project.path.path)
        saveSidebarPreferences()
    }

    /// Stable key for a branch bucket within a project.
    private func branchKey(_ project: Project, _ branch: String?) -> String {
        "\(project.path.path)::\(branch ?? "∅")"
    }

    /// Whether a branch sub-group's chats are hidden. Always false when the
    /// collapsible-groups feature is off.
    func isBranchCollapsed(_ project: Project, branch: String?) -> Bool {
        collapsibleGroupsEnabled && collapsedBranchKeys.contains(branchKey(project, branch))
    }

    /// Flip a branch sub-group's collapse state and persist it.
    func toggleBranchCollapsed(_ project: Project, branch: String?) {
        let key = branchKey(project, branch)
        if collapsedBranchKeys.contains(key) {
            collapsedBranchKeys.remove(key)
        } else {
            collapsedBranchKeys.insert(key)
        }
        saveSidebarPreferences()
    }

    /// Caches for sidebar-derived lists. Keys use cheap metadata + the session
    /// snapshot revision instead of hashing every nested chat row on render.
    private var _sidebarProjectGroupsCache: (key: Int, value: [SidebarProjectGroup])?
    private var _sidebarFlatThreadsCache: (key: Int, value: [SidebarFlatThread])?

    func invalidateSidebarCaches() {
        _sidebarProjectGroupsCache = nil
        _sidebarFlatThreadsCache = nil
    }

    var sidebarProjectGroups: [SidebarProjectGroup] {
        var hasher = Hasher()
        hasher.combine(sessionIndexRevision)
        hasher.combine(projects.count)
        for project in projects {
            hasher.combine(project.id)
            hasher.combine(project.name)
            hasher.combine(project.path.path)
            hasher.combine(project.gitBranch)
            hasher.combine(project.lastActiveAt)
        }
        hasher.combine(sidebarGroupBy)
        hasher.combine(sidebarStatusFilter)
        hasher.combine(sidebarSort)
        hasher.combine(sidebarProjectSearch)
        hasher.combine(archivedProjectPaths)
        hasher.combine(pinnedProjectPaths)
        hasher.combine(pendingChat)
        let key = hasher.finalize()

        if let cached = _sidebarProjectGroupsCache, cached.key == key {
            return cached.value
        }
        let value = computeSidebarProjectGroups()
        _sidebarProjectGroupsCache = (key, value)
        return value
    }

    private func computeSidebarProjectGroups() -> [SidebarProjectGroup] {
        let active = sortedSidebarProjects(includeArchived: false)
        let archived = sortedSidebarProjects(includeArchived: true)
            .filter { archivedProjectPaths.contains($0.path.path) }

        switch sidebarGroupBy {
        case .flatList:
            return []
        case .project, .projectBranch:
            // Both surface the project list; the Sidebar lane renders the
            // per-branch sub-grouping for `.projectBranch` from these projects.
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
        var hasher = Hasher()
        hasher.combine(sessionIndexRevision)
        hasher.combine(projects.count)
        for project in projects {
            hasher.combine(project.id)
            hasher.combine(project.name)
            hasher.combine(project.path.path)
            hasher.combine(project.gitBranch)
        }
        hasher.combine(sidebarStatusFilter)
        hasher.combine(sidebarProjectSearch)
        hasher.combine(archivedProjectPaths)
        hasher.combine(pinnedProjectPaths)
        hasher.combine(pendingChat)
        let key = hasher.finalize()

        if let cached = _sidebarFlatThreadsCache, cached.key == key {
            return cached.value
        }

        let indexed = sessionIndexSnapshot?.indexedSessions ?? []
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path.standardizedFileURL.path, $0) })
        let query = sidebarProjectSearch.trimmingCharacters(in: .whitespacesAndNewlines)

        func resolveProject(for session: IndexedSession) -> Project? {
            let projectPath = session.cwd.standardizedFileURL.path
            return projectByPath[projectPath]
                ?? projects.first(where: { projectPath.hasPrefix($0.path.standardizedFileURL.path + "/") || projectPath == $0.path.standardizedFileURL.path })
        }

        func passesFilters(_ session: IndexedSession, _ project: Project) -> Bool {
            if archivedProjectPaths.contains(project.path.path) { return false }
            switch sidebarStatusFilter {
            case .all, .withChats: break
            case .noChats: return false
            case .pinnedOnly:
                guard pinnedProjectPaths.contains(project.path.path) else { return false }
            }
            if !query.isEmpty {
                let matches = project.name.localizedCaseInsensitiveContains(query)
                    || session.title.localizedCaseInsensitiveContains(query)
                guard matches else { return false }
            }
            return true
        }

        func makeRow(_ session: IndexedSession, in project: Project, subThreads: [SidebarFlatThread] = []) -> SidebarFlatThread {
            SidebarFlatThread(
                id: session.id,
                title: session.title,
                ageLabel: relativeAge(from: session.lastActive),
                project: project,
                isSubagent: session.kind == .subagent,
                agentName: session.agentName,
                subThreads: subThreads
            )
        }

        // Bucket subagents by parent so they render nested beneath the chat that
        // spawned them (mirrors the grouped/project lists).
        let normalIds = Set(indexed.filter { $0.kind != .subagent }.map(\.id))
        var childrenByParent: [String: [IndexedSession]] = [:]
        for session in indexed where session.kind == .subagent {
            if let parentId = session.parentSessionId, normalIds.contains(parentId) {
                childrenByParent[parentId, default: []].append(session)
            }
        }
        for parentId in childrenByParent.keys {
            childrenByParent[parentId]?.sort { $0.lastActive < $1.lastActive }
        }

        let rows = indexed.compactMap { session -> SidebarFlatThread? in
            guard let project = resolveProject(for: session), passesFilters(session, project) else { return nil }

            if session.kind == .subagent {
                if let parentId = session.parentSessionId, normalIds.contains(parentId) {
                    return nil   // rendered nested under its parent
                }
                return makeRow(session, in: project)   // orphan → top level
            }

            let children: [SidebarFlatThread] = (childrenByParent[session.id] ?? []).compactMap { child in
                guard let childProject = resolveProject(for: child) else { return nil }
                return makeRow(child, in: childProject)
            }
            return makeRow(session, in: project, subThreads: children)
        }

        // Surface the optimistic "New chat" placeholder at the top of the flat
        // list the instant a chat starts, before grok persists the session.
        if let pending = pendingChat, let path = pending.projectPath,
           !rows.contains(where: { $0.id == pending.id }),
           let project = projects.first(where: { $0.path.standardizedFileURL == path }),
           !archivedProjectPaths.contains(project.path.path) {
            let placeholder = SidebarFlatThread(
                id: pending.id,
                title: "New chat",
                ageLabel: "Now",
                project: project,
                isPending: true
            )
            let value = [placeholder] + rows
            _sidebarFlatThreadsCache = (key, value)
            return value
        }

        _sidebarFlatThreadsCache = (key, rows)
        return rows
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

    // MARK: - Community marketplace

    /// Load the community marketplace from `MarketplaceService` (remote manifest,
    /// with on-disk cache fallback) and map each entry to a `Plugin`, tagging
    /// installed state from the persisted set. Never throws — on any failure the
    /// service returns `[]` (or the last cached list) and `communityPlugins` is
    /// simply set to whatever came back. Safe to call on appear / from a Rescan.
    func loadCommunityPlugins() async {
        let entries = await marketplace.loadCommunityEntries()
        let installedIDs = Set(installedPlugins.map(\.id))
        communityPlugins = entries.map { entry in
            entry.toPlugin(isInstalled: installedIDs.contains(entry.id))
        }
    }

    /// Reload the user's own published plugins from the local published store and
    /// map them to `Plugin`s (with installed state). Cheap, synchronous.
    func refreshPublishedPlugins() {
        let installedIDs = Set(installedPlugins.map(\.id))
        publishedPlugins = marketplace.loadPublishedEntries().map { entry in
            entry.toPlugin(isInstalled: installedIDs.contains(entry.id))
        }
    }

    /// Publish a plugin the user authored: append it to the local published store
    /// and refresh `publishedPlugins`. Closes the publish sheet and surfaces a
    /// toast. (The PR-submission JSON is rendered by `MarketplaceService` for the
    /// surface lane to copy/open.)
    func publishPlugin(_ entry: MarketplaceEntry) {
        marketplace.publish(entry)
        refreshPublishedPlugins()
        publishSheetOpen = false
        pluginToast = "Published \(entry.name)"
    }

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

    /// Run an automation now (headless via its selected provider). Stamps `lastRun` and
    /// refreshes the list. Failures are surfaced on `errorMessage`.
    func runAutomation(_ automation: Automation) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.runAutomationNow(automation)
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

    /// Load the grok CLI session list on demand (first Search-page open). No-op
    /// after the first successful call this launch, and a no-op when grok isn't
    /// installed. Deliberately not called at startup — see `bootstrap()`.
    func loadCLISessionsIfNeeded() async {
        guard !didLoadCLISessions, grokAvailable else { return }
        didLoadCLISessions = true
        sessions = (try? await grok.listSessions()) ?? sessions
    }

    var filteredSessions: [GrokSession] {
        guard !searchQuery.isEmpty else { return sessions }
        return sessions.filter {
            $0.summary.localizedCaseInsensitiveContains(searchQuery)
            || $0.id.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    /// Apply one coalesced batch of stream events to the assistant message. Runs
    /// once per flush (not once per chunk), so the transcript grows with a single
    /// append + re-render per frame instead of thousands. See `StreamCoalescer`.
    private func applyStreamBatch(_ batch: StreamCoalescer.Batch, assistantId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantId }) else { return }

        if !batch.reasoning.isEmpty { messages[index].reasoning += batch.reasoning }
        if !batch.text.isEmpty { messages[index].text += batch.text }
        for tool in batch.tools { upsertToolCall(tool, at: index) }

        if batch.ended {
            messages[index].isStreaming = false
            // Any tool row still showing "running" at turn-end is complete.
            for i in messages[index].toolCalls.indices
            where messages[index].toolCalls[i].status == .running {
                messages[index].toolCalls[i].status = .done
            }
            if let sessionId = batch.endSessionId {
                activeSessionId = sessionId
            }
        }
    }

    /// Insert or update a tool-call row on the assistant message at `index`,
    /// keyed by the ACP `toolCallId`. A seeding `tool_call` inserts a running
    /// row; later `tool_call_update`s refine the title/kind/detail in place and
    /// flip the status to `.done` when the payload reports completion. Refined
    /// (non-empty) title/kind/detail never overwrite known values with blanks.
    private func upsertToolCall(_ tool: ToolEventPayload, at index: Int) {
        let status: ToolCallEntry.Status = tool.done ? .done : .running
        // ACP `tool_call_update`s often carry the tool's *cumulative* output, so a
        // long-running / looping tool re-sends an ever-larger `detail`. Cap it: the
        // UI can't usefully show more, and this stops one row's string from growing
        // without bound.
        let detail = Self.cappedToolDetail(tool.detail)
        if let row = messages[index].toolCalls.firstIndex(where: { $0.id == tool.id }) {
            if !tool.title.isEmpty { messages[index].toolCalls[row].title = tool.title }
            if !tool.kind.isEmpty { messages[index].toolCalls[row].kind = tool.kind }
            if !detail.isEmpty { messages[index].toolCalls[row].detail = detail }
            // Never regress a completed row back to running.
            if tool.done { messages[index].toolCalls[row].status = .done }
        } else {
            messages[index].toolCalls.append(
                ToolCallEntry(
                    id: tool.id,
                    title: tool.title,
                    kind: tool.kind,
                    detail: detail,
                    status: status
                )
            )
        }
    }

    /// Longest tool-call detail we retain per row. Generous enough for a full diff
    /// or command output, small enough that a pathological cumulative stream can't
    /// grow the transcript into the gigabytes.
    private static let maxToolDetailLength = 64_000

    private static func cappedToolDetail(_ detail: String) -> String {
        guard detail.count > maxToolDetailLength else { return detail }
        return String(detail.prefix(maxToolDetailLength)) + "\n… (truncated)"
    }

    /// An isolated, empty working directory for "Don't work in a project" runs,
    /// so grok never touches the user's home folder / protected files.
    static func noProjectScratchDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Codessa/no-project-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Current active git branch for the provided project folder. This mirrors
    /// `git -C <folder>` by walking up to a containing repo, but never scans
    /// child folders, so container directories don't borrow a child repo branch.
    nonisolated static func gitBranch(for path: URL) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path.path, isDirectory: &isDir) else { return nil }

        var current = (isDir.boolValue ? path : path.deletingLastPathComponent()).standardizedFileURL
        while true {
            if let branch = branch(atGit: current.appendingPathComponent(".git")) { return branch }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    private nonisolated static func branch(atGit gitPath: URL) -> String? {
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

    /// Rescans the on-disk session index and each project's git branch in a
    /// latest-wins background task. Navigation never awaits this path: views
    /// render from the last completed snapshot, then settle when this applies.
    func refreshSessionSnapshot() {
        let paths = projects.map(\.path)
        let sessionIndex = sessionIndex
        let noProjectPath = Self.noProjectScratchDirectory()
        sessionSnapshotRefreshID &+= 1
        let refreshID = sessionSnapshotRefreshID

        sessionSnapshotRefreshTask?.cancel()
        sessionSnapshotRefreshTask = Task { [weak self] in
            let (snapshot, branches): (SessionIndexSnapshot, [String?]) = await Task.detached(priority: .userInitiated) {
                let branches = paths.map { AppViewModel.gitBranch(for: $0) }
                let snapshot = sessionIndex.loadSnapshot(
                    projectPaths: paths,
                    projectBranches: branches,
                    noProjectPath: noProjectPath
                )
                return (snapshot, branches)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, refreshID == self.sessionSnapshotRefreshID else { return }
                self.applySessionSnapshot(snapshot, projectPaths: paths, branches: branches)
            }
        }
    }

    private func applySessionSnapshot(
        _ snapshot: SessionIndexSnapshot,
        projectPaths: [URL],
        branches: [String?]
    ) {
        sessionIndexSnapshot = snapshot
        // Once the real session backing the in-progress chat is on disk, retire
        // the optimistic "New chat" placeholder so it doesn't double up.
        if pendingChat != nil, let active = activeSessionId,
           snapshot.indexedSessions.contains(where: { $0.id == active }) {
            pendingChat = nil
        }

        let branchByProjectPath = Dictionary(
            uniqueKeysWithValues: zip(projectPaths.map { $0.standardizedFileURL.path }, branches)
        )
        for index in projects.indices {
            let path = projects[index].path
            let normalizedPath = path.standardizedFileURL.path
            let branch = branchByProjectPath[normalizedPath] ?? nil
            projects[index].threads = snapshot.threadsByProjectPath[normalizedPath] ?? []
            projects[index].gitBranch = branch
            projects[index].lastActiveAt = snapshot.lastActiveByProjectPath[normalizedPath]

            if projects[index].createdAt == nil {
                projects[index].createdAt = (try? path.resourceValues(forKeys: [.creationDateKey]).creationDate)
            }
        }

        if let selected = selectedProject,
           let idx = projects.firstIndex(where: { $0.id == selected.id }) {
            selectedProject = projects[idx]
        }

        noProjectThreads = snapshot.noProjectThreads
        sessionIndexRevision &+= 1
        _sidebarProjectGroupsCache = nil
        _sidebarFlatThreadsCache = nil
    }

    private func sortedSidebarProjects(includeArchived: Bool) -> [Project] {
        var result = projects
            // Removed projects never appear in the active or archived lists.
            .filter { !hiddenProjectPaths.contains($0.path.path) }
            // Apply any custom display-name overrides set via "Rename project".
            .map { project -> Project in
                guard let custom = projectNameOverrides[project.path.path], !custom.isEmpty else {
                    return project
                }
                var renamed = project
                renamed.name = custom
                return renamed
            }

        if includeArchived {
            result = result.filter { archivedProjectPaths.contains($0.path.path) }
        } else {
            result = result.filter { !archivedProjectPaths.contains($0.path.path) }
            // Inject the optimistic "New chat" placeholder before the status/search
            // filters run, so a project shown only because a chat is starting isn't
            // hidden by ".withChats" and so the row groups under the current branch.
            result = result.map(injectingPendingChat)
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
        case .withChats:
            // Prefer chatted projects when they exist, but do not dead-end the
            // sidebar on a first run where every discovered folder is chat-less.
            if !includeArchived {
                // Qualify on *real* chats only — a just-started chat injects a
                // pending placeholder, and counting it here would collapse the
                // whole sidebar down to only the active project the instant a
                // chat starts. Ignoring pending threads keeps every project
                // visible; the sort simply floats the active one to the top.
                let projectsWithChats = result.filter { project in
                    project.threads.contains { !$0.isPending }
                }
                if !projectsWithChats.isEmpty {
                    result = projectsWithChats
                }
            }
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

    /// Prepend the in-progress "New chat" placeholder to its project's thread list
    /// so the sidebar reflects a freshly started chat immediately. No-op unless a
    /// `pendingChat` is set for this project.
    private func injectingPendingChat(_ project: Project) -> Project {
        guard let pending = pendingChat,
              let path = pending.projectPath,
              project.path.standardizedFileURL == path,
              !project.threads.contains(where: { $0.id == pending.id }) else { return project }
        var updated = project
        updated.threads.insert(
            ProjectThread(
                id: pending.id,
                title: "New chat",
                ageLabel: "Now",
                branch: project.gitBranch,
                isPending: true
            ),
            at: 0
        )
        return updated
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
        if let hidden = UserDefaults.standard.array(forKey: hiddenProjectsKey) as? [String] {
            hiddenProjectPaths = Set(hidden)
        }
        if let overrides = UserDefaults.standard.dictionary(forKey: projectNameOverridesKey) as? [String: String] {
            projectNameOverrides = overrides
        }
        if let collapsed = UserDefaults.standard.array(forKey: collapsedProjectsKey) as? [String] {
            collapsedProjectPaths = Set(collapsed)
        }
        if let seen = UserDefaults.standard.array(forKey: seenProjectPathsKey) as? [String] {
            seenProjectPaths = Set(seen)
        }
        projectsCollapsed = UserDefaults.standard.bool(forKey: "grokcode.projectsCollapsed")
        if let branches = UserDefaults.standard.array(forKey: collapsedBranchesKey) as? [String] {
            collapsedBranchKeys = Set(branches)
        }
        if UserDefaults.standard.object(forKey: Self.collapsibleGroupsKey) != nil {
            collapsibleGroupsEnabled = UserDefaults.standard.bool(forKey: Self.collapsibleGroupsKey)
        }
    }

    private func saveSidebarPreferences() {
        UserDefaults.standard.set(sidebarStatusFilter.rawValue, forKey: sidebarFilterKey)
        UserDefaults.standard.set(sidebarGroupBy.rawValue, forKey: sidebarGroupByKey)
        UserDefaults.standard.set(sidebarSort.rawValue, forKey: sidebarSortKey)
        UserDefaults.standard.set(Array(pinnedProjectPaths), forKey: pinnedProjectsKey)
        UserDefaults.standard.set(Array(archivedProjectPaths), forKey: archivedProjectsKey)
        UserDefaults.standard.set(Array(hiddenProjectPaths), forKey: hiddenProjectsKey)
        UserDefaults.standard.set(projectNameOverrides, forKey: projectNameOverridesKey)
        UserDefaults.standard.set(Array(collapsedProjectPaths), forKey: collapsedProjectsKey)
        UserDefaults.standard.set(Array(collapsedBranchKeys), forKey: collapsedBranchesKey)
    }

    /// Restore appearance / layout preferences from UserDefaults. Reads each key
    /// only if present so the inline defaults (system / 280 / collapsed=false /
    /// sendOnReturn=true / warm=true) stand in for a fresh install. Runs early
    /// (from `init`) so there's no light→dark flash on launch.
    private func loadAppearancePreferences() {
        let d = UserDefaults.standard
        loadPreferences()
        if let raw = d.string(forKey: Self.appearanceKey),
           let value = AppAppearance(rawValue: raw) {
            appearance = value
        }
        if d.object(forKey: Self.sidebarWidthKey) != nil {
            let storedWidth = d.double(forKey: Self.sidebarWidthKey)
            let migratedWidth = (storedWidth == 290 || storedWidth <= 220) ? 280 : storedWidth
            sidebarWidth = min(max(migratedWidth, 240), 340)
        }
        if d.object(forKey: Self.sidebarCollapsedKey) != nil {
            sidebarCollapsed = d.bool(forKey: Self.sidebarCollapsedKey)
        }
        if d.object(forKey: Self.sendOnReturnKey) != nil {
            sendOnReturn = d.bool(forKey: Self.sendOnReturnKey)
        }
        if d.object(forKey: Self.warmSessionKey) != nil {
            warmSessionEnabled = d.bool(forKey: Self.warmSessionKey)
        }
    }

    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
              let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return }
        preferences = decoded
    }

    func resetPreferencesScope(_ scope: SettingsPreferenceScope) {
        var copy = preferences
        let defaults = AppPreferences.defaults
        switch scope {
        case .all:
            copy = defaults
        case .general:
            copy.launchPage = defaults.launchPage
            copy.restoreLastPage = defaults.restoreLastPage
            copy.openSplitViewOnLaunch = defaults.openSplitViewOnLaunch
            copy.showLaunchMascot = defaults.showLaunchMascot
            copy.allowFollowupQueue = defaults.allowFollowupQueue
            copy.defaultPursueGoal = defaults.defaultPursueGoal
            copy.defaultPlanMode = defaults.defaultPlanMode
            copy.keepComposerDraft = defaults.keepComposerDraft
            copy.clearComposerAfterSend = defaults.clearComposerAfterSend
            copy.confirmStopRunning = defaults.confirmStopRunning
            copy.confirmDestructiveActions = defaults.confirmDestructiveActions
            copy.defaultAttachmentBehavior = defaults.defaultAttachmentBehavior
            copy.defaultNewChatLocation = defaults.defaultNewChatLocation
        case .appearance:
            copy.accent = defaults.accent
            copy.highContrast = defaults.highContrast
            copy.vibrancyEnabled = defaults.vibrancyEnabled
            copy.ambientBackgroundEnabled = defaults.ambientBackgroundEnabled
            copy.reduceMotion = defaults.reduceMotion
            copy.animationSpeed = defaults.animationSpeed
            copy.uiFontSize = defaults.uiFontSize
            copy.chatFontSize = defaults.chatFontSize
            copy.codeFontSize = defaults.codeFontSize
            copy.messageDensity = defaults.messageDensity
            copy.bubbleStyle = defaults.bubbleStyle
            copy.showTimestamps = defaults.showTimestamps
            copy.toolCallStyle = defaults.toolCallStyle
            copy.wrapCode = defaults.wrapCode
            copy.showCodeLineNumbers = defaults.showCodeLineNumbers
        case .personalization:
            copy.contextFilePolicy = defaults.contextFilePolicy
            copy.contextEnabled = defaults.contextEnabled
            copy.languagePreference = defaults.languagePreference
            copy.responseLength = defaults.responseLength
            copy.explanationDepth = defaults.explanationDepth
            copy.tonePreset = defaults.tonePreset
            copy.preferBritishEnglish = defaults.preferBritishEnglish
            copy.avoidEmDashes = defaults.avoidEmDashes
            copy.preserveUserWording = defaults.preserveUserWording
            copy.draftOnlyMessaging = defaults.draftOnlyMessaging
            copy.showPlansByDefault = defaults.showPlansByDefault
            copy.askBeforeAssumptions = defaults.askBeforeAssumptions
            copy.includeProjectRules = defaults.includeProjectRules
            copy.includeStyleRules = defaults.includeStyleRules
        case .shortcuts:
            copy.shortcutPreset = defaults.shortcutPreset
            copy.shortcutsEnabled = defaults.shortcutsEnabled
            copy.shortcutSearch = defaults.shortcutSearch
            copy.customShortcuts = defaults.customShortcuts
        case .mcp:
            copy.mcpSearch = defaults.mcpSearch
            copy.mcpFilter = defaults.mcpFilter
            copy.mcpSort = defaults.mcpSort
            copy.mcpShowDetails = defaults.mcpShowDetails
            copy.mcpShowEnvKeys = defaults.mcpShowEnvKeys
            copy.mcpRequireWriteConfirmation = defaults.mcpRequireWriteConfirmation
        case .hooks:
            copy.hookSearch = defaults.hookSearch
            copy.hookFilter = defaults.hookFilter
            copy.hookCompactView = defaults.hookCompactView
            copy.hookShowCommandPreview = defaults.hookShowCommandPreview
            copy.hookRequireTrustAllConfirmation = defaults.hookRequireTrustAllConfirmation
        case .cli:
            copy.grokBinaryOverride = defaults.grokBinaryOverride
            copy.forceOneShotMode = defaults.forceOneShotMode
            copy.inactivityTimeoutSeconds = defaults.inactivityTimeoutSeconds
            copy.defaultSessionLimit = defaults.defaultSessionLimit
            copy.copyDiagnosticsIncludesSettings = defaults.copyDiagnosticsIncludesSettings
        case .data:
            copy.retentionDays = defaults.retentionDays
            copy.autoCleanOnLaunch = defaults.autoCleanOnLaunch
            copy.exportBeforeDelete = defaults.exportBeforeDelete
            copy.includeSettingsInDiagnostics = defaults.includeSettingsInDiagnostics
            copy.includeSystemInfoInDiagnostics = defaults.includeSystemInfoInDiagnostics
        case .archive:
            copy.archiveSearch = defaults.archiveSearch
            copy.archiveSort = defaults.archiveSort
            copy.archiveFilter = defaults.archiveFilter
            copy.keepPinnedUnarchived = defaults.keepPinnedUnarchived
            copy.autoArchiveInactiveProjects = defaults.autoArchiveInactiveProjects
            copy.archiveInactiveDays = defaults.archiveInactiveDays
        }
        preferences = copy
    }

    /// Toggle the sidebar collapsed state (didSet persists it).
    func toggleSidebarCollapsed() {
        sidebarCollapsed.toggle()
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
        do {
            let data = try JSONEncoder().encode(paths)
            UserDefaults.standard.set(data, forKey: rootsKey)
        } catch {
            // Never silently drop the project-roots write.
            #if DEBUG
            print("[AppViewModel] Failed to persist project roots: \(error)")
            #endif
        }
    }

    init() {
        loadRoots()
        loadSidebarPreferences()
        loadAppearancePreferences()
        setupActiveAppObserver()
    }
}

extension AppViewModel {
    func persistSidebarPreferences() {
        saveSidebarPreferences()
    }
}
