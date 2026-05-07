import AppKit
import Observation
import SwiftUI

/// Owns annotation/preview windows. The coordinator forwards preview requests
/// here so views that drive the editor live in one place.
@MainActor
@Observable
final class PreviewPresenter {
    private var previewWindows: [UUID: NSWindow] = [:]
    private let captureStore: CaptureStore

    var contentProvider: ((CaptureItem) -> AnyView)?
    /// Called after a new preview window is opened so the stack presenter
    /// can decide whether to auto-hide.
    var onPreviewOpened: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(captureStore: CaptureStore) {
        self.captureStore = captureStore
    }

    func openPreview(for item: CaptureItem) {
        if let window = previewWindows[item.id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView: AnyView
        switch item.mediaType {
        case .image:
            guard let contentProvider else { return }
            rootView = contentProvider(item)
        case .video:
            rootView = AnyView(VideoTrimView(item: item))
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = item.filename
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        previewWindows[item.id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onPreviewOpened?()
    }

    func closePreview(for itemID: UUID) {
        previewWindows[itemID]?.close()
        previewWindows[itemID] = nil
    }

    /// True when `window` is one of the open preview/annotation windows.
    /// Consulted by the stack presenter so auto-hide pauses while the user
    /// is editing.
    func isPreviewWindow(_ window: NSWindow) -> Bool {
        previewWindows.values.contains(window)
    }

    func delete(_ item: CaptureItem) {
        do {
            try captureStore.delete(item)
            closePreview(for: item.id)
        } catch {
            onError?(error)
        }
    }
}
