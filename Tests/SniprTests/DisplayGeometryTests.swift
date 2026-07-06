import AppKit
import XCTest
@testable import Snipr

final class DisplayGeometryTests: XCTestCase {
    func testPixelRectScalesByBackingScaleFactor() throws {
        let screen = try XCTUnwrap(NSScreen.main, "requires a display")
        let displayID = try XCTUnwrap(screen.sniprDisplayID)
        let points = CGRect(x: 10, y: 20, width: 300, height: 200)

        let pixels = DisplayGeometry.pixelRect(
            forDisplayPointsRect: points,
            displayID: displayID,
            screen: screen
        )

        let scale = screen.backingScaleFactor
        XCTAssertEqual(pixels.width, (points.width * scale).rounded(), accuracy: 1)
        XCTAssertEqual(pixels.height, (points.height * scale).rounded(), accuracy: 1)
    }
}
