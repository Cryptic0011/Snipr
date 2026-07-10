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
        static let captureDelaySeconds = "captureDelaySeconds"
        static let freezeScreenDuringSelection = "freezeScreenDuringSelection"
        static let recordingFormat = "recordingFormat"
        static let recordMicrophone = "recordMicrophone"
        static let showInputOverlaysWhileRecording = "showInputOverlaysWhileRecording" // legacy combined toggle
        static let showKeystrokesWhileRecording = "showKeystrokesWhileRecording"
        static let showClicksWhileRecording = "showClicksWhileRecording"
        static let showWebcamWhileRecording = "showWebcamWhileRecording"
        static let webcamBubbleDiameter = "webcamBubbleDiameter"
        static let webcamBubbleBorderColor = "webcamBubbleBorderColor"
        static let recordingCustomCursor = "recordingCustomCursor"
        static let recordingCursorSmoothing = "recordingCursorSmoothing"
        static let recordingCursorScale = "recordingCursorScale"
        static let recordingCursorColor = "recordingCursorColor"
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

    /// Self-timer: seconds between committing a selection and the shot. 0 = off.
    var captureDelaySeconds: Int {
        didSet { defaults.set(captureDelaySeconds, forKey: Keys.captureDelaySeconds) }
    }

    /// Draw a still of the display behind the selection overlay so on-screen
    /// motion doesn't shift under the crosshair mid-drag.
    var freezeScreenDuringSelection: Bool {
        didSet { defaults.set(freezeScreenDuringSelection, forKey: Keys.freezeScreenDuringSelection) }
    }

    /// Container recordings are written into (.mov or .mp4).
    var recordingFormat: RecordingFileFormat {
        didSet { defaults.set(recordingFormat.rawValue, forKey: Keys.recordingFormat) }
    }

    /// Include the microphone in recordings. Only effective on macOS 15+,
    /// where ScreenCaptureKit exposes mic capture.
    var recordMicrophone: Bool {
        didSet { defaults.set(recordMicrophone, forKey: Keys.recordMicrophone) }
    }

    /// Show pressed keys on screen while recording (needs Input Monitoring).
    var showKeystrokesWhileRecording: Bool {
        didSet { defaults.set(showKeystrokesWhileRecording, forKey: Keys.showKeystrokesWhileRecording) }
    }

    /// Show click ripples on screen while recording.
    var showClicksWhileRecording: Bool {
        didSet { defaults.set(showClicksWhileRecording, forKey: Keys.showClicksWhileRecording) }
    }

    /// Float a circular webcam bubble on screen while recording.
    var showWebcamWhileRecording: Bool {
        didSet { defaults.set(showWebcamWhileRecording, forKey: Keys.showWebcamWhileRecording) }
    }

    /// Webcam bubble diameter in points.
    var webcamBubbleDiameter: Double {
        didSet { defaults.set(webcamBubbleDiameter, forKey: Keys.webcamBubbleDiameter) }
    }

    /// Webcam bubble border color preset.
    var webcamBubbleBorderColor: WebcamBorderColor {
        didSet { defaults.set(webcamBubbleBorderColor.rawValue, forKey: Keys.webcamBubbleBorderColor) }
    }

    /// Record with the system cursor hidden and bake a synthetic smoothed
    /// cursor into the file right after the recording stops.
    var recordingCustomCursor: Bool {
        didSet { defaults.set(recordingCustomCursor, forKey: Keys.recordingCustomCursor) }
    }

    /// Smooth the synthetic cursor's path (cubic interpolation over a
    /// thinned sample set). Off = raw 60 Hz path.
    var recordingCursorSmoothing: Bool {
        didSet { defaults.set(recordingCursorSmoothing, forKey: Keys.recordingCursorSmoothing) }
    }

    /// Synthetic cursor size multiplier (1.0–3.0).
    var recordingCursorScale: Double {
        didSet { defaults.set(recordingCursorScale, forKey: Keys.recordingCursorScale) }
    }

    /// Synthetic cursor tint preset.
    var recordingCursorColor: CursorColor {
        didSet { defaults.set(recordingCursorColor.rawValue, forKey: Keys.recordingCursorColor) }
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
        captureDelaySeconds = defaults.object(forKey: Keys.captureDelaySeconds) as? Int ?? 0
        freezeScreenDuringSelection = defaults.object(forKey: Keys.freezeScreenDuringSelection) as? Bool ?? false
        recordingFormat = RecordingFileFormat(
            rawValue: defaults.string(forKey: Keys.recordingFormat) ?? ""
        ) ?? .mov
        recordMicrophone = defaults.object(forKey: Keys.recordMicrophone) as? Bool ?? false
        // Migration: the combined "keystrokes and clicks" toggle seeds both.
        let legacyInputOverlays = defaults.object(forKey: Keys.showInputOverlaysWhileRecording) as? Bool ?? false
        showKeystrokesWhileRecording = defaults.object(forKey: Keys.showKeystrokesWhileRecording) as? Bool ?? legacyInputOverlays
        showClicksWhileRecording = defaults.object(forKey: Keys.showClicksWhileRecording) as? Bool ?? legacyInputOverlays
        showWebcamWhileRecording = defaults.object(forKey: Keys.showWebcamWhileRecording) as? Bool ?? false
        webcamBubbleDiameter = defaults.object(forKey: Keys.webcamBubbleDiameter) as? Double ?? 160
        webcamBubbleBorderColor = WebcamBorderColor(
            rawValue: defaults.string(forKey: Keys.webcamBubbleBorderColor) ?? ""
        ) ?? .white
        recordingCustomCursor = defaults.object(forKey: Keys.recordingCustomCursor) as? Bool ?? false
        recordingCursorSmoothing = defaults.object(forKey: Keys.recordingCursorSmoothing) as? Bool ?? true
        recordingCursorScale = defaults.object(forKey: Keys.recordingCursorScale) as? Double ?? 1.5
        recordingCursorColor = CursorColor(
            rawValue: defaults.string(forKey: Keys.recordingCursorColor) ?? ""
        ) ?? .white
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
