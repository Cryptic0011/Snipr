import CoreGraphics
import XCTest
@testable import Snipr

final class BeautifyRendererTests: XCTestCase {
    func testRenderProducesPaddedImageWithGradientBackdrop() throws {
        let source = try XCTUnwrap(makeSolidImage(width: 100, height: 100, gray: 1.0))
        let rendered = try XCTUnwrap(
            BeautifyRenderer.render(image: source, backdrop: .gradient(.ocean), style: ExportStyle())
        )

        // Default style: 8% of the short side = 8px padding each edge.
        XCTAssertEqual(rendered.width, 116)
        XCTAssertEqual(rendered.height, 116)

        // A corner pixel sits on the gradient, not the white source image.
        let corner = try XCTUnwrap(pixel(at: CGPoint(x: 2, y: 2), in: rendered))
        XCTAssertLessThan(corner.red, 0.9, "Corner should show the gradient backdrop, not the white image")
    }

    func testRenderFillsSolidColorBackdrop() throws {
        let source = try XCTUnwrap(makeSolidImage(width: 100, height: 100, gray: 1.0))
        let rendered = try XCTUnwrap(BeautifyRenderer.render(
            image: source,
            backdrop: .color(RGBA(red: 1, green: 0, blue: 0, alpha: 1)),
            style: ExportStyle()
        ))

        // Generic-RGB → sRGB conversion shifts pure red a little; assert the
        // corner is unambiguously red, not exact channel values.
        let corner = try XCTUnwrap(pixel(at: CGPoint(x: 2, y: 2), in: rendered))
        XCTAssertGreaterThan(corner.red, 0.85)
        XCTAssertLessThan(corner.green, 0.3)
    }

    func testRenderExpandsCanvasToTargetAspect() throws {
        let source = try XCTUnwrap(makeSolidImage(width: 100, height: 100, gray: 1.0))
        var style = ExportStyle()
        style.aspect = .widescreen
        let rendered = try XCTUnwrap(
            BeautifyRenderer.render(image: source, backdrop: .gradient(.ocean), style: style)
        )

        XCTAssertEqual(Double(rendered.width) / Double(rendered.height), 16.0 / 9.0, accuracy: 0.02)

        // Image is centered: mid pixel is the white source.
        let mid = try XCTUnwrap(pixel(at: CGPoint(x: rendered.width / 2, y: rendered.height / 2), in: rendered))
        XCTAssertGreaterThan(mid.red, 0.9)
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
