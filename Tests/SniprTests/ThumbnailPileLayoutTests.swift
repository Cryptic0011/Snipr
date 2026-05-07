import XCTest
@testable import Snipr

final class ThumbnailPileLayoutTests: XCTestCase {
    func testTopCardIsFlatAndUnshifted() {
        let layout = ThumbnailPileLayout.default
        let placement = layout.placement(forIndex: 0, totalCount: 4)
        XCTAssertEqual(placement.xOffset, 0, accuracy: 0.0001)
        XCTAssertEqual(placement.yOffset, 0, accuracy: 0.0001)
        XCTAssertEqual(placement.rotationDegrees, 0, accuracy: 0.0001)
        XCTAssertEqual(placement.scale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(placement.opacity, 1.0, accuracy: 0.0001)
    }

    func testRotationAlternatesPerIndex() {
        let layout = ThumbnailPileLayout.default
        let p1 = layout.placement(forIndex: 1, totalCount: 4)
        let p2 = layout.placement(forIndex: 2, totalCount: 4)
        let p3 = layout.placement(forIndex: 3, totalCount: 4)
        XCTAssertLessThan(p1.rotationDegrees, 0, "Index 1 should tilt counter-clockwise")
        XCTAssertGreaterThan(p2.rotationDegrees, 0, "Index 2 should tilt clockwise")
        XCTAssertLessThan(p3.rotationDegrees, 0, "Index 3 should tilt counter-clockwise again")
        XCTAssertEqual(abs(p1.rotationDegrees), layout.rotationDegrees, accuracy: 0.0001)
    }

    func testRotationStaysWithinBlueprintBand() {
        // Blueprint asks for 0.5°-1.5° magnitude on tilted cards.
        let layout = ThumbnailPileLayout.default
        for index in 1..<ThumbnailPileLayout.maxVisibleCards {
            let placement = layout.placement(forIndex: index, totalCount: 6)
            let mag = abs(placement.rotationDegrees)
            XCTAssertGreaterThanOrEqual(mag, 0.5, "Index \(index) tilt too small")
            XCTAssertLessThanOrEqual(mag, 1.5, "Index \(index) tilt too large")
        }
    }

    func testVerticalOffsetWithinBlueprintBand() {
        // Blueprint asks for 3–5 px offset.
        let layout = ThumbnailPileLayout.default
        XCTAssertGreaterThanOrEqual(layout.verticalOffset, 3)
        XCTAssertLessThanOrEqual(layout.verticalOffset, 5)
    }

    func testVerticalOffsetGrowsWithDepth() {
        let layout = ThumbnailPileLayout.default
        let p0 = layout.placement(forIndex: 0, totalCount: 6)
        let p1 = layout.placement(forIndex: 1, totalCount: 6)
        let p2 = layout.placement(forIndex: 2, totalCount: 6)
        XCTAssertLessThan(p0.yOffset, p1.yOffset)
        XCTAssertLessThan(p1.yOffset, p2.yOffset)
    }

    func testZIndexOrdersTopCardFirst() {
        let layout = ThumbnailPileLayout.default
        let p0 = layout.placement(forIndex: 0, totalCount: 6)
        let p1 = layout.placement(forIndex: 1, totalCount: 6)
        XCTAssertGreaterThan(p0.zIndex, p1.zIndex)
    }

    func testVisibleCardCountIsCappedAtSix() {
        XCTAssertEqual(ThumbnailPileLayout.visibleCardCount(forTotal: 0), 0)
        XCTAssertEqual(ThumbnailPileLayout.visibleCardCount(forTotal: 3), 3)
        XCTAssertEqual(ThumbnailPileLayout.visibleCardCount(forTotal: 6), 6)
        XCTAssertEqual(ThumbnailPileLayout.visibleCardCount(forTotal: 14), 6)
    }

    func testIndexBeyondMaxClampsToBottomLayer() {
        let layout = ThumbnailPileLayout.default
        let last = layout.placement(forIndex: ThumbnailPileLayout.maxVisibleCards - 1, totalCount: 12)
        let beyond = layout.placement(forIndex: 11, totalCount: 12)
        XCTAssertEqual(last.yOffset, beyond.yOffset, accuracy: 0.0001)
        XCTAssertEqual(last.rotationDegrees, beyond.rotationDegrees, accuracy: 0.0001)
    }
}
