import AppKit
import XCTest
@testable import Snipr

final class ColorPickerOverlayViewTests: XCTestCase {
    @MainActor
    func testMouseExitHidesColorPickerPreviewReadouts() throws {
        let view = ColorPickerOverlayView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let loupe = try XCTUnwrap(view.subviews.compactMap { $0 as? MagnifierLoupeView }.first)
        let label = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)

        loupe.isHidden = false
        label.isHidden = false

        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
        view.mouseExited(with: event)

        XCTAssertTrue(loupe.isHidden)
        XCTAssertTrue(label.isHidden)
    }
}
