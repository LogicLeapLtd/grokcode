import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat lane behaviour (edit-and-resend + composer attachments)
//
// Stored state lives on AppViewModel (Foundation lane). Everything here is
// derived from existing state (`messages`, `promptText`) or routes through the
// existing attach pipeline, so this lane adds no stored properties.

extension AppViewModel {

    // MARK: #8 — Edit & resend a previous user message

    /// Replace the text of the user message at `id`, drop everything after it
    /// (the stale answer + any later turns), then re-run from that point —
    /// `retryLast`-style. Used when the user clicks a sent message, edits it,
    /// and confirms. No-op while a run is in flight.
    func editAndResend(messageID id: UUID, newText: String) {
        guard !isRunning else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].role == .user else { return }

        // Truncate the thread to (and including) the edited turn, then apply the
        // new text in place so the bubble keeps its identity/position.
        messages.removeSubrange((index + 1)...)
        messages[index].text = trimmed
        messages[index].errorText = nil
        messages[index].isQueued = false

        // grok locks a session to the prior turn sequence; editing rewrites
        // history, so start a fresh session rather than resuming a stale one.
        resetSessionForEdit()

        // The edited bubble is now the trailing user message, so the existing
        // retry path resends exactly it (and starts a new assistant turn).
        retryLast()
    }

    // MARK: #13 — Composer attachments

    /// Attachment chips staged on the composer. Stored separately from the prompt
    /// text (`composerAttachmentPaths`) so the path token is never shown in — or
    /// breakable by editing — the input. Removal is only via the chip's × button.
    var composerAttachments: [ComposerAttachment] {
        composerAttachmentPaths.map { ComposerAttachment(path: $0) }
    }

    /// Whether the composer has at least one staged attachment.
    var hasComposerAttachments: Bool {
        !composerAttachmentPaths.isEmpty
    }

    /// Remove a single staged attachment (the chip's × button).
    func removeComposerAttachment(_ attachment: ComposerAttachment) {
        composerAttachmentPaths.removeAll { $0 == attachment.path }
    }

    /// Compose the text actually sent to grok from typed text + attachment paths.
    static func composedSendText(_ text: String, attachments: [String]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else { return trimmed }
        let tokens = attachments.map { "[\($0)]" }.joined(separator: " ")
        return trimmed.isEmpty ? tokens : trimmed + "\n" + tokens
    }

    /// Attach files dropped onto the composer. Resolves each provider to a file
    /// URL and feeds it through the same inline `[<path>]` pipeline as the
    /// paperclip menu. Returns true if it will consume at least one provider.
    @discardableResult
    func handleComposerDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor [weak self] in
                    self?.attachDroppedFile(at: url)
                }
            }
        }
        return true
    }

    /// Cmd-V in the composer: if the pasteboard holds an image (rather than
    /// text), write it to a temp PNG and attach it. Returns true when an image
    /// was consumed so the caller can swallow the paste (otherwise let the field
    /// paste text as usual). Also handles file URLs copied in Finder.
    @discardableResult
    func handleComposerPaste() -> Bool {
        let pb = NSPasteboard.general

        // File(s) copied from Finder paste as file URLs — attach them directly.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty, urls.allSatisfy({ $0.isFileURL }) {
            urls.forEach { attachDroppedFile(at: $0) }
            return true
        }

        // A raw image on the pasteboard (screenshot, copied picture) — persist
        // it to a temp PNG so grok can read it from a path.
        guard let image = NSImage(pasteboard: pb),
              let url = Self.writeTempPNG(from: image) else { return false }
        appendAttachmentPath(url.path)
        return true
    }

    // MARK: - Private helpers

    /// Append a resolved file path as a staged attachment.
    private func attachDroppedFile(at url: URL) {
        appendAttachmentPath(url.standardizedFileURL.path)
    }

    /// Stage an attachment path (deduped). Shared by the menu / drop / paste paths.
    func appendAttachmentPath(_ path: String) {
        guard !composerAttachmentPaths.contains(path) else { return }
        composerAttachmentPaths.append(path)
    }

    /// Drop the active grok session so an edited (rewritten) history starts a
    /// brand-new conversation. Mirrors the private reset that `selectProject`
    /// performs, but only touches the session — keeps the visible thread.
    private func resetSessionForEdit() {
        activeSessionId = nil
        errorMessage = nil
    }

    // MARK: - Token utilities

    /// Persist an in-memory image to a unique temp PNG; returns its URL.
    fileprivate static func writeTempPNG(from image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok_paste_\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

/// A single composer attachment chip, derived from an inline `[<path>]` token.
struct ComposerAttachment: Identifiable, Hashable {
    /// The absolute file path the token points at.
    let path: String

    var id: String { path }

    /// Last path component for the chip label (e.g. `screenshot.png`).
    var fileName: String {
        (path as NSString).lastPathComponent
    }

    /// File extension, lowercased, used to pick an icon (empty for folders).
    var ext: String {
        (path as NSString).pathExtension.lowercased()
    }

    /// True when the path resolves to a directory on disk.
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Whether this attachment is an image we can thumbnail.
    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp"].contains(ext)
    }

    /// SF Symbol used when we can't render a thumbnail.
    var iconSystemName: String {
        if isDirectory { return "folder.fill" }
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "bmp":
            return "photo"
        case "pdf": return "doc.richtext"
        case "swift", "py", "js", "ts", "rb", "go", "rs", "c", "cpp", "h", "java", "json", "yml", "yaml", "sh":
            return "curlybraces"
        case "md", "txt", "rtf": return "doc.text"
        case "zip", "tar", "gz", "dmg": return "doc.zipper"
        default: return "doc"
        }
    }
}
