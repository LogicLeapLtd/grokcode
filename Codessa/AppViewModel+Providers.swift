import AppKit
import Foundation

/// Multi-provider support (shared contract). Codessa is a provider-agnostic
/// shell over agent CLIs — Claude Code, Codex, Cursor, Gemini, Grok, Z.AI, and
/// any custom binary. This extension owns detection, selection, and the
/// convenience accessors the onboarding dock, composer, and Settings read.
///
/// Execution note: live runs currently route through the wired engine (Grok).
/// A non-wired provider can be detected and selected — Codessa surfaces that
/// honestly (`selectedProviderIsWired`) rather than pretending every CLI's
/// streaming protocol is implemented.
@MainActor
extension AppViewModel {
    private var registry: ProviderRegistry { .shared }

    /// Re-detect installed providers and sync the selected id from the registry.
    func refreshProviders() {
        providerStatuses = registry.detectAll()
        selectedProviderId = registry.selectedProviderId
        // If the persisted selection points at a provider that no longer exists
        // (e.g. a removed custom one), fall back to the wired default.
        if !providerStatuses.contains(where: { $0.provider.id == selectedProviderId }) {
            selectProvider(AgentProvider.wiredDefault.id)
        }
    }

    /// The currently selected provider (falls back to the wired default).
    var selectedProvider: AgentProvider {
        providerStatuses.first { $0.provider.id == selectedProviderId }?.provider
            ?? registry.selectedProvider()
    }

    /// Whether Codessa has a wired streaming adapter for the selected provider.
    /// Drives the honest "live runs route through Grok" notice in the UI.
    var selectedProviderIsWired: Bool { selectedProvider.streamingWired }

    /// Count of providers detected on disk — surfaced in onboarding ("2 of 7
    /// ready").
    var installedProviderCount: Int { providerStatuses.filter(\.installed).count }

    /// Total providers in the catalog (known + custom).
    var totalProviderCount: Int { providerStatuses.count }

    /// The short names of installed providers, for the onboarding subtitle.
    var installedProviderNames: [String] {
        providerStatuses.filter(\.installed).map(\.provider.shortName)
    }

    /// Persist a provider choice and mirror it locally.
    func selectProvider(_ id: String) {
        registry.selectedProviderId = id
        selectedProviderId = id
    }

    /// Sign-in / setup entry point for a provider — opens Terminal at the login
    /// command where the CLI exposes one, else opens its docs. Grok keeps its
    /// dedicated `grok login` path via `runGrokLogin()`.
    func setUpProvider(_ provider: AgentProvider) {
        if provider.id == AgentProvider.grok.id {
            runGrokLogin()
            return
        }
        openProviderDocs(provider)
    }

    /// Open a provider's install/setup docs in the browser.
    func openProviderDocs(_ provider: AgentProvider) {
        guard !provider.docsURL.isEmpty, let url = URL(string: provider.docsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// "Add custom provider" — pick an executable, register it, re-detect.
    func addCustomProvider() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose an agent CLI executable to drive."
        // Default into /usr/local/bin where most CLIs land.
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = (url.lastPathComponent as NSString).deletingPathExtension
        registry.addCustomProvider(name: name, binaryPath: url.path)
        refreshProviders()
        // Select the freshly-added provider so the choice sticks.
        selectProvider(AgentProvider.custom(name: name, binaryPath: url.path).id)
    }

    /// Remove a user-defined custom provider and re-detect.
    func removeCustomProvider(_ provider: AgentProvider) {
        guard provider.isCustom else { return }
        registry.removeCustomProvider(id: provider.id)
        refreshProviders()
    }
}
