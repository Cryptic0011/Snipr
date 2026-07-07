import CoreGraphics
import XCTest
@testable import Snipr

final class BeautifyRendererTests: XCTestCase {
    func testCanvasGeometryEnforcesMinimumPadding() {
        let (canvas, padding) = BeautifyRenderer.canvasGeometry(for: CGSize(width: 100, height: 100))
        XCTAssertEqual(padding, 48)
        XCTAssertEqual(canvas, CGSize(width: 196, height: 196))
    }

    func testCanvasGeometryScalesPaddingWithImage() {
        let (canvas, padding) = BeautifyRenderer.canvasGeometry(for: CGSize(width: 2000, height: 1000))
        XCTAssertEqual(padding, 80) // 8% of the short side
        XCTAssertEqual(canvas, CGSize(width: 2160, height: 1160))
    }

    func testRenderProducesPaddedImageWithBackdrop() throws {
        let source = try XCTUnwrap(makeSolidImage(width: 100, height: 100, gray: 1.0))
        let rendered = try XCTUnwrap(BeautifyRenderer.render(image: source, style: .ocean))

        XCTAssertEqual(rendered.width, 196)
        XCTAssertEqual(rendered.height, 196)

        // A corner pixel sits on the gradient, not the white source image.
        let corner = try XCTUnwrap(pixel(at: CGPoint(x: 2, y: 2), in: rendered))
        XCTAssertLessThan(corner.red, 0.9, "Corner should show the gradient backdrop, not the white image")
    }

    private func makeSolidImage(width: Int, height: Int, gray: CGFloat) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func pixel(at point: CGPoint, in image: CGImage) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: -point.x, y: -point.y, width: CGFloat(image.width), height: CGFloat(image.height)))
        return (CGFloat(data[0]) / 255, CGFloat(data[1]) / 255, CGFloat(data[2]) / 255)
    }
}
