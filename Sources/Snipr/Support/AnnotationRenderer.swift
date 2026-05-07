import AppKit
import CoreGraphics

/// Composites a base image plus a stack of `AnnotationLayer`s into a final
/// `NSImage` (or its PNG representation). Per-tool drawing lives in the
/// concrete `AnnotationTool` types under `Annotation/Tools/`; this enum just
/// orchestrates the layer order and applies the destructive crop step at
/// the very end.
enum AnnotationRenderer {
    /// Order layers are painted in. Effect layers (blur / pixelate /
    /// highlight) sit underneath strokes and labels so users see their
    /// arrows on top of the redacted region, not buried under it.
    private static let drawOrder: [AnnotationKind] = [
        .blur, .pixelate, .highlight,
        .arrow, .rectangle, .ellipse,
        .text, .step
    ]

    static func renderImage(baseURL: URL, annotations: [AnnotationLayer]) -> NSImage? {
        guard let source = NSImage(contentsOf: baseURL),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let size = CGSize(width: width, height: height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let imageRect = CGRect(origin: .zero, size: size)
        context.draw(cgImage, in: imageRect)

        let drawCtx = AnnotationDrawingContext(
            context: context,
            baseImage: cgImage,
            imageHeight: CGFloat(height),
            imageWidth: CGFloat(width)
        )

        for kind in drawOrder {
            guard let tool = AnnotationToolRegistry.tool(for: kind) else { continue }
            for annotation in annotations where annotation.kind == kind {
                tool.draw(annotation, in: drawCtx)
            }
        }

        // Crop is destructive; apply last (last crop wins).
        if let crop = annotations.last(where: { $0.kind == .crop }) {
            return cropImage(context: context, size: size, cropRect: crop.bounds.intersection(imageRect))
        }

        guard let output = context.makeImage() else {
            return nil
        }

        return NSImage(cgImage: output, size: size)
    }

    static func pngData(baseURL: URL, annotations: [AnnotationLayer]) -> Data? {
        guard let image = renderImage(baseURL: baseURL, annotations: annotations),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        return rep.representation(using: .png, properties: [:])
    }

    private static func cropImage(context: CGContext, size: CGSize, cropRect: CGRect) -> NSImage? {
        guard cropRect.width >= 2, cropRect.height >= 2 else {
            guard let output = context.makeImage() else { return nil }
            return NSImage(cgImage: output, size: size)
        }
        guard let full = context.makeImage() else { return nil }
        let cgCrop = CGRect(
            x: cropRect.minX,
            y: size.height - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        )
        guard let cropped = full.cropping(to: cgCrop) else {
            return NSImage(cgImage: full, size: size)
        }
        return NSImage(cgImage: cropped, size: CGSize(width: cropped.width, height: cropped.height))
    }
}
