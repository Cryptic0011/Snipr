import AppKit
@preconcurrency import AVFoundation
import CoreMedia

struct RecordedVideo {
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
        }
    }
}

final class ScreenRecordingService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.grayson.snipr.screen-recording")
    private var session: AVCaptureSession?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var destinationURL: URL?
    private var pixelSize: CGSize = .zero
    private var displayID: CGDirectDisplayID?
    private var firstPresentationTime: CMTime?
    private var lastPresentationTime: CMTime?
    private var finishContinuation: CheckedContinuation<RecordedVideo, Error>?

    var isRecording: Bool {
        session?.isRunning == true
    }

    func start(displayID: CGDirectDisplayID, rectInDisplayPoints: CGRect, screen: NSScreen, destinationURL: URL) throws {
        guard session == nil else {
            throw ScreenRecordingError.alreadyRecording
        }

        let displayBounds = CGDisplayBounds(displayID)
        let scaleX = displayBounds.width / screen.frame.width
        let scaleY = displayBounds.height / screen.frame.height
        let pixelRect = CGRect(
            x: rectInDisplayPoints.minX * scaleX,
            y: rectInDisplayPoints.minY * scaleY,
            width: rectInDisplayPoints.width * scaleX,
            height: rectInDisplayPoints.height * scaleY
        ).integral

        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let input = AVCaptureScreenInput(displayID: displayID) else {
            throw ScreenRecordingError.displayInputUnavailable
        }
        input.cropRect = pixelRect
        input.minFrameDuration = CMTime(value: 1, timescale: 30)
        input.capturesCursor = true
        input.capturesMouseClicks = true

        guard session.canAddInput(input) else {
            throw ScreenRecordingError.displayInputUnavailable
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw ScreenRecordingError.displayInputUnavailable
        }
        session.addOutput(output)

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let width = max(2, Int(pixelRect.width.rounded()))
        let height = max(2, Int(pixelRect.height.rounded()))
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

        self.session = session
        self.writer = writer
        self.writerInput = writerInput
        self.destinationURL = destinationURL
        self.pixelSize = CGSize(width: width, height: height)
        self.displayID = displayID
        firstPresentationTime = nil
        lastPresentationTime = nil

        guard writer.startWriting() else {
            reset()
            throw ScreenRecordingError.writerUnavailable
        }

        session.startRunning()
    }

    func stop() async throws -> RecordedVideo {
        guard session != nil, writer != nil, writerInput != nil, destinationURL != nil else {
            throw ScreenRecordingError.notRecording
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ScreenRecordingError.recordingFailed)
                    return
                }

                self.finishContinuation = continuation
                self.session?.stopRunning()
                self.writerInput?.markAsFinished()
                self.writer?.finishWriting { [weak self] in
                    self?.queue.async { [weak self] in
                        self?.finishRecording()
                    }
                }
            }
        }
    }

    func cancel() {
        let url = destinationURL
        session?.stopRunning()
        writerInput?.markAsFinished()
        writer?.cancelWriting()
        reset()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let writer, let writerInput, CMSampleBufferDataIsReady(sampleBuffer) else {
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

    private func finishRecording() {
        guard let destinationURL, let writer else {
            finishContinuation?.resume(throwing: ScreenRecordingError.recordingFailed)
            reset()
            return
        }

        let duration: TimeInterval
        if let firstPresentationTime, let lastPresentationTime {
            duration = max(0, CMTimeGetSeconds(lastPresentationTime - firstPresentationTime))
        } else {
            duration = 0
        }

        let continuation = finishContinuation
        let recordedVideo = RecordedVideo(fileURL: destinationURL, pixelSize: pixelSize, duration: duration)
        let didSucceed = writer.status == .completed && FileManager.default.fileExists(atPath: destinationURL.path)
        reset()

        if didSucceed {
            continuation?.resume(returning: recordedVideo)
        } else {
            continuation?.resume(throwing: writer.error ?? ScreenRecordingError.recordingFailed)
        }
    }

    private func reset() {
        session = nil
        writer = nil
        writerInput = nil
        destinationURL = nil
        pixelSize = .zero
        displayID = nil
        firstPresentationTime = nil
        lastPresentationTime = nil
        finishContinuation = nil
    }
}
