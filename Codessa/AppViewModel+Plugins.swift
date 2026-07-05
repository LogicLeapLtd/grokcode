import Foundation

/// Plugins lane behavior on `AppViewModel`.
///
/// Foundation owns the stored properties (`installedPlugins`, `importablePlugins`,
/// `pluginSearchQuery`, `pluginToast`) and the base `installPlugin`/`removePlugin`
/// (which only sync the persisted UserDefaults set via `PluginImportService`).
///
/// This extension adds the grok-aware variants the Plugins UI actually calls:
/// they register / unregister MCP servers with the local `grok` CLI **and** keep
/// the persisted installed set in sync, surfacing `pluginToast` feedback. They
/// never touch `AppViewModel.swift`.
extension AppViewModel {

    // MARK: - Install / remove (grok-aware)

    /// Add a plugin: register it with grok (for MCP servers) and record it in the
    /// persisted installed set. Shows a toast reflecting success/failure.
    ///
    /// For non-MCP plugins (skills, commands, hooks, …) grok has no registry to
    /// mutate, so we just persist the install and confirm. MCP registration runs
    /// off the main actor; the persisted set + toast are updated back on main.
    func installPluginViaGrok(_ plugin: Plugin) {
        // Non-MCP plugins: local-only install, no grok registry call.
        guard plugin.kind == .mcpServer else {
            installPlugin(plugin)
            pluginToast = "Added \(plugin.displayName)"
            return
        }

        // MCP servers: register with grok first, then persist + toast.
        Task { [weak self] in
            let ok = await Task.detached { GrokMCPService.shared.add(plugin) }.value
            guard let self else { return }
            // Persist regardless so the GUI's installed set stays the source of
            // truth for display; the toast tells the user if grok registration
            // failed (e.g. binary missing) so the state isn't silently wrong.
            self.installPlugin(plugin)
            self.pluginToast = ok
                ? "Added \(plugin.displayName)"
                : "Added \(plugin.displayName) (grok registration failed)"
        }
    }

    /// Remove a plugin: unregister it from grok (for MCP servers) and drop it
    /// from the persisted installed set. Shows a confirmation toast.
    func removePluginViaGrok(_ plugin: Plugin) {
        guard plugin.kind == .mcpServer else {
            removePlugin(plugin)
            pluginToast = "Removed \(plugin.displayName)"
            return
        }

        Task { [weak self] in
            await Task.detached { GrokMCPService.shared.remove(plugin) }.value
            guard let self else { return }
            self.removePlugin(plugin)
            self.pluginToast = "Removed \(plugin.displayName)"
        }
    }

    // MARK: - Configure (env vars / API keys)

    /// Persist edited environment variables for an installed plugin and, for MCP
    /// servers, re-register it with grok so the new keys take effect (grok `mcp
    /// add` replaces an existing server of the same name). Shows a toast.
    ///
    /// Accepts the full replacement env map from the Configure sheet. Empty keys
    /// are dropped. The updated blob is written back to the installed set via the
    /// base `installPlugin`, then both lists refresh.
    func updatePluginEnv(_ plugin: Plugin, env: [String: String]) {
        var updated = plugin
        updated.env = env.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }

        guard plugin.kind == .mcpServer else {
            // Non-MCP: just persist the edited config.
            installPlugin(updated)
            pluginToast = "Saved \(updated.displayName)"
            return
        }

        Task { [weak self] in
            // Re-register so the new env reaches the launched server. grok's
            // `mcp add` is replace-by-name, so a plain re-add is sufficient.
            let ok = await Task.detached { GrokMCPService.shared.add(updated) }.value
            guard let self else { return }
            self.installPlugin(updated)
            self.pluginToast = ok
                ? "Saved \(updated.displayName)"
                : "Saved \(updated.displayName) (grok update failed)"
        }
    }

    // MARK: - Local source management

    /// Enable or disable the real local definition, then refresh the synced
    /// inventory so the Manage tab reflects the new source state.
    func setLocalPlugin(_ plugin: Plugin, enabled: Bool) {
        let ok = PluginImportService().setEnabled(plugin, enabled: enabled)
        refreshPlugins()
        pluginToast = ok
            ? "\(plugin.displayName) \(enabled ? "enabled" : "disabled")"
            : "Couldn't \(enabled ? "enable" : "disable") \(plugin.displayName)"
    }

    /// Delete the real local definition (or remove it from its config), then
    /// refresh the synced inventory and installed set.
    func deleteLocalPlugin(_ plugin: Plugin) {
        let ok = PluginImportService().deleteDefinition(plugin)
        refreshPlugins()
        pluginToast = ok
            ? "Deleted \(plugin.displayName)"
            : "Couldn't delete \(plugin.displayName)"
    }

    // MARK: - Reconcile installed set with grok

    /// Reconcile the persisted installed set against grok's live MCP registry.
    ///
    /// If the user removed a server with `grok mcp remove` outside the app, this
    /// drops the corresponding installed entry so the Installed tab reflects
    /// reality. Only MCP-server plugins are reconciled (other kinds have no grok
    /// registry to compare against and are always kept). Runs the `grok mcp list`
    /// shell call off the main actor.
    func syncInstalledFromGrok() {
        // Snapshot the MCP-server entries we might prune (value types → Sendable).
        let mcpInstalled = installedPlugins.filter { $0.kind == .mcpServer }
        guard !mcpInstalled.isEmpty, GrokMCPService.shared.isAvailable else { return }

        Task { [weak self] in
            let registered = await Task.detached {
                Set(GrokMCPService.shared.listServerNames())
            }.value
            guard let self else { return }

            // Drop installed MCP servers grok no longer knows about.
            let stale = mcpInstalled.filter { plugin in
                !registered.contains(GrokMCPService.serverName(for: plugin))
            }
            guard !stale.isEmpty else { return }
            for plugin in stale { self.removePlugin(plugin) }
        }
    }
}
