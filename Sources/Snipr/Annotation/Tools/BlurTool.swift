import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct BlurTool: AnnotationTool {
    let kind: AnnotationKind = .blur

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
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = crop.clampedToExtent()
        filter.radius = 12

        guard let output = filter.outputImage?.cropped(to: ciRect),
              let cg = CIContext(options: nil).createCGImage(output, from: ciRect) else {
            return
        }
        ctx.context.draw(cg, in: AnnotationGeometry.flip(rect, imageHeight: ctx.imageHeight))
    }
}
