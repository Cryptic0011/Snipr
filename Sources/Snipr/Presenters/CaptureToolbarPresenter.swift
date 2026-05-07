import AppKit
import SwiftUI

/// Lightweight helper that owns the floating capture-toolbar panel. Sibling
/// of `CommandPalettePresenter` — both are extracted so `WindowCoordinator`
/// stays focused on routing.
@MainActor
final class CaptureToolbarPresenter {
    private weak var coordinator: WindowCoordinator?
    private var panel: NSPanel?

    init(coordinator: WindowCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        guard let coordinator, let screen = NSScreen.main else {
            return
        }

        let size = NSSize(width: 720, height: 58)
        let origin = NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 34
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
        panel.hasShadow = false
        panel.contentView = NSHostingView(
            rootView: CaptureToolbarView(
                onCancel: { [weak self] in
                    self?.hide()
                },
                onOptions: { [weak coordinator] in
                    coordinator?.openSettingsWindow()
                },
                onExecute: { [weak coordinator] mode in
                    coordinator?.executeCaptureToolbarMode(mode)
                }
            )
        )
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
