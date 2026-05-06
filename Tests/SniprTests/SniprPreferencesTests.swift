import XCTest
@testable import Snipr

final class SniprPreferencesTests: XCTestCase {
    @MainActor
    func testStackPreferencesPersist() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SniprPreferences(defaults: defaults)
        preferences.showStackAfterCapture = false
        preferences.autoHideStack = false
        preferences.stackAutoHideDelay = 14
        preferences.pauseStackAutoHideOnHover = false
        preferences.hideStackAfterPreview = false

        let reloaded = SniprPreferences(defaults: defaults)

        XCTAssertFalse(reloaded.showStackAfterCapture)
        XCTAssertFalse(reloaded.autoHideStack)
        XCTAssertEqual(reloaded.stackAutoHideDelay, 14)
        XCTAssertFalse(reloaded.pauseStackAutoHideOnHover)
        XCTAssertFalse(reloaded.hideStackAfterPreview)
    }

    @MainActor
    func testResetStackDefaultsRestoresRecommendedBehavior() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SniprPreferences(defaults: defaults)
        preferences.showStackAfterCapture = false
        preferences.autoHideStack = false
        preferences.stackAutoHideDelay = 30
        preferences.pauseStackAutoHideOnHover = false
        preferences.hideStackAfterPreview = false

        preferences.resetStackDefaults()

        XCTAssertTrue(preferences.showStackAfterCapture)
        XCTAssertTrue(preferences.autoHideStack)
        XCTAssertEqual(preferences.stackAutoHideDelay, 8)
        XCTAssertTrue(preferences.pauseStackAutoHideOnHover)
        XCTAssertTrue(preferences.hideStackAfterPreview)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SniprPreferencesTests-\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
