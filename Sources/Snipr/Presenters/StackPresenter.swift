import AppKit
import Observation
import SwiftUI

/// Owns the floating thumbnail stack panel and its hover/pin/auto-hide state.
/// `WindowCoordinator` is constructed with this presenter and forwards its
/// `showThumbnailStack` / `hideThumbnailStack` calls so views that already
/// reference the coordinator don't churn.
@MainActor
@Observable
final class StackPresenter {
    private(set) var isPinned = false
    private var isHovered = false
    private var thumbnailPanel: NSPanel?
    private var thumbnailHideTask: Task<Void, Never>?

    let captureStore: CaptureStore
    let preferences: SniprPreferences

    /// Provider for the SwiftUI body so the presenter is testable without
    /// reaching into the real `WindowCoordinator`.
    var contentProvider: (() -> AnyView)?

    init(captureStore: CaptureStore, preferences: SniprPreferences) {
        self.captureStore = captureStore
        self.preferences = preferences
    }

    func show() {
        guard preferences.showStackAfterCapture || thumbnailPanel != nil else {
            return
        }

        thumbnailHideTask?.cancel()
        thumbnailPanel?.orderOut(nil)

        guard !captureStore.items.isEmpty,
              let screen = NSScreen.main,
              let contentProvider else {
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
        panel.contentView = NSHostingView(rootView: contentProvider())
        thumbnailPanel = panel
        panel.orderFrontRegardless()
        scheduleAutoHide()
    }

    func hide() {
        thumbnailHideTask?.cancel()
        thumbnailHideTask = nil
        thumbnailPanel?.orderOut(nil)
        thumbnailPanel = nil
        isHovered = false
        isPinned = false
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            thumbnailHideTask?.cancel()
            thumbnailHideTask = nil
        } else {
            scheduleAutoHide()
        }
    }

    func setHovering(_ hovered: Bool) {
        isHovered = hovered

        guard preferences.pauseStackAutoHideOnHover, preferences.autoHideStack, !isPinned else {
            return
        }

        if hovered {
            thumbnailHideTask?.cancel()
            thumbnailHideTask = nil
        } else {
            scheduleAutoHide(delay: 2)
        }
    }

    /// Whether hiding the stack after opening a preview is appropriate. The
    /// preview presenter consults this so we don't auto-hide a pinned stack.
    var shouldHideAfterPreview: Bool {
        preferences.hideStackAfterPreview && !isPinned
    }

    private func scheduleAutoHide(delay explicitDelay: Double? = nil) {
        thumbnailHideTask?.cancel()

        guard preferences.autoHideStack,
              !isPinned,
              !(preferences.pauseStackAutoHideOnHover && isHovered),
              thumbnailPanel != nil else {
            return
        }

        let delay = max(1, explicitDelay ?? preferences.stackAutoHideDelay)
        thumbnailHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self,
                  !self.isPinned,
                  !(self.preferences.pauseStackAutoHideOnHover && self.isHovered) else {
                return
            }

            self.hide()
        }
    }
}
