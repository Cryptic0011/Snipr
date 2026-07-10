import CoreGraphics
import XCTest
@testable import Snipr

final class VideoCompositorTests: XCTestCase {
    func testEvenSizeRoundsUpToEven() {
        XCTAssertEqual(VideoCompositor.evenSize(CGSize(width: 641, height: 480)), CGSize(width: 642, height: 480))
        XCTAssertEqual(VideoCompositor.evenSize(CGSize(width: 640.4, height: 479.5)), CGSize(width: 642, height: 480))
        XCTAssertEqual(VideoCompositor.evenSize(CGSize(width: 2, height: 2)), CGSize(width: 2, height: 2))
    }

    func testCursorArrowPathIsNonEmptyAndAnchoredAtTip() {
        let path = VideoCompositor.cursorArrowPath(height: 24)
        XCTAssertFalse(path.isEmpty)
        let box = path.boundingBox
        // Tip at origin, arrow extends right/down in top-left-origin space.
        XCTAssertEqual(box.minX, 0, accuracy: 0.001)
        XCTAssertEqual(box.minY, 0, accuracy: 0.001)
        XCTAssertEqual(box.maxY, 24, accuracy: 0.5)
        XCTAssertGreaterThan(box.maxX, 10)
        // Scales linearly.
        XCTAssertEqual(VideoCompositor.cursorArrowPath(height: 48).boundingBox.maxY, 48, accuracy: 1)
    }
}
