import CoreGraphics

/// Crop is special-cased in `AnnotationRenderer` because it produces a
/// destructively cropped image rather than overlay strokes — the renderer
/// applies it after every other layer, replacing the output canvas. This
/// tool's `draw(...)` is a no-op so the protocol contract is satisfied;
/// the renderer detects `kind == .crop` and crops directly.
struct CropTool: AnnotationTool {
    let kind: AnnotationKind = .crop

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        // Crop is destructive; AnnotationRenderer.cropImage handles it.
    }

    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        layer.bounds.insetBy(dx: -8, dy: -8).contains(point)
    }
}
