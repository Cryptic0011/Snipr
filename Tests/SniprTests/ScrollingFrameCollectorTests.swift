import CoreGraphics
import XCTest
@testable import Snipr

@MainActor
final class ScrollingFrameCollectorTests: XCTestCase {
    func testRetainsEveryThirdFrameUntilTheCap() {
        var retainedCount = 0
        var retainedIndices: [Int] = []
        for index in 0..<2000 where ScrollingFrameCollector.shouldRetainFrame(
            at: index, alreadyRetained: retainedCount, retainedBytes: 0
        ) {
            retainedIndices.append(index)
            retainedCount += 1
        }

        // ~10 fps out of the 30 fps source: every third delivered frame.
        XCTAssertEqual(retainedIndices.first, 0)
        XCTAssertEqual(retainedIndices[1], ScrollingFrameCollector.retainStride)
        // Buffer is bounded so a long scroll can't exhaust memory.
        XCTAssertEqual(retainedCount, ScrollingFrameCollector.maxRetainedFrames)
    }

    func testStopsRetainingOnceCapIsReached() {
        XCTAssertFalse(
            ScrollingFrameCollector.shouldRetainFrame(
                at: 0,
                alreadyRetained: ScrollingFrameCollector.maxRetainedFrames,
                retainedBytes: 0
            )
        )
    }

    func testStopsRetainingOnceByteBudgetIsSpent() {
        XCTAssertFalse(
            ScrollingFrameCollector.shouldRetainFrame(
                at: 0,
                alreadyRetained: 0,
                retainedBytes: ScrollingFrameCollector.maxRetainedBytes
            )
        )
    }
}
