import AppKit
import CoreGraphics

/// Drawing context handed to an `AnnotationTool` when the renderer asks it
/// to paint itself. Holds the active CG context, the base image (so blur
/// / pixelate can read pixels), and the image height (for top-left ↔
/// bottom-left flips).
struct AnnotationDrawingContext {
    let context: CGContext
    let baseImage: CGImage
    let imageHeight: CGFloat
    let imageWidth: CGFloat
}

/// JSON-friendly per-tool payload. We don't currently persist annotations,
/// but defining this now keeps the door open for Phase 4+ workflows that
/// chain annotations into other steps.
struct AnnotationData: Codable, Equatable {
    let kind: AnnotationKind
    let payload: [String: String]
}

/// Per-tool surface. Each concrete tool — `ArrowTool`, `RectangleTool`,
/// `BlurTool`, etc. — owns one of these and lives in its own file under
/// `Sources/Snipr/Annotation/Tools/`. The renderer dispatches through the
/// `tools` registry below; the SwiftUI canvas in `PreviewWindowView` paints a
/// live preview using its own draw routines (kept there because they speak
/// SwiftUI's `GraphicsContext`, not CG).
protocol AnnotationTool: Sendable {
    /// Discriminator used to look the tool up from a stored layer.
    var kind: AnnotationKind { get }

    /// Paint the layer's contents into the destination context.
    func draw(_ layer: AnnotationLayer, in context: AnnotationDrawingContext)

    /// Test whether `point` (image coordinates, top-left origin) hits the
    /// layer's drawn area. Used by selection / hover affordances. Default
    /// implementation falls back to a bounding-rect test.
    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool

    /// Serialise to a portable representation. Default implementation
    /// captures `start`, `end`, `lineWidth`, `text`, `stepNumber`,
    /// `fontSize`. Override only if a tool stores extra state.
    func encode(_ layer: AnnotationLayer) -> AnnotationData
}

extension AnnotationTool {
    func hitTest(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        layer.bounds.insetBy(dx: -8, dy: -8).contains(point)
    }

    func encode(_ layer: AnnotationLayer) -> AnnotationData {
        AnnotationData(
            kind: kind,
            payload: [
                "startX": String(Double(layer.start.x)),
                "startY": String(Double(layer.start.y)),
                "endX": String(Double(layer.end.x)),
                "endY": String(Double(layer.end.y)),
                "lineWidth": String(Double(layer.lineWidth)),
                "text": layer.text,
                "stepNumber": String(layer.stepNumber),
                "fontSize": String(Double(layer.fontSize)),
                "ink": layer.ink.rawValue
            ]
        )
    }
}

/// Stateless lookup from a layer's `kind` to the concrete tool. Adding a new
/// tool? Drop a `Tools/<Name>.swift` file with the conforming struct and add
/// it here.
enum AnnotationToolRegistry {
    static let tools: [AnnotationKind: any AnnotationTool] = [
        .arrow: ArrowTool(),
        .line: LineTool(),
        .rectangle: RectangleTool(),
        .ellipse: EllipseTool(),
        .blur: BlurTool(),
        .pixelate: PixelateTool(),
        .highlight: HighlightTool(),
        .text: TextTool(),
        .step: StepTool(),
        .crop: CropTool()
    ]

    static func tool(for kind: AnnotationKind) -> (any AnnotationTool)? {
        tools[kind]
    }
}

/// Shared coordinate-flip helpers used by every CG-context tool — top-left
/// origin in `AnnotationLayer` coordinates ↔ bottom-left origin in CG.
enum AnnotationGeometry {
    static func flip(_ point: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: imageHeight - point.y)
    }

    static func flip(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Distance from `point` to the segment `a`–`b`. Used by segment-shaped
    /// tools (arrow, line) so they're selectable along their length, not just
    /// inside their bounding rect.
    static func distanceFromSegment(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
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
