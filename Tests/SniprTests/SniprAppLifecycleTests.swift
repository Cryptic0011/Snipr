import AppKit
import XCTest
@testable import Snipr

@MainActor
final class SniprAppLifecycleTests: XCTestCase {
    func testClosingLastWindowDoesNotTerminateMenuBarApp() {
        let delegate = SniprAppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
