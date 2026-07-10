@preconcurrency import AVFoundation
import CoreMedia
import XCTest
@testable import Snipr

final class TrimExportTests: XCTestCase {
    func testClampedRangeRejectsZeroDuration() {
        XCTAssertNil(TrimExporter.clampedRange(start: 0, end: 1, duration: 0))
    }

    func testClampedRangeClampsToDuration() throws {
        let result = try XCTUnwrap(TrimExporter.clampedRange(start: -2, end: 100, duration: 10))
        XCTAssertEqual(result.start, 0)
        XCTAssertEqual(result.end, 10)
    }

    func testClampedRangeRejectsTinyRanges() {
        XCTAssertNil(TrimExporter.clampedRange(start: 1.0, end: 1.01, duration: 5))
    }

    func testClampedRangeRejectsRangeEntirelyBeyondDuration() {
        // Both bounds past the end collapse to [duration, duration] — empty,
        // so no trim should be applied (VideoCompositor relies on this).
        XCTAssertNil(TrimExporter.clampedRange(start: 12, end: 15, duration: 10))
    }

    func testClampedRangeAllowsValidRange() throws {
        let result = try XCTUnwrap(TrimExporter.clampedRange(start: 1, end: 4, duration: 5))
        XCTAssertEqual(result.start, 1)
        XCTAssertEqual(result.end, 4)
    }

    /// Build a tiny synthetic mov asset, trim it, and verify the exported
    /// duration matches the requested range. This is an end-to-end check that
    /// validates the AVAssetExportSession path against a known input.
    func testExportProducesAssetWithExpectedDuration() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sourceURL = temp.appending(path: "source.mov")
        try writeFixtureMov(to: sourceURL, durationSeconds: 5, width: 64, height: 48)

        let outputURL = temp.appending(path: "trimmed.mov")
        _ = try await TrimExporter.export(
            sourceURL: sourceURL,
            outputURL: outputURL,
            start: 1.0,
            end: 3.0
        )

        let exported = AVURLAsset(url: outputURL)
        let duration = try await exported.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        XCTAssertEqual(seconds, 2.0, accuracy: 0.5)
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
                [
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
                ] as CFDictionary,
                &pixelBuffer
            )
            guard let buffer = pixelBuffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            // Fill with a flat color — content doesn't matter for the duration assertion.
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, Int32((frame * 7) % 256), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let pts = CMTime(value: CMTimeValue(frame), timescale: frameRate)
            adaptor.append(buffer, withPresentationTime: pts)
        }
        input.markAsFinished()

        let exp = expectation(description: "writer finished")
        writer.finishWriting {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }
}
