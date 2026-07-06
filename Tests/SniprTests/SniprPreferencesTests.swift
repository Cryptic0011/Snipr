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

    @MainActor
    func testCapturePreferenceDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SniprPreferences(defaults: defaults)
        XCTAssertTrue(preferences.copyToClipboardOnCapture)
        XCTAssertTrue(preferences.saveToDiskOnCapture)
        XCTAssertFalse(preferences.showCaptureMagnifier)
        XCTAssertEqual(preferences.captureFormat, .png)
        XCTAssertEqual(preferences.captureFilenameTemplate, "Snipr {date} {time}")
    }

    @MainActor
    func testCapturePreferencesPersistAndReload() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SniprPreferences(defaults: defaults)
        preferences.copyToClipboardOnCapture = false
        preferences.saveToDiskOnCapture = false
        preferences.showCaptureMagnifier = true
        preferences.captureFormat = .jpeg(quality: 0.7)
        preferences.captureFilenameTemplate = "{app} {date}"

        let reloaded = SniprPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.copyToClipboardOnCapture)
        XCTAssertFalse(reloaded.saveToDiskOnCapture)
        XCTAssertTrue(reloaded.showCaptureMagnifier)
        XCTAssertEqual(reloaded.captureFormat, .jpeg(quality: 0.7))
        XCTAssertEqual(reloaded.captureFilenameTemplate, "{app} {date}")
    }

    @MainActor
    func testScrollingCaptureReEnableMigrationRunsOnce() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Simulate an install that persisted the old disabled default.
        let preferences = SniprPreferences(defaults: defaults)
        var legacy = preferences.binding(for: .scrollingCapture)
        legacy.isEnabled = false
        preferences.setHotKeyBinding(legacy, for: .scrollingCapture)
        defaults.removeObject(forKey: "didEnableScrollingCapture")

        // First reload migrates the stale disabled binding to the new default.
        let migrated = SniprPreferences(defaults: defaults)
        XCTAssertTrue(migrated.binding(for: .scrollingCapture).isEnabled)

        // A user who disables it afterwards stays disabled — one-shot only.
        var disabled = migrated.binding(for: .scrollingCapture)
        disabled.isEnabled = false
        migrated.setHotKeyBinding(disabled, for: .scrollingCapture)
        let reloaded = SniprPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.binding(for: .scrollingCapture).isEnabled)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "SniprPreferencesTests-\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
