import AppKit
import Observation
import ScreenCaptureKit
import SwiftUI

/// Router that forwards capture / record / preview commands to the appropriate
/// presenter. Heavy lifting lives in `Presenters/*`; this file stays small
/// enough to scan in one screen.
@MainActor
@Observable
final class WindowCoordinator {
    private enum WindowPickerPurpose {
        case capture
        case recording
        case scrollingCapture
    }

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

    let ocrHistory: OCRHistoryStore
    let pinPresenter: PinPresenter
    let translationEngine: any TranslationEngine
    let ocrEngine: any OCREngine
    let scrollingCapturePresenter: ScrollingCapturePresenter

    init(
        captureStore: CaptureStore,
        preferences: SniprPreferences,
        captureEngine: CaptureEngine,
        recordingEngine: RecordingEngine,
        ocrEngine: any OCREngine,
        ocrHistory: OCRHistoryStore,
        translationEngine: (any TranslationEngine)? = nil
    ) {
        self.captureStore = captureStore
        self.preferences = preferences
        self.captureEngine = captureEngine
        self.ocrHistory = ocrHistory
        self.ocrEngine = ocrEngine
        self.translationEngine = translationEngine ?? DefaultTranslationEngineFactory.makeDefault()
        self.pinPresenter = PinPresenter()
        self.scrollingCapturePresenter = ScrollingCapturePresenter(
            captureStore: captureStore,
            preferences: preferences
        )
        self.overlayPresenter = OverlayPresenter()
        self.stackPresenter = StackPresenter(captureStore: captureStore, preferences: preferences)
        self.recordingPresenter = RecordingPresenter(recordingEngine: recordingEngine, captureStore: captureStore, preferences: preferences)
        self.previewPresenter = PreviewPresenter(captureStore: captureStore)
        self.captureFlowPresenter = CaptureFlowPresenter(
            captureStore: captureStore,
            preferences: preferences,
            captureEngine: captureEngine,
            ocrEngine: ocrEngine,
            ocrHistory: ocrHistory
        )
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
        case .ocrSelection: startOCR()
        case .showOCRHistory: showOCRHistory()
        case .pickColor: startColorPick()
        case .scrollingCapture: startScrollingCapture()
        }
    }

    func executeCaptureToolbarMode(_ mode: CaptureToolbarMode) {
        hideCaptureToolbar()
        switch mode {
        case .captureScreen: startCaptureFullScreen()
        case .captureWindow: startWindowCapture()
        case .captureSelection: startCaptureArea()
        case .recordScreen: startScreenRecordingFullScreen()
        case .recordWindow: startWindowRecording()
        case .recordSelection: startScreenRecordingArea()
        case .ocrSelection: startOCR()
        case .pickColor: startColorPick()
        }
    }

    func startCaptureArea() {
        guard captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        overlayPresenter.showCaptureOverlays(mode: .screenshot, showMagnifier: preferences.showCaptureMagnifier)
    }

    func startScreenRecordingArea() {
        guard !recordingPresenter.isRecording, captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        overlayPresenter.showCaptureOverlays(mode: .recording, showMagnifier: preferences.showCaptureMagnifier)
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

    func startWindowCapture() {
        guard captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        windowPickerPurpose = .capture
        overlayPresenter.showWindowPickerOverlays()
    }

    func startWindowRecording() {
        guard !recordingPresenter.isRecording, captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        windowPickerPurpose = .recording
        overlayPresenter.showWindowPickerOverlays()
    }

    /// Phase 4 scrolling capture entry point. Reuses the Phase 1 window picker
    /// — once the user picks a window we hand the SCWindow + app name to
    /// `ScrollingCapturePresenter`, which streams frames at ~10 fps until the
    /// user clicks "Stitch Now" on the floating progress HUD.
    func startScrollingCapture() {
        guard captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        windowPickerPurpose = .scrollingCapture
        overlayPresenter.showWindowPickerOverlays()
    }

    private var windowPickerPurpose: WindowPickerPurpose = .capture

    func startOCR() {
        guard captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        overlayPresenter.showCaptureOverlays(mode: .ocr, showMagnifier: preferences.showCaptureMagnifier)
    }

    func startColorPick() {
        guard captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        overlayPresenter.showColorPickerOverlays { [weak self] result in
            guard let self else { return }
            let formatted = ColorPicker.format(
                red: result.red,
                green: result.green,
                blue: result.blue,
                format: self.preferences.colorOutputFormat
            )
            ClipboardSink.copyText(formatted)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func pin(_ item: CaptureItem) {
        pinPresenter.pin(item: item, onCopy: { [weak self] in self?.copy(item) },
                         onSave: { [weak self] in self?.saveAs(item) })
    }

    private var ocrHistoryWindow: NSWindow?
    private var ocrHistoryCloseObserver: NSObjectProtocol?

    func showOCRHistory() {
        if let window = ocrHistoryWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OCRHistoryView(coordinator: self, history: ocrHistory)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        SniprDiagnostics.disableRestoration(for: window)
        window.title = "OCR History"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        ocrHistoryWindow = window

        // Drop the cached reference when the user closes the window so the
        // next invocation rebuilds it (and observes the latest entries).
        ocrHistoryCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let observer = self.ocrHistoryCloseObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                self.ocrHistoryCloseObserver = nil
                self.ocrHistoryWindow = nil
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func recopyOCREntry(_ entry: OCRHistoryEntry) {
        ClipboardSink.copyText(entry.text)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func captureLastRegion() {
        guard captureFlowPresenter.ensureScreenRecordingAccess() else { return }
        captureFlowPresenter.captureLastRegion()
    }

    func showThumbnailStack() { stackPresenter.show() }
    /// Hotkey path: restore even if the user pinned the stack closed.
    func showThumbnailStackForced() { stackPresenter.forceShow() }
    func hideThumbnailStack() { stackPresenter.hide() }
    func setThumbnailStackPinned(_ pinned: Bool) { stackPresenter.setPinned(pinned) }
    func setThumbnailStackHovering(_ hovered: Bool) { stackPresenter.setHovering(hovered) }
    var isThumbnailStackPinned: Bool { stackPresenter.isPinned }
    var isThumbnailStackExpanded: Bool { stackPresenter.isExpanded }

    func openPreview(for item: CaptureItem) { previewPresenter.openPreview(for: item) }
    func copy(_ item: CaptureItem) { ImageTransfer.copy(item) }
    func saveAs(_ item: CaptureItem) { ImageTransfer.saveAs(item) }
    func reveal(_ item: CaptureItem) { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }

    func delete(_ item: CaptureItem) {
        previewPresenter.delete(item)
        showThumbnailStack()
    }

    func clearStack() {
        guard !captureStore.items.isEmpty else { hideThumbnailStack(); return }

        let alert = NSAlert()
        alert.messageText = "Clear the stack?"
        alert.informativeText = "This deletes all \(captureStore.items.count) captured files. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear Stack").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do { try captureStore.clear(); hideThumbnailStack() }
        catch { NSAlert(error: error).runModal() }
    }

    func stopScreenRecording() { recordingPresenter.stop() }
    func cancelScreenRecording() { recordingPresenter.cancel() }

    func showCommandPalette() {
        if commandPalettePresenter == nil { commandPalettePresenter = CommandPalettePresenter(coordinator: self) }
        commandPalettePresenter?.show()
    }
    func hideCommandPalette() {
        commandPalettePresenter?.hide()
    }

    func showCaptureToolbar() {
        if captureToolbarPresenter == nil { captureToolbarPresenter = CaptureToolbarPresenter(coordinator: self) }
        captureToolbarPresenter?.show()
    }
    func hideCaptureToolbar() {
        captureToolbarPresenter?.hide()
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Snipr" }) ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Restore the default overlay handlers after a workflow temporarily
    /// retargeted them. Workflows borrow the selection overlay for the
    /// `capture` step; once the user commits or cancels we hand the overlay
    /// back to the regular capture/recording/OCR routing here.
    func rewireOverlayHandlers() {
        wirePresenters()
    }

    func runWorkflow(_ workflow: Workflow) {
        let environment = CoordinatorWorkflowEnvironment(
            coordinator: self,
            captureEngine: captureEngine,
            ocrEngine: ocrEngine,
            translationEngine: translationEngine,
            captureStore: captureStore,
            preferences: preferences
        )
        let executor = WorkflowExecutor(environment: environment)
        Task { @MainActor [weak self] in
            do {
                _ = try await executor.run(workflow)
            } catch {
                self?.captureFlowPresenter.onError?(error)
            }
        }
    }

    private func wirePresenters() {
        overlayPresenter.onSelectionComplete = { [weak self] mode, displayID, screen, rect in
            self?.handleSelection(mode: mode, displayID: displayID, screen: screen, rect: rect)
        }
        overlayPresenter.onWindowPicked = { [weak self] entry, displayID, screen, rect in
            guard let self else { return }
            switch self.windowPickerPurpose {
            case .capture:
                self.captureFlowPresenter.captureWindow(
                    scWindowID: entry.scWindowID,
                    displayID: displayID,
                    windowTitle: entry.title,
                    appName: entry.appName
                )
            case .recording:
                self.windowPickerPurpose = .capture
                self.recordingPresenter.start(displayID: displayID, screen: screen, rect: rect)
            case .scrollingCapture:
                self.windowPickerPurpose = .capture
                self.startScrolling(entry: entry)
            }
        }
        overlayPresenter.onCancel = nil
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
        stackPresenter.isPreviewWindow = { [weak self] window in
            self?.previewPresenter.isPreviewWindow(window) ?? false
        }
        previewPresenter.onError = { error in NSAlert(error: error).runModal() }
        captureFlowPresenter.onError = { error in NSAlert(error: error).runModal() }
        captureFlowPresenter.onCaptureStored = { [weak self] in self?.showThumbnailStack() }
        scrollingCapturePresenter.onError = { error in NSAlert(error: error).runModal() }
        scrollingCapturePresenter.onCaptureStored = { [weak self] in self?.showThumbnailStack() }
    }

    private func startScrolling(entry: WindowPickerNSView.WindowEntry) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scWindow = content.windows.first(where: { $0.windowID == entry.scWindowID }) else {
                    self.captureFlowPresenter.onError?(ScreenCaptureError.displayNotFound)
                    return
                }
                self.scrollingCapturePresenter.start(scWindow: scWindow, appName: entry.appName)
            } catch {
                self.captureFlowPresenter.onError?(error)
            }
        }
    }

    private func handleSelection(mode: CaptureOverlayMode, displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        switch mode {
        case .screenshot:
            captureFlowPresenter.completeCapture(displayID: displayID, screen: screen, rect: rect)
        case .recording:
            recordingPresenter.start(displayID: displayID, screen: screen, rect: rect)
        case .ocr:
            captureFlowPresenter.runOCR(displayID: displayID, screen: screen, rect: rect)
        }
    }

}
