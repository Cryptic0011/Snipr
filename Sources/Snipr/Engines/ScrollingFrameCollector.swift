import AppKit
import CoreGraphics
import CoreImage
@preconcurrency import CoreMedia
import ScreenCaptureKit

/// SCStream-driven helper that collects CGImages off a single window's
/// content filter at ~8–10 fps. The collector is intentionally separate
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

    init(progressUpdate: @escaping @MainActor (Int) -> Void = { _ in }) {
        self.progressUpdate = progressUpdate
    }

    func start(scWindow: SCWindow) async throws {
        // Re-fetch the SCWindow immediately before creating the filter.
        // `SCContentFilter(desktopIndependentWindow:)` can return -3815 if
        // the SCWindow handle is even slightly stale (the window picker has
        // closed, focus has shifted, etc.). Resolve against fresh content.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let freshWindow = content.windows.first(where: { $0.windowID == scWindow.windowID }) else {
            throw StitchError.noFrames
        }

        let configuration = SCStreamConfiguration()
        let backingScale: CGFloat = NSScreen.screens.first(where: { screen in
            screen.frame.intersects(freshWindow.frame)
        })?.backingScaleFactor ?? 2.0
        let pixelWidth = max(2, Int((freshWindow.frame.width * backingScale).rounded()))
        let pixelHeight = max(2, Int((freshWindow.frame.height * backingScale).rounded()))

        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.capturesAudio = false
        // 30 fps — SCK appears to misbehave at very low rates, dropping the
        // capture source within ~150ms. 30 fps is closer to the working
        // configuration the recording engine uses.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(desktopIndependentWindow: freshWindow)

        let adapter = ScrollingStreamOutputAdapter(state: state) { [weak self] cumulativePixels in
            // Hop to MainActor for UI updates.
            Task { @MainActor in
                self?.progressUpdate(cumulativePixels)
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: adapter)
        try stream.addStreamOutput(adapter, type: .screen, sampleHandlerQueue: queue)

        self.output = adapter
        self.stream = stream

        try await stream.startCapture()
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
        Task {
            try? await stream?.stopCapture()
        }
        self.stream = nil
        self.output = nil
        queue.async { [state] in
            _ = state.drainFrames()
        }
    }
}

/// Bridges SCK's nonisolated delegate callbacks into our serial queue.
/// Mirrors `SCKStreamOutputAdapter` from the recording engine.
private final class ScrollingStreamOutputAdapter: NSObject, SCStreamOutput, SCStreamDelegate {
    let state: ScrollingFrameState
    let progressUpdate: (Int) -> Void

    init(state: ScrollingFrameState, progressUpdate: @escaping (Int) -> Void) {
        self.state = state
        self.progressUpdate = progressUpdate
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
        if let cgImage = ScrollingStreamOutputAdapter.cgImage(from: imageBuffer) {
            let cumulative = state.append(image: cgImage)
            progressUpdate(cumulative)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Reserved for future Phase 4.5 scrolling-capture rewrite (full-display
        // capture + window crop). The current path is disabled at the user-
        // facing surface; engine retained so re-enabling is a single PR.
    }

    private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
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

    /// Append a frame and return the running cumulative height in pixels —
    /// used by the progress HUD to count "captured vertical pixels" without
    /// waiting for the row-correlation kernel.
    func append(image: CGImage) -> Int {
        frames.append(image)
        cumulativeHeight += image.height
        return cumulativeHeight
    }

    func drainFrames() -> [CGImage] {
        defer {
            frames.removeAll()
            cumulativeHeight = 0
        }
        return frames
    }
}
