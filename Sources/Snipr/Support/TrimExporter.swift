@preconcurrency import AVFoundation
import Foundation

enum TrimExporterError: LocalizedError {
    case invalidRange
    case exportFailed(any Error)
    case sessionUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            "Trim range is empty or out of bounds."
        case .exportFailed(let error):
            error.localizedDescription
        case .sessionUnavailable:
            "Snipr could not start an AVAssetExportSession."
        }
    }
}

/// Stateless helper that trims a video to a half-open `[start, end)` time
/// range and writes the result to `outputURL`. Used by the preview window's
/// trim handles for video items.
enum TrimExporter {
    /// Validate a trim range against an asset duration. Pure math so this is
    /// trivially testable without driving AVAssetExportSession.
    static func clampedRange(start: TimeInterval, end: TimeInterval, duration: TimeInterval) -> (start: TimeInterval, end: TimeInterval)? {
        guard duration > 0 else { return nil }
        let clampedStart = max(0, min(start, duration))
        let clampedEnd = max(0, min(end, duration))
        guard clampedEnd - clampedStart > 0.05 else { return nil }
        return (clampedStart, clampedEnd)
    }

    static func export(
        sourceURL: URL,
        outputURL: URL,
        start: TimeInterval,
        end: TimeInterval
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard let range = clampedRange(start: start, end: end, duration: durationSeconds) else {
            throw TrimExporterError.invalidRange
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TrimExporterError.sessionUnavailable
        }
        session.outputURL = outputURL
        session.outputFileType = outputURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: 600),
            end: CMTime(seconds: range.end, preferredTimescale: 600)
        )

        do {
            // macOS 15+ exposes `export(to:as:)` async. macOS 14 still ships
            // the deprecated `exportAsynchronously` callback path, but
            // `states(updateInterval:)` is available on 14.x for us to drive
            // the export without warnings.
            try await session.export(to: outputURL, as: session.outputFileType ?? .mov)
        } catch {
            throw TrimExporterError.exportFailed(error)
        }

        return outputURL
    }
}
