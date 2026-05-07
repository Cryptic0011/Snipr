import AppKit
import Observation
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
    private var activeMode: CaptureOverlayMode?
    var onSelectionComplete: ((CaptureOverlayMode, CGDirectDisplayID, NSScreen, CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init() {}

    func showCaptureOverlays(mode: CaptureOverlayMode) {
        closeCaptureOverlays()
        activeMode = mode

        for screen in NSScreen.screens {
            guard let displayID = screen.sniprDisplayID else {
                continue
            }

            let window = NSPanel(
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
            window.contentView = NSHostingView(
                rootView: CaptureOverlayView(
                    screen: screen,
                    onComplete: { [weak self] rect in
                        self?.completeSelection(displayID: displayID, screen: screen, rect: rect)
                    },
                    onCancel: { [weak self] in
                        self?.closeCaptureOverlays()
                        self?.onCancel?()
                    }
                )
            )

            overlayWindows.append(window)
            window.orderFrontRegardless()
        }
    }

    func closeCaptureOverlays() {
        overlayWindows.forEach { window in
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        activeMode = nil
    }

    private func completeSelection(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        guard let mode = activeMode else {
            return
        }

        closeCaptureOverlays()
        onSelectionComplete?(mode, displayID, screen, rect)
    }
}
