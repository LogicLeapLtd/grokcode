import AppKit
import Foundation

/// Multi-provider support (shared contract). Codessa is a provider-agnostic
/// shell over agent CLIs — Claude Code, Codex, Cursor, Gemini, Grok, Z.AI, and
/// any custom binary. This extension owns detection, selection, and the
/// convenience accessors the onboarding dock, composer, and Settings read.
///
@MainActor
extension AppViewModel {
    private var registry: ProviderRegistry { .shared }
    private var defaultProviderKey: String { "grokcode.defaultProviderInstanceId" }

    /// Re-detect installed providers and sync the selected id from the registry.
    func refreshProviders() {
        providerStatuses = registry.detectAll()
        selectedProviderId = UserDefaults.standard.string(forKey: defaultProviderKey) ?? registry.selectedProviderId
        // If the persisted selection points at a provider that no longer exists
        // (e.g. a removed custom one), fall back to the first runnable provider.
        if !providerStatuses.contains(where: { $0.provider.id == selectedProviderId }) {
            selectProvider(providerStatuses.first(where: \.installed)?.provider.id ?? AgentProvider.wiredDefault.id)
        }
        syncModelsForSelectedProvider()
    }

    func refreshProviderSnapshots() async {
        let snapshots = await AgentProviderRuntime.shared.snapshots(for: providerStatuses.isEmpty ? registry.detectAll() : providerStatuses)
        providerStatuses = snapshots
        if !providerStatuses.contains(where: { $0.provider.id == selectedProviderId }) {
            selectProvider(providerStatuses.first(where: \.installed)?.provider.id ?? AgentProvider.wiredDefault.id)
        } else {
            syncModelsForSelectedProvider()
        }
    }

    /// The currently selected provider (falls back to the wired default).
    var selectedProvider: AgentProvider {
        providerStatuses.first { $0.provider.id == selectedProviderId }?.provider
            ?? registry.selectedProvider()
    }

    /// Whether Codessa has a direct runtime path for the selected provider.
    var selectedProviderIsWired: Bool { selectedProvider.streamingWired }

    var selectedProviderStatus: ProviderStatus? {
        providerStatuses.first { $0.provider.id == selectedProviderId }
    }

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
        UserDefaults.standard.set(id, forKey: defaultProviderKey)
        selectedProviderId = id
        syncModelsForSelectedProvider()
        persistDefaults()
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

    func modelOptions(for providerId: String) -> [GrokModelOption] {
        providerStatuses.first { $0.provider.id == providerId }?.models
            ?? AgentProvider.known.first { $0.id == providerId }.map(AgentProviderModelCatalog.models(for:))
            ?? []
    }

    func modelOptions(forProviderID providerId: String) -> [GrokModelOption] {
        modelOptions(for: providerId)
    }

    func modelOption(providerId: String, modelId: String) -> GrokModelOption? {
        modelOptions(for: providerId).first { $0.id == modelId }
    }

    func selectModel(_ option: GrokModelOption) {
        if option.providerId != selectedProviderId {
            selectProvider(option.providerId)
        }
        selectedModel = option
        seedDefaultOptions(for: option)
        persistDefaults()
    }

    func selectedOptionValue(for descriptor: ProviderOptionDescriptor, model: GrokModelOption? = nil) -> String? {
        let optionModel = model ?? selectedModel
        guard let optionModel else { return descriptor.defaultValue }
        return modelOptionSelections[optionSelectionKey(model: optionModel, descriptorId: descriptor.id)]
            ?? descriptor.defaultValue
    }

    func setSelectedOptionValue(_ value: String, for descriptor: ProviderOptionDescriptor, model: GrokModelOption? = nil) {
        guard let optionModel = model ?? selectedModel else { return }
        modelOptionSelections[optionSelectionKey(model: optionModel, descriptorId: descriptor.id)] = value
        persistDefaults()
    }

    func runOptions(for option: GrokModelOption) -> [String: String] {
        var out: [String: String] = [:]
        for descriptor in option.optionDescriptors {
            if let value = modelOptionSelections[optionSelectionKey(model: option, descriptorId: descriptor.id)]
                ?? descriptor.defaultValue {
                out[descriptor.id] = value
                if descriptor.id.lowercased().contains("reasoning") || descriptor.id.lowercased().contains("effort") {
                    out["reasoning"] = value
                }
            }
        }
        return out
    }

    func syncModelsForSelectedProvider() {
        let providerModels = modelOptions(for: selectedProviderId)
        models = providerModels

        let defaults = UserDefaults.standard
        let savedProviderModel = defaults.string(forKey: "grokcode.defaultModel.\(selectedProviderId)")
        let legacySaved = selectedProviderId == AgentProvider.grok.id ? defaults.string(forKey: "grokcode.defaultModel") : nil
        let saved = savedProviderModel ?? legacySaved

        if let current = selectedModel,
           current.providerId == selectedProviderId,
           providerModels.contains(where: { $0.id == current.id }) {
            seedDefaultOptions(for: current)
            return
        }

        selectedModel = saved.flatMap { id in providerModels.first { $0.id == id } }
            ?? providerModels.first(where: \.isDefault)
            ?? providerModels.first
        if let selectedModel {
            seedDefaultOptions(for: selectedModel)
        }
    }

    private func seedDefaultOptions(for option: GrokModelOption) {
        for descriptor in option.optionDescriptors {
            let key = optionSelectionKey(model: option, descriptorId: descriptor.id)
            if modelOptionSelections[key] == nil, let value = descriptor.defaultValue {
                modelOptionSelections[key] = value
            }
        }
    }

    private func optionSelectionKey(model: GrokModelOption, descriptorId: String) -> String {
        "\(model.providerId)::\(model.id)::\(descriptorId)"
    }
}
