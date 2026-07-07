import AppKit
import Observation
import SwiftUI

/// Owns the still-capture flow — turning a selected (display, rect) into a
/// stored `CaptureItem`. Phase 1 expanded the surface here (last-region
/// recall, format/template prefs, clipboard-only mode, window picking) so the
/// coordinator stays a router and this presenter is the place capture
/// behavior lives.
@MainActor
@Observable
final class CaptureFlowPresenter {
    let captureStore: CaptureStore
    let preferences: SniprPreferences
    let captureEngine: CaptureEngine
    let ocrEngine: any OCREngine
    let ocrHistory: OCRHistoryStore

    /// Last completed capture region; remembered in memory so the user can
    /// repeat it via `captureLastRegion` without re-dragging.
    private(set) var lastRegion: LastRegion?

    /// Monotonic sequence used by filename templates (`{seq}` token).
    private var captureSequence: Int = 0

    var onError: ((Error) -> Void)?
    var onCaptureStored: (() -> Void)?

    init(
        captureStore: CaptureStore,
        preferences: SniprPreferences,
        captureEngine: CaptureEngine,
        ocrEngine: any OCREngine = VisionOCREngine(),
        ocrHistory: OCRHistoryStore? = nil
    ) {
        self.captureStore = captureStore
        self.preferences = preferences
        self.captureEngine = captureEngine
        self.ocrEngine = ocrEngine
        self.ocrHistory = ocrHistory ?? OCRHistoryStore()
    }

    /// Capture pixels for the selected region, run OCR, copy the recognized
    /// text to the clipboard, and surface a haptic cue. Used by the Phase 3
    /// OCR hotkey path.
    func runOCR(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.performOCR(displayID: displayID, screen: screen, rect: rect)
        }
    }

    private func performOCR(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) async {
        do {
            let captured = try await captureEngine.capture(
                displayID: displayID,
                rectInDisplayPoints: rect,
                screen: screen
            )
            let text = try await ocrEngine.recognizeText(in: captured.cgImage)
            ClipboardSink.copyText(text)
            ocrHistory.append(text: text)
            // Subtle haptic — replaces the popup the blueprint explicitly
            // calls out as a non-goal.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            ToastPresenter.show("Text copied")
        } catch {
            onError?(error)
        }
    }

    /// Snapshot of the most recently captured region, used for last-region
    /// recall. We keep `displayID` + `screenFrame` so we can find the same
    /// `NSScreen` even if the screens list reordered between captures.
    struct LastRegion: Sendable, Equatable {
        let displayID: CGDirectDisplayID
        let screenFrame: CGRect
        let rect: CGRect
    }

    func completeCapture(
        displayID: CGDirectDisplayID,
        screen: NSScreen,
        rect: CGRect,
        windowTitle: String? = nil,
        appName: String? = nil
    ) {
        let delay = preferences.captureDelaySeconds
        // Tiny delay so the overlay window finishes tearing down before we
        // ask SCK for pixels — without it the overlay would land in the shot.
        Task { @MainActor [weak self] in
            if delay > 0 {
                // Self-timer: countdown toasts, then shoot. The toast panel
                // is excluded from captures via sharingType.
                for remaining in stride(from: delay, through: 1, by: -1) {
                    ToastPresenter.show("Capturing in \(remaining)…", systemImage: "timer")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                ToastPresenter.dismiss()
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.storeCapture(
                displayID: displayID,
                screen: screen,
                rect: rect,
                windowTitle: windowTitle,
                appName: appName
            )
        }
    }

    /// Capture pixels for the selected region and read any barcode in them —
    /// payload goes to the clipboard, mirroring the OCR flow.
    func runQRScan(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self else { return }
            do {
                let captured = try await self.captureEngine.capture(
                    displayID: displayID,
                    rectInDisplayPoints: rect,
                    screen: screen
                )
                let payload = try QRCodeScanner.payload(in: captured.cgImage)
                ClipboardSink.copyText(payload)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                ToastPresenter.show("QR code copied")
            } catch {
                self.onError?(error)
            }
        }
    }

    /// Capture a single on-screen window via SCK's
    /// `SCContentFilter(desktopIndependentWindow:)`. Different code path from
    /// `completeCapture` because the engine call is window-scoped, not
    /// display-rect-scoped — overlapping content is excluded.
    func captureWindow(scWindowID: CGWindowID, displayID: CGDirectDisplayID, windowTitle: String?, appName: String?) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.storeWindowCapture(
                scWindowID: scWindowID,
                displayID: displayID,
                windowTitle: windowTitle,
                appName: appName
            )
        }
    }

    private func storeWindowCapture(
        scWindowID: CGWindowID,
        displayID: CGDirectDisplayID,
        windowTitle: String?,
        appName: String?
    ) async {
        do {
            let captured = try await captureEngine.captureWindow(scWindowID: scWindowID)

            captureSequence &+= 1
            let format = preferences.captureFormat
            let encoded = captured.encode(as: format) ?? captured.pngData

            let suggestedFilename = CaptureFilenameTemplate.expand(
                template: preferences.captureFilenameTemplate,
                date: Date(),
                appName: appName,
                windowTitle: windowTitle,
                pixelSize: captured.pixelSize,
                sequence: captureSequence,
                fileExtension: format.fileExtension
            )

            if preferences.copyToClipboardOnCapture {
                ClipboardSink.copy(data: encoded, format: format)
            }

            if preferences.saveToDiskOnCapture {
                let subfolder = SmartFolderRouter.subfolder(
                    forAppName: appName,
                    rules: preferences.smartFolderRules
                )
                _ = try captureStore.addCapture(
                    pngData: encoded,
                    pixelSize: captured.pixelSize,
                    displayID: displayID,
                    fileExtension: format.fileExtension,
                    suggestedFilename: suggestedFilename,
                    subfolder: subfolder
                )
                onCaptureStored?()
            }
            // Don't update lastRegion for window captures — recall is for
            // user-drawn rects.
        } catch {
            onError?(error)
        }
    }

    func captureLastRegion() {
        guard let last = lastRegion else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame == last.screenFrame }) ?? NSScreen.main else {
            return
        }
        guard let displayID = screen.sniprDisplayID else { return }
        completeCapture(displayID: displayID, screen: screen, rect: last.rect)
    }

    var hasLastRegion: Bool { lastRegion != nil }

    func storeCapture(
        displayID: CGDirectDisplayID,
        screen: NSScreen,
        rect: CGRect,
        windowTitle: String? = nil,
        appName: String? = nil
    ) async {
        do {
            let captured = try await captureEngine.capture(
                displayID: displayID,
                rectInDisplayPoints: rect,
                screen: screen
            )

            captureSequence &+= 1
            let format = preferences.captureFormat
            let encoded = captured.encode(as: format) ?? captured.pngData

            let suggestedFilename = CaptureFilenameTemplate.expand(
                template: preferences.captureFilenameTemplate,
                date: Date(),
                appName: appName,
                windowTitle: windowTitle,
                pixelSize: captured.pixelSize,
                sequence: captureSequence,
                fileExtension: format.fileExtension
            )

            if preferences.copyToClipboardOnCapture {
                ClipboardSink.copy(data: encoded, format: format)
            }

            if preferences.saveToDiskOnCapture {
                let subfolder = SmartFolderRouter.subfolder(
                    forAppName: appName,
                    rules: preferences.smartFolderRules
                )
                _ = try captureStore.addCapture(
                    pngData: encoded,
                    pixelSize: captured.pixelSize,
                    displayID: displayID,
                    fileExtension: format.fileExtension,
                    suggestedFilename: suggestedFilename,
                    subfolder: subfolder
                )
                onCaptureStored?()
            }

            lastRegion = LastRegion(
                displayID: displayID,
                screenFrame: screen.frame,
                rect: rect
            )
        } catch {
            onError?(error)
        }
    }

    func ensureScreenRecordingAccess() -> Bool {
        if PermissionService.hasScreenRecordingAccess || PermissionService.requestScreenRecordingAccess() {
            return true
        }

        // The system prompt from CGRequestScreenCaptureAccess only ever shows
        // once per install; every later denial lands here. Explain what to do
        // instead of silently bouncing the user into System Settings.
        let alert = NSAlert()
        alert.messageText = "Snipr needs Screen Recording permission"
        alert.informativeText = """
        Enable Snipr under System Settings → Privacy & Security → \
        Screen Recording, then relaunch Snipr — macOS applies the \
        permission on the next launch.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionService.openScreenRecordingSettings()
        }
        return false
    }
}
