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
}
