import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct PixelateTool: AnnotationTool {
    let kind: AnnotationKind = .pixelate

    func draw(_ layer: AnnotationLayer, in ctx: AnnotationDrawingContext) {
        let rect = layer.bounds.intersection(CGRect(x: 0, y: 0, width: ctx.imageWidth, height: ctx.imageHeight))
        guard rect.width >= 2, rect.height >= 2 else { return }

        let ciImage = CIImage(cgImage: ctx.baseImage)
        let ciRect = CGRect(
            x: rect.minX,
            y: ctx.imageHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let crop = ciImage.cropped(to: ciRect)
        let filter = CIFilter.pixellate()
        filter.inputImage = crop.clampedToExtent()
        filter.scale = Float(max(8, min(rect.width, rect.height) / 16))
        filter.center = CGPoint(x: ciRect.midX, y: ciRect.midY)

        guard let output = filter.outputImage?.cropped(to: ciRect),
              let cg = CIContext(options: nil).createCGImage(output, from: ciRect) else {
            return
        }
        ctx.context.draw(cg, in: AnnotationGeometry.flip(rect, imageHeight: ctx.imageHeight))
    }
}
