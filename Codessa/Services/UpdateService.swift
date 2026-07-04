import Foundation
import AppKit
import Combine

/// In-app software updater for Codessa.
///
/// The old "Check for updates" action just opened the GitHub releases page. This
/// service does the real thing:
///
///   1. Queries the GitHub Releases API for the latest published release.
///   2. Compares its version to the running build.
///   3. If newer, downloads the release's `.dmg`/`.zip` asset (with progress),
///      extracts the `.app`, swaps it into a **stable install location**, and
///      relaunches — all without the user touching Finder.
///
/// ### Why the stable install location matters (the "works on dev" ask)
///
/// A Dock icon is pinned to an exact app-bundle path. When Codessa is run
/// straight out of Xcode's DerivedData, that path rotates every clean build, so
/// the pinned Dock icon goes stale and has to be re-added by hand, and the app
/// has to be quit/relaunched manually to pick up a new build.
///
/// This updater always installs to — and relaunches from — a single canonical
/// path: `/Applications/Codessa.app`. So:
///   • A real release update replaces the bundle *in place* at that path; the
///     Dock pin keeps working.
///   • When you're running a dev build from DerivedData, "Check for updates"
///     offers **Install this build to /Applications & relaunch**, which promotes
///     the running build to the canonical path and reopens it there. Pin that
///     copy once and the Dock shortcut never breaks again — no manual reboot,
///     no re-pinning.
@MainActor
final class UpdateService: ObservableObject {

    // MARK: - Configuration

    /// GitHub repository that hosts Codessa's releases. Mirrors the URL the old
    /// sidebar action used. Change here if releases move.
    static let repoOwner = "LogicLeapLtd"
    static let repoName = "grokcode"

    /// Human-facing releases page, used as a safety-net fallback ("Open releases
    /// page") when an in-app update can't complete.
    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
    }

    private static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    }

    /// Where an installed Codessa should live. Keeping this constant is what
    /// keeps the Dock pin stable across updates and dev promotions.
    static var canonicalInstallURL: URL {
        URL(fileURLWithPath: "/Applications/\(appBundleName)")
    }

    private static var appBundleName: String {
        Bundle.main.bundleURL.lastPathComponent // "Codessa.app"
    }

    private static let autoCheckDefaultsKey = "codessa.updates.autoCheckOnLaunch"
    private static let lastBackgroundCheckKey = "codessa.updates.lastBackgroundCheck"

    /// Minimum spacing between *automatic* launch checks. GitHub's unauthenticated
    /// API allows only 60 requests/hour per IP, so a check on every single launch
    /// (common during development) burns that budget and trips rate limiting.
    /// User-initiated "Check for updates" is never throttled.
    private static let backgroundCheckInterval: TimeInterval = 6 * 60 * 60

    // MARK: - Published state

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(UpdateRelease)
        case downloading(progress: Double)
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Drives the modal. Sidebar / Settings flip this on; the dialog reads it.
    @Published var isDialogPresented = false

    /// True once a background check has found a newer release, so menus can show
    /// an "Update available" badge without popping a dialog on launch.
    @Published private(set) var updateAvailableInBackground = false

    /// Whether we silently check on launch. User-toggleable in Settings.
    @Published var automaticallyChecksOnLaunch: Bool {
        didSet { UserDefaults.standard.set(automaticallyChecksOnLaunch, forKey: Self.autoCheckDefaultsKey) }
    }

    // MARK: - Derived facts about the running build

    /// The currently-running app bundle.
    let currentBundleURL = Bundle.main.bundleURL

    /// Marketing version of the running build, e.g. "1.0".
    let currentVersion: String = {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }()

    /// True when the running build already lives at the canonical install path.
    /// When false we're a dev / Downloads / non-standard build and can offer to
    /// promote ourselves to `/Applications`.
    var isRunningFromCanonicalLocation: Bool {
        currentBundleURL.standardizedFileURL == Self.canonicalInstallURL.standardizedFileURL
    }

    /// True when the build is running out of Xcode's DerivedData (a dev build),
    /// used only to word the UI ("development build") — the promote action works
    /// the same for any non-canonical location.
    var isDevBuild: Bool {
        currentBundleURL.path.contains("/DerivedData/") || currentBundleURL.path.contains("/Build/Products/")
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.autoCheckDefaultsKey) == nil {
            defaults.set(true, forKey: Self.autoCheckDefaultsKey)
        }
        self.automaticallyChecksOnLaunch = defaults.bool(forKey: Self.autoCheckDefaultsKey)
    }

    // MARK: - Public entry points

    /// Opens the update dialog and kicks off a check if one isn't already in a
    /// terminal-ish state. Called from the sidebar menu + Settings.
    func presentDialog() {
        isDialogPresented = true
        switch phase {
        case .idle, .upToDate, .failed:
            Task { await checkForUpdates(userInitiated: true) }
        default:
            break // a check / download / install is already in flight or resolved to an update
        }
    }

    /// Silent launch-time check. Never opens the dialog; only lights the badge.
    /// Throttled so repeated relaunches don't exhaust GitHub's hourly rate limit.
    func checkInBackgroundIfEnabled() {
        guard automaticallyChecksOnLaunch else { return }
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: Self.lastBackgroundCheckKey)
        let now = Date().timeIntervalSince1970
        if last > 0, now - last < Self.backgroundCheckInterval { return }
        defaults.set(now, forKey: Self.lastBackgroundCheckKey)
        Task { await checkForUpdates(userInitiated: false) }
    }

    /// Queries GitHub for the latest release and resolves `phase`.
    func checkForUpdates(userInitiated: Bool) async {
        if userInitiated { phase = .checking }
        do {
            guard let release = try await fetchLatestRelease() else {
                // No published releases yet (or the endpoint 404'd). Nothing to
                // offer — treat as "up to date" so the dev-promote path can still
                // show in the dialog.
                updateAvailableInBackground = false
                if userInitiated { phase = .upToDate }
                return
            }

            if Self.isVersion(release.version, newerThan: currentVersion) {
                updateAvailableInBackground = true
                // A background check leaves `phase` alone unless it's idle, so we
                // don't stomp an in-flight user action; the dialog will surface
                // the found release when opened.
                if userInitiated || phase == .idle {
                    phase = .updateAvailable(release)
                }
            } else {
                updateAvailableInBackground = false
                if userInitiated { phase = .upToDate }
            }
        } catch {
            if userInitiated {
                phase = .failed(Self.friendlyMessage(for: error))
            }
        }
    }

    /// Downloads the release asset, extracts the app, and installs + relaunches.
    func downloadAndInstall(_ release: UpdateRelease) {
        guard let assetURL = release.downloadURL else {
            phase = .failed("This release has no downloadable app attached. Use “Open releases page” to grab it manually.")
            return
        }
        Task { await runDownloadInstall(release: release, assetURL: assetURL) }
    }

    /// Dev path: copy the running (non-canonical) build to `/Applications` and
    /// relaunch it there, so the Dock pin becomes stable.
    func promoteRunningBuildToApplications() {
        phase = .installing
        do {
            try swapAndRelaunch(source: currentBundleURL, destination: Self.canonicalInstallURL)
            // Give the detached swapper a beat, then quit so it can replace us.
            terminateSoon()
        } catch {
            phase = .failed(Self.friendlyMessage(for: error))
        }
    }

    // MARK: - Download + install pipeline

    private func runDownloadInstall(release: UpdateRelease, assetURL: URL) async {
        phase = .downloading(progress: 0)
        do {
            let downloader = FileDownloader { [weak self] p in
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.phase { self.phase = .downloading(progress: p) }
                }
            }
            let downloaded = try await downloader.download(assetURL)

            phase = .installing
            let extractedApp = try await extractApp(from: downloaded, assetName: release.assetName ?? assetURL.lastPathComponent)

            // A release update always lands at the canonical path, promoting the
            // install off a dev/Downloads location in the same step.
            let destination = Self.canonicalInstallURL
            try swapAndRelaunch(source: extractedApp, destination: destination)
            terminateSoon()
        } catch {
            phase = .failed(Self.friendlyMessage(for: error))
        }
    }

    /// Mounts a `.dmg` (or unzips a `.zip`), finds the `.app`, and copies it to a
    /// stable staging dir so the archive/mount can be released before the swap.
    private func extractApp(from archive: URL, assetName: String) async throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("codessa-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let lower = assetName.lowercased()
        let appInStaging: URL

        if lower.hasSuffix(".zip") {
            // ditto -x -k unzips; then locate the .app inside.
            let status = try await runProcess("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
            guard status == 0 else { throw UpdateError.extractionFailed("Unzip failed (code \(status)).") }
            guard let app = Self.firstApp(in: staging, fm: fm) else {
                throw UpdateError.extractionFailed("No .app found inside the downloaded zip.")
            }
            appInStaging = app
        } else {
            // Treat everything else as a DMG. Mount → copy the .app off → detach.
            let mountPoint = fm.temporaryDirectory.appendingPathComponent("codessa-mnt-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

            let attach = try await runProcess("/usr/bin/hdiutil",
                ["attach", archive.path, "-mountpoint", mountPoint.path, "-nobrowse", "-noverify", "-noautoopen"])
            guard attach == 0 else { throw UpdateError.extractionFailed("Couldn't open the downloaded disk image (code \(attach)).") }

            defer {
                Task { _ = try? await runProcess("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }
            }

            guard let mountedApp = Self.firstApp(in: mountPoint, fm: fm) else {
                throw UpdateError.extractionFailed("No .app found inside the downloaded disk image.")
            }
            let copied = staging.appendingPathComponent(mountedApp.lastPathComponent)
            // ditto preserves symlinks / signatures / xattrs correctly for a bundle.
            let copy = try await runProcess("/usr/bin/ditto", [mountedApp.path, copied.path])
            guard copy == 0 else { throw UpdateError.extractionFailed("Couldn't copy the app off the disk image (code \(copy)).") }
            appInStaging = copied
        }
        return appInStaging
    }

    /// Writes a small detached shell script that waits for this process to exit,
    /// atomically swaps `destination` for `source`, clears the quarantine flag,
    /// and reopens the app. Because it runs *after* we quit, it can replace our
    /// own bundle. The path stays constant, so the Dock pin survives.
    private func swapAndRelaunch(source: URL, destination: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        SRC="$1"
        DEST="$2"
        PID="$3"
        # Wait (up to ~20s) for the running app to fully exit.
        i=0
        while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 200 ]; do
          sleep 0.1
          i=$((i + 1))
        done
        BACKUP="${DEST}.codessa-old"
        /bin/rm -rf "$BACKUP" 2>/dev/null
        if [ -d "$DEST" ]; then
          /bin/mv "$DEST" "$BACKUP" || exit 1
        fi
        if /usr/bin/ditto "$SRC" "$DEST"; then
          /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
          /bin/rm -rf "$BACKUP" 2>/dev/null
          /usr/bin/open "$DEST"
        else
          # Roll back to the previous install on failure.
          /bin/rm -rf "$DEST" 2>/dev/null
          if [ -d "$BACKUP" ]; then /bin/mv "$BACKUP" "$DEST"; fi
          /usr/bin/open "$DEST"
        fi
        """

        let fm = FileManager.default
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("codessa-swap-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let task = Process()
        let destParent = destination.deletingLastPathComponent()

        if fm.isWritableFile(atPath: destParent.path) {
            // Common case: /Applications is writable by admin users — no prompt.
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [scriptURL.path, source.path, destination.path, String(pid)]
        } else {
            // Locked-down machine: authenticate the swap once via AppleScript.
            // Relaunch is deliberately left to a separate unprivileged `open`
            // inside the script running as the invoking user.
            let inner = "/bin/sh \(Self.shQuote(scriptURL.path)) \(Self.shQuote(source.path)) \(Self.shQuote(destination.path)) \(pid)"
            let osa = "do shell script \(Self.appleScriptQuote(inner)) with administrator privileges"
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osa]
        }
        try task.run()
    }

    /// Quit shortly after handing off to the swapper. A tiny delay lets the
    /// Process spawn settle before the app tears down.
    private func terminateSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - GitHub fetch

    private func fetchLatestRelease() async throws -> UpdateRelease? {
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codessa/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.network("No response from the update server.") }

        // GitHub's unauthenticated API allows only 60 requests/hour per IP. When
        // that's exhausted it answers 403 (sometimes 429) with a JSON error body,
        // and `X-RateLimit-Remaining: 0`. Surface that as its own friendly state
        // instead of a raw decode failure.
        let remaining = Int(http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "")
        if http.statusCode == 403 || http.statusCode == 429 || remaining == 0 {
            let reset = (http.value(forHTTPHeaderField: "X-RateLimit-Reset")).flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
            throw UpdateError.rateLimited(reset)
        }

        if http.statusCode == 404 { return nil } // repo has no published releases yet
        guard (200...299).contains(http.statusCode) else {
            throw UpdateError.network("The update server returned HTTP \(http.statusCode). Try again shortly.")
        }

        do {
            return try JSONDecoder.githubDecoder.decode(GitHubRelease.self, from: data).asUpdateRelease()
        } catch {
            // Not a release payload — most often a GitHub `{"message": …}` error
            // (rate limit / temporary block) that arrived with a 2xx-ish status.
            // Show its message rather than Foundation's cryptic "data … missing".
            if let apiError = try? JSONDecoder().decode(GitHubAPIError.self, from: data), !apiError.message.isEmpty {
                if apiError.message.lowercased().contains("rate limit") { throw UpdateError.rateLimited(nil) }
                throw UpdateError.network(apiError.message)
            }
            throw UpdateError.network("The update server returned an unexpected response. Try again shortly.")
        }
    }

    // MARK: - Version comparison

    /// True when `candidate` is a strictly-newer marketing version than `current`.
    /// Tolerates a leading `v` and pre-release/build suffixes on the core.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        compareVersions(candidate, current) == .orderedDescending
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parseVersion(a)
        let pb = parseVersion(b)
        let count = max(pa.core.count, pb.core.count)
        for i in 0..<count {
            let va = i < pa.core.count ? pa.core[i] : 0
            let vb = i < pb.core.count ? pb.core[i] : 0
            if va != vb { return va < vb ? .orderedAscending : .orderedDescending }
        }
        // Same numeric core: a normal release outranks a pre-release of it
        // (1.1.0 is newer than 1.1.0-beta.2), matching SemVer precedence.
        if pa.isPrerelease != pb.isPrerelease {
            return pa.isPrerelease ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    /// Splits a version into its numeric core and whether it carries a
    /// pre-release tag. "v1.2.0-beta.1+sha" -> (core: [1,2,0], isPrerelease: true).
    private static func parseVersion(_ version: String) -> (core: [Int], isPrerelease: Bool) {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        let isPrerelease = v.contains("-")
        let core = v.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? v
        return (core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }, isPrerelease)
    }

    // MARK: - Helpers

    private static func firstApp(in directory: URL, fm: FileManager) -> URL? {
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        return items.first { $0.pathExtension == "app" }
    }

    /// Runs a command off the main actor and returns its exit code.
    nonisolated private func runProcess(_ launchPath: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let e = error as? UpdateError { return e.message }
        if error is DecodingError {
            return "The update server returned an unexpected response. Try again shortly."
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach the update server. Check your connection and try again."
        }
        return ns.localizedDescription
    }
}

// MARK: - Release model

/// A normalized view of a GitHub release, ready for the UI.
struct UpdateRelease: Equatable {
    let version: String       // "1.2.0" (tag, minus any leading v)
    let name: String          // release title
    let notes: String         // markdown body / changelog
    let downloadURL: URL?      // the .dmg/.zip asset, if any
    let assetName: String?
    let htmlURL: URL           // release page (fallback)
    let publishedAt: Date?
}

// MARK: - GitHub API decoding

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let contentType: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case contentType = "content_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    func asUpdateRelease() -> UpdateRelease {
        // Prefer a .dmg, then a .zip, then the first asset.
        let dmg = assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        let zip = assets.first { $0.name.lowercased().hasSuffix(".zip") }
        let chosen = dmg ?? zip ?? assets.first

        var version = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }

        return UpdateRelease(
            version: version,
            name: (name?.isEmpty == false ? name! : "Codessa \(version)"),
            notes: body ?? "",
            downloadURL: chosen?.browserDownloadURL,
            assetName: chosen?.name,
            htmlURL: htmlURL,
            publishedAt: publishedAt
        )
    }
}

private extension JSONDecoder {
    static var githubDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - Errors

enum UpdateError: Error {
    case network(String)
    case rateLimited(Date?)
    case extractionFailed(String)
    case installFailed(String)

    var message: String {
        switch self {
        case .network(let m): return m
        case .rateLimited(let reset):
            if let reset {
                let mins = max(1, Int(reset.timeIntervalSinceNow / 60) + 1)
                return "GitHub's update-check rate limit was reached (60/hour). Try again in about \(mins) minute\(mins == 1 ? "" : "s")."
            }
            return "GitHub's update-check rate limit was reached (60/hour). Try again in a little while."
        case .extractionFailed(let m): return m
        case .installFailed(let m): return m
        }
    }
}

/// GitHub's error envelope (`{"message": "...", "documentation_url": "..."}`),
/// used to turn a non-release response into a readable message.
private struct GitHubAPIError: Decodable {
    let message: String
}

// MARK: - Download with progress

/// Minimal `URLSessionDownloadDelegate` wrapper that reports progress and
/// resolves to a stable temp file. Kept separate from the `@MainActor` service
/// because its delegate callbacks arrive off the main thread.
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    init(progress: @escaping (Double) -> Void) {
        self.progress = progress
    }

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            var request = URLRequest(url: url)
            request.setValue("Codessa-Updater", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 60
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // `location` is deleted as soon as this returns — move it somewhere stable.
        let name = downloadTask.originalRequest?.url?.lastPathComponent ?? "download"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume(returning: dest)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}
