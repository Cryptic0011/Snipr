import CoreGraphics

struct RectangleTool: AnnotationTool {
    let kind: AnnotationKind = .rectangle

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        let context = ctx.context
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(layer.ink.nsColor.cgColor)
        context.setLineWidth(layer.lineWidth)
        context.setLineJoin(.round)
        context.stroke(AnnotationGeometry.flip(layer.bounds, imageHeight: ctx.imageHeight))
    }

    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        let bounds = layer.bounds
        let outer = bounds.insetBy(dx: -8, dy: -8)
        let inner = bounds.insetBy(dx: 8, dy: 8)
        return outer.contains(point) && !inner.contains(point)
    }
}
