import Foundation
import Observation

@MainActor
@Observable
final class SniprAppModel {
    let captureStore: CaptureStore
    let coordinator: WindowCoordinator

    init() {
        let captureStore = CaptureStore()
        self.captureStore = captureStore
        self.coordinator = WindowCoordinator(captureStore: captureStore)
    }
}
