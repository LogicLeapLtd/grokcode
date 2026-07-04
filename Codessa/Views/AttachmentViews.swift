import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A reusable attachment chip used by both the composer (with a × remove button)
/// and the chat history (read-only). Hovering reveals a popover with the image
/// preview above the full file name and its directory; clicking an image opens
/// the full-screen viewer.
struct AttachmentChipView: View {
    let path: String
    /// When provided, a × button removes the attachment (composer only).
    var onRemove: (() -> Void)? = nil

    @Environment(AppViewModel.self) private var model
    @State private var hovering = false
    @State private var showPreview = false
    @State private var thumbnail: NSImage?

    private var meta: ComposerAttachment { ComposerAttachment(path: path) }

    var body: some View {
        HStack(spacing: 7) {
            leading

            Text(meta.fileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .leading)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(CodexTheme.textTertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.5)
                .help("Remove attachment")
            }
        }
        .padding(.leading, (meta.isImage && thumbnail != nil) ? 4 : 8)
        .padding(.trailing, onRemove == nil ? 9 : 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(CodexTheme.pillBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(CodexTheme.composerShellBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { h in
            hovering = h
            showPreview = h
        }
        .onTapGesture {
            if meta.isImage { model.fullScreenImagePath = path }
        }
        .popover(isPresented: $showPreview, arrowEdge: .top) {
            AttachmentPreviewPopover(path: path)
        }
        .task(id: path) { await loadThumbnailIfNeeded() }
    }

    @ViewBuilder
    private var leading: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: meta.iconSystemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(CodexTheme.textSecondary)
                .frame(width: 18, height: 18)
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard meta.isImage, thumbnail == nil else { return }
        let p = path
        let data = await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: URL(fileURLWithPath: p))
        }.value
        guard let data, let image = NSImage(data: data) else { return }
        thumbnail = image
    }
}

/// Hover popover: the image preview (for images) above the full file name and its
/// containing directory.
private struct AttachmentPreviewPopover: View {
    let path: String
    @State private var image: NSImage?

    private var meta: ComposerAttachment { ComposerAttachment(path: path) }
    private var directory: String { (path as NSString).deletingLastPathComponent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if meta.isImage {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CodexTheme.pillBackground)
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
                .frame(maxWidth: 320, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(meta.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CodexTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(directory)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexTheme.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 320, alignment: .leading)

            if meta.isImage {
                Text("Click to open full screen")
                    .font(.system(size: 10))
                    .foregroundStyle(CodexTheme.textTertiary)
            }
        }
        .padding(12)
        .frame(width: 344)
        .task(id: path) { await load() }
    }

    private func load() async {
        guard meta.isImage, image == nil else { return }
        let p = path
        let data = await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: URL(fileURLWithPath: p))
        }.value
        guard let data, let img = NSImage(data: data) else { return }
        image = img
    }
}

/// Full-screen image viewer with download + close, presented over the whole
/// window when `model.fullScreenImagePath` is set.
struct FullScreenImageOverlay: View {
    let path: String
    var onClose: () -> Void

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.93)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(56)
            } else {
                ProgressView().controlSize(.large)
            }

            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    controlButton("arrow.down.to.line", help: "Download") { download() }
                    controlButton("xmark", help: "Close") { onClose() }
                }
                .padding(16)
                Spacer()
            }
        }
        .transition(.opacity)
        .task(id: path) { await load() }
        .onExitCommand { onClose() }
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func load() async {
        let p = path
        let data = await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: URL(fileURLWithPath: p))
        }.value
        guard let data, let img = NSImage(data: data) else { return }
        image = img
    }

    private func download() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (path as NSString).lastPathComponent
        if let ext = (path as NSString).pathExtension as String?,
           let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dest)
        }
    }
}
