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

/// Wraps an image in padding, a backdrop, rounded corners, and a drop shadow
/// — the "make it look shareable" pass, applied at screenshot export time.
/// The still-image counterpart to VideoCompositor's styled export path;
/// shares the `VideoBackdrop` and `ExportStyle` models with it.
enum BeautifyRenderer {
    static func render(
        image: CGImage,
        backdrop: VideoBackdrop,
        style: ExportStyle,
        screen: NSScreen? = nil
    ) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let (canvas, padding) = style.canvas(for: imageSize)
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

        drawBackground(backdrop, in: context, canvas: canvas, colorSpace: colorSpace, screen: screen)

        // Image centered in the (possibly aspect-expanded) canvas.
        let imageRect = CGRect(
            x: ((canvas.width - imageSize.width) / 2).rounded(),
            y: ((canvas.height - imageSize.height) / 2).rounded(),
            width: imageSize.width,
            height: imageSize.height
        )
        // Radius/shadow are authored in points; captures are 2× Retina, so
        // double them to match the video export's look (VideoCompositor does
        // the same). Shadow scale floors to a fraction of the image so it
        // stays visible even at padding 0 with an aspect-expanded canvas.
        let cornerRadius = style.cornerRadius * 2
        let shadowScale = max(padding, min(imageSize.width, imageSize.height) * 0.04)
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
            offset: CGSize(width: 0, height: -shadowScale * 0.16),
            blur: shadowScale * 0.5,
            color: CGColor(gray: 0, alpha: style.shadowOpacity)
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

    private static func drawBackground(
        _ backdrop: VideoBackdrop,
        in context: CGContext,
        canvas: CGSize,
        colorSpace: CGColorSpace,
        screen: NSScreen?
    ) {
        let frame = CGRect(origin: .zero, size: canvas)
        switch backdrop {
        case .gradient(let style):
            let (top, bottom) = style.colors
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    CGColor(colorSpace: colorSpace, components: top),
                    CGColor(colorSpace: colorSpace, components: bottom)
                ].compactMap { $0 } as CFArray,
                locations: [0, 1]
            ) else { return }
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: canvas.height),
                end: CGPoint(x: canvas.width, y: 0),
                options: []
            )
        case .color(let rgba):
            context.setFillColor(rgba.cgColor)
            context.fill(frame)
        case .bundled, .wallpaper, .customImage:
            guard let image = backdrop.resolveImage(for: screen),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                // Unreadable wallpaper / custom image — graphite fallback (spec).
                drawBackground(.gradient(.graphite), in: context, canvas: canvas, colorSpace: colorSpace, screen: nil)
                return
            }
            // CGContext clips the overflow, so an aspect-fill rect fills the canvas.
            context.draw(cg, in: aspectFillRect(imageSize: CGSize(width: cg.width, height: cg.height), in: frame))
        }
    }

    private static func aspectFillRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
