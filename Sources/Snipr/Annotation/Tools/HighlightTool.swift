import AppKit
import CoreGraphics

struct HighlightTool: AnnotationTool {
    let kind: AnnotationKind = .highlight

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        let context = ctx.context
        context.saveGState()
        defer { context.restoreGState() }
        // Multiply blend so the highlight tints the underlying pixels rather
        // than overwriting them — matches blueprint's "highlighter pen" feel.
        context.setBlendMode(.multiply)
        context.setFillColor(layer.ink.nsColor.withAlphaComponent(0.45).cgColor)
        context.fill(AnnotationGeometry.flip(layer.bounds, imageHeight: ctx.imageHeight))
    }
}
