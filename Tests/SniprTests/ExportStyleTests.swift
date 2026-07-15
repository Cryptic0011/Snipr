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

        // Baseline: a 360×640 video is already portrait, so .portrait (still
        // set from above) leaves its height untouched — used below to
        // confirm switching to .widescreen grows width only.
        let tallBaseline = style.canvas(for: CGSize(width: 360, height: 640)).canvas

        // Widescreen for a tall video grows width, keeps height
        style.aspect = .widescreen
        let wide = style.canvas(for: CGSize(width: 360, height: 640)).canvas
        XCTAssertEqual(wide.height, tallBaseline.height)
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

    /// A hand-edited/corrupted defaults blob (e.g. paddingFraction ≤ -0.5)
    /// must never reach `canvas(for:)` unclamped: a negative/zero canvas
    /// makes `AVAssetExportSession` throw an uncatchable
    /// NSInvalidArgumentException ("renderSize must be positive") and kill
    /// the process. `load()` must clamp every field to its UI range.
    func testLoadClampsHostileStoredValues() throws {
        let suite = "ExportStyleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let hostileJSON = """
        {"paddingFraction": -0.9, "cornerRadius": 500, "shadowOpacity": 7, "aspect": "auto"}
        """
        defaults.set(Data(hostileJSON.utf8), forKey: "videoExportStyle")

        let loaded = ExportStyle.load(from: defaults)
        XCTAssertEqual(loaded.paddingFraction, 0)
        XCTAssertEqual(loaded.cornerRadius, 40)
        XCTAssertEqual(loaded.shadowOpacity, 1)

        let (canvas, padding) = loaded.canvas(for: CGSize(width: 640, height: 360))
        XCTAssertGreaterThan(canvas.width, 0)
        XCTAssertGreaterThan(canvas.height, 0)
        XCTAssertGreaterThanOrEqual(padding, 0)
    }
}
