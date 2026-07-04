import AppKit
import Combine
import Foundation

@MainActor
final class LocalBuildUpdateService: ObservableObject {
    struct PendingBuild: Equatable {
        let modifiedAt: Date
        let version: String
        let build: String

        var versionLabel: String {
            build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
        }

        var signature: String {
            "\(modifiedAt.timeIntervalSince1970)-\(version)-\(build)"
        }
    }

    static let pendingDirectoryURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Codessa/PendingUpdate", isDirectory: true)

    static let pendingAppURL = pendingDirectoryURL.appendingPathComponent("Codessa.app", isDirectory: true)

    @Published private(set) var pendingBuild: PendingBuild?
    @Published private(set) var isInstalling = false
    @Published private(set) var errorMessage: String?

    private var pollTask: Task<Void, Never>?
    private var snoozedSignature: String?

    deinit {
        pollTask?.cancel()
    }

    var hasPromptableBuild: Bool {
        pendingBuild != nil || isInstalling
    }

    func startWatching() {
        guard pollTask == nil else {
            scanForPendingBuild()
            return
        }

        ensurePendingDirectoryExists()
        scanForPendingBuild()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    self?.scanForPendingBuild()
                }
            }
        }
    }

    func snoozeCurrent() {
        snoozedSignature = pendingBuild?.signature
        pendingBuild = nil
        errorMessage = nil
    }

    func installAndRelaunch() {
        guard pendingBuild != nil else { return }
        isInstalling = true
        errorMessage = nil

        do {
            try swapPendingBuildIntoApplications()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        } catch {
            isInstalling = false
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    private func ensurePendingDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: Self.pendingDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func scanForPendingBuild() {
        guard !isInstalling else { return }

        let fm = FileManager.default
        let appURL = Self.pendingAppURL
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            pendingBuild = nil
            return
        }

        let modifiedAt = ((try? fm.attributesOfItem(atPath: appURL.path)[.modificationDate]) as? Date) ?? Date()
        let info = Bundle(url: appURL)?.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "local"
        let build = (info?["CFBundleVersion"] as? String) ?? ""
        let buildInfo = PendingBuild(modifiedAt: modifiedAt, version: version, build: build)

        if buildInfo.signature == snoozedSignature {
            return
        }

        pendingBuild = buildInfo
        errorMessage = nil
    }

    private func swapPendingBuildIntoApplications() throws {
        let source = Self.pendingAppURL
        let destination = UpdateService.canonicalInstallURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        SRC="$1"
        DEST="$2"
        PID="$3"

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
          /bin/rm -rf "$SRC" 2>/dev/null
          /usr/bin/open "$DEST"
        else
          /bin/rm -rf "$DEST" 2>/dev/null
          if [ -d "$BACKUP" ]; then /bin/mv "$BACKUP" "$DEST"; fi
          /usr/bin/open "$DEST"
        fi
        """

        let fm = FileManager.default
        let scriptURL = fm.temporaryDirectory.appendingPathComponent("codessa-local-swap-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let task = Process()
        let destParent = destination.deletingLastPathComponent()

        if fm.isWritableFile(atPath: destParent.path) {
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [scriptURL.path, source.path, destination.path, String(pid)]
        } else {
            let inner = "/bin/sh \(Self.shQuote(scriptURL.path)) \(Self.shQuote(source.path)) \(Self.shQuote(destination.path)) \(pid)"
            let osa = "do shell script \(Self.appleScriptQuote(inner)) with administrator privileges"
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osa]
        }

        try task.run()
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
