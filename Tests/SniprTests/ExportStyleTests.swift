import XCTest
@testable import Snipr

final class ExportStyleTests: XCTestCase {
    func testAutoCanvasMatchesPaddedSize() {
        let style = ExportStyle()   // defaults: 0.08, auto
        let (canvas, padding) = style.canvas(for: CGSize(width: 640, height: 360))
        XCTAssertEqual(padding, 29)                    // round(360 * 0.08)
        XCTAssertEqual(canvas, CGSize(width: 698, height: 418))
    }

    func testZeroPaddingMeansNoPadding() {
        var style = ExportStyle()
        style.paddingFraction = 0
        let (canvas, padding) = style.canvas(for: CGSize(width: 640, height: 360))
        XCTAssertEqual(padding, 0)
        XCTAssertEqual(canvas, CGSize(width: 640, height: 360))
    }

    func testAspectExpansionOnlyGrows() {
        var style = ExportStyle()
        style.paddingFraction = 0

        // 640×360 is already 16:9 → widescreen changes nothing
        style.aspect = .widescreen
        XCTAssertEqual(style.canvas(for: CGSize(width: 640, height: 360)).canvas,
                       CGSize(width: 640, height: 360))

        // Square canvas for a wide video grows height, keeps width
        style.aspect = .square
        XCTAssertEqual(style.canvas(for: CGSize(width: 640, height: 360)).canvas,
                       CGSize(width: 640, height: 640))

        // Portrait 9:16 for a wide video grows height
        style.aspect = .portrait
        let portrait = style.canvas(for: CGSize(width: 640, height: 360)).canvas
        XCTAssertEqual(portrait.width, 640)
        XCTAssertEqual(portrait.height, (640.0 / (9.0 / 16.0)).rounded(), accuracy: 1)

        // Widescreen for a tall video grows width
        let tall = style.canvas(for: CGSize(width: 360, height: 640)).canvas
        style.aspect = .widescreen
        let wide = style.canvas(for: CGSize(width: 360, height: 640)).canvas
        XCTAssertEqual(wide.height, tall.height)
        XCTAssertEqual(wide.width, (640.0 * (16.0 / 9.0)).rounded(), accuracy: 1)
        XCTAssertGreaterThan(wide.width, 360)
    }

    func testPersistenceRoundTrip() throws {
        let suite = "ExportStyleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ExportStyle.load(from: defaults), ExportStyle())  // defaults when unset

        var style = ExportStyle()
        style.paddingFraction = 0.2
        style.cornerRadius = 30
        style.shadowOpacity = 0.8
        style.aspect = .square
        style.save(to: defaults)
        XCTAssertEqual(ExportStyle.load(from: defaults), style)
    }
}
