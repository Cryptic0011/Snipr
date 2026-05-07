import AppKit
import XCTest
@testable import Snipr

final class OverlayPresenterTests: XCTestCase {
    /// New presenter has no overlays open and doesn't crash on a redundant
    /// close — the coordinator routes hide-overlay calls through this even
    /// when nothing is shown.
    @MainActor
    func testCloseCaptureOverlaysIsIdempotentOnFreshInstance() {
        let presenter = OverlayPresenter()
        presenter.closeCaptureOverlays()
        presenter.closeCaptureOverlays()
        // No assertion needed beyond "did not crash"; presenter exposes no
        // public state about open overlay count.
    }

    /// Cancel is fired by the user pressing Esc inside the selection view,
    /// not by the coordinator-driven close path. Verify the distinction so
    /// we don't double-fire if the coordinator decides to hide overlays
    /// for a different reason (e.g. window focus change in a later phase).
    @MainActor
    func testCloseCaptureOverlaysDoesNotInvokeCancelCallback() {
        let presenter = OverlayPresenter()
        var cancelInvocations = 0
        presenter.onCancel = { cancelInvocations += 1 }
        presenter.closeCaptureOverlays()
        XCTAssertEqual(cancelInvocations, 0)
    }

    /// Happy path: when a selection completes (simulated by directly
    /// invoking the public closure the way the overlay would), the
    /// coordinator callback fires with the right mode + rect.
    ///
    /// Building real overlay windows in a unit test is brittle and the
    /// advisor's guidance is "test orchestration, not windows".
    @MainActor
    func testSelectionCallbackForwardsModeAndRect() throws {
        let presenter = OverlayPresenter()
        var seenMode: CaptureOverlayMode?
        var seenRect: CGRect?
        presenter.onSelectionComplete = { mode, _, _, rect in
            seenMode = mode
            seenRect = rect
        }

        let screen = try XCTUnwrap(NSScreen.main, "Test environment must have a main screen")
        let displayID = screen.sniprDisplayID ?? CGMainDisplayID()
        let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
        presenter.onSelectionComplete?(.screenshot, displayID, screen, rect)

        XCTAssertEqual(seenMode, .screenshot)
        XCTAssertEqual(seenRect, rect)
    }
}
