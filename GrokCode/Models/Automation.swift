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

    /// Model id to run with, e.g. "grok-composer-2.5-fast".
    var modelId: String

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

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        projectPath: String? = nil,
        modelId: String,
        scheduleKind: AutomationScheduleKind = .manual,
        intervalMinutes: Int? = nil,
        timeOfDay: String? = nil,
        enabled: Bool = true,
        lastRun: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.projectPath = projectPath
        self.modelId = modelId
        self.scheduleKind = scheduleKind
        self.intervalMinutes = intervalMinutes
        self.timeOfDay = timeOfDay
        self.enabled = enabled
        self.lastRun = lastRun
        self.createdAt = createdAt
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

    /// A copy with `lastRun` stamped to `date`. Services use this rather than
    /// mutating in place.
    func markingRun(at date: Date = Date()) -> Automation {
        var copy = self
        copy.lastRun = date
        return copy
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
