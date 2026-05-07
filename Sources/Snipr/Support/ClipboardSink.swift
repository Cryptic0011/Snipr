import AppKit
import Foundation

/// Writes encoded capture data to `NSPasteboard.general`. Used by the capture
/// flow when `copyToClipboardOnCapture` is enabled, and as the only sink when
/// `saveToDiskOnCapture` is disabled (clipboard-only mode).
enum ClipboardSink {
    /// Writes the encoded image bytes to the general pasteboard under the
    /// pasteboard type appropriate for the format. PNG bytes are written as
    /// `public.png`; lossy formats are normalized to TIFF (via `NSImage`)
    /// because most paste targets lack HEIC decoders.
    @MainActor
    static func copy(data: Data, format: CaptureFormat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch format {
        case .png:
            pasteboard.setData(data, forType: .png)
        case .jpeg, .heic:
            // Round-trip through NSImage to land usable pixels for callers
            // that don't speak the original container. Falls back to writing
            // raw bytes under the format's UTI so power users can still grab
            // them with Pasteboard.dataForType.
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(format.utType.identifier))
        }
    }
}
