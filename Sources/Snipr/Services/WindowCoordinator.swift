import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class WindowCoordinator {
    let captureStore: CaptureStore
    let preferences: SniprPreferences
    private let captureService = ScreenCaptureService()
    private let recordingService = ScreenRecordingService()
    private var commandPalettePanel: NSPanel?
    private var thumbnailPanel: NSPanel?
    private var thumbnailHideTask: Task<Void, Never>?
    private var isThumbnailStackHovered = false
    var isThumbnailStackPinned = false
    private var previewWindows: [UUID: NSWindow] = [:]
    private var overlayWindows: [NSWindow] = []
    private var recordingHUDPanel: NSPanel?
    private var recordingRegionFramePanel: NSPanel?
    private var activeRecordingDisplayID: CGDirectDisplayID?

    init(captureStore: CaptureStore, preferences: SniprPreferences) {
        self.captureStore = captureStore
        self.preferences = preferences
    }

    func showCommandPalette() {
        if let commandPalettePanel {
            commandPalettePanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(
            rootView: CommandPaletteView { [weak self] command in
                self?.hideCommandPalette()
                self?.execute(command)
            }
        )
        center(panel)
        commandPalettePanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideCommandPalette() {
        commandPalettePanel?.orderOut(nil)
        commandPalettePanel = nil
    }

    func execute(_ command: SniprCommand) {
        switch command.id {
        case .captureArea:
            startCaptureArea()
        case .recordArea:
            startScreenRecordingArea()
        case .openHistory:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        case .clearStack:
            clearStack()
        case .openSettings:
            openSettingsWindow()
        case .quit:
            NSApp.terminate(nil)
        }
    }

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

    func startScreenRecordingArea() {
        guard !recordingService.isRecording else {
            return
        }

        guard PermissionService.hasScreenRecordingAccess || PermissionService.requestScreenRecordingAccess() else {
            PermissionService.openScreenRecordingSettings()
            return
        }

        showCaptureOverlays(mode: .recording)
    }

    func startCaptureArea() {
        guard PermissionService.hasScreenRecordingAccess || PermissionService.requestScreenRecordingAccess() else {
            PermissionService.openScreenRecordingSettings()
            return
        }

        showCaptureOverlays(mode: .screenshot)
    }

    func showThumbnailStack() {
        guard preferences.showStackAfterCapture || thumbnailPanel != nil else {
            return
        }

        thumbnailHideTask?.cancel()
        thumbnailPanel?.orderOut(nil)

        guard !captureStore.items.isEmpty, let screen = NSScreen.main else {
            thumbnailPanel = nil
            return
        }

        let visibleItemCount = max(1, captureStore.items.prefix(6).count)
        let size = NSSize(width: 220, height: min(560, 48 + visibleItemCount * 136))
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.minY + 24
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ThumbnailStackView(store: captureStore, coordinator: self))
        thumbnailPanel = panel
        panel.orderFrontRegardless()
        scheduleThumbnailAutoHide()
    }

    func hideThumbnailStack() {
        thumbnailHideTask?.cancel()
        thumbnailHideTask = nil
        thumbnailPanel?.orderOut(nil)
        thumbnailPanel = nil
        isThumbnailStackHovered = false
        isThumbnailStackPinned = false
    }

    func setThumbnailStackPinned(_ isPinned: Bool) {
        isThumbnailStackPinned = isPinned
        if isPinned {
            thumbnailHideTask?.cancel()
            thumbnailHideTask = nil
        } else {
            scheduleThumbnailAutoHide()
        }
    }

    func setThumbnailStackHovering(_ isHovered: Bool) {
        isThumbnailStackHovered = isHovered

        guard preferences.pauseStackAutoHideOnHover, preferences.autoHideStack, !isThumbnailStackPinned else {
            return
        }

        if isHovered {
            thumbnailHideTask?.cancel()
            thumbnailHideTask = nil
        } else {
            scheduleThumbnailAutoHide(delay: 2)
        }
    }

    func openPreview(for item: CaptureItem) {
        guard item.mediaType == .image else {
            NSWorkspace.shared.open(item.fileURL)
            if preferences.hideStackAfterPreview, !isThumbnailStackPinned {
                hideThumbnailStack()
            }
            return
        }

        if let window = previewWindows[item.id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = item.filename
        window.contentView = NSHostingView(rootView: PreviewWindowView(item: item, coordinator: self))
        window.center()
        previewWindows[item.id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if preferences.hideStackAfterPreview, !isThumbnailStackPinned {
            hideThumbnailStack()
        }
    }

    func copy(_ item: CaptureItem) {
        ImageTransfer.copy(item)
    }

    func saveAs(_ item: CaptureItem) {
        ImageTransfer.saveAs(item)
    }

    func reveal(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    func delete(_ item: CaptureItem) {
        do {
            try captureStore.delete(item)
            previewWindows[item.id]?.close()
            previewWindows[item.id] = nil
            showThumbnailStack()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func clearStack() {
        do {
            try captureStore.clear()
            hideThumbnailStack()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func stopScreenRecording() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let recordedVideo = try await self.recordingService.stop()
                self.closeRecordingHUD()
                _ = try self.captureStore.addRecording(
                    fileURL: recordedVideo.fileURL,
                    pixelSize: recordedVideo.pixelSize,
                    displayID: self.activeRecordingDisplayID,
                    duration: recordedVideo.duration
                )
                self.activeRecordingDisplayID = nil
                self.showThumbnailStack()
            } catch {
                self.activeRecordingDisplayID = nil
                self.closeRecordingHUD()
                NSAlert(error: error).runModal()
            }
        }
    }

    func cancelScreenRecording() {
        recordingService.cancel()
        activeRecordingDisplayID = nil
        closeRecordingHUD()
    }

    private func scheduleThumbnailAutoHide(delay explicitDelay: Double? = nil) {
        thumbnailHideTask?.cancel()

        guard preferences.autoHideStack,
              !isThumbnailStackPinned,
              !(preferences.pauseStackAutoHideOnHover && isThumbnailStackHovered),
              thumbnailPanel != nil else {
            return
        }

        let delay = max(1, explicitDelay ?? preferences.stackAutoHideDelay)
        thumbnailHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self,
                  !self.isThumbnailStackPinned,
                  !(self.preferences.pauseStackAutoHideOnHover && self.isThumbnailStackHovered) else {
                return
            }

            self.hideThumbnailStack()
        }
    }

    private func showCaptureOverlays(mode: CaptureOverlayMode) {
        closeCaptureOverlays()

        for screen in NSScreen.screens {
            guard let displayID = screen.sniprDisplayID else {
                continue
            }

            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.contentView = NSHostingView(
                rootView: CaptureOverlayView(
                    screen: screen,
                    onComplete: { [weak self] rect in
                        self?.completeSelection(mode: mode, displayID: displayID, screen: screen, rect: rect)
                    },
                    onCancel: { [weak self] in
                        self?.closeCaptureOverlays()
                    }
                )
            )

            overlayWindows.append(window)
            window.orderFrontRegardless()
        }
    }

    private func completeSelection(mode: CaptureOverlayMode, displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        switch mode {
        case .screenshot:
            completeCapture(displayID: displayID, screen: screen, rect: rect)
        case .recording:
            startRecording(displayID: displayID, screen: screen, rect: rect)
        }
    }

    private func completeCapture(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        closeCaptureOverlays()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            self?.storeCapture(displayID: displayID, screen: screen, rect: rect)
        }
    }

    private func storeCapture(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        do {
            let capturedImage = try captureService.capture(displayID: displayID, rectInDisplayPoints: rect, screen: screen)
            _ = try captureStore.addCapture(
                pngData: capturedImage.pngData,
                pixelSize: capturedImage.pixelSize,
                displayID: displayID
            )
            showThumbnailStack()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func startRecording(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        closeCaptureOverlays()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: 120_000_000)

            do {
                let destinationURL = try self.captureStore.nextRecordingURL()
                try self.recordingService.start(displayID: displayID, rectInDisplayPoints: rect, screen: screen, destinationURL: destinationURL)
                self.activeRecordingDisplayID = displayID
                self.showRecordingRegionFrame(screen: screen, rect: rect)
                self.showRecordingHUD()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func showRecordingRegionFrame(screen: NSScreen, rect: CGRect) {
        closeRecordingRegionFrame()

        let frameRect = NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let panel = NSPanel(
            contentRect: frameRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: RecordingRegionFrameView(size: rect.size))
        recordingRegionFramePanel = panel
        panel.orderFrontRegardless()
    }

    private func showRecordingHUD() {
        closeRecordingHUD()

        guard let screen = NSScreen.main else {
            return
        }

        let size = NSSize(width: 246, height: 58)
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.maxY - size.height - 24
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(
            rootView: RecordingHUDView(
                startedAt: Date(),
                onStop: { [weak self] in
                    self?.stopScreenRecording()
                },
                onCancel: { [weak self] in
                    self?.cancelScreenRecording()
                }
            )
        )
        recordingHUDPanel = panel
        panel.orderFrontRegardless()
    }

    private func closeRecordingHUD() {
        recordingHUDPanel?.orderOut(nil)
        recordingHUDPanel?.close()
        recordingHUDPanel = nil
        closeRecordingRegionFrame()
    }

    private func closeRecordingRegionFrame() {
        recordingRegionFramePanel?.orderOut(nil)
        recordingRegionFramePanel?.close()
        recordingRegionFramePanel = nil
    }

    private func closeCaptureOverlays() {
        overlayWindows.forEach { window in
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }

    private func center(_ panel: NSPanel) {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            ))
        } else {
            panel.center()
        }
    }
}

private enum CaptureOverlayMode {
    case screenshot
    case recording
}
