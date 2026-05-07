import AppKit
import CoreGraphics

struct TextTool: AnnotationTool {
    let kind: AnnotationKind = .text

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        guard !layer.text.isEmpty else { return }
        let nsString = layer.text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: layer.fontSize, weight: .semibold),
            .foregroundColor: layer.ink.nsColor
        ]
        let origin = AnnotationGeometry.flip(layer.start, imageHeight: ctx.imageHeight)
        let size = nsString.size(withAttributes: attrs)
        let drawRect = CGRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)

        let nsContext = NSGraphicsContext(cgContext: ctx.context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        nsString.draw(in: drawRect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        guard !layer.text.isEmpty else { return false }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: layer.fontSize, weight: .semibold)
        ]
        let size = (layer.text as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: layer.start.x, y: layer.start.y, width: size.width, height: size.height)
        return rect.insetBy(dx: -4, dy: -4).contains(point)
    }
}
