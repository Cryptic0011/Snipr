import AppKit
import CoreGraphics
import Foundation

/// Recorded `.mov` artifact produced by a `RecordingEngine`.
struct RecordedVideo: Sendable {
    let fileURL: URL
    let pixelSize: CGSize
    let duration: TimeInterval
}

enum ScreenRecordingError: LocalizedError {
    case alreadyRecording
    case displayInputUnavailable
    case writerUnavailable
    case notRecording
    case recordingFailed
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Snipr is already recording."
        case .displayInputUnavailable:
            "Snipr could not create a screen recording input for this display."
        case .writerUnavailable:
            "Snipr could not create the recording file."
        case .notRecording:
            "Snipr is not currently recording."
        case .recordingFailed:
            "Snipr could not finish the screen recording."
        case .displayNotFound:
            "Snipr could not find the display being recorded."
        }
    }
}

/// Pluggable screen-recording surface. The default ScreenCaptureKit engine is
/// injected by `SniprAppModel`; tests substitute a fake to assert recording
/// orchestration without driving SCStream.
///
/// `@MainActor` for the same reason as `CaptureEngine`: callers hand us an
/// `NSScreen`. The default SCK implementation hops onto its own queue inside.
@MainActor
protocol RecordingEngine: AnyObject {
    var isRecording: Bool { get }

    func start(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen,
        destinationURL: URL
    ) async throws

    func stop() async throws -> RecordedVideo

    func cancel()
}
