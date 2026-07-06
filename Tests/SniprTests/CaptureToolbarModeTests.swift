import AppKit
import XCTest
@testable import Snipr

final class CaptureToolbarModeTests: XCTestCase {
    @MainActor
    func testToolbarModeIconsResolveToSystemSymbols() {
        for mode in CaptureToolbarMode.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: mode.systemImage, accessibilityDescription: nil),
                "\(mode.systemImage) should resolve for \(mode.title)"
            )
        }
    }
}
