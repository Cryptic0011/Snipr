import Carbon
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

    @MainActor
    func testHotKeyPreferencesPersist() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SniprPreferences(defaults: defaults)
        preferences.setHotKeyBinding(
            HotKeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: hotKeyModifiers(command: true, option: true), isEnabled: true),
            for: .captureArea
        )

        let reloaded = SniprPreferences(defaults: defaults)
        let binding = reloaded.binding(for: .captureArea)

        XCTAssertEqual(binding.keyCode, UInt32(kVK_ANSI_A))
        XCTAssertEqual(binding.modifiers, hotKeyModifiers(command: true, option: true))
        XCTAssertTrue(binding.isEnabled)
    }

    @MainActor
    func testHotKeyConflictDetectionIgnoresDisabledBindings() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SniprPreferences(defaults: defaults)
        let duplicate = preferences.binding(for: .captureArea)

        XCTAssertEqual(preferences.conflictingAction(for: .commandPalette, binding: duplicate), .captureArea)

        var disabledDuplicate = duplicate
        disabledDuplicate.isEnabled = false
        XCTAssertNil(preferences.conflictingAction(for: .commandPalette, binding: disabledDuplicate))
    }

    @MainActor
    func testResetHotKeyDefaultsRestoresDefaultBindings() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SniprPreferences(defaults: defaults)
        preferences.setHotKeyBinding(
            HotKeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: hotKeyModifiers(command: true), isEnabled: true),
            for: .captureArea
        )

        preferences.resetHotKeyDefaults()

        XCTAssertEqual(preferences.binding(for: .captureArea), HotKeyDefaults.bindings[.captureArea])
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SniprPreferencesTests-\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
