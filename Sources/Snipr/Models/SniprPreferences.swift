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
        static let didEnableScrollingCapture = "didEnableScrollingCapture"
        static let copyToClipboardOnCapture = "copyToClipboardOnCapture"
        static let saveToDiskOnCapture = "saveToDiskOnCapture"
        static let showCaptureMagnifier = "showCaptureMagnifier"
        static let captureFormat = "captureFormat"
        static let captureFilenameTemplate = "captureFilenameTemplate"
        static let colorOutputFormat = "colorOutputFormat"
        static let recordSystemAudio = "recordSystemAudio"
        static let smartFolderRules = "smartFolderRules"
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

    /// Phase 1: copy each capture to the clipboard automatically.
    var copyToClipboardOnCapture: Bool {
        didSet { defaults.set(copyToClipboardOnCapture, forKey: Keys.copyToClipboardOnCapture) }
    }

    /// Phase 1: persist captures to the filesystem-backed stack. When this is
    /// false the capture is clipboard-only and never lands in the stack.
    var saveToDiskOnCapture: Bool {
        didSet { defaults.set(saveToDiskOnCapture, forKey: Keys.saveToDiskOnCapture) }
    }

    var showCaptureMagnifier: Bool {
        didSet { defaults.set(showCaptureMagnifier, forKey: Keys.showCaptureMagnifier) }
    }

    /// Phase 1: encoded format new captures land on disk / clipboard as.
    var captureFormat: CaptureFormat {
        didSet { saveCaptureFormat() }
    }

    /// Phase 1: token-driven naming template (see `CaptureFilenameTemplate`).
    var captureFilenameTemplate: String {
        didSet { defaults.set(captureFilenameTemplate, forKey: Keys.captureFilenameTemplate) }
    }

    /// Phase 3: format used by the pixel-sampler / color picker hotkey.
    var colorOutputFormat: ColorOutputFormat {
        didSet { defaults.set(colorOutputFormat.rawValue, forKey: Keys.colorOutputFormat) }
    }

    /// Phase 3: include system audio in screen recordings.
    var recordSystemAudio: Bool {
        didSet { defaults.set(recordSystemAudio, forKey: Keys.recordSystemAudio) }
    }

    /// Phase 4: app-name → subfolder routing rules. Rules are evaluated in
    /// order; first match wins. Empty array means "no routing, captures land
    /// in the existing `Images/` root".
    var smartFolderRules: [SmartFolderRule] {
        didSet { saveSmartFolderRules() }
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
        copyToClipboardOnCapture = defaults.object(forKey: Keys.copyToClipboardOnCapture) as? Bool ?? true
        saveToDiskOnCapture = defaults.object(forKey: Keys.saveToDiskOnCapture) as? Bool ?? true
        showCaptureMagnifier = defaults.object(forKey: Keys.showCaptureMagnifier) as? Bool ?? false
        captureFormat = Self.loadCaptureFormat(from: defaults)
        captureFilenameTemplate = (defaults.object(forKey: Keys.captureFilenameTemplate) as? String)
            ?? CaptureFilenameTemplate.defaultTemplate
        colorOutputFormat = ColorOutputFormat(
            rawValue: defaults.string(forKey: Keys.colorOutputFormat) ?? ""
        ) ?? .hex
        recordSystemAudio = defaults.object(forKey: Keys.recordSystemAudio) as? Bool ?? false
        smartFolderRules = Self.loadSmartFolderRules(from: defaults)
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

    private func saveCaptureFormat() {
        guard let data = try? JSONEncoder().encode(captureFormat) else { return }
        defaults.set(data, forKey: Keys.captureFormat)
    }

    private static func loadHotKeyBindings(from defaults: UserDefaults) -> [SniprHotKeyAction: HotKeyBinding] {
        guard let data = defaults.data(forKey: Keys.hotKeyBindings),
              let stored = try? JSONDecoder().decode([SniprHotKeyAction: HotKeyBinding].self, from: data) else {
            return HotKeyDefaults.bindings
        }

        var merged = HotKeyDefaults.bindings.merging(stored) { _, stored in stored }

        // One-shot migration: scrolling capture shipped disabled while its SCK
        // frame source was broken, so existing installs persisted a disabled
        // binding that would otherwise shadow the new enabled default forever.
        if !defaults.bool(forKey: Keys.didEnableScrollingCapture) {
            defaults.set(true, forKey: Keys.didEnableScrollingCapture)
            if merged[.scrollingCapture]?.isEnabled == false,
               let defaultBinding = HotKeyDefaults.bindings[.scrollingCapture] {
                merged[.scrollingCapture] = defaultBinding
            }
        }

        return merged
    }

    private func saveSmartFolderRules() {
        guard let data = try? JSONEncoder().encode(smartFolderRules) else { return }
        defaults.set(data, forKey: Keys.smartFolderRules)
    }

    private static func loadSmartFolderRules(from defaults: UserDefaults) -> [SmartFolderRule] {
        guard let data = defaults.data(forKey: Keys.smartFolderRules),
              let stored = try? JSONDecoder().decode([SmartFolderRule].self, from: data) else {
            return []
        }
        return stored
    }

    private static func loadCaptureFormat(from defaults: UserDefaults) -> CaptureFormat {
        guard let data = defaults.data(forKey: Keys.captureFormat),
              let stored = try? JSONDecoder().decode(CaptureFormat.self, from: data) else {
            return .default
        }
        return stored
    }
}
