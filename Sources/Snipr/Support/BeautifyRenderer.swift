import AppKit
import CoreGraphics
import SwiftUI

/// Gradient backdrop presets for the share-ready "background" export. Colors
/// are fixed pairs — presets, not a color picker, on purpose.
enum BeautifyStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case brass
    case ocean
    case sunset
    case forest
    case graphite

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Editor-preview approximation of the export gradient.
    var previewGradient: LinearGradient {
        let (top, bottom) = colors
        return LinearGradient(
            colors: [
                Color(red: top[0], green: top[1], blue: top[2]),
                Color(red: bottom[0], green: bottom[1], blue: bottom[2])
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Top-left → bottom-right gradient endpoints, sRGB.
    var colors: (top: [CGFloat], bottom: [CGFloat]) {
        switch self {
        case .brass: ([0.80, 0.67, 0.33, 1], [0.16, 0.13, 0.06, 1])
        case .ocean: ([0.16, 0.39, 0.62, 1], [0.05, 0.10, 0.20, 1])
        case .sunset: ([0.91, 0.45, 0.32, 1], [0.35, 0.10, 0.31, 1])
        case .forest: ([0.24, 0.47, 0.32, 1], [0.05, 0.14, 0.10, 1])
        case .graphite: ([0.42, 0.43, 0.45, 1], [0.10, 0.10, 0.11, 1])
        }
    }
}

/// Wraps an image in padding, a gradient backdrop, rounded corners, and a
/// drop shadow — the "make it look shareable" pass, applied at export time.
enum BeautifyRenderer {
    /// Canvas geometry for an image. Pure math so it's testable.
    static func canvasGeometry(
        for imageSize: CGSize,
        paddingFraction: CGFloat = 0.08,
        minPadding: CGFloat = 48
    ) -> (canvas: CGSize, padding: CGFloat) {
        let padding = max(minPadding, (min(imageSize.width, imageSize.height) * paddingFraction).rounded())
        return (
            CGSize(width: imageSize.width + padding * 2, height: imageSize.height + padding * 2),
            padding
        )
    }

    static func render(image: CGImage, style: BeautifyStyle, cornerRadius: CGFloat = 16) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let (canvas, padding) = canvasGeometry(for: imageSize)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: Int(canvas.width),
            height: Int(canvas.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let (top, bottom) = style.colors
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(colorSpace: colorSpace, components: top),
                CGColor(colorSpace: colorSpace, components: bottom)
            ].compactMap { $0 } as CFArray,
            locations: [0, 1]
        ) else {
            return nil
        }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: canvas.height),
            end: CGPoint(x: canvas.width, y: 0),
            options: []
        )

        let imageRect = CGRect(x: padding, y: padding, width: imageSize.width, height: imageSize.height)
        let rounded = CGPath(
            roundedRect: imageRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        // Shadow applies to the fill; the image is then drawn clipped to the
        // same rounded path so its corners match.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -padding * 0.16),
            blur: padding * 0.5,
            color: CGColor(gray: 0, alpha: 0.45)
        )
        context.addPath(rounded)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(rounded)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()

        return context.makeImage()
    }
}
