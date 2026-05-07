import Foundation
import Observation

@MainActor
@Observable
final class SniprAppModel {
    let captureStore: CaptureStore
    let preferences: SniprPreferences
    let coordinator: WindowCoordinator
    private var hotKeyService: HotKeyService?

    init(
        captureEngine: CaptureEngine = SCKCaptureEngine(),
        recordingEngine: RecordingEngine = SCKRecordingEngine()
    ) {
        let captureStore = CaptureStore()
        let preferences = SniprPreferences()
        self.captureStore = captureStore
        self.preferences = preferences
        self.coordinator = WindowCoordinator(
            captureStore: captureStore,
            preferences: preferences,
            captureEngine: captureEngine,
            recordingEngine: recordingEngine
        )
    }

    func installHotkeys() {
        if hotKeyService == nil {
            hotKeyService = HotKeyService { [weak self] action in
                self?.executeHotKey(action)
            }
        }

        hotKeyService?.register(preferences.hotKeyBindings)
    }

    func reinstallHotkeys() {
        installHotkeys()
    }

    func registrationFailure(for action: SniprHotKeyAction) -> OSStatus? {
        hotKeyService?.registrationFailures[action]
    }

    private func executeHotKey(_ action: SniprHotKeyAction) {
        switch action {
        case .openApp:
            coordinator.openMainWindow()
        case .captureArea:
            coordinator.startCaptureArea()
        case .captureToolbar:
            coordinator.showCaptureToolbar()
        case .screenRecord:
            coordinator.startScreenRecordingArea()
        case .commandPalette:
            coordinator.showCommandPalette()
        case .hideStack:
            coordinator.hideThumbnailStack()
        case .showStack:
            coordinator.showThumbnailStack()
        case .clearStack:
            coordinator.clearStack()
        }
    }
}
