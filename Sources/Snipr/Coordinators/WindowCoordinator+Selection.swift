import AppKit
import SwiftUI

/// Selection / capture / recording flow internals broken out so the
/// coordinator router stays under the 150-line budget.
@MainActor
extension WindowCoordinator {
    func wirePresenters() {
        overlayPresenter.onSelectionComplete = { [weak self] mode, displayID, screen, rect in
            self?.handleSelection(mode: mode, displayID: displayID, screen: screen, rect: rect)
        }
        stackPresenter.contentProvider = { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(ThumbnailStackView(store: self.captureStore, coordinator: self))
        }
        recordingPresenter.onRecordingFinished = { [weak self] in self?.showThumbnailStack() }
        recordingPresenter.onError = { error in NSAlert(error: error).runModal() }
        previewPresenter.contentProvider = { [weak self] item in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PreviewWindowView(item: item, coordinator: self))
        }
        previewPresenter.onPreviewOpened = { [weak self] in
            guard let self, self.stackPresenter.shouldHideAfterPreview else { return }
            self.hideThumbnailStack()
        }
        previewPresenter.onError = { error in NSAlert(error: error).runModal() }
    }

    func handleSelection(mode: CaptureOverlayMode, displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        switch mode {
        case .screenshot: completeCapture(displayID: displayID, screen: screen, rect: rect)
        case .recording: recordingPresenter.start(displayID: displayID, screen: screen, rect: rect)
        }
    }

    func completeCapture(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.storeCapture(displayID: displayID, screen: screen, rect: rect)
        }
    }

    func storeCapture(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) async {
        do {
            let captured = try await captureEngine.capture(displayID: displayID, rectInDisplayPoints: rect, screen: screen)
            _ = try captureStore.addCapture(pngData: captured.pngData, pixelSize: captured.pixelSize, displayID: displayID)
            showThumbnailStack()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func ensureScreenRecordingAccess() -> Bool {
        if PermissionService.hasScreenRecordingAccess || PermissionService.requestScreenRecordingAccess() {
            return true
        }
        PermissionService.openScreenRecordingSettings()
        return false
    }

    func showWindowCaptureComingSoon() {
        let alert = NSAlert()
        alert.messageText = "Window Capture"
        alert.informativeText = "The toolbar option is in place. Window picking is the next capture mode to wire."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
