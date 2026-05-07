import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Top-aligned vertical concatenation of multiple PNG images into a single
/// PNG.
///
/// This is the dumb concat helper the Phase 2 brief asks for; it is **not**
/// the scrolling-capture stitcher (Phase 4). Each input keeps its own
/// width — the output canvas matches the widest image and narrower images
/// are left-aligned with transparent padding to the right.
enum VerticalStitcher {
    enum Failure: LocalizedError {
        case noImages
        case decodeFailed(URL)
        case contextFailed
        case encodeFailed(URL)

        var errorDescription: String? {
            switch self {
            case .noImages:
                "No images to stitch."
            case .decodeFailed(let url):
                "Could not decode \(url.lastPathComponent)."
            case .contextFailed:
                "Could not allocate stitch context."
            case .encodeFailed(let url):
                "Could not write stitched PNG to \(url.path)."
            }
        }
    }

    /// Stitch `imageURLs` into a single PNG written to `destination`. Returns
    /// the resulting pixel size.
    @discardableResult
    static func stitchVertically(imageURLs: [URL], to destination: URL) throws -> CGSize {
        guard !imageURLs.isEmpty else { throw Failure.noImages }

        var cgImages: [CGImage] = []
        cgImages.reserveCapacity(imageURLs.count)
        var maxWidth = 0
        var totalHeight = 0
        for url in imageURLs {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw Failure.decodeFailed(url)
            }
            cgImages.append(cgImage)
            maxWidth = max(maxWidth, cgImage.width)
            totalHeight += cgImage.height
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: maxWidth,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Failure.contextFailed
        }

        // Core Graphics origin is bottom-left; we want top-aligned output,
        // so we draw the first image at the top of the canvas and walk
        // downward. Each image's destination y is computed from the running
        // height consumed by earlier images.
        var consumed = 0
        for image in cgImages {
            let y = totalHeight - consumed - image.height
            // Left-align inside the canvas; narrower images get transparent
            // padding to the right.
            let rect = CGRect(x: 0, y: y, width: image.width, height: image.height)
            context.draw(image, in: rect)
            consumed += image.height
        }

        guard let combined = context.makeImage() else {
            throw Failure.contextFailed
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.encodeFailed(destination)
        }

        CGImageDestinationAddImage(imageDestination, combined, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw Failure.encodeFailed(destination)
        }

        return CGSize(width: maxWidth, height: totalHeight)
    }
}
