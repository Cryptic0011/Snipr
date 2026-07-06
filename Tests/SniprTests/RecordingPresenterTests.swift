import AppKit
import XCTest
@testable import Snipr

@MainActor
final class RecordingPresenterTests: XCTestCase {
    private nonisolated(unsafe) var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    /// Happy path: starting a recording calls the engine with the right
    /// args; stopping it lands a `CaptureItem` of media-type `.video` in
    /// the store and fires `onRecordingFinished` so the coordinator can
    /// reveal the stack.
    func testStartThenStopAddsRecordingToStore() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store)

        let finishedExpectation = expectation(description: "onRecordingFinished fires")
        presenter.onRecordingFinished = { finishedExpectation.fulfill() }
        presenter.onError = { error in
            XCTFail("Unexpected error: \(error)")
        }

        let screen = try XCTUnwrap(NSScreen.main, "Test environment must have a main screen")
        let displayID = screen.sniprDisplayID ?? CGMainDisplayID()
        let rect = CGRect(x: 0, y: 0, width: 320, height: 240)

        presenter.start(displayID: displayID, screen: screen, rect: rect)

        // `start` defers via Task.sleep(120ms); poll briefly for the engine
        // to have been invoked rather than hard-sleeping.
        try await waitFor(timeout: 2) { engine.startCalls.count == 1 }

        XCTAssertEqual(engine.startCalls.first?.displayID, displayID)
        XCTAssertEqual(engine.startCalls.first?.rectInDisplayPoints, rect)

        presenter.stop()

        await fulfillment(of: [finishedExpectation], timeout: 2)
        XCTAssertEqual(engine.stopCalls, 1)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.mediaType, .video)
    }

    /// `start()` is gated by `engine.isRecording`. If the engine claims it's
    /// already recording, the presenter must not try to start again.
    func testStartGatedByIsRecording() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        engine.isRecording = true
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store)

        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = screen.sniprDisplayID ?? CGMainDisplayID()
        presenter.start(displayID: displayID, screen: screen, rect: .zero)

        // Wait briefly to give the deferred Task a chance to run if it
        // mistakenly were going to.
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(engine.startCalls.count, 0)
    }

    /// `cancel()` is synchronous and must short-circuit the engine even
    /// before any frames are written — it's called when the user hits the X
    /// in the recording HUD.
    func testCancelCallsEngineImmediately() {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store)

        presenter.cancel()
        XCTAssertEqual(engine.cancelCalls, 1)
    }

    private func waitFor(timeout seconds: TimeInterval, condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met within \(seconds)s")
    }
}
