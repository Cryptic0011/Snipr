import AppKit
import XCTest
@testable import Snipr

final class CaptureSelectionNSViewTests: XCTestCase {
    @MainActor
    func testSelectionViewAcceptsFirstMouse() {
        let view = CaptureSelectionNSView()
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    @MainActor
    func testSharedSelectionClipsAcrossAdjacentScreens() {
        let coordinator = CaptureOverlaySelectionCoordinator()
        coordinator.begin(at: CGPoint(x: 50, y: 20))
        coordinator.update(to: CGPoint(x: 170, y: 60))

        XCTAssertEqual(
            coordinator.selectionRect(inScreenFrame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            CGRect(x: 50, y: 40, width: 50, height: 40)
        )
        XCTAssertEqual(
            coordinator.selectionRect(inScreenFrame: CGRect(x: 100, y: 0, width: 100, height: 100)),
            CGRect(x: 0, y: 40, width: 70, height: 40)
        )
    }

    @MainActor
    func testSharedSelectionReturnsNilForScreensOutsideSelection() {
        let coordinator = CaptureOverlaySelectionCoordinator()
        coordinator.begin(at: CGPoint(x: 10, y: 10))
        coordinator.update(to: CGPoint(x: 30, y: 40))

        XCTAssertNil(coordinator.selectionRect(inScreenFrame: CGRect(x: 100, y: 0, width: 100, height: 100)))
    }

    @MainActor
    func testMouseExitHidesCapturePreviewReadouts() throws {
        let view = CaptureSelectionNSView()
        let loupe = try XCTUnwrap(view.subviews.compactMap { $0 as? MagnifierLoupeView }.first)
        let labels = view.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(labels.count, 2)

        loupe.isHidden = false
        labels.forEach { $0.isHidden = false }

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
        XCTAssertTrue(labels.allSatisfy(\.isHidden))
    }

    @MainActor
    func testMouseMoveActivatesPointerPreviewOwnership() throws {
        let view = CaptureSelectionNSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var activatedView: CaptureSelectionNSView?
        view.onPointerPreviewActivated = { activatedView = $0 }

        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: CGPoint(x: 20, y: 30),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
        view.mouseMoved(with: event)

        XCTAssertTrue(activatedView === view)
    }

    @MainActor
    func testMagnifierIsHiddenByDefault() throws {
        let view = CaptureSelectionNSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let loupe = try XCTUnwrap(view.subviews.compactMap { $0 as? MagnifierLoupeView }.first)

        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: CGPoint(x: 20, y: 30),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
        view.mouseMoved(with: event)

        XCTAssertTrue(loupe.isHidden)
    }
}
