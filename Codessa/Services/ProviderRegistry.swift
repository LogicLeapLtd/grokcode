import Foundation

/// Detects which agent-CLI providers are installed on the machine, tracks the
/// user's selected provider, and stores any user-defined custom providers.
///
/// Detection probes each provider's candidate executable names across `$PATH`
/// plus the common per-tool install locations (npm globals, Homebrew, Bun,
/// `~/.local/bin`, and each vendor's dot-dir), mirroring how the shells that
/// install these CLIs lay them out.
nonisolated final class ProviderRegistry: @unchecked Sendable {
    static let shared = ProviderRegistry()

    private let selectedKey = "grokcode.selectedProvider"
    private let customKey = "grokcode.customProviders"

    // MARK: - Catalog

    /// Known providers plus any user-defined custom ones (persisted).
    func catalog() -> [AgentProvider] {
        AgentProvider.known + customProviders()
    }

    /// Custom providers the user has added (persisted as JSON).
    func customProviders() -> [AgentProvider] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let list = try? JSONDecoder().decode([AgentProvider].self, from: data)
        else { return [] }
        return list
    }

    func addCustomProvider(name: String, binaryPath: String) {
        var list = customProviders()
        let provider = AgentProvider.custom(name: name, binaryPath: binaryPath)
        guard !list.contains(where: { $0.id == provider.id }) else { return }
        list.append(provider)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    func removeCustomProvider(id: String) {
        let list = customProviders().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    // MARK: - Selection

    /// The user's chosen provider id. Defaults to the wired engine (Grok) so the
    /// shipping run path is unchanged until the user picks another.
    var selectedProviderId: String {
        get { UserDefaults.standard.string(forKey: selectedKey) ?? AgentProvider.wiredDefault.id }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    func selectedProvider() -> AgentProvider {
        let id = selectedProviderId
        return catalog().first { $0.id == id } ?? AgentProvider.wiredDefault
    }

    // MARK: - Detection

    /// A snapshot of install status for every catalog provider.
    func detectAll() -> [ProviderStatus] {
        catalog().map { provider in
            let path = resolveBinary(for: provider)
            return ProviderStatus(provider: provider, installed: path != nil, binaryPath: path)
        }
    }

    func isInstalled(_ provider: AgentProvider) -> Bool {
        resolveBinary(for: provider) != nil
    }

    /// Resolve the on-disk executable path for a provider, or `nil` if not found.
    func resolveBinary(for provider: AgentProvider) -> String? {
        if let explicit = provider.explicitBinaryPath {
            return FileManager.default.isExecutableFile(atPath: explicit) ? explicit : nil
        }
        for name in provider.binaryNames {
            if let path = which(name) { return path }
        }
        return nil
    }

    // MARK: - PATH resolution

    /// Directories searched for provider executables, de-duplicated in priority
    /// order: `$PATH` first, then the well-known per-tool install locations.
    private func searchDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs: [String] = []

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }

        dirs += [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/current/bin",
            "\(home)/.claude/local",
            "\(home)/.grok/bin",
            "\(home)/.cursor/bin",
            "\(home)/.codex/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]

        // Stable de-dup preserving first-seen priority.
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
    }

    private func which(_ name: String) -> String? {
        let fm = FileManager.default
        for dir in searchDirectories() {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
