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

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showStackAfterCapture = defaults.object(forKey: Keys.showStackAfterCapture) as? Bool ?? true
        autoHideStack = defaults.object(forKey: Keys.autoHideStack) as? Bool ?? true
        stackAutoHideDelay = defaults.object(forKey: Keys.stackAutoHideDelay) as? Double ?? 8
        pauseStackAutoHideOnHover = defaults.object(forKey: Keys.pauseStackAutoHideOnHover) as? Bool ?? true
        hideStackAfterPreview = defaults.object(forKey: Keys.hideStackAfterPreview) as? Bool ?? true
    }

    func resetStackDefaults() {
        showStackAfterCapture = true
        autoHideStack = true
        stackAutoHideDelay = 8
        pauseStackAutoHideOnHover = true
        hideStackAfterPreview = true
    }
}
