import Foundation

struct PendingHook: Identifiable, Hashable {
    let id: String
    let fileName: String
    let event: String
    let command: String
}

struct HooksService {
    private let hooksDirectory: URL
    private let trustedKey = "grokcode.trustedHooks"

    init() {
        hooksDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/hooks")
    }

    func loadPendingHooks(trusted: Set<String>) -> [PendingHook] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: hooksDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var pending: [PendingHook] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooksRoot = json["hooks"] as? [String: Any] else { continue }

            for (event, value) in hooksRoot {
                guard let groups = value as? [[String: Any]] else { continue }
                for group in groups {
                    guard let inner = group["hooks"] as? [[String: Any]] else { continue }
                    for (index, hook) in inner.enumerated() {
                        guard hook["type"] as? String == "command",
                              let command = hook["command"] as? String else { continue }
                        let id = "\(file.lastPathComponent):\(event):\(index)"
                        if !trusted.contains(id) {
                            pending.append(PendingHook(
                                id: id,
                                fileName: file.lastPathComponent,
                                event: event,
                                command: command
                            ))
                        }
                    }
                }
            }
        }

        return pending
    }

    func loadTrustedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: trustedKey) ?? [])
    }

    func saveTrustedIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: trustedKey)
    }
}