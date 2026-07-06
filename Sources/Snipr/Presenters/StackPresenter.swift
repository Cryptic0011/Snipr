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
    private(set) var isExpanded = false
    private var isHovered = false
    private var thumbnailPanel: NSPanel?
    private var thumbnailHideTask: Task<Void, Never>?
    // Notification tokens. We capture them in a nonisolated holder so
    // `deinit` (which runs in a nonisolated context under Swift 6 strict
    // concurrency) can remove them without crossing the actor boundary.
    private let observerBox = NotificationObserverBox()

    let captureStore: CaptureStore
    let preferences: SniprPreferences

    /// Provider for the SwiftUI body so the presenter is testable without
    /// reaching into the real `WindowCoordinator`.
    var contentProvider: (() -> AnyView)?

    /// Reports whether `windowID` belongs to a preview window opened by
    /// `PreviewPresenter`. Consulted on `NSWindow.didBecomeKey` so we can
    /// pause auto-hide while the user is actively annotating.
    var isPreviewWindow: ((NSWindow) -> Bool)?

    /// Collapsed pile geometry — Raycast-style small footprint in the corner.
    private static let pileSize = NSSize(width: 232, height: 168)
    /// Expanded sidebar geometry — vertical list with quick actions.
    private static let expandedSize = NSSize(width: 304, height: 568)

    init(captureStore: CaptureStore, preferences: SniprPreferences) {
        self.captureStore = captureStore
        self.preferences = preferences
        installPreviewKeyObservers()
    }

    deinit {
        observerBox.removeAll()
    }

    /// Standard show — respects `showStackAfterCapture` and stays a no-op
    /// when there's nothing to show. Used by the post-capture flow.
    func show() {
        guard preferences.showStackAfterCapture || thumbnailPanel != nil else {
            return
        }
        present()
    }

    /// `showThumbnailStack` hotkey path. Always restores the panel even if
    /// the user previously dismissed a pinned-closed stack — that's the
    /// "restore even if pinned closed" requirement from the Phase 2 brief.
    func forceShow() {
        present()
    }

    func hide() {
        thumbnailHideTask?.cancel()
        thumbnailHideTask = nil
        closeThumbnailPanel()
        isHovered = false
        isPinned = false
        isExpanded = false
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
        // SwiftUI fires a spurious `.onHover(false)` while the panel is
        // resizing between pile/expanded states, even when the cursor never
        // leaves. Reject it if the cursor is still inside the panel frame.
        let effective = hovered || cursorIsInsidePanel
        let wasHovered = isHovered
        isHovered = effective
        if effective != isExpanded {
            setExpanded(effective)
        }

        guard preferences.pauseStackAutoHideOnHover, preferences.autoHideStack, !isPinned else {
            return
        }

        if effective {
            thumbnailHideTask?.cancel()
            thumbnailHideTask = nil
        } else if wasHovered {
            // True hover-out (we were hovered, cursor really has left).
            scheduleAutoHide(delay: 2)
        }
    }

    /// Whether hiding the stack after opening a preview is appropriate. The
    /// preview presenter consults this so we don't auto-hide a pinned stack.
    var shouldHideAfterPreview: Bool {
        preferences.hideStackAfterPreview && !isPinned
    }

    /// Drives the pile↔sidebar size transition. Public so tests can drive
    /// it without faking AppKit hover events.
    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        guard let panel = thumbnailPanel,
              let screen = NSScreen.main else { return }
        let target = expanded ? Self.expandedSize : Self.pileSize
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - target.width - 24,
            y: screen.visibleFrame.minY + 24
        )
        panel.setFrame(NSRect(origin: origin, size: target), display: true, animate: false)
        if expanded {
            panel.makeKey()
        }
    }

    private func present() {
        thumbnailHideTask?.cancel()

        guard !captureStore.items.isEmpty,
              let screen = NSScreen.main,
              let contentProvider else {
            closeThumbnailPanel()
            return
        }

        if let panel = thumbnailPanel {
            panel.contentView = NSHostingView(rootView: contentProvider())
            panel.orderFrontRegardless()
            scheduleAutoHide()
            return
        }

        let size = isExpanded ? Self.expandedSize : Self.pileSize
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.minY + 24
        )
        let panel = StackPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        SniprDiagnostics.disableRestoration(for: panel)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: contentProvider())
        thumbnailPanel = panel
        panel.orderFrontRegardless()
        scheduleAutoHide()
    }

    private func closeThumbnailPanel() {
        guard let panel = thumbnailPanel else { return }
        panel.contentView = nil
        panel.orderOut(nil)
        panel.close()
        thumbnailPanel = nil
    }

    private func installPreviewKeyObservers() {
        let center = NotificationCenter.default
        // The notification's `object` is an `NSWindow` which is `MainActor`
        // owned in practice. The strict-concurrency checker can't see that,
        // so we extract the pointer identity and re-resolve on the main
        // actor before touching it.
        let becomeKey = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let windowRef = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self,
                      let window = windowRef,
                      self.isPreviewWindow?(window) == true else { return }
                self.thumbnailHideTask?.cancel()
                self.thumbnailHideTask = nil
            }
        }
        let resignKey = center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let windowRef = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self,
                      let window = windowRef,
                      self.isPreviewWindow?(window) == true else { return }
                self.scheduleAutoHide()
            }
        }
        observerBox.set(tokens: [becomeKey, resignKey])
    }

    private func scheduleAutoHide(delay explicitDelay: Double? = nil) {
        thumbnailHideTask?.cancel()

        guard preferences.autoHideStack,
              !isPinned,
              !(preferences.pauseStackAutoHideOnHover && isHovered),
              thumbnailPanel != nil,
              !isPreviewWindowKey else {
            return
        }

        let delay = max(1, explicitDelay ?? preferences.stackAutoHideDelay)
        thumbnailHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // A cancelled Task continues past `try?`, which would otherwise
            // run `hide()` even though a newer scheduleAutoHide call meant to
            // replace this one. Bail early on cancellation.
            if Task.isCancelled { return }
            guard let self,
                  !self.isPinned,
                  !(self.preferences.pauseStackAutoHideOnHover && self.isHovered),
                  !self.isPreviewWindowKey,
                  !self.cursorIsInsidePanel else {
                return
            }

            self.hide()
        }
    }

    /// True when the cursor is currently inside the stack panel's frame, even
    /// if SwiftUI's `.onHover` reported a false transition. The expansion
    /// animation can re-identify the hovered view and deliver a spurious
    /// `.onHover(false)` while the cursor never actually left.
    private var cursorIsInsidePanel: Bool {
        guard let panel = thumbnailPanel else { return false }
        let mouse = NSEvent.mouseLocation
        return panel.frame.contains(mouse)
    }

    private var isPreviewWindowKey: Bool {
        guard let isPreview = isPreviewWindow,
              let key = NSApp.keyWindow else { return false }
        return isPreview(key)
    }
}

/// Holds notification observer tokens so they can be removed from a
/// nonisolated `deinit`. `NotificationCenter.removeObserver` is
/// thread-safe, and `NSObjectProtocol` tokens are opaque — `@unchecked
/// Sendable` is fine here. // reason: nonisolated cleanup of opaque tokens
/// across actor-isolated owners.
private final class NotificationObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    func set(tokens newTokens: [NSObjectProtocol]) {
        lock.lock()
        defer { lock.unlock() }
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        tokens = newTokens
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        tokens = []
    }
}

/// `NSPanel` subclass that opts in to becoming key while keeping the
/// `.nonactivatingPanel` behavior. Required so the expanded sidebar can
/// receive keyDown events (arrows, Enter, Cmd+C, Del) without bringing
/// the app forward.
private final class StackPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
