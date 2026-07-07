import XCTest
@testable import Snipr

@MainActor
final class WebcamBubbleTests: XCTestCase {
    func testBubbleSitsInsetInBottomLeftOfRegion() {
        let region = CGRect(x: 300, y: 200, width: 800, height: 600)
        let origin = WebcamBubblePresenter.bubbleOrigin(region: region, diameter: 160)
        XCTAssertEqual(origin, CGPoint(x: 320, y: 220))
    }

    func testTinyRegionCentersBubble() {
        let region = CGRect(x: 300, y: 200, width: 120, height: 120)
        let origin = WebcamBubblePresenter.bubbleOrigin(region: region, diameter: 160)
        XCTAssertEqual(origin, CGPoint(x: 280, y: 180))
    }
}
