import Foundation
import Observation

@MainActor
@Observable
final class SniprAppModel {
    let captureStore: CaptureStore
    let preferences: SniprPreferences
    let coordinator: WindowCoordinator

    init() {
        let captureStore = CaptureStore()
        let preferences = SniprPreferences()
        self.captureStore = captureStore
        self.preferences = preferences
        self.coordinator = WindowCoordinator(captureStore: captureStore, preferences: preferences)
    }
}
