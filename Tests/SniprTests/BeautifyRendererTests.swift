import CoreGraphics
import XCTest
@testable import Snipr

final class BeautifyRendererTests: XCTestCase {
    func testRenderPadsImageWithGradientBackdrop() throws {
        let source = try XCTUnwrap(makeSolidImage(width: 400, height: 400, gray: 1.0))
        let rendered = try XCTUnwrap(
            BeautifyRenderer.render(image: source, backdrop: .gradient(.ocean), style: ExportStyle())
        )

        // 8% padding of the 400px short side → 32px each side, canvas 464².
        XCTAssertEqual(rendered.width, 464)
        XCTAssertEqual(rendered.height, 464)

        // A corner pixel sits on the gradient, not the white source image.
        let corner = try XCTUnwrap(pixel(at: CGPoint(x: 2, y: 2), in: rendered))
        XCTAssertLessThan(corner.red, 0.9, "Corner should show the gradient backdrop, not the white image")
    }

    func testColorBackdropFillsCorners() throws {
        let source = try XCTUnwrap(makeSolidImage(width: 400, height: 400, gray: 1.0))
        let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)
        let rendered = try XCTUnwrap(
            BeautifyRenderer.render(image: source, backdrop: .color(red), style: ExportStyle())
        )

        // sRGB gamut-maps pure red slightly, so green/blue aren't exactly 0.
        let corner = try XCTUnwrap(pixel(at: CGPoint(x: 2, y: 2), in: rendered))
        XCTAssertGreaterThan(corner.red, 0.9)
        XCTAssertLessThan(corner.green, 0.25)
        XCTAssertLessThan(corner.blue, 0.25)
    }

    func testNonAutoAspectExpandsCanvas() throws {
        let source = try XCTUnwrap(makeSolidImage(width: 400, height: 400, gray: 1.0))
        var style = ExportStyle()
        style.aspect = .widescreen
        let rendered = try XCTUnwrap(
            BeautifyRenderer.render(image: source, backdrop: .color(RGBA(red: 0, green: 0, blue: 0, alpha: 1)), style: style)
        )

        // Padded 464² canvas expands to 16:9; height stays, width grows.
        XCTAssertEqual(rendered.height, 464)
        XCTAssertEqual(rendered.width, Int((464.0 * 16.0 / 9.0).rounded()))
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
