import AppKit
import XCTest
@testable import Snipr

final class WindowPickerOverlayViewTests: XCTestCase {
    @MainActor
    func testExcludedOverlayWindowDoesNotWinWindowPick() throws {
        let view = WindowPickerNSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let overlay = WindowPickerNSView.WindowEntry(
            frame: view.bounds,
            scWindowID: 100,
            title: "Snipr Overlay",
            appName: "Snipr"
        )
        let appWindow = WindowPickerNSView.WindowEntry(
            frame: CGRect(x: 40, y: 30, width: 120, height: 90),
            scWindowID: 200,
            title: "Document",
            appName: "Notes"
        )

        view.setWindows([overlay, appWindow], excludingWindowIDs: [overlay.scWindowID])

        XCTAssertEqual(
            view.windowEntry(at: CGPoint(x: 60, y: 50))?.scWindowID,
            appWindow.scWindowID
        )
    }

    @MainActor
    func testFullScreenWindowCanBePickedWhenItIsNotExcluded() throws {
        let view = WindowPickerNSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let fullScreenApp = WindowPickerNSView.WindowEntry(
            frame: view.bounds,
            scWindowID: 300,
            title: "Presentation",
            appName: "Keynote"
        )

        view.setWindows([fullScreenApp], excludingWindowIDs: [])

        XCTAssertEqual(
            view.windowEntry(at: CGPoint(x: 60, y: 50))?.scWindowID,
            fullScreenApp.scWindowID
        )
    }

    @MainActor
    func testDockWindowDoesNotWinWindowPick() throws {
        let view = WindowPickerNSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let dock = WindowPickerNSView.WindowEntry(
            frame: view.bounds,
            scWindowID: 500,
            title: nil,
            appName: "Dock"
        )
        let appWindow = WindowPickerNSView.WindowEntry(
            frame: CGRect(x: 40, y: 30, width: 120, height: 90),
            scWindowID: 600,
            title: "Document",
            appName: "Notes"
        )

        view.setWindows([dock, appWindow])

        XCTAssertEqual(
            view.windowEntry(at: CGPoint(x: 60, y: 50))?.scWindowID,
            appWindow.scWindowID
        )
    }

    @MainActor
    func testMouseExitClearsStaleWindowHighlight() throws {
        let view = WindowPickerNSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let appWindow = WindowPickerNSView.WindowEntry(
            frame: CGRect(x: 40, y: 30, width: 120, height: 90),
            scWindowID: 400,
            title: "Document",
            appName: "Notes"
        )

        view.setWindows([appWindow])
        view.updateHover(at: CGPoint(x: 60, y: 50))
        XCTAssertEqual(view.highlightedWindowID, appWindow.scWindowID)

        view.clearHover()

        XCTAssertNil(view.highlightedWindowID)
    }

    @MainActor
    func testWindowPickerLabelUsesPlainProcessAndTitle() {
        let entry = WindowPickerNSView.WindowEntry(
            frame: .zero,
            scWindowID: 700,
            title: "Quarterly Report",
            appName: "Numbers"
        )

        XCTAssertEqual(WindowPickerNSView.labelText(for: entry), "Numbers - Quarterly Report")
    }
}
