import AppKit
import Observation
import ScreenCaptureKit
import SwiftUI

/// Mode the selection overlay should resolve to once the user has dragged a
/// rect — kept here (not in the coordinator) so adding new modes (window
/// picker etc) in later phases stays inside the presenter.
enum CaptureOverlayMode: Sendable {
    case screenshot
    case recording
}

/// Snapshot of the on-screen window list at the moment the overlay opened,
/// converted into the snapping/highlighting forms the overlay needs.
@MainActor
struct OverlayWindowSnapshot: Sendable {
    /// Per-screen list of windows. Each entry is a frame in display points
    /// (with the same top-left origin convention the overlay uses) plus
    /// metadata for the window-picker label.
    struct Window: Sendable {
        let frameInScreen: CGRect
        let scWindowID: CGWindowID
        let title: String?
        let appName: String?
    }

    /// Keyed by `CGDirectDisplayID`. A display with no on-screen windows
    /// (rare) still gets an empty array.
    let windowsByDisplay: [CGDirectDisplayID: [Window]]
    /// Cached display image keyed by `CGDirectDisplayID`. Populated
    /// asynchronously after the overlay opens — the loupe falls back to a
    /// neutral background until the snapshot resolves.
    var displayImageByDisplay: [CGDirectDisplayID: CGImage]
}

/// Owns the per-screen selection overlay windows. Its job is purely to put up
/// `CaptureOverlayView` panels, listen for the user's selection, and notify
/// the coordinator. It does not know about engines or stores.
@MainActor
@Observable
final class OverlayPresenter {
    private var overlayWindows: [NSWindow] = []
    private var hostViews: [CaptureSelectionNSView] = []
    private var activeMode: CaptureOverlayMode?
    var onSelectionComplete: ((CaptureOverlayMode, CGDirectDisplayID, NSScreen, CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init() {}

    func showCaptureOverlays(mode: CaptureOverlayMode) {
        closeCaptureOverlays()
        activeMode = mode

        var hostViews: [CaptureSelectionNSView] = []

        for screen in NSScreen.screens {
            guard let displayID = screen.sniprDisplayID else {
                continue
            }

            let view = CaptureSelectionNSView()
            view.onComplete = { [weak self] rect in
                self?.completeSelection(displayID: displayID, screen: screen, rect: rect)
            }
            view.onCancel = { [weak self] in
                self?.closeCaptureOverlays()
                self?.onCancel?()
            }
            view.sourceScale = screen.backingScaleFactor

            let window = KeyableSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.contentView = view

            overlayWindows.append(window)
            hostViews.append(view)
            window.orderFrontRegardless()
            // Borderless + nonactivating panels can't become key by default,
            // so keyDown (Esc to cancel) never reaches the overlay view.
            // KeyableSelectionPanel opts in to canBecomeKey without activating
            // the app, then we make it key on the screen the user clicks.
            window.makeKey()
        }

        self.hostViews = hostViews

        // Kick off async loaders for the loupe source image and the on-screen
        // window list. Both are best-effort — overlay stays usable without
        // them; loupe falls back to no zoom and snap is a no-op until the
        // window list arrives.
        Task { @MainActor [weak self] in
            await self?.loadDisplayImagesAndWindows()
        }
    }

    func closeCaptureOverlays() {
        overlayWindows.forEach { window in
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        hostViews.removeAll()
        activeMode = nil
    }

    private func completeSelection(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        guard let mode = activeMode else {
            return
        }

        closeCaptureOverlays()
        onSelectionComplete?(mode, displayID, screen, rect)
    }

    private func loadDisplayImagesAndWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            distributeWindowList(content: content)
            await loadDisplayImages(content: content)
        } catch {
            // Non-fatal: the overlay still works without the cache.
        }
    }

    private func distributeWindowList(content: SCShareableContent) {
        for view in hostViews {
            guard let displayID = view.window?.screen?.sniprDisplayID,
                  let screen = view.window?.screen else {
                continue
            }

            let windowsForDisplay: [(rect: CGRect, scWindowID: CGWindowID, title: String?, app: String?)] = content.windows.compactMap { window in
                let frame = window.frame
                guard frame.intersects(CGDisplayBounds(displayID)) else { return nil }
                let frameInScreen = displayBoundsToScreenPoints(frame, displayID: displayID, screen: screen)
                return (frameInScreen, window.windowID, window.title, window.owningApplication?.applicationName)
            }
            view.setSnapEdges(windowsForDisplay.map(\.rect))
        }
    }

    private func loadDisplayImages(content: SCShareableContent) async {
        for view in hostViews {
            guard let screen = view.window?.screen, let displayID = screen.sniprDisplayID,
                  let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                continue
            }

            let configuration = SCStreamConfiguration()
            configuration.width = Int(CGDisplayBounds(displayID).width)
            configuration.height = Int(CGDisplayBounds(displayID).height)
            configuration.showsCursor = false
            configuration.capturesAudio = false

            // Build the filter excluding the overlay windows themselves so
            // the loupe doesn't sample our own dim layer back to the user.
            let overlayCGWindows = overlayWindows.compactMap { $0.windowNumber }
            let excluded = content.windows.filter { window in
                overlayCGWindows.contains(Int(window.windowID))
            }
            let filter = SCContentFilter(display: scDisplay, excludingWindows: excluded)

            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                view.setSourceImage(image)
            } catch {
                // Non-fatal — loupe simply doesn't show pixels.
            }
        }
    }

    /// Convert a `CGRect` from the global display coordinate space (where
    /// `CGDisplayBounds` lives, with origin top-left) to the per-screen point
    /// space the overlay uses (also top-left origin, but framed at the
    /// screen, since the overlay panel was sized to `screen.frame`).
    private func displayBoundsToScreenPoints(_ rect: CGRect, displayID: CGDirectDisplayID, screen: NSScreen) -> CGRect {
        let displayBounds = CGDisplayBounds(displayID)
        let scaleX = screen.frame.width / displayBounds.width
        let scaleY = screen.frame.height / displayBounds.height
        let translatedX = (rect.minX - displayBounds.minX) * scaleX
        let translatedY = (rect.minY - displayBounds.minY) * scaleY
        return CGRect(
            x: translatedX,
            y: translatedY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }
}

/// `NSPanel` subclass that opts in to becoming key while keeping the
/// `.nonactivatingPanel` behavior. Required so the selection overlay can
/// receive keyDown events (Esc to cancel) without bringing the app forward.
private final class KeyableSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
