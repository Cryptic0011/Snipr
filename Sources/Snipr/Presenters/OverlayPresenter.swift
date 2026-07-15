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
    case ocr
    case qr
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
    private var colorPickerViews: [ColorPickerOverlayView] = []
    private let selectionCoordinator = CaptureOverlaySelectionCoordinator()
    private var activeMode: CaptureOverlayMode?
    var onSelectionComplete: ((CaptureOverlayMode, CGDirectDisplayID, NSScreen, CGRect) -> Void)?
    var onWindowPicked: ((WindowPickerNSView.WindowEntry, CGDirectDisplayID, NSScreen, CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var onColorSampled: ((ColorPickerOverlayView.SampleResult) -> Void)?

    init() {}

    func showCaptureOverlays(mode: CaptureOverlayMode, showMagnifier: Bool = false, showCoordinates: Bool = false, freezeScreen: Bool = false) {
        closeCaptureOverlays()
        activeMode = mode
        selectionCoordinator.reset()
        selectionCoordinator.onChange = { [weak self] in
            self?.hostViews.forEach { $0.needsDisplay = true }
        }

        var hostViews: [CaptureSelectionNSView] = []

        for screen in NSScreen.screens {
            guard let displayID = screen.sniprDisplayID else {
                continue
            }

            let view = CaptureSelectionNSView()
            view.selectionCoordinator = selectionCoordinator
            view.showsMagnifier = showMagnifier
            view.showsCoordinates = showCoordinates
            view.freezesBackground = freezeScreen
            view.onCompleteInScreenCoordinates = { [weak self] globalRect, releasePoint in
                self?.completeSelection(globalRect: globalRect, releasePoint: releasePoint)
            }
            view.onComplete = { [weak self] rect in
                self?.completeSelection(displayID: displayID, screen: screen, rect: rect)
            }
            view.onCancel = { [weak self] in
                self?.closeCaptureOverlays()
                self?.onCancel?()
            }
            view.onPointerPreviewActivated = { [weak self] activeView in
                self?.hostViews
                    .filter { $0 !== activeView }
                    .forEach { $0.hidePointerPreview() }
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

    /// Show a per-screen color picker overlay. Each screen gets a translucent
    /// click-through panel; click samples a pixel and reports back via the
    /// closure. Cancel via Esc or right-click.
    func showColorPickerOverlays(onSample: @escaping (ColorPickerOverlayView.SampleResult) -> Void) {
        closeCaptureOverlays()
        activeMode = .ocr // not really, but distinct from screenshot/recording
        onColorSampled = onSample

        var pickers: [ColorPickerOverlayView] = []
        for screen in NSScreen.screens {
            guard let _ = screen.sniprDisplayID else { continue }
            let view = ColorPickerOverlayView()
            view.sourceScale = screen.backingScaleFactor
            view.onSample = { [weak self] sample in
                self?.closeCaptureOverlays()
                self?.onColorSampled?(sample)
                self?.onColorSampled = nil
            }
            view.onCancel = { [weak self] in
                self?.closeCaptureOverlays()
                self?.onCancel?()
                self?.onColorSampled = nil
            }
            view.onPointerPreviewActivated = { [weak self] activeView in
                self?.colorPickerViews
                    .filter { $0 !== activeView }
                    .forEach { $0.hidePointerPreview() }
            }

            let window = makePanel(frame: screen.frame, content: view)
            overlayWindows.append(window)
            pickers.append(view)
            window.orderFrontRegardless()
            window.makeKey()
        }
        self.colorPickerViews = pickers

        Task { @MainActor [weak self] in
            await self?.loadDisplayImagesForColorPickers()
        }
    }

    func closeCaptureOverlays() {
        guard !overlayWindows.isEmpty || !hostViews.isEmpty || !pickerViews.isEmpty || !colorPickerViews.isEmpty else {
            selectionCoordinator.reset()
            selectionCoordinator.onChange = nil
            activeMode = nil
            return
        }
        overlayWindows.forEach { window in
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        hostViews.removeAll()
        pickerViews.removeAll()
        colorPickerViews.removeAll()
        selectionCoordinator.reset()
        selectionCoordinator.onChange = nil
        activeMode = nil
    }

    private func makePanel(frame: NSRect, content: NSView) -> NSPanel {
        let panel = KeyableSelectionPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SniprDiagnostics.disableRestoration(for: panel)
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

    private func completeSelection(globalRect: CGRect, releasePoint: CGPoint) {
        guard let mode = activeMode,
              let target = targetScreen(for: globalRect, releasePoint: releasePoint),
              let rect = CaptureOverlaySelectionCoordinator.selectionRect(
                forGlobalRect: globalRect,
                inScreenFrame: target.screen.frame
              ),
              rect.width >= 4,
              rect.height >= 4 else {
            closeCaptureOverlays()
            onCancel?()
            return
        }

        closeCaptureOverlays()
        onSelectionComplete?(mode, target.displayID, target.screen, rect)
    }

    private func targetScreen(
        for globalRect: CGRect,
        releasePoint: CGPoint
    ) -> (displayID: CGDirectDisplayID, screen: NSScreen)? {
        let screens = NSScreen.screens.compactMap { screen -> (displayID: CGDirectDisplayID, screen: NSScreen)? in
            guard let displayID = screen.sniprDisplayID else { return nil }
            return (displayID, screen)
        }

        if let screenUnderRelease = screens.first(where: { $0.screen.frame.contains(releasePoint) }) {
            return screenUnderRelease
        }

        let candidates: [(displayID: CGDirectDisplayID, screen: NSScreen, area: CGFloat)] = screens.map { candidate in
            let clipped = globalRect.intersection(candidate.screen.frame)
            let area = clipped.isNull ? 0 : clipped.width * clipped.height
            return (candidate.displayID, candidate.screen, area)
        }
        guard let best = candidates.filter({ $0.area > 0 }).max(by: { $0.area < $1.area }) else {
            return nil
        }
        return (best.displayID, best.screen)
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
            let overlayCGWindowIDs = Set(overlayWindows.map { CGWindowID($0.windowNumber) })
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
                view.setWindows(entries, excludingWindowIDs: overlayCGWindowIDs)
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

    private func loadDisplayImagesForColorPickers() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for view in colorPickerViews {
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
                    // Non-fatal — picker still works for visible cursor
                    // movement, just no live sampling preview.
                }
            }
        } catch {
            // Non-fatal.
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
