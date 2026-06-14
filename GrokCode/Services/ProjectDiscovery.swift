import Foundation

struct ProjectDiscovery {
    private let fileManager = FileManager.default

    func discoverProjects(in roots: [URL]) -> [Project] {
        var projects: [Project] = []
        var seen = Set<String>()

        for root in roots {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                guard isProjectDirectory(url) else { continue }
                let key = url.standardizedFileURL.path
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                projects.append(Project(
                    name: url.lastPathComponent,
                    path: url
                ))
            }
        }

        return projects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func defaultRoots() -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Development"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Developer"),
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func isProjectDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true else { return false }

        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }

        // Match Codex-style project lists: any folder in a dev root is a project.
        // Skip obvious non-project containers.
        let skipped = ["node_modules", "vendor", "build", "dist", "target", ".build"]
        if skipped.contains(name) { return false }

        return true
    }
}