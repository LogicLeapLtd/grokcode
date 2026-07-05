import Foundation

nonisolated enum AgentModeKind: String, CaseIterable, Identifiable, Codable {
    case execute
    case plan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .execute: "Execution"
        case .plan: "Planning"
        }
    }

    var symbol: String {
        switch self {
        case .execute: "hammer"
        case .plan: "list.bullet.clipboard"
        }
    }
}

nonisolated enum ModeModelSelection: String, CaseIterable, Identifiable, Codable {
    case inheritParent
    case explicit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inheritParent: "Inherit chat model"
        case .explicit: "Use specific model"
        }
    }
}

nonisolated struct ModeModelRoute: Hashable, Codable {
    var selection: ModeModelSelection
    var providerID: String
    var modelID: String

    init(
        selection: ModeModelSelection = .inheritParent,
        providerID: String = AgentProvider.wiredDefault.id,
        modelID: String = ""
    ) {
        self.selection = selection
        self.providerID = providerID
        self.modelID = modelID
    }

    var usesParentModel: Bool {
        selection == .inheritParent || modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

nonisolated struct AgentModeProfile: Identifiable, Hashable, Codable {
    static let executeID = "execute"
    static let planID = "plan"

    var id: String
    var name: String
    var kind: AgentModeKind
    var permissionMode: PermissionMode
    var planningRoute: ModeModelRoute
    var executionRoute: ModeModelRoute
    var customInstructions: String
    var isBuiltIn: Bool

    init(
        id: String,
        name: String,
        kind: AgentModeKind,
        permissionMode: PermissionMode,
        planningRoute: ModeModelRoute = ModeModelRoute(),
        executionRoute: ModeModelRoute = ModeModelRoute(),
        customInstructions: String = "",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.permissionMode = permissionMode
        self.planningRoute = planningRoute
        self.executionRoute = executionRoute
        self.customInstructions = customInstructions
        self.isBuiltIn = isBuiltIn
    }

    var activeRoute: ModeModelRoute {
        kind == .plan ? planningRoute : executionRoute
    }

    var lockedInstructions: String {
        switch kind {
        case .execute:
            return "Execute the approved task using the selected permission mode. Keep the user informed and verify the result before handing back."
        case .plan:
            return """
            You are in Plan mode. Do not modify files, run destructive commands, push, publish, or change external state.
            Produce a concrete plan for the requested work, then finish the response with exactly one XML block named <present_plan>.
            The <present_plan> block must include a short <title>, a <summary>, and one <step> element per planned step.
            """
        }
    }

    var routeSummary: String {
        let route = activeRoute
        if route.usesParentModel {
            return "Inherits chat model"
        }
        let provider = AgentProvider.known.first { $0.id == route.providerID }?.shortName
            ?? route.providerID.capitalized
        let model = GrokModelOption(id: route.modelID, isDefault: false, providerId: route.providerID).displayName
        return "\(provider) · \(model)"
    }

    static let defaults: [AgentModeProfile] = [
        AgentModeProfile(
            id: executeID,
            name: "Execute",
            kind: .execute,
            permissionMode: .fullAccess,
            executionRoute: ModeModelRoute(selection: .inheritParent),
            isBuiltIn: true
        ),
        AgentModeProfile(
            id: planID,
            name: "Plan",
            kind: .plan,
            permissionMode: .plan,
            planningRoute: ModeModelRoute(selection: .inheritParent),
            executionRoute: ModeModelRoute(selection: .inheritParent),
            isBuiltIn: true
        ),
    ]
}

nonisolated struct PresentedPlan: Hashable {
    let title: String
    let summary: String
    let steps: [String]
    let bodyText: String

    static func extract(from text: String) -> PresentedPlan? {
        guard let openRange = text.range(of: "<present_plan>", options: [.caseInsensitive]),
              let closeRange = text.range(of: "</present_plan>", options: [.caseInsensitive])
        else { return nil }

        let xml = String(text[openRange.upperBound..<closeRange.lowerBound])
        let body = (text[..<openRange.lowerBound] + text[closeRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let title = firstTag("title", in: xml) ?? "Plan"
        let summary = firstTag("summary", in: xml) ?? ""
        let steps = allTags("step", in: xml)
        return PresentedPlan(title: title, summary: summary, steps: steps, bodyText: body)
    }

    private static func firstTag(_ tag: String, in text: String) -> String? {
        allTags(tag, in: text).first
    }

    private static func allTags(_ tag: String, in text: String) -> [String] {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
