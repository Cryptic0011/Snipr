import AppKit
import CoreGraphics
import CoreImage
@preconcurrency import CoreMedia
import ScreenCaptureKit

/// SCStream-driven helper that collects cropped CGImages from the target
/// window at ~10 fps. The collector is intentionally separate
/// from `SCKRecordingEngine` — that engine's state machine is bonded to
/// AVAssetWriter and the scrolling capture flow only needs in-memory
/// frames.
///
/// Reason for `@unchecked Sendable` on the inner state: SCK delivers sample
/// buffers on its own dispatch queue and we serialize all access to
/// `frames` through that queue. Same pattern as `SCKRecordingEngine` —
/// `CMSampleBuffer` and friends aren't statically Sendable but the access
/// is single-threaded.
@MainActor
final class ScrollingFrameCollector {
    private var stream: SCStream?
    private var output: ScrollingStreamOutputAdapter?
    private let queue = DispatchQueue(label: "com.grayson.snipr.scrolling-capture")
    private let state = ScrollingFrameState()
    private let progressUpdate: @MainActor (Int) -> Void

    /// Fired when the stream dies without stop()/cancel() being called —
    /// e.g. the target window closed or its display disconnected mid-scroll.
    var onUnexpectedStop: ((Error) -> Void)?

    init(progressUpdate: @escaping @MainActor (Int) -> Void = { _ in }) {
        self.progressUpdate = progressUpdate
    }

    private func handleStreamStopped(_ error: Error) {
        guard stream != nil else { return }
        stream = nil
        output = nil
        onUnexpectedStop?(error)
    }

    // Retain every Nth delivered frame (~10 fps out of the 30 fps source) and
    // cap the buffer so a runaway scroll can't exhaust memory before the user
    // stops. 10 fps keeps enough overlap between consecutive frames for the
    // stitch kernel even on a brisk scroll.
    // ponytail: fixed stride + cap. Raise `maxRetainedFrames` if longer
    // sessions are needed; switch to content-aware retention only if memory
    // actually becomes a problem.
    nonisolated static let retainStride = 3
    nonisolated static let maxRetainedFrames = 600
    /// Raw-byte bound as well as a count bound: 600 full-Retina BGRA frames
    /// is multi-GB, so the frame count alone is not a real memory cap.
    nonisolated static let maxRetainedBytes = 1_500_000_000
    nonisolated static func shouldRetainFrame(at index: Int, alreadyRetained: Int, retainedBytes: Int) -> Bool {
        index.isMultiple(of: retainStride)
            && alreadyRetained < maxRetainedFrames
            && retainedBytes < maxRetainedBytes
    }

    func start(scWindow: SCWindow) async throws {
        guard stream == nil else { throw ScreenRecordingError.alreadyRecording }
        // Defensive drain: a cancelled session's late frames must never
        // prepend to this one.
        queue.async { [state] in _ = state.drainFrames() }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let freshWindow = content.windows.first(where: { $0.windowID == scWindow.windowID }) else {
            throw StitchError.noFrames
        }
        guard let scDisplay = Self.display(for: freshWindow, in: content),
              let screen = NSScreen.screens.first(where: { $0.sniprDisplayID == scDisplay.displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }

        // Capture the whole display and crop to the window via `sourceRect` —
        // the exact filter shape `SCKRecordingEngine` uses. The per-window
        // `SCContentFilter(desktopIndependentWindow:)` filter dies ~150ms after
        // `startCapture()` with -3815; the display filter is stable. Frames
        // therefore arrive already cropped to the window at the engine level —
        // no per-frame CGImage crop needed.
        let displayBounds = CGDisplayBounds(scDisplay.displayID)
        let localPointsRect = CGRect(
            x: freshWindow.frame.minX - displayBounds.minX,
            y: freshWindow.frame.minY - displayBounds.minY,
            width: freshWindow.frame.width,
            height: freshWindow.frame.height
        )
        let pixelRect = DisplayGeometry.pixelRect(
            forDisplayPointsRect: localPointsRect,
            displayID: scDisplay.displayID,
            screen: screen
        )
        let pixelWidth = max(2, Int(pixelRect.width.rounded()))
        let pixelHeight = max(2, Int(pixelRect.height.rounded()))

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localPointsRect
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        let adapter = ScrollingStreamOutputAdapter(
            state: state,
            progressUpdate: { [weak self] cumulativePixels in
                // Hop to MainActor for UI updates.
                Task { @MainActor in
                    self?.progressUpdate(cumulativePixels)
                }
            },
            streamStopped: { [weak self] error in
                Task { @MainActor in
                    self?.handleStreamStopped(error)
                }
            }
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: adapter)
        try stream.addStreamOutput(adapter, type: .screen, sampleHandlerQueue: queue)

        self.output = adapter
        self.stream = stream

        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            self.output = nil
            throw error
        }
    }

    private static func display(for window: SCWindow, in content: SCShareableContent) -> SCDisplay? {
        content.displays
            .map { display -> (SCDisplay, CGFloat) in
                let intersection = CGDisplayBounds(display.displayID).intersection(window.frame)
                return (display, intersection.width * intersection.height)
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Stop collection and return the accumulated frames in temporal order.
    func stop() async -> [CGImage] {
        if let stream {
            try? await stream.stopCapture()
        }
        let frames = await withCheckedContinuation { (continuation: CheckedContinuation<[CGImage], Never>) in
            queue.async { [state] in
                let snapshot = state.drainFrames()
                continuation.resume(returning: snapshot)
            }
        }
        self.stream = nil
        self.output = nil
        return frames
    }

    func cancel() {
        let stream = self.stream
        self.stream = nil
        self.output = nil
        // Drain only after the stream has actually stopped — draining while
        // frames are still being delivered leaves stale frames in the shared
        // state to pollute the next session.
        Task { [queue, state] in
            try? await stream?.stopCapture()
            queue.async { _ = state.drainFrames() }
        }
    }
}

/// Bridges SCK's nonisolated delegate callbacks into our serial queue.
/// Mirrors `SCKStreamOutputAdapter` from the recording engine.
private final class ScrollingStreamOutputAdapter: NSObject, SCStreamOutput, SCStreamDelegate {
    let state: ScrollingFrameState
    let progressUpdate: (Int) -> Void
    let streamStopped: @Sendable (Error) -> Void

    init(
        state: ScrollingFrameState,
        progressUpdate: @escaping (Int) -> Void,
        streamStopped: @escaping @Sendable (Error) -> Void
    ) {
        self.state = state
        self.progressUpdate = progressUpdate
        self.streamStopped = streamStopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let attachment = attachments.first,
           let rawStatus = attachment[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Frames already arrive cropped to the window via `sourceRect`. The
        // conversion runs lazily inside `append` so the ~2/3 of frames the
        // retain stride discards are never converted at all.
        let cumulative = state.append { ScrollingStreamOutputAdapter.cgImage(from: imageBuffer) }
        progressUpdate(cumulative)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        SniprDiagnostics.windowing.error(
            "ScrollingCapture stream stopped error=\(String(describing: error), privacy: .public)"
        )
        streamStopped(error)
    }

    // CIContext is expensive; one per adapter, not one per frame.
    private static let ciContext = CIContext(options: nil)

    private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}

/// Owns the captured CGImage list. All access is serialised through the
/// collector's `queue`. `@unchecked Sendable` because `CGImage` is not
/// statically Sendable — same trade-off as the recording engine.
// reason: CGImage isn't statically Sendable; access is serialised through
// ScrollingFrameCollector.queue.
private final class ScrollingFrameState: @unchecked Sendable {
    private var frames: [CGImage] = []
    private var cumulativeHeight: Int = 0
    private var cumulativeBytes: Int = 0
    private var seenFrames: Int = 0

    /// Append a frame and return the running cumulative height in pixels —
    /// used by the progress HUD to count "captured vertical pixels" without
    /// waiting for the row-correlation kernel. `makeImage` runs only when the
    /// frame will actually be retained.
    func append(makeImage: () -> CGImage?) -> Int {
        defer { seenFrames += 1 }
        guard ScrollingFrameCollector.shouldRetainFrame(
            at: seenFrames,
            alreadyRetained: frames.count,
            retainedBytes: cumulativeBytes
        ), let image = makeImage() else {
            return cumulativeHeight
        }
        frames.append(image)
        cumulativeHeight += image.height
        cumulativeBytes += image.bytesPerRow * image.height
        return cumulativeHeight
    }

    func drainFrames() -> [CGImage] {
        defer {
            frames.removeAll()
            cumulativeHeight = 0
            cumulativeBytes = 0
            seenFrames = 0
        }
        return frames
    }
}
