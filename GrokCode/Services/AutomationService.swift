import Foundation

/// Persistence + simple in-app scheduling for user-defined `Automation`s.
///
/// Plain `final class` in the style of `ProjectDiscovery` — it is constructed and
/// consumed on the `@MainActor` `AppViewModel`, so every public method is
/// synchronous except `runNow` (which awaits the grok CLI). The master timer and
/// all `UserDefaults` access stay on the main run loop, so no `Sendable` /
/// isolation gymnastics are required; if this is ever touched off-main, mirror
/// the `GrokCLIService` `nonisolated + @unchecked Sendable` pattern instead.
final class AutomationService {
    /// Single UserDefaults key holding `Data` = `JSONEncoder().encode([Automation])`.
    private static let storageKey = "grokcode.automations"

    /// How often the master timer wakes to look for due automations.
    private static let tickInterval: TimeInterval = 30

    private let defaults: UserDefaults

    /// The repeating master timer that drives interval/daily scheduling. Owned by
    /// the service; created in `startScheduler`, invalidated in `stopScheduler`.
    private var schedulerTimer: Timer?

    /// Callback handed to us by `AppViewModel`; invoked on the main actor with the
    /// ids of automations whose trigger has elapsed. The caller performs the run
    /// and the `lastRun` update.
    private var onDue: (@MainActor ([UUID]) -> Void)?

    /// The schedule snapshot the timer evaluates each tick. Kept in sync via
    /// `reschedule(with:)` so the service never has to re-read UserDefaults on a
    /// hot path.
    private var scheduled: [Automation] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Persistence (UserDefaults JSON, key "grokcode.automations")

    /// Decode the persisted automations, returning `[]` on any failure (missing
    /// key, corrupt blob, schema drift). Never throws.
    func load() -> [Automation] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([Automation].self, from: data)) ?? []
    }

    /// Encode and persist the whole automation array. Silently no-ops if encoding
    /// fails (should never happen for a value-type `Codable`).
    func save(_ automations: [Automation]) {
        guard let data = try? JSONEncoder().encode(automations) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Append a new automation (load → append → save).
    func add(_ automation: Automation) {
        var all = load()
        all.append(automation)
        save(all)
    }

    /// Replace an existing automation in place by id (no-op if absent), then save.
    func update(_ automation: Automation) {
        var all = load()
        if let index = all.firstIndex(where: { $0.id == automation.id }) {
            all[index] = automation
        }
        save(all)
    }

    /// Remove an automation by id, then save. Idempotent.
    func delete(_ automation: Automation) {
        let all = load().filter { $0.id != automation.id }
        save(all)
    }

    // MARK: - Manual run

    /// Fire one automation now, headless, via the existing grok CLI surface. Uses
    /// `.auto` permissions by default (NOT `.plan`) so the run can actually do
    /// work; stream events are ignored (nothing is surfaced to chat). On success
    /// the automation's `lastRun` is stamped via `markingRun()` and persisted.
    /// Returns the final session id (or nil).
    @discardableResult
    func runNow(_ automation: Automation, using grok: GrokCLIService) async throws -> String? {
        let sessionId = try await grok.streamPrompt(
            automation.prompt,
            cwd: automation.workingDirectory,
            model: automation.modelId,
            permissionMode: .auto,
            effort: .medium,
            check: false,
            sessionId: nil,
            onEvent: { _ in }
        )

        // Stamp lastRun against the freshest persisted copy so we never clobber a
        // concurrent edit to the rest of the automation's fields.
        let now = Date()
        if let current = load().first(where: { $0.id == automation.id }) {
            update(current.markingRun(at: now))
        } else {
            update(automation.markingRun(at: now))
        }

        // Keep the in-memory schedule snapshot fresh so the next tick computes
        // due-ness from the new lastRun.
        reschedule(with: load())

        return sessionId
    }

    // MARK: - Simple in-app scheduling

    /// Start the master timer. `onDue` is invoked on the main actor with the ids
    /// of automations whose interval/daily trigger has elapsed; the caller
    /// (AppViewModel) performs the run + lastRun update. Seeds the schedule
    /// snapshot from persisted automations.
    func startScheduler(onDue: @escaping @MainActor ([UUID]) -> Void) {
        self.onDue = onDue
        scheduled = load()

        schedulerTimer?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common run-loop mode so the timer keeps firing during UI tracking
        // (menus, scrolling) instead of stalling.
        RunLoop.main.add(timer, forMode: .common)
        schedulerTimer = timer
    }

    /// Stop and tear down the master timer.
    func stopScheduler() {
        schedulerTimer?.invalidate()
        schedulerTimer = nil
    }

    /// Recompute the internal schedule snapshot from the current automation set.
    /// Call after any add/update/delete/toggle so due-ness is evaluated against
    /// the latest state.
    func reschedule(with automations: [Automation]) {
        scheduled = automations
    }

    // MARK: - Scheduling internals

    /// Evaluate the current snapshot and notify the caller of any due ids.
    private func tick() {
        let now = Date()
        let dueIDs = scheduled
            .filter { $0.isScheduled && isDue($0, now: now) }
            .map(\.id)

        guard !dueIDs.isEmpty else { return }

        // The caller stamps lastRun (via runAutomation → service.update), and is
        // expected to call reschedule afterwards. As a safety net, optimistically
        // bump the in-memory snapshot's lastRun now so a long-running job can't be
        // re-triggered on the very next tick before the caller persists.
        let dueSet = Set(dueIDs)
        for index in scheduled.indices where dueSet.contains(scheduled[index].id) {
            scheduled[index].lastRun = now
        }

        let callback = onDue
        Task { @MainActor in
            callback?(dueIDs)
        }
    }

    /// Has this automation's trigger elapsed as of `now`?
    ///
    /// - `.interval`: fire if `now - (lastRun ?? createdAt) >= intervalMinutes*60`.
    /// - `.daily`: fire if the local clock has passed `timeOfDayComponents` today
    ///   and it has not already run today.
    /// - `.manual`: never fires automatically.
    private func isDue(_ automation: Automation, now: Date) -> Bool {
        switch automation.scheduleKind {
        case .manual:
            return false

        case .interval:
            guard let minutes = automation.intervalMinutes, minutes > 0 else { return false }
            let reference = automation.lastRun ?? automation.createdAt
            return now.timeIntervalSince(reference) >= Double(minutes) * 60

        case .daily:
            let calendar = Calendar.current
            let (hour, minute) = automation.timeOfDayComponents
            guard let fireTime = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: now
            ) else {
                return false
            }
            // Not yet time today.
            guard now >= fireTime else { return false }
            // Already ran today? Then it's not due again until tomorrow.
            if let lastRun = automation.lastRun, calendar.isDate(lastRun, inSameDayAs: now) {
                return false
            }
            return true
        }
    }
}
