import Foundation
import Observation

@MainActor
@Observable
final class SniprPreferences {
    private enum Keys {
        static let showStackAfterCapture = "showStackAfterCapture"
        static let autoHideStack = "autoHideStack"
        static let stackAutoHideDelay = "stackAutoHideDelay"
        static let pauseStackAutoHideOnHover = "pauseStackAutoHideOnHover"
        static let hideStackAfterPreview = "hideStackAfterPreview"
        static let hotKeyBindings = "hotKeyBindings"
    }

    var showStackAfterCapture: Bool {
        didSet { defaults.set(showStackAfterCapture, forKey: Keys.showStackAfterCapture) }
    }

    var autoHideStack: Bool {
        didSet { defaults.set(autoHideStack, forKey: Keys.autoHideStack) }
    }

    var stackAutoHideDelay: Double {
        didSet { defaults.set(stackAutoHideDelay, forKey: Keys.stackAutoHideDelay) }
    }

    var pauseStackAutoHideOnHover: Bool {
        didSet { defaults.set(pauseStackAutoHideOnHover, forKey: Keys.pauseStackAutoHideOnHover) }
    }

    var hideStackAfterPreview: Bool {
        didSet { defaults.set(hideStackAfterPreview, forKey: Keys.hideStackAfterPreview) }
    }

    var hotKeyBindings: [SniprHotKeyAction: HotKeyBinding] {
        didSet { saveHotKeyBindings() }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showStackAfterCapture = defaults.object(forKey: Keys.showStackAfterCapture) as? Bool ?? true
        autoHideStack = defaults.object(forKey: Keys.autoHideStack) as? Bool ?? true
        stackAutoHideDelay = defaults.object(forKey: Keys.stackAutoHideDelay) as? Double ?? 8
        pauseStackAutoHideOnHover = defaults.object(forKey: Keys.pauseStackAutoHideOnHover) as? Bool ?? true
        hideStackAfterPreview = defaults.object(forKey: Keys.hideStackAfterPreview) as? Bool ?? true
        hotKeyBindings = Self.loadHotKeyBindings(from: defaults)
    }

    func resetStackDefaults() {
        showStackAfterCapture = true
        autoHideStack = true
        stackAutoHideDelay = 8
        pauseStackAutoHideOnHover = true
        hideStackAfterPreview = true
    }

    func binding(for action: SniprHotKeyAction) -> HotKeyBinding {
        hotKeyBindings[action] ?? HotKeyDefaults.bindings[action] ?? HotKeyBinding(keyCode: 0, modifiers: 0, isEnabled: false)
    }

    func setHotKeyBinding(_ binding: HotKeyBinding, for action: SniprHotKeyAction) {
        hotKeyBindings[action] = binding
    }

    func resetHotKeyDefaults() {
        hotKeyBindings = HotKeyDefaults.bindings
    }

    func conflictingAction(for action: SniprHotKeyAction, binding: HotKeyBinding) -> SniprHotKeyAction? {
        guard binding.isEnabled else {
            return nil
        }

        return hotKeyBindings.first { candidateAction, candidateBinding in
            candidateAction != action &&
                candidateBinding.isEnabled &&
                candidateBinding.keyCode == binding.keyCode &&
                candidateBinding.modifiers == binding.modifiers
        }?.key
    }

    private func saveHotKeyBindings() {
        guard let data = try? JSONEncoder().encode(hotKeyBindings) else {
            return
        }

        defaults.set(data, forKey: Keys.hotKeyBindings)
    }

    private static func loadHotKeyBindings(from defaults: UserDefaults) -> [SniprHotKeyAction: HotKeyBinding] {
        guard let data = defaults.data(forKey: Keys.hotKeyBindings),
              let stored = try? JSONDecoder().decode([SniprHotKeyAction: HotKeyBinding].self, from: data) else {
            return HotKeyDefaults.bindings
        }

        return HotKeyDefaults.bindings.merging(stored) { _, stored in stored }
    }
}
