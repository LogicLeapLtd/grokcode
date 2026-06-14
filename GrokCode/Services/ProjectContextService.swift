import Foundation

/// Reads and writes a project's agent-context file (the per-repo instructions an
/// agent reads on every run — `AGENTS.md` for Codex/grok, `GROK.md` as a fallback
/// name). Pure file I/O, stateless, and deliberately **never throws to the UI**:
/// reads return an empty string when nothing's there, and writes return a `Bool`
/// success flag so the surface lane can show a quiet toast rather than handle an
/// error. The Project Context editor sheet calls `read`/`write`; the rest of the
/// app uses `contextFileURL`/`fileName` to label and locate the file.
struct ProjectContextService {
    /// Candidate file names, in preference order. An existing file wins; when
    /// none exist we default to the first (`AGENTS.md`) for a fresh write.
    private static let candidateNames = ["AGENTS.md", "GROK.md"]

    init() {}

    /// The on-disk URL of the project's context file. Prefers an existing
    /// `AGENTS.md`, then an existing `GROK.md`; if neither is present, points at
    /// `<projectPath>/AGENTS.md` (the default we'd create on first write).
    func contextFileURL(for project: Project) -> URL {
        let root = project.path
        let fm = FileManager.default
        for name in Self.candidateNames {
            let candidate = root.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return root.appendingPathComponent(Self.candidateNames[0])
    }

    /// The bare file name of the project's context file (e.g. `AGENTS.md`),
    /// suitable for labelling the editor sheet.
    func fileName(for project: Project) -> String {
        contextFileURL(for: project).lastPathComponent
    }

    /// The current contents of the project's context file. Returns an empty
    /// string when the file is missing or unreadable — never throws.
    func read(_ project: Project) -> String {
        let url = contextFileURL(for: project)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Write `text` to the project's context file (UTF-8). Returns `true` on
    /// success, `false` on any failure — never throws. Creates intermediate
    /// directories defensively so a write can't fail purely because the path
    /// isn't there yet.
    @discardableResult
    func write(_ project: Project, _ text: String) -> Bool {
        let url = contextFileURL(for: project)
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            #if DEBUG
            print("[ProjectContextService] Failed to write \(url.path): \(error)")
            #endif
            return false
        }
    }
}
