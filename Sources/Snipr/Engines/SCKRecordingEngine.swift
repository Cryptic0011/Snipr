import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Default `RecordingEngine` powered by `SCStream` + `AVAssetWriter`. Audio
/// is intentionally out of scope for Phase 0 and is added in Phase 3.
///
/// The class is `@MainActor`-isolated so it satisfies the main-actor
/// `RecordingEngine` protocol. SCK delivers sample buffers on its own queue,
/// so we use a private serial dispatch queue and a `@unchecked Sendable`
/// box for the writer state to bridge them onto the main actor.
///
/// reason: the `Box` is `@unchecked Sendable` because `AVAssetWriter` /
/// `AVAssetWriterInput` are `NSObject`-backed and not statically Sendable,
/// but we serialize all writer access through the recording queue, which is
/// the canonical pattern for this kind of CMSampleBuffer pump.
@MainActor
final class SCKRecordingEngine: NSObject, RecordingEngine {
    private let queue = DispatchQueue(label: "com.grayson.snipr.screen-recording")
    private let state = SCKRecordingState()
    private var stream: SCStream?
    private var pixelSize: CGSize = .zero
    private var destinationURL: URL?
    private var isStreamRunning = false
    private var streamOutputAdapter: SCKStreamOutputAdapter?

    var isRecording: Bool {
        isStreamRunning
    }

    func start(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen,
        destinationURL: URL
    ) async throws {
        guard stream == nil else {
            throw ScreenRecordingError.alreadyRecording
        }

        let pixelRect = DisplayGeometry.pixelRect(
            forDisplayPointsRect: rectInDisplayPoints,
            displayID: displayID,
            screen: screen
        )

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenRecordingError.displayNotFound
        }

        let width = max(2, Int(pixelRect.width.rounded()))
        let height = max(2, Int(pixelRect.height.rounded()))

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = pixelRect
        configuration.width = width
        configuration.height = height
        configuration.scalesToFit = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(writerInput) else {
            throw ScreenRecordingError.writerUnavailable
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw ScreenRecordingError.writerUnavailable
        }

        state.assignWriter(writer, input: writerInput)

        let adapter = SCKStreamOutputAdapter(state: state)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: adapter)
        try stream.addStreamOutput(adapter, type: .screen, sampleHandlerQueue: queue)

        self.streamOutputAdapter = adapter
        self.stream = stream
        self.pixelSize = CGSize(width: width, height: height)
        self.destinationURL = destinationURL

        do {
            try await stream.startCapture()
            isStreamRunning = true
        } catch {
            self.stream = nil
            self.streamOutputAdapter = nil
            self.destinationURL = nil
            self.pixelSize = .zero
            writerInput.markAsFinished()
            writer.cancelWriting()
            state.clearWriter()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    func stop() async throws -> RecordedVideo {
        guard let stream, let destinationURL else {
            throw ScreenRecordingError.notRecording
        }

        do {
            try await stream.stopCapture()
        } catch {
            // Stream might already be stopped; carry on to finalize the
            // writer rather than throwing — a recording usually still made
            // it to disk.
        }

        let pixelSize = self.pixelSize
        let video: RecordedVideo = try await withCheckedThrowingContinuation { continuation in
            queue.async { [state] in
                state.finishWriting(destinationURL: destinationURL, pixelSize: pixelSize, continuation: continuation)
            }
        }

        self.stream = nil
        self.streamOutputAdapter = nil
        self.destinationURL = nil
        self.pixelSize = .zero
        isStreamRunning = false
        return video
    }

    func cancel() {
        let url = destinationURL
        let stream = self.stream
        let state = self.state
        let queue = self.queue

        Task {
            try? await stream?.stopCapture()
            queue.async {
                state.cancelWriting()
            }
        }

        self.stream = nil
        self.streamOutputAdapter = nil
        self.destinationURL = nil
        self.pixelSize = .zero
        isStreamRunning = false

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Bridges SCK's nonisolated delegate callbacks into our serial queue.
private final class SCKStreamOutputAdapter: NSObject, SCStreamOutput, SCStreamDelegate {
    let state: SCKRecordingState

    init(state: SCKRecordingState) {
        self.state = state
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let attachment = attachments.first,
           let rawStatus = attachment[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }

        state.append(sampleBuffer: sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        state.failWithError(error)
    }
}

/// Owns the writer + presentation-time state. All methods are intended to
/// run on the recording queue (or, for `assignWriter` / `clearWriter`,
/// before/after streaming starts/ends). The class is `@unchecked Sendable`
/// because its only mutable state is touched serially.
///
/// reason: `AVAssetWriter` and `AVAssetWriterInput` aren't statically
/// `Sendable`, and SCK's delegate-driven CMSampleBuffer pump fundamentally
/// needs us to bridge them across actor boundaries. Serialised through
/// `recording-queue`, this is the standard pattern.
private final class SCKRecordingState: @unchecked Sendable {
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var firstPresentationTime: CMTime?
    private var lastPresentationTime: CMTime?
    private var finishContinuation: CheckedContinuation<RecordedVideo, Error>?

    func assignWriter(_ writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.writer = writer
        self.writerInput = input
        self.firstPresentationTime = nil
        self.lastPresentationTime = nil
    }

    func clearWriter() {
        writer = nil
        writerInput = nil
        firstPresentationTime = nil
        lastPresentationTime = nil
    }

    func append(sampleBuffer: CMSampleBuffer) {
        guard let writer, let writerInput else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if firstPresentationTime == nil {
            firstPresentationTime = presentationTime
            writer.startSession(atSourceTime: presentationTime)
        }

        guard writer.status == .writing, writerInput.isReadyForMoreMediaData else {
            return
        }

        if writerInput.append(sampleBuffer) {
            lastPresentationTime = presentationTime
        }
    }

    func finishWriting(destinationURL: URL, pixelSize: CGSize, continuation: CheckedContinuation<RecordedVideo, Error>) {
        guard let writer, let writerInput else {
            continuation.resume(throwing: ScreenRecordingError.recordingFailed)
            clearWriter()
            return
        }

        finishContinuation = continuation
        writerInput.markAsFinished()

        let firstTime = firstPresentationTime
        let lastTime = lastPresentationTime
        writer.finishWriting { [weak self] in
            // Look the writer back up through `self` so the @Sendable
            // callback closure doesn't capture an `AVAssetWriter` directly,
            // which Swift 6 strict concurrency rejects.
            self?.handleFinish(destinationURL: destinationURL, pixelSize: pixelSize, firstTime: firstTime, lastTime: lastTime)
        }
    }

    private func handleFinish(destinationURL: URL, pixelSize: CGSize, firstTime: CMTime?, lastTime: CMTime?) {
        guard let writer else {
            return
        }

        let duration: TimeInterval
        if let firstTime, let lastTime {
            duration = max(0, CMTimeGetSeconds(lastTime - firstTime))
        } else {
            duration = 0
        }

        let didSucceed = writer.status == .completed && FileManager.default.fileExists(atPath: destinationURL.path)
        let writerError = writer.error
        let pending = finishContinuation
        finishContinuation = nil
        clearWriter()

        if didSucceed {
            pending?.resume(returning: RecordedVideo(fileURL: destinationURL, pixelSize: pixelSize, duration: duration))
        } else {
            pending?.resume(throwing: writerError ?? ScreenRecordingError.recordingFailed)
        }
    }

    func cancelWriting() {
        writerInput?.markAsFinished()
        writer?.cancelWriting()
        if let pending = finishContinuation {
            finishContinuation = nil
            pending.resume(throwing: ScreenRecordingError.recordingFailed)
        }
        clearWriter()
    }

    func failWithError(_ error: Error) {
        guard let pending = finishContinuation else {
            return
        }
        finishContinuation = nil
        clearWriter()
        pending.resume(throwing: error)
    }
}
