import AppKit
import SwiftUI

/// Wraps `NSSharingServicePicker` so SwiftUI views can open the standard share
/// menu (Mail, Messages, AirDrop, system Share extensions).
///
/// Phase 4 hard line: **no built-in cloud upload**. We deliberately restrict
/// ourselves to the system picker — anything Snipr ships ourselves keeps the
/// app local-first.
enum ShareMenu {
    /// Show the system share picker anchored to `view`, sharing the given
    /// `items` (typically file URLs). The picker auto-dismisses.
    @MainActor
    static func show(items: [Any], from view: NSView, edge: NSRectEdge = .minY) {
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
    }
}

/// SwiftUI button that hosts an `NSButton` and opens the system share picker
/// rooted at its own frame on click. Wraps AppKit so SwiftUI doesn't have to
/// reach for a hidden NSView — the AppKit button is the anchor.
struct ShareButton: NSViewRepresentable {
    let urlsProvider: () -> [URL]
    let symbolName: String
    let helpText: String

    init(symbolName: String = "square.and.arrow.up", helpText: String = "Share", urlsProvider: @escaping () -> [URL]) {
        self.symbolName = symbolName
        self.helpText = helpText
        self.urlsProvider = urlsProvider
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(urlsProvider: urlsProvider)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = ShareNSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: helpText) ?? NSImage(), target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .accessoryBar
        button.isBordered = false
        button.toolTip = helpText
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.urlsProvider = urlsProvider
    }

    @MainActor
    final class Coordinator: NSObject {
        var urlsProvider: () -> [URL]

        init(urlsProvider: @escaping () -> [URL]) {
            self.urlsProvider = urlsProvider
        }

        @MainActor
        @objc func share(_ sender: NSButton) {
            let urls = urlsProvider()
            ShareMenu.show(items: urls, from: sender)
        }
    }
}

/// Internal subclass kept around so a future iteration can override
/// hit-testing or appearance without touching the SwiftUI surface above.
private final class ShareNSButton: NSButton {}
