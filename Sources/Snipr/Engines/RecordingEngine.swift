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
/// Phase 3 recording-time options. New options should default to off so
/// existing call sites compile cleanly and behavior stays unchanged for
/// callers that don't opt in.
struct RecordingOptions: Sendable {
    var capturesSystemAudio: Bool

    static let `default` = RecordingOptions(capturesSystemAudio: false)
}

@MainActor
protocol RecordingEngine: AnyObject {
    var isRecording: Bool { get }

    /// Fired when the stream dies without the user asking it to (display
    /// disconnect, window server restart). Gives the presenter a chance to
    /// tear down the HUD and salvage the partial file instead of showing
    /// "recording" forever.
    var onUnexpectedStop: ((Error) -> Void)? { get set }

    func start(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen,
        destinationURL: URL
    ) async throws

    /// Start recording with extra Phase 3 toggles (system audio). Default
    /// implementation forwards to the legacy entry point so engines that
    /// don't yet implement the options keep working.
    func start(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen,
        destinationURL: URL,
        options: RecordingOptions
    ) async throws

    func stop() async throws -> RecordedVideo

    func cancel()
}

extension RecordingEngine {
    func start(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen,
        destinationURL: URL,
        options: RecordingOptions
    ) async throws {
        try await start(
            displayID: displayID,
            rectInDisplayPoints: rectInDisplayPoints,
            screen: screen,
            destinationURL: destinationURL
        )
    }
}
