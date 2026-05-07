import XCTest
@testable import Snipr

final class EdgeSnapTests: XCTestCase {
    func testSnapsToCandidateWithinThreshold() {
        let snapped = EdgeSnap.snapped(
            rect: CGRect(x: 95, y: 200, width: 200, height: 100),
            xEdges: [100, 400],
            yEdges: [200, 350]
        )
        // minX 95 → 100 (5 px snap, within 8 px threshold)
        XCTAssertEqual(snapped.minX, 100, accuracy: 0.0001)
        XCTAssertEqual(snapped.minY, 200, accuracy: 0.0001)
    }

    func testDoesNotSnapBeyondThreshold() {
        let snapped = EdgeSnap.snapped(
            rect: CGRect(x: 80, y: 200, width: 200, height: 100),
            xEdges: [100],
            yEdges: []
        )
        // 100 - 80 = 20 > 8 px threshold; no snap
        XCTAssertEqual(snapped.minX, 80, accuracy: 0.0001)
    }

    func testSnapsBothEdgesIndependently() {
        let snapped = EdgeSnap.snapped(
            rect: CGRect(x: 95, y: 200, width: 210, height: 100),
            xEdges: [100, 300],
            yEdges: []
        )
        XCTAssertEqual(snapped.minX, 100, accuracy: 0.0001)
        XCTAssertEqual(snapped.maxX, 300, accuracy: 0.0001)
    }

    func testEmptyCandidateListLeavesRectUntouched() {
        let original = CGRect(x: 12, y: 34, width: 56, height: 78)
        let snapped = EdgeSnap.snapped(rect: original, xEdges: [], yEdges: [])
        XCTAssertEqual(snapped, original)
    }
}
