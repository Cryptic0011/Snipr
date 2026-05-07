import XCTest
@testable import Snipr

final class ColorPickerTests: XCTestCase {
    func testHexFormatting() {
        XCTAssertEqual(
            ColorPicker.format(red: 1.0, green: 1.0, blue: 1.0, format: .hex),
            "#FFFFFF"
        )
        XCTAssertEqual(
            ColorPicker.format(red: 0, green: 0, blue: 0, format: .hex),
            "#000000"
        )
        XCTAssertEqual(
            ColorPicker.format(red: 0.5, green: 0.0, blue: 0.5, format: .hex),
            "#800080"
        )
    }

    func testRGBFormatting() {
        XCTAssertEqual(
            ColorPicker.format(red: 1.0, green: 0.5, blue: 0.0, format: .rgb),
            "rgb(255, 128, 0)"
        )
    }

    func testHSLFormatting() {
        // Pure red = hsl(0, 100%, 50%)
        XCTAssertEqual(
            ColorPicker.format(red: 1.0, green: 0.0, blue: 0.0, format: .hsl),
            "hsl(0, 100%, 50%)"
        )
        // Pure green = hsl(120, 100%, 50%)
        XCTAssertEqual(
            ColorPicker.format(red: 0.0, green: 1.0, blue: 0.0, format: .hsl),
            "hsl(120, 100%, 50%)"
        )
        // Pure blue = hsl(240, 100%, 50%)
        XCTAssertEqual(
            ColorPicker.format(red: 0.0, green: 0.0, blue: 1.0, format: .hsl),
            "hsl(240, 100%, 50%)"
        )
        // Black is l=0, s=0
        XCTAssertEqual(
            ColorPicker.format(red: 0, green: 0, blue: 0, format: .hsl),
            "hsl(0, 0%, 0%)"
        )
    }

    func testRGBToHSLRoundTripsHueRange() {
        let (h, s, l) = ColorPicker.rgbToHSL(r: 0.2, g: 0.4, b: 0.6)
        XCTAssertGreaterThanOrEqual(h, 0)
        XCTAssertLessThan(h, 360)
        XCTAssertGreaterThanOrEqual(s, 0)
        XCTAssertLessThanOrEqual(s, 1)
        XCTAssertGreaterThanOrEqual(l, 0)
        XCTAssertLessThanOrEqual(l, 1)
    }

    func testSamplePixel() throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context.makeImage())

        let sample = try XCTUnwrap(ColorPicker.sample(image: image, at: CGPoint(x: 2, y: 2)))
        XCTAssertEqual(sample.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(sample.green, 0.0, accuracy: 0.01)
        XCTAssertEqual(sample.blue, 0.0, accuracy: 0.01)
    }
}
