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
}
