import AppKit
import CoreGraphics

struct StepTool: AnnotationTool {
    let kind: AnnotationKind = .step

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        let radius: CGFloat = max(18, layer.lineWidth * 4)
        let center = AnnotationGeometry.flip(layer.start, imageHeight: ctx.imageHeight)
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        ctx.context.setFillColor(layer.ink.nsColor.cgColor)
        ctx.context.fillEllipse(in: circle)
        ctx.context.setStrokeColor(NSColor.white.cgColor)
        ctx.context.setLineWidth(2)
        ctx.context.strokeEllipse(in: circle)

        let label = String(layer.stepNumber) as NSString
        let fontSize = radius
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = label.size(withAttributes: attrs)
        let textRect = CGRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        let nsContext = NSGraphicsContext(cgContext: ctx.context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        label.draw(in: textRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        let radius: CGFloat = max(18, layer.lineWidth * 4)
        let dx = point.x - layer.start.x
        let dy = point.y - layer.start.y
        return dx * dx + dy * dy <= (radius + 6) * (radius + 6)
    }
}
