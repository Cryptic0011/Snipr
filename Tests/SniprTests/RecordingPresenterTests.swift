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
    /// A stream that dies without the user asking (display disconnect) must
    /// surface the error and run the stop path so the HUD comes down and the
    /// partial file is finalized — not stay "recording" forever.
    func testUnexpectedStreamStopSurfacesErrorAndStops() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store)

        var receivedError: Error?
        presenter.onError = { receivedError = $0 }

        engine.isRecording = true
        engine.onUnexpectedStop?(ScreenRecordingError.recordingFailed)

        try await waitFor(timeout: 2) { engine.stopCalls == 1 }
        XCTAssertNotNil(receivedError)
    }

    func testCancelCallsEngineImmediately() {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store)

        presenter.cancel()
        XCTAssertEqual(engine.cancelCalls, 1)
    }

    /// Custom-cursor pref on → the engine is asked to hide the system
    /// cursor; off → it isn't.
    func testCustomCursorPrefHidesSystemCursor() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        // Isolated defaults, same pattern as SniprPreferencesTests.makeDefaults():
        let suiteName = "RecordingPresenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = SniprPreferences(defaults: defaults)
        prefs.recordingCustomCursor = true
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store, preferences: prefs)

        let screen = try XCTUnwrap(NSScreen.main)
        presenter.start(displayID: CGMainDisplayID(), screen: screen, rect: CGRect(x: 0, y: 0, width: 320, height: 240))
        try await waitFor(timeout: 2) { engine.startCalls.count == 1 }
        XCTAssertEqual(engine.lastOptions?.hidesSystemCursor, true)

        presenter.cancel()
    }

    /// With the pref off, options say so and no bake runs — the stored file
    /// is byte-identical to what the engine produced.
    func testNoCursorPrefLeavesRecordingUntouched() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let suiteName = "RecordingPresenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = SniprPreferences(defaults: defaults)
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store, preferences: prefs)

        let finished = expectation(description: "finished")
        presenter.onRecordingFinished = { finished.fulfill() }

        let screen = try XCTUnwrap(NSScreen.main)
        presenter.start(displayID: CGMainDisplayID(), screen: screen, rect: CGRect(x: 0, y: 0, width: 320, height: 240))
        try await waitFor(timeout: 2) { engine.startCalls.count == 1 }
        XCTAssertEqual(engine.lastOptions?.hidesSystemCursor, false)

        presenter.stop()
        await fulfillment(of: [finished], timeout: 2)
        // FakeRecordingEngine writes Data([0x00]); an accidental bake attempt
        // on a bogus file would fail and surface an error instead.
        let url = try XCTUnwrap(store.items.first?.fileURL)
        XCTAssertEqual(try Data(contentsOf: url), Data([0x00]))
    }

    /// Bake failure (the fake's file isn't a real video) falls back to the
    /// raw recording: item still lands in the store, error is surfaced.
    func testFailedCursorBakeKeepsRawRecording() async throws {
        let store = CaptureStore(rootDirectory: tempRoot)
        let engine = FakeRecordingEngine()
        let suiteName = "RecordingPresenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = SniprPreferences(defaults: defaults)
        prefs.recordingCustomCursor = true
        let presenter = RecordingPresenter(recordingEngine: engine, captureStore: store, preferences: prefs)

        let finished = expectation(description: "finished")
        presenter.onRecordingFinished = { finished.fulfill() }
        var surfacedError: Error?
        presenter.onError = { surfacedError = $0 }

        let screen = try XCTUnwrap(NSScreen.main)
        presenter.start(displayID: CGMainDisplayID(), screen: screen, rect: CGRect(x: 0, y: 0, width: 320, height: 240))
        try await waitFor(timeout: 2) { engine.startCalls.count == 1 }

        presenter.stop()
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertEqual(store.items.count, 1, "raw recording must survive a failed bake")
        XCTAssertNotNil(surfacedError, "bake failure should be reported")
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
