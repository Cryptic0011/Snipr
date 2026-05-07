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

    /// Last completed capture region; remembered in memory so the user can
    /// repeat it via `captureLastRegion` without re-dragging.
    private(set) var lastRegion: LastRegion?

    /// Monotonic sequence used by filename templates (`{seq}` token).
    private var captureSequence: Int = 0

    var onError: ((Error) -> Void)?
    var onCaptureStored: (() -> Void)?

    init(captureStore: CaptureStore, preferences: SniprPreferences, captureEngine: CaptureEngine) {
        self.captureStore = captureStore
        self.preferences = preferences
        self.captureEngine = captureEngine
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
        // Tiny delay so the overlay window finishes tearing down before we
        // ask SCK for pixels — without it the overlay would land in the shot.
        Task { @MainActor [weak self] in
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
                _ = try captureStore.addCapture(
                    pngData: encoded,
                    pixelSize: captured.pixelSize,
                    displayID: displayID,
                    fileExtension: format.fileExtension,
                    suggestedFilename: suggestedFilename
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
                _ = try captureStore.addCapture(
                    pngData: encoded,
                    pixelSize: captured.pixelSize,
                    displayID: displayID,
                    fileExtension: format.fileExtension,
                    suggestedFilename: suggestedFilename
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
        PermissionService.openScreenRecordingSettings()
        return false
    }
}
