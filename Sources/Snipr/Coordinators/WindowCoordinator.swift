import AppKit
import Observation
import SwiftUI

/// Router that forwards capture / record / preview commands to the appropriate
/// presenter. Heavy lifting lives in `Presenters/*`; this file stays small
/// enough to scan in one screen.
@MainActor
@Observable
final class WindowCoordinator {
    let captureStore: CaptureStore
    let preferences: SniprPreferences
    let captureEngine: CaptureEngine
    let overlayPresenter: OverlayPresenter
    let stackPresenter: StackPresenter
    let recordingPresenter: RecordingPresenter
    let previewPresenter: PreviewPresenter
    let captureFlowPresenter: CaptureFlowPresenter
    private var commandPalettePresenter: CommandPalettePresenter?
    private var captureToolbarPresenter: CaptureToolbarPresenter?

    init(
        captureStore: CaptureStore,
        preferences: SniprPreferences,
        captureEngine: CaptureEngine,
        recordingEngine: RecordingEngine
    ) {
        self.captureStore = captureStore
        self.preferences = preferences
        self.captureEngine = captureEngine
        self.overlayPresenter = OverlayPresenter()
        self.stackPresenter = StackPresenter(captureStore: captureStore, preferences: preferences)
        self.recordingPresenter = RecordingPresenter(recordingEngine: recordingEngine, captureStore: captureStore)
        self.previewPresenter = PreviewPresenter(captureStore: captureStore)
        self.captureFlowPresenter = CaptureFlowPresenter(captureStore: captureStore, captureEngine: captureEngine)
        wirePresenters()
    }

    func execute(_ command: SniprCommand) {
        switch command.id {
        case .captureArea: startCaptureArea()
        case .recordArea: startScreenRecordingArea()
        case .captureToolbar: showCaptureToolbar()
        case .openHistory:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        case .clearStack: clearStack()
        case .openSettings: openSettingsWindow()
        case .quit: NSApp.terminate(nil)
        }
    }

    func executeCaptureToolbarMode(_ mode: CaptureToolbarMode) {
        hideCaptureToolbar()
        switch mode {
        case .captureScreen: startCaptureFullScreen()
        case .captureWindow: showWindowCaptureComingSoon()
        case .captureSelection: startCaptureArea()
        case .recordScreen: startScreenRecordingFullScreen()
        case .recordSelection: startScreenRecordingArea()
        }
    }

    func startCaptureArea() {
        guard captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        overlayPresenter.showCaptureOverlays(mode: .screenshot)
    }

    func startScreenRecordingArea() {
        guard !recordingPresenter.isRecording, captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        overlayPresenter.showCaptureOverlays(mode: .recording)
    }

    func startCaptureFullScreen() {
        guard captureFlowPresenter.ensureScreenRecordingAccess(),
              let screen = NSScreen.main, let displayID = screen.sniprDisplayID else { return }
        captureFlowPresenter.completeCapture(displayID: displayID, screen: screen, rect: CGRect(origin: .zero, size: screen.frame.size))
    }

    func startScreenRecordingFullScreen() {
        guard !recordingPresenter.isRecording, captureFlowPresenter.ensureScreenRecordingAccess(),
              let screen = NSScreen.main, let displayID = screen.sniprDisplayID else { return }
        recordingPresenter.start(displayID: displayID, screen: screen, rect: CGRect(origin: .zero, size: screen.frame.size))
    }

    func showThumbnailStack() { stackPresenter.show() }
    func hideThumbnailStack() { stackPresenter.hide() }
    func setThumbnailStackPinned(_ pinned: Bool) { stackPresenter.setPinned(pinned) }
    func setThumbnailStackHovering(_ hovered: Bool) { stackPresenter.setHovering(hovered) }
    var isThumbnailStackPinned: Bool { stackPresenter.isPinned }

    func openPreview(for item: CaptureItem) { previewPresenter.openPreview(for: item) }
    func copy(_ item: CaptureItem) { ImageTransfer.copy(item) }
    func saveAs(_ item: CaptureItem) { ImageTransfer.saveAs(item) }
    func reveal(_ item: CaptureItem) { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }

    func delete(_ item: CaptureItem) {
        previewPresenter.delete(item)
        showThumbnailStack()
    }

    func clearStack() {
        do { try captureStore.clear(); hideThumbnailStack() }
        catch { NSAlert(error: error).runModal() }
    }

    func stopScreenRecording() { recordingPresenter.stop() }
    func cancelScreenRecording() { recordingPresenter.cancel() }

    func showCommandPalette() {
        if commandPalettePresenter == nil { commandPalettePresenter = CommandPalettePresenter(coordinator: self) }
        commandPalettePresenter?.show()
    }
    func hideCommandPalette() { commandPalettePresenter?.hide() }

    func showCaptureToolbar() {
        if captureToolbarPresenter == nil { captureToolbarPresenter = CaptureToolbarPresenter(coordinator: self) }
        captureToolbarPresenter?.show()
    }
    func hideCaptureToolbar() { captureToolbarPresenter?.hide() }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Snipr" }) ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func wirePresenters() {
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
        captureFlowPresenter.onError = { error in NSAlert(error: error).runModal() }
        captureFlowPresenter.onCaptureStored = { [weak self] in self?.showThumbnailStack() }
    }

    private func handleSelection(mode: CaptureOverlayMode, displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        switch mode {
        case .screenshot:
            captureFlowPresenter.completeCapture(displayID: displayID, screen: screen, rect: rect)
        case .recording:
            recordingPresenter.start(displayID: displayID, screen: screen, rect: rect)
        }
    }

    func showWindowCaptureComingSoon() {
        let alert = NSAlert()
        alert.messageText = "Window Capture"
        alert.informativeText = "The toolbar option is in place. Window picking is the next capture mode to wire."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
