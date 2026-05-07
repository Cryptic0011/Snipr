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
    let captureEngine: CaptureEngine

    var onError: ((Error) -> Void)?
    var onCaptureStored: (() -> Void)?

    init(captureStore: CaptureStore, captureEngine: CaptureEngine) {
        self.captureStore = captureStore
        self.captureEngine = captureEngine
    }

    func completeCapture(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        // Tiny delay so the overlay window finishes tearing down before we
        // ask SCK for pixels — without it the overlay would land in the shot.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.storeCapture(displayID: displayID, screen: screen, rect: rect)
        }
    }

    func storeCapture(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) async {
        do {
            let captured = try await captureEngine.capture(
                displayID: displayID,
                rectInDisplayPoints: rect,
                screen: screen
            )
            _ = try captureStore.addCapture(
                pngData: captured.pngData,
                pixelSize: captured.pixelSize,
                displayID: displayID
            )
            onCaptureStored?()
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
