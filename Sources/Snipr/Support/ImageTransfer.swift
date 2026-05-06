import AppKit
import UniformTypeIdentifiers

enum ImageTransfer {
    @MainActor
    static func copy(_ item: CaptureItem) {
        switch item.mediaType {
        case .image:
            guard let image = NSImage(contentsOf: item.fileURL) else {
                return
            }

            copyImage(image)
        case .video:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([item.fileURL as NSURL])
        }
    }

    @MainActor
    static func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @MainActor
    static func saveAs(_ item: CaptureItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = item.mediaType == .image ? [.png] : [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.filename

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: item.fileURL, to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @MainActor
    static func savePNGData(_ data: Data, suggestedFilename: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            try data.write(to: destination, options: [.atomic])
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
