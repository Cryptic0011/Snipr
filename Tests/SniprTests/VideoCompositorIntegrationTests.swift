// Integration check for the compositor render pipeline: generates a real H.264 video with AVAssetWriter, then drives
// VideoCompositor through both production paths (backdrop export,
// cursor-only bake) and asserts on the actual output files.
@preconcurrency import AVFoundation
import AppKit
import XCTest
@testable import Snipr

@MainActor
final class VideoCompositorIntegrationTests: XCTestCase {
    private nonisolated(unsafe) var tempDir: URL!

    nonisolated override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    nonisolated override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 2-second 640×360 30fps H.264 movie with a moving gradient so frames differ.
    private func makeSourceVideo() async throws -> URL {
        let url = tempDir.appending(path: "source.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 360
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 360
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: 640, height: 360, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )!
            ctx.setFillColor(CGColor(red: CGFloat(frame) / 60, green: 0.3, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    private func videoInfo(_ url: URL) async throws -> (size: CGSize, duration: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let duration = try await CMTimeGetSeconds(asset.load(.duration))
        return (size, duration)
    }

    func testBackdropExportProducesPaddedEvenCanvas() async throws {
        let source = try await makeSourceVideo()
        let out = tempDir.appending(path: "styled.mov")
        _ = try await VideoCompositor.composite(
            sourceURL: source, outputURL: out,
            backdrop: .bundled("sonoma-horizon"), backdropScreen: nil,
            cursor: nil, trimStart: nil, trimEnd: nil
        )
        let info = try await videoInfo(out)
        // canvasGeometry: padding = max(48, min(640,360)*0.08 rounded) = 48
        XCTAssertEqual(info.size.width, 736)   // 640 + 96
        XCTAssertEqual(info.size.height, 456)  // 360 + 96
        XCTAssertEqual(info.duration, 2.0, accuracy: 0.1)

        // Pin the render geometry itself, not just the canvas dimensions.
        // makeSourceVideo fills every frame with a single known color (at
        // t=1.0, nominally ~(0.5, 0.3, 0.6) before H.264 color-matching on
        // decode; sample the source's own re-encoded frame as ground truth
        // rather than hardcoding the pre-encode value, since AVFoundation's
        // color management shifts raw RGB on readback). The video rect is
        // centered in the 48px padding: x/y in [48, 688]x[48, 408].
        //
        // Regression this catches: AVVideoCompositionCoreAnimationTool
        // squeezes the renderSize-sized composited frame into videoLayer's
        // bounds. A passthrough (untransformed) layer instruction leaves the
        // video at natural size in the canvas's top-left corner, so the
        // whole canvas — including its black background — gets squeezed
        // into the smaller, centered video rect: aspect distortion plus
        // black bands where the video's own edges should be. Sampling near
        // the rect's edges (not corners, which are clipped by the rounded
        // mask) catches exactly that: before the transform fix these pixels
        // read as black instead of the video's fill color.
        let frame = try await frameImage(out, at: 1.0)
        let sourceFrame = try await frameImage(source, at: 1.0)
        let videoColor = pixelColor(sourceFrame, x: 320, y: 180)
        assertPixelColor(frame, x: 10, y: 10, isNear: videoColor, tolerance: 0.15, expectMatch: false)
        assertPixelColor(frame, x: 368, y: 58, isNear: videoColor, tolerance: 0.15, expectMatch: true)   // top edge, mid
        assertPixelColor(frame, x: 368, y: 398, isNear: videoColor, tolerance: 0.15, expectMatch: true)  // bottom edge, mid
        assertPixelColor(frame, x: 58, y: 228, isNear: videoColor, tolerance: 0.15, expectMatch: true)   // left edge, mid
        assertPixelColor(frame, x: 678, y: 228, isNear: videoColor, tolerance: 0.15, expectMatch: true)  // right edge, mid
    }

    func testGradientBackdropWithTrim() async throws {
        let source = try await makeSourceVideo()
        let out = tempDir.appending(path: "trimmed-styled.mp4")
        _ = try await VideoCompositor.composite(
            sourceURL: source, outputURL: out,
            backdrop: .gradient(.ocean), backdropScreen: nil,
            cursor: nil, trimStart: 0.5, trimEnd: 1.5
        )
        let info = try await videoInfo(out)
        XCTAssertEqual(info.duration, 1.0, accuracy: 0.15)
        XCTAssertEqual(info.size.width, 736)
    }

    func testCursorOnlyBakeKeepsVideoSize() async throws {
        let source = try await makeSourceVideo()
        let out = tempDir.appending(path: "baked.mov")
        let region = CGRect(x: 0, y: 0, width: 640, height: 360)
        let samples = (0..<120).map {
            CursorSample(
                time: Double($0) / 60.0,
                location: CGPoint(x: Double($0) * 5, y: Double($0) * 3)
            )
        }
        _ = try await VideoCompositor.composite(
            sourceURL: source, outputURL: out,
            backdrop: nil, backdropScreen: nil,
            cursor: CursorOverlaySpec(
                samples: samples, regionInScreen: region,
                scale: 2.0, color: .brass, smoothed: true
            ),
            trimStart: nil, trimEnd: nil
        )
        let info = try await videoInfo(out)
        XCTAssertEqual(info.size, CGSize(width: 640, height: 360))
        XCTAssertEqual(info.duration, 2.0, accuracy: 0.1)
        // The cursor must actually be drawn: the baked frame at t=1s should
        // differ from the source frame at t=1s in the cursor's vicinity.
        let sourceFrame = try await frameImage(source, at: 1.0)
        let bakedFrame = try await frameImage(out, at: 1.0)
        XCTAssertFalse(pixelsEqual(sourceFrame, bakedFrame), "baked frame should contain a drawn cursor")
    }

    func testCursorBakeForcesDenseFrameRateFromSparseSource() async throws {
        // ScreenCaptureKit recordings of a static screen produce very sparse
        // tracks; simulate that here with 3 frames spread over 2 seconds.
        let source = try await makeSparseSourceVideo()
        let out = tempDir.appending(path: "sparse-baked.mov")
        let region = CGRect(x: 0, y: 0, width: 640, height: 360)
        let samples = (0..<120).map {
            CursorSample(
                time: Double($0) / 60.0,
                location: CGPoint(x: Double($0) * 5, y: Double($0) * 3)
            )
        }
        _ = try await VideoCompositor.composite(
            sourceURL: source, outputURL: out,
            backdrop: nil, backdropScreen: nil,
            cursor: CursorOverlaySpec(
                samples: samples, regionInScreen: region,
                scale: 2.0, color: .brass, smoothed: true
            ),
            trimStart: nil, trimEnd: nil
        )
        let frameCount = try await countVideoFrames(out)
        // Without forcing frameDuration, AVMutableVideoComposition(propertiesOf:)
        // would inherit the sparse source's ~1.5fps nominal rate (3 frames /
        // 2s), yielding only a handful of output frames and discarding most
        // of the 60 Hz cursor keyframe animation. Forcing 1/60s frameDuration
        // over a ~2s composition should densely resample to roughly 120
        // frames; assert comfortably above the sparse-source baseline.
        XCTAssertGreaterThanOrEqual(
            frameCount, 60,
            "forcing frameDuration=1/60 should densely resample the sparse source; got \(frameCount) frames"
        )
    }

    /// 3-frame, 2-second 640×360 H.264 movie with long presentation gaps —
    /// mimics ScreenCaptureKit's sparse tracks for a static screen.
    private func makeSparseSourceVideo() async throws -> URL {
        let url = tempDir.appending(path: "sparse-source.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 360
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 360
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let presentationTimes: [CMTime] = [
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(seconds: 1.0, preferredTimescale: 600),
            CMTime(seconds: 1.9, preferredTimescale: 600)
        ]
        for (index, pts) in presentationTimes.enumerated() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: 640, height: 360, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )!
            ctx.setFillColor(CGColor(red: CGFloat(index) / 3, green: 0.5, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: pts)
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 2.0, preferredTimescale: 600))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    /// Counts actual encoded video frames by reading the track directly,
    /// rather than trusting duration × nominalFrameRate (which can lie for
    /// composited output).
    private func countVideoFrames(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var count = 0
        while output.copyNextSampleBuffer() != nil {
            count += 1
        }
        return count
    }

    private func frameImage(_ url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return image
    }

    private func pixelsEqual(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        func data(_ img: CGImage) -> Data? {
            (img.dataProvider?.data).map { Data(referencing: $0) }
        }
        return data(a) == data(b)
    }

    /// Samples an (x, y) pixel's RGB (top-left origin, matching how the
    /// frame visually looks) and asserts whether it's near `color` within
    /// `tolerance` per channel.
    private func assertPixelColor(
        _ image: CGImage,
        x: Int,
        y: Int,
        isNear color: (r: Double, g: Double, b: Double),
        tolerance: Double,
        expectMatch: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = pixelColor(image, x: x, y: y)
        let matches = abs(actual.r - color.r) <= tolerance
            && abs(actual.g - color.g) <= tolerance
            && abs(actual.b - color.b) <= tolerance
        XCTAssertEqual(
            matches, expectMatch,
            "pixel (\(x),\(y)) = \(actual), expected \(expectMatch ? "near" : "far from") \(color)",
            file: file, line: line
        )
    }

    private func pixelColor(_ image: CGImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        guard let rep = NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            return (0, 0, 0)
        }
        return (Double(rep.redComponent), Double(rep.greenComponent), Double(rep.blueComponent))
    }
}
