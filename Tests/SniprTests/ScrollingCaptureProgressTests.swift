import XCTest
@testable import Snipr

@MainActor
final class ScrollingCaptureProgressTests: XCTestCase {
    func testStartResetsCapturedPixelsAndRunningFlag() {
        let progress = ScrollingCaptureProgress()
        progress.update(capturedPixels: 1280)
        progress.start()
        XCTAssertEqual(progress.capturedPixels, 0)
        XCTAssertTrue(progress.isRunning)
    }

    func testUpdateMonotonicallyTracksMaximum() {
        let progress = ScrollingCaptureProgress()
        progress.start()
        progress.update(capturedPixels: 100)
        progress.update(capturedPixels: 250)
        // Out-of-order delivery shouldn't roll the count backwards.
        progress.update(capturedPixels: 200)
        XCTAssertEqual(progress.capturedPixels, 250)
    }

    func testFinishStopsRunningWithoutResettingPixels() {
        let progress = ScrollingCaptureProgress()
        progress.start()
        progress.update(capturedPixels: 480)
        progress.finish()
        XCTAssertFalse(progress.isRunning)
        XCTAssertEqual(progress.capturedPixels, 480)
    }

    func testDisplayTextRoundsDownToTen() {
        let progress = ScrollingCaptureProgress()
        progress.start()
        progress.update(capturedPixels: 1287)
        XCTAssertEqual(progress.displayText, "Scrolling capture · 1280 px")
    }
}
