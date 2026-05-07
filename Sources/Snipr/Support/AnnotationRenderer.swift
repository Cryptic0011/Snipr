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

        for annotation in annotations where annotation.kind == .blur {
            drawBlur(annotation, baseImage: cgImage, into: context, imageHeight: CGFloat(height))
        }

        for annotation in annotations where annotation.kind == .pixelate {
            drawPixelate(annotation, baseImage: cgImage, into: context, imageHeight: CGFloat(height))
        }

        for annotation in annotations where annotation.kind == .highlight {
            drawHighlight(annotation, into: context, imageHeight: CGFloat(height))
        }

        for annotation in annotations where ![.blur, .pixelate, .highlight, .crop].contains(annotation.kind) {
            drawAnnotation(annotation, into: context, imageHeight: CGFloat(height))
        }

        // Apply destructive crop last (single crop, last one wins).
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

    private static func drawAnnotation(_ annotation: AnnotationLayer, into context: CGContext, imageHeight: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(annotation.ink.nsColor.cgColor)
        context.setFillColor(annotation.ink.nsColor.cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.kind {
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
        case .text:
            drawText(annotation, into: context, imageHeight: imageHeight)
        case .step:
            drawStep(annotation, into: context, imageHeight: imageHeight)
        case .blur, .pixelate, .highlight, .crop:
            break
        }
    }

    private static func drawText(_ annotation: AnnotationLayer, into context: CGContext, imageHeight: CGFloat) {
        let nsString = annotation.text as NSString
        guard !annotation.text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
            .foregroundColor: annotation.ink.nsColor,
        ]
        let origin = flip(annotation.start, imageHeight: imageHeight)
        let size = nsString.size(withAttributes: attrs)
        // Origin is text baseline-ish; CG draws starting at top-left in flipped context.
        let drawRect = CGRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        nsString.draw(in: drawRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawStep(_ annotation: AnnotationLayer, into context: CGContext, imageHeight: CGFloat) {
        let radius: CGFloat = max(18, annotation.lineWidth * 4)
        let center = flip(annotation.start, imageHeight: imageHeight)
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        context.setFillColor(annotation.ink.nsColor.cgColor)
        context.fillEllipse(in: circleRect)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: circleRect)

        let label = String(annotation.stepNumber) as NSString
        let fontSize = radius * 1.0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = label.size(withAttributes: attrs)
        let textRect = CGRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        label.draw(in: textRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawHighlight(_ annotation: AnnotationLayer, into context: CGContext, imageHeight: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(.multiply)
        context.setFillColor(annotation.ink.nsColor.withAlphaComponent(0.45).cgColor)
        context.fill(flip(annotation.bounds, imageHeight: imageHeight))
    }

    private static func drawPixelate(_ annotation: AnnotationLayer, baseImage: CGImage, into context: CGContext, imageHeight: CGFloat) {
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
        let filter = CIFilter.pixellate()
        filter.inputImage = crop.clampedToExtent()
        filter.scale = Float(max(8, min(rect.width, rect.height) / 16))
        filter.center = CGPoint(x: ciRect.midX, y: ciRect.midY)

        guard let output = filter.outputImage?.cropped(to: ciRect),
              let cgOutput = CIContext(options: nil).createCGImage(output, from: ciRect) else {
            return
        }

        context.draw(cgOutput, in: flip(rect, imageHeight: imageHeight))
    }

    private static func cropImage(context: CGContext, size: CGSize, cropRect: CGRect) -> NSImage? {
        guard cropRect.width >= 2, cropRect.height >= 2 else {
            guard let output = context.makeImage() else { return nil }
            return NSImage(cgImage: output, size: size)
        }
        guard let full = context.makeImage() else { return nil }
        // Convert top-left rect to bottom-left for CG cropping.
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
