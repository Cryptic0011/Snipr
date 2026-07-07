import AppKit
import SwiftUI

/// Transient confirmation pill near the top of the main screen. Haptic
/// feedback is invisible on desktops without a trackpad, so clipboard
/// actions flash this as well.
@MainActor
enum ToastPresenter {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.close()
        panel = nil
    }

    static func show(_ message: String, systemImage: String = "checkmark.circle.fill") {
        dismissTask?.cancel()
        panel?.close()
        panel = nil

        let content = HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
            Text(message)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())

        let hosting = NSHostingView(rootView: content)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        // Keep toasts out of captures and recordings — the self-timer
        // countdown would otherwise photobomb its own shot.
        panel.sharingType = .none
        panel.contentView = hosting
        SniprDiagnostics.disableRestoration(for: panel)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - panel.frame.height - 24
            ))
        }
        panel.orderFrontRegardless()
        Self.panel = panel

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // A cancelled sleep falls through — never close the panel a
            // newer toast now owns (same race as the stack auto-hide fix).
            guard !Task.isCancelled, Self.panel === panel else { return }
            panel.close()
            Self.panel = nil
        }
    }
}
