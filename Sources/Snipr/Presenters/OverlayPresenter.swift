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

/// Owns the per-screen selection overlay windows. Its job is purely to put up
/// `CaptureOverlayView` panels, listen for the user's selection, and notify
/// the coordinator. It does not know about engines or stores.
@MainActor
@Observable
final class OverlayPresenter {
    private var overlayWindows: [NSWindow] = []
    private var hostViews: [CaptureSelectionNSView] = []
    private var pickerViews: [WindowPickerNSView] = []
    private var activeMode: CaptureOverlayMode?
    var onSelectionComplete: ((CaptureOverlayMode, CGDirectDisplayID, NSScreen, CGRect) -> Void)?
    var onWindowPicked: ((WindowPickerNSView.WindowEntry, CGDirectDisplayID, NSScreen, CGRect) -> Void)?
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

            let window = makePanel(frame: screen.frame, content: view)
            overlayWindows.append(window)
            hostViews.append(view)
            window.orderFrontRegardless()
            window.makeKey()
        }

        self.hostViews = hostViews

        Task { @MainActor [weak self] in
            await self?.loadDisplayImagesAndWindows()
        }
    }

    /// Show a per-screen window-picker overlay. Click highlights the window
    /// under cursor, click captures it through the existing capture flow.
    func showWindowPickerOverlays() {
        closeCaptureOverlays()
        activeMode = .screenshot

        var pickers: [WindowPickerNSView] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.sniprDisplayID else { continue }

            let view = WindowPickerNSView()
            view.onPick = { [weak self] entry, rect in
                self?.closeCaptureOverlays()
                self?.onWindowPicked?(entry, displayID, screen, rect)
            }
            view.onCancel = { [weak self] in
                self?.closeCaptureOverlays()
                self?.onCancel?()
            }

            let window = makePanel(frame: screen.frame, content: view)
            overlayWindows.append(window)
            pickers.append(view)
            window.orderFrontRegardless()
            window.makeKey()
        }
        self.pickerViews = pickers

        Task { @MainActor [weak self] in
            await self?.loadWindowsForPicker()
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
        pickerViews.removeAll()
        activeMode = nil
    }

    private func makePanel(frame: NSRect, content: NSView) -> NSPanel {
        let panel = KeyableSelectionPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.contentView = content
        return panel
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

    private func loadWindowsForPicker() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for view in pickerViews {
                guard let screen = view.window?.screen, let displayID = screen.sniprDisplayID else { continue }
                let entries: [WindowPickerNSView.WindowEntry] = content.windows.compactMap { window in
                    let frame = window.frame
                    guard frame.intersects(CGDisplayBounds(displayID)) else { return nil }
                    let frameInScreen = displayBoundsToScreenPoints(frame, displayID: displayID, screen: screen)
                    return WindowPickerNSView.WindowEntry(
                        frame: frameInScreen,
                        scWindowID: window.windowID,
                        title: window.title,
                        appName: window.owningApplication?.applicationName
                    )
                }
                view.setWindows(entries)
            }
        } catch {
            // Non-fatal: picker still cancels on right-click / Esc even with
            // no entries; we'd rather show an empty picker than a hang.
        }
    }

    private func distributeWindowList(content: SCShareableContent) {
        for view in hostViews {
            guard let displayID = view.window?.screen?.sniprDisplayID,
                  let screen = view.window?.screen else {
                continue
            }

            let rectsForDisplay: [CGRect] = content.windows.compactMap { window in
                let frame = window.frame
                guard frame.intersects(CGDisplayBounds(displayID)) else { return nil }
                return displayBoundsToScreenPoints(frame, displayID: displayID, screen: screen)
            }
            view.setSnapEdges(rectsForDisplay)
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
