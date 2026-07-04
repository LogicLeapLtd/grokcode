import Foundation

/// Turns a raw CLI process failure (exit code + whatever it wrote to stderr) into
/// a human, actionable message — instead of the useless "exited with code 75".
///
/// The exit codes follow BSD `sysexits.h`, which the Grok CLI (and most
/// well-behaved Unix tools) use. `75` in particular is `EX_TEMPFAIL`, a
/// *transient* failure that's worth retrying — the exact case that produced the
/// original "Grok exited with code 75" the user saw.
enum CLIProcessMessage {
    /// - Parameters:
    ///   - name: user-facing tool name, e.g. "Grok" or a provider's short name.
    ///   - exitCode: the process `terminationStatus`.
    ///   - stderr: raw standard-error text (may be empty).
    static func friendly(name: String, exitCode: Int32, stderr: String) -> String {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = err.lowercased()

        // If the CLI told us something specific, trust it — but lead with a
        // friendly summary for signals we recognise, otherwise pass it through.
        if !err.isEmpty {
            if lower.contains("rate limit") || lower.contains("429") || lower.contains("too many requests") {
                return "\(name) is being rate limited. Wait a few seconds and try again.\n\n\(err)"
            }
            if lower.contains("unauthorized") || lower.contains("401") || lower.contains("not logged in")
                || lower.contains("authentication") || lower.contains("api key") {
                return "\(name) isn't authenticated. Run `grok login` in a terminal, then try again.\n\n\(err)"
            }
            if lower.contains("timed out") || lower.contains("timeout") {
                return "\(name) timed out. Check your connection and try again.\n\n\(err)"
            }
            // A real diagnostic we don't have special copy for — show it verbatim.
            return err
        }

        // No stderr — map the exit code to something meaningful.
        switch exitCode {
        case 75: // EX_TEMPFAIL
            return "\(name) hit a temporary failure — usually rate limiting or a brief network/backend hiccup. Wait a few seconds and try again."
        case 69: // EX_UNAVAILABLE
            return "\(name) is unavailable right now. Check your connection and try again in a moment."
        case 77: // EX_NOPERM
            return "\(name) was denied access. Run `grok login` in a terminal to re-authenticate, then try again."
        case 70: // EX_SOFTWARE
            return "\(name) ran into an internal error. Try again; if it keeps happening, restart \(name)."
        case 64, 2: // EX_USAGE / usage error
            return "\(name) rejected the request as malformed. Try rephrasing, or start a new chat."
        case 130: // SIGINT
            return "\(name) was interrupted."
        default:
            return "\(name) stopped unexpectedly (exit code \(exitCode)). Try again, or run `grok` in a terminal to see what's wrong."
        }
    }
}
