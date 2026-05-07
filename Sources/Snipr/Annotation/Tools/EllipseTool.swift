import CoreGraphics
import Foundation

struct EllipseTool: AnnotationTool {
    let kind: AnnotationKind = .ellipse

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        let context = ctx.context
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(layer.ink.nsColor.cgColor)
        context.setLineWidth(layer.lineWidth)
        context.strokeEllipse(in: AnnotationGeometry.flip(layer.bounds, imageHeight: ctx.imageHeight))
    }

    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        let bounds = layer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return false }
        // Distance from the ellipse perimeter — `((x-cx)/rx)^2 + ((y-cy)/ry)^2 ~= 1`
        let cx = bounds.midX
        let cy = bounds.midY
        let rx = bounds.width / 2
        let ry = bounds.height / 2
        let nx = (point.x - cx) / rx
        let ny = (point.y - cy) / ry
        let d = abs(nx * nx + ny * ny - 1)
        return d < 0.25
    }
}
