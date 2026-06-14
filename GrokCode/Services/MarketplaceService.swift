import Foundation

/// Loads and persists GrokCode's *own* community plugin marketplace.
///
/// Three responsibilities:
///   1. **Remote community manifest** — fetch the curated community list from a
///      raw GitHub URL, decode to `[MarketplaceEntry]`, never throw to the UI
///      (returns `[]` on any failure), and cache the last good result on disk so
///      the Discover tab still shows community plugins offline.
///   2. **Local published store** — load/save the user's *own* published entries
///      to Application Support, so in-app publishing survives relaunches.
///   3. **PR submission helper** — render a single manifest entry as pretty JSON
///      so the user can paste it into a `grokcode-marketplace` pull request.
///
/// Mirrors the project's service style (`AutomationService`, `HooksService`):
/// a final class with a `shared` singleton. The network call is `async` via
/// `URLSession`; all disk I/O is synchronous JSON on a private serial queue. The
/// type is `Sendable`-safe because it holds no mutable shared state (paths and
/// the session config are constant after init).
final class MarketplaceService: @unchecked Sendable {
    static let shared = MarketplaceService()

    /// Default remote manifest URL (raw GitHub). Overridable for tests / forks.
    static let defaultManifestURL = URL(
        string: "https://raw.githubusercontent.com/logicleaplabs/grokcode-marketplace/main/marketplace.json"
    )!

    private let manifestURL: URL
    private let session: URLSession

    /// Short timeout: the Discover tab must not hang waiting on the network. On
    /// timeout we fall back to the on-disk cache (or `[]`).
    private static let requestTimeout: TimeInterval = 6

    init(manifestURL: URL = MarketplaceService.defaultManifestURL,
         session: URLSession? = nil) {
        self.manifestURL = manifestURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = MarketplaceService.requestTimeout
            config.timeoutIntervalForResource = MarketplaceService.requestTimeout
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Application Support paths

    /// `~/Library/Application Support/GrokCode`. Created on demand.
    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("GrokCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    /// Last-good remote community manifest, cached on disk.
    private var cacheURL: URL {
        supportDirectory.appendingPathComponent("marketplace-cache.json")
    }

    /// The user's own published entries.
    private var publishedURL: URL {
        supportDirectory.appendingPathComponent("published-plugins.json")
    }

    // MARK: - Remote community manifest

    /// Fetch the community manifest from the remote URL and return its entries.
    ///
    /// Never throws. On success the result is also written to the on-disk cache.
    /// On *any* failure (offline, timeout, non-200, malformed JSON) it falls back
    /// to the cached manifest, and to `[]` if there is no cache. The UI can call
    /// this on appear and simply assign the result.
    func loadCommunityEntries() async -> [MarketplaceEntry] {
        do {
            var request = URLRequest(url: manifestURL)
            request.timeoutInterval = Self.requestTimeout
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return cachedCommunityEntries()
            }

            let manifest = try JSONDecoder().decode(MarketplaceManifest.self, from: data)
            writeCache(data)            // cache the raw bytes we just decoded
            return manifest.plugins
        } catch {
            return cachedCommunityEntries()
        }
    }

    /// Read the cached community manifest written by the last successful fetch.
    /// Returns `[]` if there is no cache or it is unreadable.
    func cachedCommunityEntries() -> [MarketplaceEntry] {
        guard let data = try? Data(contentsOf: cacheURL),
              let manifest = try? JSONDecoder().decode(MarketplaceManifest.self, from: data)
        else { return [] }
        return manifest.plugins
    }

    /// Persist the raw manifest bytes as the on-disk cache. Silent on failure —
    /// a missing cache just means the next offline load returns `[]`.
    private func writeCache(_ data: Data) {
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - Local published store

    /// Load the user's own published entries (the local "I published this" list).
    /// Returns `[]` on any failure. Never throws.
    func loadPublishedEntries() -> [MarketplaceEntry] {
        guard let data = try? Data(contentsOf: publishedURL),
              let manifest = try? JSONDecoder().decode(MarketplaceManifest.self, from: data)
        else { return [] }
        return manifest.plugins
    }

    /// Overwrite the local published store with `entries`. Wrapped in a
    /// `MarketplaceManifest` so the file shape matches the remote manifest.
    /// Silent on failure (encode/IO) — the in-memory state is still correct.
    @discardableResult
    func savePublishedEntries(_ entries: [MarketplaceEntry]) -> Bool {
        let manifest = MarketplaceManifest(plugins: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return false }
        do {
            try data.write(to: publishedURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Publish an entry: append it to the local published store (replacing any
    /// existing entry with the same derived id so re-publishing edits in place),
    /// then return the full updated list. Pure append-and-persist — registering
    /// the plugin with grok is the surface/AppViewModel's job.
    @discardableResult
    func publish(_ entry: MarketplaceEntry) -> [MarketplaceEntry] {
        var entries = loadPublishedEntries()
        let newID = entry.id
        entries.removeAll { $0.id == newID }
        entries.append(entry)
        savePublishedEntries(entries)
        return entries
    }

    /// Remove a previously published entry by its derived id; returns the
    /// updated list. No-op (still returns the current list) if not present.
    @discardableResult
    func unpublish(id: String) -> [MarketplaceEntry] {
        var entries = loadPublishedEntries()
        entries.removeAll { $0.id == id }
        savePublishedEntries(entries)
        return entries
    }

    // MARK: - PR submission helper

    /// Render a single entry as pretty-printed JSON suitable for pasting into a
    /// `grokcode-marketplace` pull request (one object from the manifest's
    /// `plugins` array). Keys are sorted for stable diffs. Returns `""` only if
    /// encoding somehow fails (never for a normal value-type `Codable`).
    func manifestEntryJSON(for entry: MarketplaceEntry) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }
}
