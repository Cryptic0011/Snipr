@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GIFExportError: LocalizedError {
    case noFrames
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .noFrames:
            "The recording has no readable frames."
        case .destinationUnavailable:
            "Snipr could not write the GIF file."
        }
    }
}

/// Converts a recorded video into an animated GIF by sampling frames at a
/// fixed rate. GIFs are for sharing, not archiving — output is capped at
/// `maxWidth` and `fps` to keep files Slack-postable.
enum GIFExporter {
    /// Sample times for a duration at fps. Pure math so it's testable
    /// without decoding video.
    static func frameTimes(duration: TimeInterval, fps: Double) -> [TimeInterval] {
        guard duration > 0, fps > 0 else { return [] }
        let count = max(1, Int((duration * fps).rounded(.down)))
        return (0..<count).map { Double($0) / fps }
    }

    static func export(
        sourceURL: URL,
        outputURL: URL,
        fps: Double = 12,
        maxWidth: CGFloat = 800
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let times = frameTimes(duration: duration, fps: fps)
        guard !times.isEmpty else { throw GIFExportError.noFrames }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            times.count,
            nil
        ) else {
            throw GIFExportError.destinationUnavailable
        }

        // Loop forever; per-frame delay matches the sample rate.
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        )
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]
        ] as CFDictionary

        var appended = 0
        for time in times {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let image = try? await generator.image(at: cmTime).image else {
                continue // an unreadable frame shouldn't sink the whole export
            }
            CGImageDestinationAddImage(destination, image, frameProperties)
            appended += 1
        }
        guard appended > 0, CGImageDestinationFinalize(destination) else {
            throw GIFExportError.noFrames
        }
        return outputURL
    }
}
