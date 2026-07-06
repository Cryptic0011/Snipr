import AppKit
import Foundation
@testable import Snipr

/// Records the args passed to a `CaptureEngine.capture(...)` invocation so
/// presenter tests can assert orchestration without driving SCK.
@MainActor
final class FakeCaptureEngine: CaptureEngine {
    struct Invocation {
        let displayID: CGDirectDisplayID
        let rectInDisplayPoints: CGRect
        let screen: NSScreen
    }

    var invocations: [Invocation] = []
    var stubbedResult: Result<CapturedImage, Error> = .success(
        CapturedImage(cgImage: FakeCaptureEngine.makeCGImage(), pngData: Data([0x89]), pixelSize: CGSize(width: 8, height: 6))
    )

    static func makeCGImage(width: Int = 8, height: Int = 6) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    var windowInvocations: [CGWindowID] = []

    func capture(displayID: CGDirectDisplayID, rectInDisplayPoints: CGRect, screen: NSScreen) async throws -> CapturedImage {
        invocations.append(Invocation(displayID: displayID, rectInDisplayPoints: rectInDisplayPoints, screen: screen))
        return try stubbedResult.get()
    }

    func captureWindow(scWindowID: CGWindowID) async throws -> CapturedImage {
        windowInvocations.append(scWindowID)
        return try stubbedResult.get()
    }
}

/// Drives the `RecordingPresenter` lifecycle without touching SCStream.
@MainActor
final class FakeRecordingEngine: RecordingEngine {
    struct StartCall {
        let displayID: CGDirectDisplayID
        let rectInDisplayPoints: CGRect
        let screen: NSScreen
        let destinationURL: URL
    }

    var startCalls: [StartCall] = []
    var stopCalls = 0
    var cancelCalls = 0
    var isRecording = false
    var onUnexpectedStop: ((Error) -> Void)?
    var stubbedStartError: Error?
    var stubbedStopResult: Result<RecordedVideo, Error>?

    func start(displayID: CGDirectDisplayID, rectInDisplayPoints: CGRect, screen: NSScreen, destinationURL: URL) async throws {
        startCalls.append(StartCall(displayID: displayID, rectInDisplayPoints: rectInDisplayPoints, screen: screen, destinationURL: destinationURL))
        if let stubbedStartError {
            throw stubbedStartError
        }
        // Fabricate a tiny placeholder file so `addRecording` later sees a
        // file at that path; CaptureStore filters out items without a file
        // when re-loading.
        try? Data([0x00]).write(to: destinationURL)
        isRecording = true
    }

    func stop() async throws -> RecordedVideo {
        stopCalls += 1
        isRecording = false
        guard let stubbedStopResult else {
            // Default: pretend we wrote a 1080p file lasting 2s.
            let url = startCalls.last?.destinationURL ?? URL(fileURLWithPath: "/tmp/fake.mov")
            return RecordedVideo(fileURL: url, pixelSize: CGSize(width: 1920, height: 1080), duration: 2)
        }
        return try stubbedStopResult.get()
    }

    func cancel() {
        cancelCalls += 1
        isRecording = false
    }
}
