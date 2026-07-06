import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileDragPasteboardItem {
    static func make(url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(url.absoluteString, forType: .sniprPublicURL)
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.path, forType: .string)
        return item
    }
}

extension NSPasteboard.PasteboardType {
    static let sniprPublicURL = NSPasteboard.PasteboardType(UTType.url.identifier)
}

/// SwiftUI bridge that emits a real *multi-file* AppKit drag session on
/// mouse-drag, so dropping into Finder / Slack / Discord lands every URL
/// instead of just the first.
///
/// SwiftUI's `View.onDrag` returns one `NSItemProvider` per call; macOS has
/// no multi-item SwiftUI variant in the supported deployment range. The
/// blueprint's "drag the entire stack into Discord and all files land"
/// requirement therefore needs `beginDraggingSession(with:event:source:)`.
struct MultiFileDragView: NSViewRepresentable {
    let urlsProvider: () -> [URL]

    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView(urlsProvider: urlsProvider)
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.urlsProvider = urlsProvider
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var urlsProvider: () -> [URL]
        private var mouseDownEvent: NSEvent?

        init(urlsProvider: @escaping () -> [URL]) {
            self.urlsProvider = urlsProvider
            super.init(frame: .zero)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownEvent = nil
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDown = mouseDownEvent else { return }
            let urls = urlsProvider()
            guard !urls.isEmpty else { return }

            // Build one NSDraggingItem per URL so Finder/Slack receive
            // multiple file promises in a single session.
            var items: [NSDraggingItem] = []
            items.reserveCapacity(urls.count)
            for (offset, url) in urls.enumerated() {
                let dragItem = NSDraggingItem(pasteboardWriter: FileDragPasteboardItem.make(url: url))
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let size = NSSize(width: 96, height: 64)
                let frame = NSRect(
                    x: bounds.midX - size.width / 2 + CGFloat(offset) * 6,
                    y: bounds.midY - size.height / 2 - CGFloat(offset) * 6,
                    width: size.width,
                    height: size.height
                )
                dragItem.setDraggingFrame(frame, contents: icon)
                items.append(dragItem)
            }
            beginDraggingSession(with: items, event: mouseDown, source: self)
            mouseDownEvent = nil
        }

        // MARK: NSDraggingSource

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            switch context {
            case .outsideApplication:
                return [.copy]
            case .withinApplication:
                return [.copy]
            @unknown default:
                return [.copy]
            }
        }
    }
}
