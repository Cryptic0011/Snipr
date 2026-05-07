import AppKit
import XCTest
@testable import Snipr

final class CaptureFlowPresenterTests: XCTestCase {
    /// Happy path: `storeCapture` runs the engine, persists through the
    /// store, fires `onCaptureStored`, and remembers the last region for
    /// recall.
    @MainActor
    func testStoreCaptureWritesItemAndRemembersLastRegion() async throws {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = CaptureStore(rootDirectory: temp)
        let preferences = SniprPreferences(defaults: makeIsolatedDefaults())
        preferences.copyToClipboardOnCapture = false // avoid touching general pasteboard

        let engine = FakeCaptureEngine()
        let presenter = CaptureFlowPresenter(
            captureStore: store,
            preferences: preferences,
            captureEngine: engine
        )

        let storedExpectation = expectation(description: "onCaptureStored")
        presenter.onCaptureStored = { storedExpectation.fulfill() }

        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = screen.sniprDisplayID ?? CGMainDisplayID()
        let rect = CGRect(x: 10, y: 20, width: 200, height: 100)

        await presenter.storeCapture(displayID: displayID, screen: screen, rect: rect)

        await fulfillment(of: [storedExpectation], timeout: 1)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(engine.invocations.count, 1)
        XCTAssertEqual(presenter.lastRegion?.rect, rect)
        XCTAssertEqual(presenter.lastRegion?.screenFrame, screen.frame)
    }

    /// Clipboard-only mode (`saveToDiskOnCapture == false`) skips the store
    /// entirely. The presenter still updates `lastRegion`.
    @MainActor
    func testClipboardOnlyModeDoesNotPersist() async throws {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = CaptureStore(rootDirectory: temp)
        let preferences = SniprPreferences(defaults: makeIsolatedDefaults())
        preferences.copyToClipboardOnCapture = false
        preferences.saveToDiskOnCapture = false

        let presenter = CaptureFlowPresenter(
            captureStore: store,
            preferences: preferences,
            captureEngine: FakeCaptureEngine()
        )

        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = screen.sniprDisplayID ?? CGMainDisplayID()
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

        await presenter.storeCapture(displayID: displayID, screen: screen, rect: rect)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNotNil(presenter.lastRegion)
    }

    /// Errors from the engine bubble through `onError` and don't crash; the
    /// store stays empty.
    @MainActor
    func testEngineErrorTriggersOnErrorCallback() async throws {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = CaptureStore(rootDirectory: temp)
        let preferences = SniprPreferences(defaults: makeIsolatedDefaults())
        preferences.copyToClipboardOnCapture = false

        let engine = FakeCaptureEngine()
        engine.stubbedResult = .failure(ScreenCaptureError.imageCreationFailed)

        let presenter = CaptureFlowPresenter(
            captureStore: store,
            preferences: preferences,
            captureEngine: engine
        )

        let errorExpectation = expectation(description: "onError")
        presenter.onError = { _ in errorExpectation.fulfill() }

        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = screen.sniprDisplayID ?? CGMainDisplayID()
        await presenter.storeCapture(displayID: displayID, screen: screen, rect: CGRect(x: 0, y: 0, width: 50, height: 50))

        await fulfillment(of: [errorExpectation], timeout: 1)
        XCTAssertTrue(store.items.isEmpty)
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "CaptureFlowPresenterTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CaptureFlowPresenterTests-\(UUID().uuidString)")!
    }
}
