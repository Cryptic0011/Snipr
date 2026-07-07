@preconcurrency import AVFoundation
import ImageIO
import XCTest
@testable import Snipr

final class GIFExporterTests: XCTestCase {
    func testFrameTimesEmptyForZeroDuration() {
        XCTAssertTrue(GIFExporter.frameTimes(duration: 0, fps: 12).isEmpty)
        XCTAssertTrue(GIFExporter.frameTimes(duration: 5, fps: 0).isEmpty)
    }

    func testFrameTimesSampleAtRate() {
        let times = GIFExporter.frameTimes(duration: 1.0, fps: 5)
        XCTAssertEqual(times.count, 5)
        XCTAssertEqual(times[0], 0)
        XCTAssertEqual(times[1], 0.2, accuracy: 0.0001)
        XCTAssertEqual(times[4], 0.8, accuracy: 0.0001)
    }

    func testExportWritesAnimatedGIF() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sourceURL = temp.appending(path: "source.mov")
        try writeFixtureMov(to: sourceURL, durationSeconds: 1, width: 64, height: 48)

        let outputURL = temp.appending(path: "out.gif")
        _ = try await GIFExporter.export(sourceURL: sourceURL, outputURL: outputURL, fps: 5, maxWidth: 64)

        let data = try Data(contentsOf: outputURL)
        XCTAssertTrue(data.starts(with: Array("GIF8".utf8)), "Output should be a GIF container")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        XCTAssertGreaterThan(CGImageSourceGetCount(source), 1, "GIF should be animated")
    }

    private func writeFixtureMov(to url: URL, durationSeconds: Double, width: Int, height: Int) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frameRate: Int32 = 30
        let totalFrames = Int(durationSeconds * Double(frameRate))
        var pixelBuffer: CVPixelBuffer?
        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            CVPixelBufferCreate(
                nil,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary] as CFDictionary,
                &pixelBuffer
            )
            guard let buffer = pixelBuffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32((frame * 11) % 256), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: frameRate))
        }
        input.markAsFinished()

        let exp = expectation(description: "writer finished")
        writer.finishWriting { exp.fulfill() }
        wait(for: [exp], timeout: 30)
    }
}
