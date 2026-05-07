import XCTest
@testable import Snipr

final class CaptureFilenameTemplateTests: XCTestCase {
    private let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 7
        components.hour = 14
        components.minute = 30
        components.second = 5
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    func testDateAndTimeTokensExpand() {
        let result = CaptureFilenameTemplate.expand(
            template: "Snipr {date} {time}",
            date: referenceDate,
            appName: nil,
            windowTitle: nil,
            pixelSize: CGSize(width: 800, height: 600),
            sequence: 1,
            fileExtension: "png",
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(result, "Snipr 2026-05-07 14-30-05.png")
    }

    func testMissingAppTokenCollapsesWhitespace() {
        let result = CaptureFilenameTemplate.expand(
            template: "{app} shot {seq}",
            date: referenceDate,
            appName: nil,
            windowTitle: nil,
            pixelSize: CGSize(width: 100, height: 100),
            sequence: 7,
            fileExtension: "png",
            timeZone: TimeZone(identifier: "UTC")!
        )
        // Empty {app} + collapsed whitespace produces "shot 0007".
        XCTAssertEqual(result, "shot 0007.png")
    }

    func testSequenceTokenZeroPads() {
        let result = CaptureFilenameTemplate.expand(
            template: "Cap {seq}",
            date: referenceDate,
            appName: nil,
            windowTitle: nil,
            pixelSize: CGSize(width: 1, height: 1),
            sequence: 42,
            fileExtension: "jpg",
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(result, "Cap 0042.jpg")
    }

    func testWidthHeightTokens() {
        let result = CaptureFilenameTemplate.expand(
            template: "{w}x{h}",
            date: referenceDate,
            appName: nil,
            windowTitle: nil,
            pixelSize: CGSize(width: 1920, height: 1080),
            sequence: 0,
            fileExtension: "png",
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(result, "1920x1080.png")
    }

    func testSanitizesForbiddenCharacters() {
        let result = CaptureFilenameTemplate.expand(
            template: "{app} {window}",
            date: referenceDate,
            appName: "Web/Browser",
            windowTitle: "Tab: \"hello\"",
            pixelSize: .zero,
            sequence: 0,
            fileExtension: "png",
            timeZone: TimeZone(identifier: "UTC")!
        )
        // `/`, `:`, `"` all replaced with `-`.
        XCTAssertFalse(result.contains("/"))
        XCTAssertFalse(result.contains(":"))
        XCTAssertFalse(result.contains("\""))
        XCTAssertTrue(result.hasSuffix(".png"))
    }

    func testEmptyTemplateFallsBackToSnipr() {
        let result = CaptureFilenameTemplate.expand(
            template: "{app}",
            date: referenceDate,
            appName: nil,
            windowTitle: nil,
            pixelSize: .zero,
            sequence: 0,
            fileExtension: "heic",
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(result, "Snipr.heic")
    }
}
