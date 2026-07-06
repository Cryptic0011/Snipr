import CoreGraphics
import Foundation

struct LineTool: AnnotationTool {
    let kind: AnnotationKind = .line

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        let context = ctx.context
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(layer.ink.nsColor.cgColor)
        context.setLineWidth(layer.lineWidth)
        context.setLineCap(.round)

        context.move(to: AnnotationGeometry.flip(layer.start, imageHeight: ctx.imageHeight))
        context.addLine(to: AnnotationGeometry.flip(layer.end, imageHeight: ctx.imageHeight))
        context.strokePath()
    }

    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        AnnotationGeometry.distanceFromSegment(point: point, a: layer.start, b: layer.end) <= max(8, layer.lineWidth)
    }
}
