import CoreGraphics
import Foundation

struct ArrowTool: AnnotationTool {
    let kind: AnnotationKind = .arrow

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        let context = ctx.context
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(layer.ink.nsColor.cgColor)
        context.setFillColor(layer.ink.nsColor.cgColor)
        context.setLineWidth(layer.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let start = AnnotationGeometry.flip(layer.start, imageHeight: ctx.imageHeight)
        let end = AnnotationGeometry.flip(layer.end, imageHeight: ctx.imageHeight)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Arrowhead — same geometry as the SwiftUI preview path so the
        // exported file matches what the user sees while drawing.
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

    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        // Distance-from-segment hit test — keeps the arrow "selectable" along
        // its length, not just inside its bounding rect.
        distanceFromSegment(point: point, a: layer.start, b: layer.end) <= max(8, layer.lineWidth)
    }

    private func distanceFromSegment(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            return hypot(point.x - a.x, point.y - a.y)
        }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
