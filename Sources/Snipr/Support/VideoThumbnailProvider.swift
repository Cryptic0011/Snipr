import AppKit
import AVFoundation

enum VideoThumbnailProvider {
    static func thumbnail(for url: URL, maximumSize: CGSize) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let image = try generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
            return NSImage(cgImage: image, size: maximumSize)
        } catch {
            return nil
        }
    }
}
