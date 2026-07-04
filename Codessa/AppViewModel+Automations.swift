import Foundation

/// Automations-lane methods on `AppViewModel`. Stored properties live in
/// `AppViewModel.swift` (Foundation lane); behaviour added here keeps lanes from
/// editing the same file.
///
/// `runAutomationNow` is the UI-driven sibling of the contract's fire-and-forget
/// `runAutomation`: it `await`s the headless provider run, records the outcome
/// (success *or* failure) into the automation's `runHistory` + `lastRun`, and
/// returns whether it succeeded so the card can flip its inline status from a
/// spinner to ✓ / ✗.
extension AppViewModel {
    /// Run one automation now, headless, and report success.
    ///
    /// Uses `.auto` permissions, no `check`, stream events discarded, but is awaitable and
    /// records failures too. Persistence goes through the same UserDefaults-backed
    /// store, then `loadAutomations()` refreshes the in-memory list and the
    /// scheduler snapshot — so the card, the schedule, and the next auto-run all
    /// see the new `lastRun`.
    ///
    /// - Returns: `true` if the grok invocation completed without throwing.
    @MainActor
    @discardableResult
    func runAutomationNow(_ automation: Automation) async -> Bool {
        let ok: Bool
        do {
            let request = try providerRunRequest(for: automation)
            _ = try await AgentProviderRuntime.shared.streamPrompt(request: request, onEvent: { _ in })
            ok = true
        } catch {
            errorMessage = error.localizedDescription
            ok = false
        }

        // Stamp against the freshest persisted copy so a concurrent edit to the
        // automation's other fields isn't clobbered. A private store instance is
        // fine: it's stateless for load/update (UserDefaults JSON), and the shared
        // key keeps it consistent with the view-model's own service.
        let store = AutomationService()
        let now = Date()
        let base = store.load().first(where: { $0.id == automation.id }) ?? automation
        store.update(base.markingRun(at: now, ok: ok))

        loadAutomations()
        return ok
    }

    private func providerRunRequest(for automation: Automation) throws -> ProviderRunRequest {
        let providerID = automation.providerId.isEmpty ? AgentProvider.grok.id : automation.providerId
        let status = providerStatuses.first { $0.provider.id == providerID }
            ?? ProviderRegistry.shared.detectAll().first { $0.provider.id == providerID }
        guard let status, let binaryPath = status.binaryPath else {
            throw AgentProviderRuntimeError.providerUnavailable("\(providerLabel(for: providerID)) is not installed.")
        }
        let model = modelOption(providerId: providerID, modelId: automation.modelId)
            ?? GrokModelOption(
                id: automation.modelId,
                isDefault: false,
                providerId: providerID,
                providerName: providerLabel(for: providerID),
                title: automation.modelId,
                isCustom: true
            )
        let options = automation.optionSelections.isEmpty ? runOptions(for: model) : automation.optionSelections
        return ProviderRunRequest(
            provider: status.provider,
            binaryPath: binaryPath,
            prompt: automation.prompt,
            cwd: automation.workingDirectory,
            model: model,
            permissionMode: .auto,
            options: options,
            check: false,
            sessionId: nil
        )
    }
}
