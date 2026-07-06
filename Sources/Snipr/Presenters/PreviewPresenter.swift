import AppKit
import Observation
import SwiftUI

/// Owns annotation/preview windows. The coordinator forwards preview requests
/// here so views that drive the editor live in one place.
@MainActor
@Observable
final class PreviewPresenter {
    private var previewWindows: [UUID: NSWindow] = [:]
    private var previewWindowIDs: Set<ObjectIdentifier> = []
    private var closeObserverTokens: [UUID: NSObjectProtocol] = [:]
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
        SniprDiagnostics.disableRestoration(for: window)
        window.title = item.filename
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        registerPreviewWindow(window, for: item.id)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onPreviewOpened?()
    }

    func closePreview(for itemID: UUID) {
        guard let window = previewWindows[itemID] else { return }
        unregisterPreviewWindow(for: itemID)
        window.contentView = nil
        window.close()
    }

    /// True when `window` is one of the open preview/annotation windows.
    /// Consulted by the stack presenter so auto-hide pauses while the user
    /// is editing.
    func isPreviewWindow(_ window: NSWindow) -> Bool {
        previewWindowIDs.contains(ObjectIdentifier(window))
    }

    func delete(_ item: CaptureItem) {
        do {
            try captureStore.delete(item)
            closePreview(for: item.id)
        } catch {
            onError?(error)
        }
    }

    private func registerPreviewWindow(_ window: NSWindow, for itemID: UUID) {
        previewWindows[itemID] = window
        previewWindowIDs.insert(ObjectIdentifier(window))
        closeObserverTokens[itemID] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                window?.contentView = nil
                self?.unregisterPreviewWindow(for: itemID)
            }
        }
    }

    private func unregisterPreviewWindow(for itemID: UUID) {
        if let token = closeObserverTokens.removeValue(forKey: itemID) {
            NotificationCenter.default.removeObserver(token)
        }
        if let window = previewWindows.removeValue(forKey: itemID) {
            previewWindowIDs.remove(ObjectIdentifier(window))
        }
    }
}
