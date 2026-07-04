import Foundation
import Combine
import AppKit

/// Owns the Codessa licensing lifecycle: the 7-day no-card trial, online
/// activation/validation of a Lemon Squeezy license key, and an offline grace
/// window so a previously-validated machine keeps working without a connection.
///
/// State machine (published as `status`):
///   • `.trial(daysLeft:)` — within the free trial, no key yet.
///   • `.licensed`         — a key is activated and last validated successfully
///                           (or we're inside the offline grace window).
///   • `.expired`          — trial elapsed and no valid license.
///   • `.invalid`          — a key was entered but the server rejected it.
///   • `.checking`         — a network activation/validation is in flight.
///
/// Storage:
///   • Tamper-resistant bits (trial start, license key, instance id, last
///     validation date) live in the Keychain via `KeychainStore`, falling back
///     to UserDefaults if the Keychain is unavailable.
///   • The fallback + cached display values also mirror into UserDefaults under
///     the existing `grokcode.*` namespace for parity with the rest of the app.
///
/// This type is deliberately a `class: ObservableObject` (not the app's
/// `@Observable` macro) because the task wires it in as a `@StateObject`; both
/// observation systems coexist fine in the same view tree.
@MainActor
final class LicenseManager: ObservableObject {

    // MARK: - Published state

    enum Status: Equatable {
        case checking
        case trial(daysLeft: Int)
        case licensed
        case expired
        case invalid
    }

    @Published private(set) var status: Status = .checking

    /// User-facing key currently activated (masked for display). Empty when none.
    @Published private(set) var activeLicenseKey: String = ""

    /// Set while an activate/validate request is in flight, so the paywall can
    /// show a spinner and disable the submit button.
    @Published private(set) var isWorking = false

    /// Last activation/validation error to surface under the key field.
    @Published var lastError: String?

    // MARK: - Derived convenience

    /// Days remaining in the trial (0 once elapsed). Drives the subtle banner.
    var trialDaysLeft: Int {
        max(0, LicenseConfig.trialDays - daysSinceTrialStart())
    }

    /// Codessa is free. The licensing gate is permanently unlocked: no trial
    /// countdown, no paywall, no limited mode, and no launch-time calls to the
    /// Lemon Squeezy activate/validate endpoints. The full activation machinery
    /// below is kept intact (just unreachable) so the app can be re-monetised
    /// later by flipping this single flag back to `false`.
    static let isFree = true

    /// Developer escape hatch: unconditionally unlocks the app, bypassing the
    /// trial/license gate entirely. Active in DEBUG builds, or in ANY build when
    /// the process is launched with `GROKCODE_DEV_UNLOCK=1` in its environment.
    /// Never true in a normal release build, so shipping customers are unaffected.
    static var devUnlock: Bool {
        if ProcessInfo.processInfo.environment["GROKCODE_DEV_UNLOCK"] == "1" { return true }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// True while the user may use the full app (trial running OR licensed).
    var isUnlocked: Bool {
        if Self.isFree || Self.devUnlock || hasOwnerUnlock { return true }
        switch status {
        case .trial, .licensed: return true
        case .checking: return true   // never block during the launch check
        case .expired, .invalid: return false
        }
    }

    /// True only when the app should show a limited-mode upsell banner. The app
    /// remains usable in this state; paid/full-version affordances can key off
    /// this without hard-blocking the whole shell.
    var isInLimitedMode: Bool {
        if Self.isFree || Self.devUnlock || hasOwnerUnlock { return false }
        switch status {
        case .expired, .invalid: return true
        case .checking, .trial, .licensed: return false
        }
    }

    /// The app no longer hard-locks on license state. Keep this around so any
    /// older call sites remain harmless while the UI moves to limited mode.
    var isLocked: Bool { false }

    /// True during the trial so the gate can show the countdown banner.
    var isInTrial: Bool {
        if case .trial = status { return true }
        return false
    }

    /// Local owner override for this Mac. This is intentionally stored outside
    /// Lemon Squeezy: it gives the app owner a permanent full build without
    /// manufacturing or shipping a fake customer license key.
    private var hasOwnerUnlock: Bool {
        defaults.bool(forKey: DefaultsKey.ownerUnlock)
    }

    // MARK: - Persistence keys

    private enum Account {
        static let trialStart = "trialStartDate"
        static let licenseKey = "licenseKey"
        static let instanceId = "instanceId"
        static let lastValidated = "lastValidatedDate"
        /// Monotonic high-water mark of the latest wall-clock time ever observed.
        /// Used as a tamper floor so rolling the system clock back can't reset the
        /// trial or extend offline grace.
        static let lastSeen = "lastSeenDate"
    }

    // UserDefaults mirror (fallback + parity with grokcode.* namespace).
    private enum DefaultsKey {
        static let trialStart = "grokcode.license.trialStart"
        static let licenseKey = "grokcode.license.key"
        static let instanceId = "grokcode.license.instanceId"
        static let lastValidated = "grokcode.license.lastValidated"
        static let lastSeen = "grokcode.license.lastSeen"
        static let ownerUnlock = "grokcode.license.ownerUnlock"
    }

    private let defaults = UserDefaults.standard
    private let session: URLSession
    private let isoFormatter = ISO8601DateFormatter()

    /// Per-request / per-resource timeouts so a captive portal or a black-holed
    /// connection can't hang the activate/validate spinner indefinitely (mirrors
    /// the bounded session `MarketplaceService` uses for the Discover tab).
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 20

    // MARK: - Init

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = LicenseManager.requestTimeout
            config.timeoutIntervalForResource = LicenseManager.resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Lifecycle entry point

    /// Call once on launch (after onboarding gating is decided). Stamps the trial
    /// start on first run, then either re-validates an existing key online or
    /// resolves the trial/expired state locally.
    func bootstrap() {
        // Free build: settle straight into a permanently-licensed state without
        // stamping a trial or calling the licensing server. Everything below is
        // retained for a future paid build (flip `isFree` to re-enable it).
        if Self.isFree {
            activeLicenseKey = ""
            lastError = nil
            status = .licensed
            return
        }

        if hasOwnerUnlock {
            activeLicenseKey = "Owner"
            lastError = nil
            status = .licensed
            return
        }

        // Advance the monotonic clock floor first so every downstream date check in
        // this launch uses the tamper-resistant "now".
        bumpLastSeen()
        ensureTrialStarted()

        if let key = storedLicenseKey(), let instance = storedInstanceId() {
            activeLicenseKey = Self.mask(key)
            // Optimistically treat a cached, in-grace license as licensed so the
            // app isn't blocked while the network check runs.
            if withinOfflineGrace() {
                status = .licensed
            } else {
                status = .checking
            }
            Task { await revalidate(key: key, instanceId: instance) }
        } else {
            resolveTrialStatus()
        }
    }

    /// Recompute `.trial`/`.expired` purely from the local clock (no key present).
    private func resolveTrialStatus() {
        let left = trialDaysLeft
        status = left > 0 ? .trial(daysLeft: left) : .expired
    }

    // MARK: - Trial timer

    private func ensureTrialStarted() {
        guard storedTrialStart() == nil else { return }
        let now = Date()
        let stamp = isoFormatter.string(from: now)
        if !KeychainStore.set(stamp, account: Account.trialStart) {
            defaults.set(stamp, forKey: DefaultsKey.trialStart)
        }
        // Always mirror so a Keychain wipe can't silently restart the trial.
        defaults.set(stamp, forKey: DefaultsKey.trialStart)
    }

    private func storedTrialStart() -> Date? {
        if let raw = defaults.string(forKey: DefaultsKey.trialStart) ?? KeychainStore.get(account: Account.trialStart),
           let date = isoFormatter.date(from: raw) {
            return date
        }
        return nil
    }

    private func daysSinceTrialStart() -> Int {
        guard let start = storedTrialStart() else { return 0 }
        // Use the high-water clock, not the raw `Date()`. Rolling the system clock
        // back to the install date would otherwise make `days` 0 and hand the user a
        // fresh 7-day trial forever; `effectiveNow()` never decreases.
        let now = max(effectiveNow(), start)
        let days = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
        return max(0, days)
    }

    // MARK: - Monotonic clock floor (tamper resistance)

    /// The greater of the real wall clock and the highest time we've ever recorded.
    /// Monotonic across launches, so a backwards clock change can never reduce it.
    private func effectiveNow() -> Date {
        let now = Date()
        guard let seen = storedLastSeen() else { return now }
        return max(now, seen)
    }

    /// Persist a new high-water mark if the real clock has moved forward past it.
    /// Never lowers the stored value.
    private func bumpLastSeen() {
        let now = Date()
        let floor = storedLastSeen() ?? .distantPast
        guard now > floor else { return }
        let stamp = isoFormatter.string(from: now)
        if !KeychainStore.set(stamp, account: Account.lastSeen) {
            defaults.set(stamp, forKey: DefaultsKey.lastSeen)
        }
        defaults.set(stamp, forKey: DefaultsKey.lastSeen)
    }

    private func storedLastSeen() -> Date? {
        if let raw = defaults.string(forKey: DefaultsKey.lastSeen) ?? KeychainStore.get(account: Account.lastSeen) {
            return isoFormatter.date(from: raw)
        }
        return nil
    }

    // MARK: - Activation (POST /licenses/activate)

    /// Activate `licenseKey` on this device. On success persists the key +
    /// returned instance id and flips to `.licensed`; on failure sets `.invalid`
    /// with `lastError`.
    func activate(licenseKey rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastError = "Enter your license key."
            return
        }

        beginWork()
        defer { endWork() }

        let body: [String: String] = [
            "license_key": key,
            "instance_name": instanceName(),
        ]

        do {
            let (response, statusCode) = try await postLicenseRequest(LicenseConfig.activateURL, body: body)

            // A non-2xx status means the *server* hiccuped (5xx) or rate-limited
            // (429) us, not that the key is bad. Don't brand a real key invalid on
            // a transient server fault — ask the user to retry instead.
            guard (200...299).contains(statusCode) else {
                status = .invalid
                lastError = "Couldn't reach the licensing server (it returned an error). Please try again in a moment."
                return
            }

            guard response.activated, response.valid != false else {
                status = .invalid
                lastError = response.error ?? "That license key couldn't be activated."
                return
            }

            if !variantMatches(response) {
                status = .invalid
                lastError = "This key is for a different product."
                return
            }

            guard let instanceId = response.instanceId else {
                status = .invalid
                lastError = "Activation succeeded but no instance was returned. Try again."
                return
            }

            persist(licenseKey: key, instanceId: instanceId, validatedAt: Date())
            activeLicenseKey = Self.mask(key)
            lastError = nil
            status = .licensed
        } catch {
            // Network/parse failure during activation is a hard fail — there's no
            // cached instance to fall back on for a brand-new key.
            status = .invalid
            lastError = friendlyNetworkError(error)
        }
    }

    // MARK: - Validation (POST /licenses/validate)

    /// Re-check an already-activated key on launch. Network failure does NOT lock
    /// the app while we're inside the offline grace window.
    private func revalidate(key: String, instanceId: String) async {
        beginWork()
        defer { endWork() }

        let body: [String: String] = [
            "license_key": key,
            "instance_id": instanceId,
        ]

        do {
            let (response, statusCode) = try await postLicenseRequest(LicenseConfig.validateURL, body: body)
            let httpOK = (200...299).contains(statusCode)

            if httpOK && response.valid == true && variantMatches(response) {
                // Confirmed good. Re-stamp the high-water validation date.
                persistLastValidated(Date())
                status = .licensed
                lastError = nil
            } else if httpOK && response.valid == false {
                // DEFINITIVE server rejection: HTTP 200 AND an explicit
                // `valid == false` (refunded, disabled, expired). This is the ONLY
                // path that may destroy cached credentials. A 200 with
                // `valid == true` but a variant mismatch deliberately does NOT clear
                // here — it falls through to the soft-fail branch so a misconfigured
                // variant id can never permanently wipe a paying customer's key.
                clearStoredLicense()
                activeLicenseKey = ""
                resolveTrialStatus()
                if status == .expired {
                    lastError = response.error ?? "Your license is no longer valid."
                }
            } else {
                // Non-200 (5xx/429/4xx other than an explicit invalid-key 200), OR a
                // 200 whose body we couldn't decode into a real verdict (valid == nil).
                // This is NOT a rejection — treat it exactly like a network failure:
                // honour the offline grace window and NEVER clear credentials.
                fallBackToGraceOrSoftFail()
            }
        } catch {
            // Couldn't reach the server at all. Honour the offline grace window.
            fallBackToGraceOrSoftFail()
        }
    }

    /// Shared "couldn't get a definitive verdict" handler for revalidate. Keeps a
    /// licensed user `.licensed` while inside the offline grace window (or while a
    /// present license has no usable lastValidated timestamp), and otherwise leaves
    /// them in a soft "couldn't verify" state without ever destroying credentials.
    private func fallBackToGraceOrSoftFail() {
        if withinOfflineGrace() {
            status = .licensed
            lastError = nil
        } else {
            // Credentials are intact; the user simply needs to get back online to
            // re-validate. Surface a soft message but don't wipe the license.
            lastError = "Couldn't verify your license right now. Connect to the internet to continue."
            status = .expired
        }
    }

    /// Public re-validate hook for a Settings "Refresh license" button.
    func refreshValidation() async {
        guard let key = storedLicenseKey(), let instance = storedInstanceId() else {
            resolveTrialStatus()
            return
        }
        await revalidate(key: key, instanceId: instance)
    }

    // MARK: - Deactivate (POST /licenses/deactivate)

    /// Release this device's activation slot and return to the trial/expired
    /// state. Best-effort: the local license is cleared even if the network call
    /// fails, so a user can always move their seat.
    func deactivateThisDevice() async {
        guard let key = storedLicenseKey(), let instance = storedInstanceId() else { return }
        beginWork()
        defer { endWork() }

        let body: [String: String] = ["license_key": key, "instance_id": instance]
        _ = try? await postLicenseRequest(LicenseConfig.deactivateURL, body: body)

        clearStoredLicense()
        activeLicenseKey = ""
        resolveTrialStatus()
    }

    // MARK: - Checkout

    /// Open the Lemon Squeezy hosted checkout (Founder discount pre-applied).
    func openCheckout() {
        NSWorkspace.shared.open(LicenseConfig.checkoutURL)
    }

    // MARK: - Offline grace

    /// True when a previously-activated machine may keep running offline.
    ///
    /// Fails OPEN toward a present license: if the key + instance are both stored
    /// but the `lastValidated` timestamp is missing or unparseable, we treat the
    /// machine as "just activated" (still inside the window) rather than locking out
    /// a paying customer over a single lost local timestamp. The next successful
    /// online validate re-stamps `lastValidated`.
    ///
    /// The elapsed-days math is clamped to the monotonic high-water clock so rolling
    /// the system clock backwards can't manufacture extra grace.
    private func withinOfflineGrace() -> Bool {
        guard storedLicenseKey() != nil, storedInstanceId() != nil else { return false }
        guard let last = storedLastValidated() else {
            // Key + instance present but no usable timestamp: don't fail closed.
            // Re-stamp now so the window is anchored, and grant grace.
            persistLastValidated(effectiveNow())
            return true
        }
        // Compare against the high-water "now" so a rolled-back clock (which would
        // make `days` small or negative) can't extend the window.
        let now = max(effectiveNow(), last)
        let days = Calendar.current.dateComponents([.day], from: last, to: now).day ?? Int.max
        return days <= LicenseConfig.offlineGraceDays
    }

    // MARK: - Networking

    /// Issue a form-encoded POST to a Lemon Squeezy license endpoint with the
    /// required headers and decode the (shared-shape) response.
    ///
    /// Returns the decoded body **and** the HTTP status code. We never throw on a
    /// non-2xx status here: callers must distinguish a *definitive* server verdict
    /// (HTTP 200 + an explicit boolean) from a transient failure (5xx/429/network),
    /// and a non-200 body must never be mistaken for a real license verdict.
    private func postLicenseRequest(_ url: URL, body: [String: String]) async throws -> (response: LSLicenseResponse, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Lemon Squeezy's License API is not their JSON:API surface. Activate,
        // validate, and deactivate expect x-www-form-urlencoded fields.
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(body)

        let (data, urlResponse) = try await session.data(for: request)
        let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        // Decode defensively: a 5xx/429/Cloudflare body may not be license JSON at
        // all. Failing to decode is NOT a license rejection — surface an empty
        // response so the caller treats it as "couldn't verify", never as invalid.
        let response = (try? JSONDecoder().decode(LSLicenseResponse.self, from: data)) ?? LSLicenseResponse.undecodable
        return (response, statusCode)
    }

    private func formEncoded(_ body: [String: String]) -> Data {
        let encoded = body
            .sorted { $0.key < $1.key }
            .map { "\(formEscape($0.key))=\(formEscape($0.value))" }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    private func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }

    private func variantMatches(_ response: LSLicenseResponse) -> Bool {
        // 0 means "don't enforce a specific variant".
        guard LicenseConfig.productVariantId != 0 else { return true }
        guard let variant = response.variantId else { return true }
        return variant == LicenseConfig.productVariantId
    }

    // MARK: - Storage helpers

    private func persist(licenseKey: String, instanceId: String, validatedAt: Date) {
        // The license key and instance id are credentials: only mirror them into
        // the (readable) UserDefaults plist when the Keychain write FAILS, mirroring
        // the `if !set { ... }` fallback used for trialStart/lastValidated. When the
        // Keychain write succeeds, scrub any previously-written plaintext copy so the
        // credentials never linger in the plist.
        if !KeychainStore.set(licenseKey, account: Account.licenseKey) {
            defaults.set(licenseKey, forKey: DefaultsKey.licenseKey)
        } else {
            defaults.removeObject(forKey: DefaultsKey.licenseKey)
        }
        if !KeychainStore.set(instanceId, account: Account.instanceId) {
            defaults.set(instanceId, forKey: DefaultsKey.instanceId)
        } else {
            defaults.removeObject(forKey: DefaultsKey.instanceId)
        }
        persistLastValidated(validatedAt)
    }

    private func persistLastValidated(_ date: Date) {
        let stamp = isoFormatter.string(from: date)
        if !KeychainStore.set(stamp, account: Account.lastValidated) {
            defaults.set(stamp, forKey: DefaultsKey.lastValidated)
        }
        defaults.set(stamp, forKey: DefaultsKey.lastValidated)
    }

    private func storedLicenseKey() -> String? {
        let value = defaults.string(forKey: DefaultsKey.licenseKey) ?? KeychainStore.get(account: Account.licenseKey)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func storedInstanceId() -> String? {
        let value = defaults.string(forKey: DefaultsKey.instanceId) ?? KeychainStore.get(account: Account.instanceId)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func storedLastValidated() -> Date? {
        if let raw = defaults.string(forKey: DefaultsKey.lastValidated) ?? KeychainStore.get(account: Account.lastValidated) {
            return isoFormatter.date(from: raw)
        }
        return nil
    }

    private func clearStoredLicense() {
        KeychainStore.delete(account: Account.licenseKey)
        KeychainStore.delete(account: Account.instanceId)
        KeychainStore.delete(account: Account.lastValidated)
        defaults.removeObject(forKey: DefaultsKey.licenseKey)
        defaults.removeObject(forKey: DefaultsKey.instanceId)
        defaults.removeObject(forKey: DefaultsKey.lastValidated)
    }

    // MARK: - Small helpers

    private func beginWork() {
        isWorking = true
        if status != .licensed { status = .checking }
    }

    private func endWork() { isWorking = false }

    /// A stable, human-readable name for this activation slot in the LS dashboard.
    private func instanceName() -> String {
        Host.current().localizedName ?? "Codessa (\(ProcessInfo.processInfo.hostName))"
    }

    /// Mask a key for display: keep the last 4 chars.
    static func mask(_ key: String) -> String {
        guard key.count > 4 else { return String(repeating: "•", count: key.count) }
        return "•••• " + String(key.suffix(4))
    }

    private func friendlyNetworkError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach the licensing server. Check your connection and try again."
        }
        return "Activation failed: \(error.localizedDescription)"
    }
}

// MARK: - Lemon Squeezy license response

/// Subset of the Lemon Squeezy `/licenses/{activate,validate,deactivate}`
/// response shape we care about. All optional so partial/edge responses decode
/// without throwing — the manager interprets the booleans defensively.
///
/// Reference shape:
/// ```
/// {
///   "activated": true,        // activate only
///   "deactivated": true,      // deactivate only
///   "valid": true,            // validate/activate
///   "error": null,
///   "license_key": { "status": "active", ... },
///   "instance": { "id": "uuid", "name": "..." },
///   "meta": { "variant_id": 123, "product_id": 99, ... }
/// }
/// ```
private struct LSLicenseResponse: Decodable {
    let activated: Bool
    let deactivated: Bool
    let valid: Bool?
    let error: String?
    let instanceId: String?
    let variantId: Int?

    private enum CodingKeys: String, CodingKey {
        case activated, deactivated, valid, error, instance, meta
    }
    private struct Instance: Decodable { let id: String? }
    private struct Meta: Decodable {
        let variantId: Int?
        private enum CodingKeys: String, CodingKey { case variantId = "variant_id" }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activated = (try? c.decode(Bool.self, forKey: .activated)) ?? false
        deactivated = (try? c.decode(Bool.self, forKey: .deactivated)) ?? false
        valid = try? c.decode(Bool.self, forKey: .valid)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        instanceId = (try? c.decode(Instance.self, forKey: .instance))?.id
        variantId = (try? c.decode(Meta.self, forKey: .meta))?.variantId
    }

    private init(activated: Bool, deactivated: Bool, valid: Bool?, error: String?, instanceId: String?, variantId: Int?) {
        self.activated = activated
        self.deactivated = deactivated
        self.valid = valid
        self.error = error
        self.instanceId = instanceId
        self.variantId = variantId
    }

    /// Sentinel used when the HTTP body couldn't be decoded as a license response
    /// (e.g. a 5xx error envelope or a rate-limit page). `valid == nil` so the
    /// manager treats it as "couldn't verify", never as an explicit rejection.
    static let undecodable = LSLicenseResponse(
        activated: false, deactivated: false, valid: nil,
        error: nil, instanceId: nil, variantId: nil
    )
}
