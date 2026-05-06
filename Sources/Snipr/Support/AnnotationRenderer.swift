import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum AnnotationRenderer {
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

        for annotation in annotations where annotation.tool == .blur {
            drawBlur(annotation, baseImage: cgImage, into: context, imageHeight: CGFloat(height))
        }

        for annotation in annotations where annotation.tool != .blur {
            drawAnnotation(annotation, into: context, imageHeight: CGFloat(height))
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

    private static func drawAnnotation(_ annotation: AnnotationLayer, into context: CGContext, imageHeight: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(annotation.ink.nsColor.cgColor)
        context.setFillColor(annotation.ink.nsColor.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.tool {
        case .arrow:
            let start = flip(annotation.start, imageHeight: imageHeight)
            let end = flip(annotation.end, imageHeight: imageHeight)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            drawArrowHead(from: start, to: end, into: context)
        case .rectangle:
            context.stroke(flip(annotation.bounds, imageHeight: imageHeight))
        case .ellipse:
            context.strokeEllipse(in: flip(annotation.bounds, imageHeight: imageHeight))
        case .blur:
            break
        }
    }

    private static func drawBlur(_ annotation: AnnotationLayer, baseImage: CGImage, into context: CGContext, imageHeight: CGFloat) {
        let rect = annotation.bounds.intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        guard rect.width >= 2, rect.height >= 2 else {
            return
        }

        let ciImage = CIImage(cgImage: baseImage)
        let ciRect = CGRect(
            x: rect.minX,
            y: imageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let crop = ciImage.cropped(to: ciRect)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = crop.clampedToExtent()
        filter.radius = 12

        guard let output = filter.outputImage?.cropped(to: ciRect),
              let cgOutput = CIContext(options: nil).createCGImage(output, from: ciRect) else {
            return
        }

        context.draw(cgOutput, in: flip(rect, imageHeight: imageHeight))
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, into context: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 18
        let spread: CGFloat = .pi / 7

        let first = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let second = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )

        context.move(to: first)
        context.addLine(to: end)
        context.addLine(to: second)
        context.strokePath()
    }

    private static func flip(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: imageHeight - point.y)
    }

    private static func flip(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
