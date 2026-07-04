import Foundation

/// How an `Automation` is triggered. Raw values are persisted (JSON in
/// UserDefaults); do not rename them.
enum AutomationScheduleKind: String, CaseIterable, Identifiable, Hashable, Codable {
    /// Only runs when the user taps "Run now".
    case manual
    /// Repeats every `intervalMinutes` while the app is open.
    case interval
    /// Runs once per day at `timeOfDay` ("HH:mm") while the app is open.
    case daily

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .interval: "Every interval"
        case .daily: "Daily"
        }
    }

    var symbol: String {
        switch self {
        case .manual: "hand.tap"
        case .interval: "timer"
        case .daily: "calendar"
        }
    }
}

/// A single recorded execution of an `Automation` — the timestamp and whether
/// the grok run succeeded. Kept in a small ring (see `Automation.maxRunHistory`)
/// so the card can show a recent run trail. Fully `Codable` for persistence.
struct AutomationRun: Hashable, Codable, Identifiable {
    /// When the run finished.
    var date: Date
    /// `true` if the grok invocation completed without throwing.
    var ok: Bool

    /// Stable identity for `ForEach`: the run instant. Two runs can't share an
    /// instant in practice (they're serialised through one CLI call).
    var id: Date { date }

    init(date: Date = Date(), ok: Bool) {
        self.date = date
        self.ok = ok
    }
}

/// A user-defined automation: a saved grok prompt that can be run on demand or
/// on a simple in-app schedule (interval / daily). Pure value type, fully
/// `Codable` for UserDefaults persistence.
struct Automation: Identifiable, Hashable, Codable {
    let id: UUID

    /// Display name, e.g. "Weekly release notes".
    var name: String

    /// The prompt sent to grok when the automation runs.
    var prompt: String

    /// Absolute path of the project to run in. `nil` ⇒ run in the home
    /// directory (the "no project" case, matching the chat flow).
    var projectPath: String?

    /// Provider instance id and model id to run with. Older automations did not
    /// persist `providerId`; they decode as Grok for compatibility.
    var providerId: String

    /// Model id to run with, e.g. "grok-composer-2.5-fast".
    var modelId: String

    /// Provider/model option selections, keyed by provider option id.
    var optionSelections: [String: String]

    /// Trigger type.
    var scheduleKind: AutomationScheduleKind

    /// Minutes between runs when `scheduleKind == .interval`.
    var intervalMinutes: Int?

    /// "HH:mm" 24-hour local time when `scheduleKind == .daily`.
    var timeOfDay: String?

    /// Whether the schedule is armed. Manual automations ignore this for
    /// scheduling but still surface it in the UI as an enabled/disabled state.
    var enabled: Bool

    /// Timestamp of the most recent run (nil if never run).
    var lastRun: Date?

    /// When the automation was created.
    var createdAt: Date

    /// Recent run trail (most-recent first), capped at `maxRunHistory`. Appended
    /// to by `markingRun(at:ok:)`; surfaced on the card.
    var runHistory: [AutomationRun]

    // MARK: Validation limits (shared by the editor)

    /// Longest accepted automation name.
    static let maxNameLength = 80
    /// Longest accepted prompt.
    static let maxPromptLength = 4000
    /// How many runs to retain in `runHistory`.
    static let maxRunHistory = 5

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        projectPath: String? = nil,
        providerId: String = AgentProvider.grok.id,
        modelId: String,
        optionSelections: [String: String] = [:],
        scheduleKind: AutomationScheduleKind = .manual,
        intervalMinutes: Int? = nil,
        timeOfDay: String? = nil,
        enabled: Bool = true,
        lastRun: Date? = nil,
        createdAt: Date = Date(),
        runHistory: [AutomationRun] = []
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.projectPath = projectPath
        self.providerId = providerId
        self.modelId = modelId
        self.optionSelections = optionSelections
        self.scheduleKind = scheduleKind
        self.intervalMinutes = intervalMinutes
        self.timeOfDay = timeOfDay
        self.enabled = enabled
        self.lastRun = lastRun
        self.createdAt = createdAt
        self.runHistory = runHistory
    }

    // MARK: Codable — tolerate older blobs without `runHistory`.

    private enum CodingKeys: String, CodingKey {
        case id, name, prompt, projectPath, providerId, modelId, optionSelections, scheduleKind
        case intervalMinutes, timeOfDay, enabled, lastRun, createdAt, runHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath)
        providerId = try c.decodeIfPresent(String.self, forKey: .providerId) ?? AgentProvider.grok.id
        modelId = try c.decode(String.self, forKey: .modelId)
        optionSelections = try c.decodeIfPresent([String: String].self, forKey: .optionSelections) ?? [:]
        scheduleKind = try c.decode(AutomationScheduleKind.self, forKey: .scheduleKind)
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes)
        timeOfDay = try c.decodeIfPresent(String.self, forKey: .timeOfDay)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        lastRun = try c.decodeIfPresent(Date.self, forKey: .lastRun)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        runHistory = try c.decodeIfPresent([AutomationRun].self, forKey: .runHistory) ?? []
    }

    // MARK: Display helpers

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled automation" : name
    }

    /// Folder name of the target project, or "Home" when project-less.
    var projectLabel: String {
        guard let projectPath, !projectPath.isEmpty else { return "Home" }
        return (projectPath as NSString).lastPathComponent
    }

    /// Human schedule summary, e.g. "Every 30 min", "Daily at 09:00", "Manual".
    var scheduleSummary: String {
        switch scheduleKind {
        case .manual:
            return "Manual"
        case .interval:
            guard let minutes = intervalMinutes, minutes > 0 else { return "Every interval" }
            if minutes % 60 == 0 {
                let hours = minutes / 60
                return hours == 1 ? "Every hour" : "Every \(hours) hours"
            }
            return "Every \(minutes) min"
        case .daily:
            return "Daily at \(timeOfDay ?? "09:00")"
        }
    }

    /// "<schedule> · <project>" caption used as the row subtitle.
    var subtitle: String {
        "\(scheduleSummary) · \(projectLabel)"
    }

    /// SF Symbol mirroring the schedule kind.
    var iconSystemName: String { scheduleKind.symbol }

    /// True when this automation participates in timer-based scheduling.
    var isScheduled: Bool {
        enabled && scheduleKind != .manual
    }

    /// Working-directory URL: the project path, or the home directory.
    var workingDirectory: URL {
        if let projectPath, !projectPath.isEmpty {
            return URL(fileURLWithPath: projectPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// A copy with `lastRun` stamped to `date` and a run appended to
    /// `runHistory` (newest first, capped at `maxRunHistory`). Services and the
    /// view-model use this rather than mutating in place. `ok` defaults to `true`
    /// so the scheduler's existing single-arg call records a success.
    func markingRun(at date: Date = Date(), ok: Bool = true) -> Automation {
        var copy = self
        copy.lastRun = date
        copy.runHistory.insert(AutomationRun(date: date, ok: ok), at: 0)
        if copy.runHistory.count > Self.maxRunHistory {
            copy.runHistory = Array(copy.runHistory.prefix(Self.maxRunHistory))
        }
        return copy
    }

    /// Whether the most recent recorded run succeeded (nil if never run).
    var lastRunSucceeded: Bool? { runHistory.first?.ok }

    /// The next time this automation is expected to fire, or `nil` for manual /
    /// disabled automations. Mirrors `AutomationService.isDue` so the card's
    /// "Next" line matches the scheduler.
    ///
    /// - `.interval`: `(lastRun ?? createdAt) + intervalMinutes`, advanced past
    ///   `now` so a long-idle automation shows its *upcoming* slot, not a stale
    ///   past one.
    /// - `.daily`: today's `timeOfDay` if still ahead and not yet run today,
    ///   otherwise tomorrow's.
    func nextRun(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isScheduled else { return nil }
        switch scheduleKind {
        case .manual:
            return nil
        case .interval:
            guard let minutes = intervalMinutes, minutes > 0 else { return nil }
            let step = Double(minutes) * 60
            var fire = (lastRun ?? createdAt).addingTimeInterval(step)
            if fire <= now {
                // Jump forward to the first slot strictly after `now`.
                let missed = (now.timeIntervalSince(fire) / step).rounded(.down) + 1
                fire = fire.addingTimeInterval(missed * step)
            }
            return fire
        case .daily:
            let (hour, minute) = timeOfDayComponents
            guard let todayFire = calendar.date(
                bySettingHour: hour, minute: minute, second: 0, of: now
            ) else { return nil }
            let ranToday = lastRun.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if todayFire > now && !ranToday {
                return todayFire
            }
            return calendar.date(byAdding: .day, value: 1, to: todayFire)
        }
    }

    /// Parsed (hour, minute) from `timeOfDay`; defaults to 09:00 when missing
    /// or malformed. Used by the daily scheduler.
    var timeOfDayComponents: (hour: Int, minute: Int) {
        let parts = (timeOfDay ?? "09:00").split(separator: ":")
        let hour = parts.count > 0 ? Int(parts[0]) ?? 9 : 9
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (min(max(hour, 0), 23), min(max(minute, 0), 59))
    }

    // MARK: Hashable / Equatable — identity is the id.

    static func == (lhs: Automation, rhs: Automation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
