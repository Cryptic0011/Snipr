import XCTest
@testable import Snipr

@MainActor
final class PinPresenterTests: XCTestCase {
    func testClampedAlphaClampsLow() {
        XCTAssertEqual(PinPresenter.clampedAlpha(0.05), PinPresenter.minAlpha)
    }

    func testClampedAlphaClampsHigh() {
        XCTAssertEqual(PinPresenter.clampedAlpha(2.0), PinPresenter.maxAlpha)
    }

    func testClampedAlphaPassesValuesInRange() {
        XCTAssertEqual(PinPresenter.clampedAlpha(0.5), 0.5)
    }

    func testAdjustedAlphaIncreasesOnPositiveScroll() {
        let next = PinPresenter.adjustedAlpha(current: 0.5, scrollDeltaY: 5)
        XCTAssertGreaterThan(next, 0.5)
        XCTAssertLessThanOrEqual(next, PinPresenter.maxAlpha)
    }

    func testAdjustedAlphaDecreasesOnNegativeScroll() {
        let next = PinPresenter.adjustedAlpha(current: 0.5, scrollDeltaY: -5)
        XCTAssertLessThan(next, 0.5)
        XCTAssertGreaterThanOrEqual(next, PinPresenter.minAlpha)
    }

    func testPersistedOpacityRoundTrips() {
        let suite = "pinPresenterTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(0.65, forKey: PinPresenter.opacityKey)
        let presenter = PinPresenter(defaults: defaults)
        XCTAssertEqual(presenter.persistedOpacity(), 0.65, accuracy: 0.001)
    }

    func testPersistedOpacityClampsStoredValue() {
        let suite = "pinPresenterTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(0.05, forKey: PinPresenter.opacityKey)
        let presenter = PinPresenter(defaults: defaults)
        XCTAssertEqual(presenter.persistedOpacity(), PinPresenter.minAlpha)
    }
}
