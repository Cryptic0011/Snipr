import AppKit
import XCTest
@testable import Snipr

final class VideoBackdropTests: XCTestCase {
    func testBundledWallpaperNamesAllResolveToImages() {
        XCTAssertEqual(VideoBackdrop.bundledWallpaperNames.count, 11)
        for name in VideoBackdrop.bundledWallpaperNames {
            XCTAssertNotNil(
                SniprAssets.wallpaper(named: name),
                "Missing bundled wallpaper resource: \(name)"
            )
        }
    }

    func testTitles() {
        XCTAssertEqual(VideoBackdrop.gradient(.ocean).title, "Ocean")
        XCTAssertEqual(VideoBackdrop.bundled("sonoma-horizon").title, "Sonoma Horizon")
        XCTAssertEqual(VideoBackdrop.wallpaper.title, "Desktop Wallpaper")
    }

    func testBundledResolvesImageAndGradientDoesNot() {
        XCTAssertNotNil(VideoBackdrop.bundled("sequoia-blue").resolveImage(for: nil))
        XCTAssertNil(VideoBackdrop.gradient(.brass).resolveImage(for: nil))
    }

    func testPickerGroupsCoverAllOptions() {
        let groups = VideoBackdrop.pickerGroups
        XCTAssertEqual(groups.map(\.label), ["Gradients", "Wallpapers", "Desktop"])
        XCTAssertEqual(groups[0].options.count, BeautifyStyle.allCases.count)
        XCTAssertEqual(groups[1].options.count, VideoBackdrop.bundledWallpaperNames.count)
        XCTAssertEqual(groups[2].options, [.wallpaper])
    }

    func testColorAndCustomImageCases() throws {
        let color = VideoBackdrop.color(RGBA(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(color.title, "Color")
        XCTAssertNil(color.resolveImage(for: nil))   // rendered as a fill, not an image

        // Custom image resolves from disk; a bundled wallpaper on disk works
        // as the fixture without adding test resources.
        let bundledURL = try XCTUnwrap(
            Bundle.module.url(forResource: "sequoia-blue", withExtension: "jpg")
        )
        let custom = VideoBackdrop.customImage(bundledURL)
        XCTAssertEqual(custom.title, "Custom Image")
        XCTAssertNotNil(custom.resolveImage(for: nil))
        XCTAssertNil(VideoBackdrop.customImage(URL(fileURLWithPath: "/nonexistent.png")).resolveImage(for: nil))
    }

    func testBackdropSelectionPersistenceRoundTrip() throws {
        let suite = "VideoBackdropTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(VideoBackdrop.loadSelection(from: defaults))

        for backdrop: VideoBackdrop in [
            .gradient(.ocean),
            .bundled("sonoma-dark"),
            .wallpaper,
            .color(RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            .customImage(URL(fileURLWithPath: "/tmp/x.png"))
        ] {
            VideoBackdrop.saveSelection(backdrop, to: defaults)
            XCTAssertEqual(VideoBackdrop.loadSelection(from: defaults), backdrop)
        }

        VideoBackdrop.saveSelection(nil, to: defaults)
        XCTAssertNil(VideoBackdrop.loadSelection(from: defaults))
    }

    func testPickerGroupsUnchangedByNewCases() {
        // Color/custom image live in dedicated UI rows, not the picker.
        XCTAssertEqual(VideoBackdrop.pickerGroups.flatMap(\.options).count,
                       BeautifyStyle.allCases.count + VideoBackdrop.bundledWallpaperNames.count + 1)
    }
}
