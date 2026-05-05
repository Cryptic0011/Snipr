import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    let captureStore: CaptureStore
    private let captureService = ScreenCaptureService()
    private var commandPalettePanel: NSPanel?
    private var thumbnailPanel: NSPanel?
    private var previewWindows: [UUID: NSWindow] = [:]
    private var overlayWindows: [NSWindow] = []

    init(captureStore: CaptureStore) {
        self.captureStore = captureStore
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
        case .openHistory:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        case .clearStack:
            clearStack()
        case .openSettings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        case .quit:
            NSApp.terminate(nil)
        }
    }

    func startCaptureArea() {
        guard PermissionService.hasScreenRecordingAccess || PermissionService.requestScreenRecordingAccess() else {
            PermissionService.openScreenRecordingSettings()
            return
        }

        showCaptureOverlays()
    }

    func showThumbnailStack() {
        thumbnailPanel?.orderOut(nil)

        guard !captureStore.items.isEmpty, let screen = NSScreen.main else {
            thumbnailPanel = nil
            return
        }

        let size = NSSize(width: 190, height: min(420, 118 + (captureStore.items.prefix(5).count - 1) * 24))
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
    }

    func openPreview(for item: CaptureItem) {
        if let window = previewWindows[item.id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
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
    }

    func copy(_ item: CaptureItem) {
        ImageTransfer.copyImage(at: item.fileURL)
    }

    func saveAs(_ item: CaptureItem) {
        ImageTransfer.saveImageAs(item)
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
            thumbnailPanel?.orderOut(nil)
            thumbnailPanel = nil
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func showCaptureOverlays() {
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
                        self?.completeCapture(displayID: displayID, screen: screen, rect: rect)
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

    private func completeCapture(displayID: CGDirectDisplayID, screen: NSScreen, rect: CGRect) {
        closeCaptureOverlays()

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

    private func closeCaptureOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
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
