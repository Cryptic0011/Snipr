import AppKit
import SwiftUI

/// Lightweight helper that owns the floating command-palette panel. Kept
/// outside `WindowCoordinator` so the coordinator stays close to the 150-line
/// router budget without losing the lifecycle in inline closures.
@MainActor
final class CommandPalettePresenter {
    private weak var coordinator: WindowCoordinator?
    private var panel: NSPanel?

    init(coordinator: WindowCoordinator) {
        self.coordinator = coordinator
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let coordinator else {
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        SniprDiagnostics.disableRestoration(for: panel)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        // ignoresSafeArea: NSHostingView otherwise insets the content below
        // the (transparent) titlebar, leaving a backdrop band above the card
        // whose edge reads as a line across the palette.
        panel.contentView = NSHostingView(
            rootView: CommandPaletteView(
                hotKeyBindings: coordinator.preferences.hotKeyBindings,
                onExecute: { [weak self, weak coordinator] command in
                    self?.hide()
                    coordinator?.execute(command)
                },
                onExecuteWorkflow: { [weak self, weak coordinator] workflow in
                    self?.hide()
                    coordinator?.runWorkflow(workflow)
                }
            )
            .ignoresSafeArea()
        )

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            ))
        } else {
            panel.center()
        }

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        guard let panel else { return }
        panel.contentView = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }
}
