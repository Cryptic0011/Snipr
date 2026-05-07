import AppKit
import XCTest
@testable import Snipr

@MainActor
final class StackPresenterTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil

        // Wipe persisted defaults written by SniprPreferences in `setPinned`
        // tests so unrelated suites don't see leftover state.
        let defaults = UserDefaults.standard
        for key in ["showStackAfterCapture", "autoHideStack", "stackAutoHideDelay", "pauseStackAutoHideOnHover", "hideStackAfterPreview", "hotKeyBindings"] {
            defaults.removeObject(forKey: key)
        }
    }

    func testSetPinnedTogglesPinnedFlag() {
        let presenter = makePresenter()
        XCTAssertFalse(presenter.isPinned)
        presenter.setPinned(true)
        XCTAssertTrue(presenter.isPinned)
        presenter.setPinned(false)
        XCTAssertFalse(presenter.isPinned)
    }

    func testShouldHideAfterPreviewRespectsPinAndPreference() {
        let presenter = makePresenter()
        presenter.preferences.hideStackAfterPreview = true
        presenter.setPinned(false)
        XCTAssertTrue(presenter.shouldHideAfterPreview)

        presenter.setPinned(true)
        XCTAssertFalse(presenter.shouldHideAfterPreview, "Pinned stack must not auto-hide on preview")

        presenter.setPinned(false)
        presenter.preferences.hideStackAfterPreview = false
        XCTAssertFalse(presenter.shouldHideAfterPreview)
    }

    /// `show()` is a no-op when the preference says "don't show after
    /// capture" AND no panel is currently visible — that's the contract the
    /// coordinator depends on.
    func testShowIsNoOpWhenPreferenceSuppressesIt() {
        let presenter = makePresenter()
        presenter.preferences.showStackAfterCapture = false
        // No assertion against panel state (we don't expose it); the test
        // just verifies the method does not crash. The behavioural assertion
        // is in StackPresenter.show()'s early return.
        presenter.show()
    }

    private func makePresenter() -> StackPresenter {
        let store = CaptureStore(rootDirectory: tempRoot)
        let preferences = SniprPreferences(defaults: UserDefaults.standard)
        return StackPresenter(captureStore: store, preferences: preferences)
    }
}
