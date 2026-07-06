import AppKit
import Foundation
import Observation
import SwiftUI

/// Owns the floating "Pin" reference panels — one per pinned `CaptureItem`.
/// Each panel is borderless, always-on-top, draggable, and accepts scroll-wheel
/// alpha control (Phase 3 differentiator). Right-click reveals a menu with
/// Unpin, Copy, Save, and an Always-on-Top toggle.
@MainActor
@Observable
final class PinPresenter {
    static let opacityKey = "pin.lastOpacity"
    static let minAlpha: CGFloat = 0.2
    static let maxAlpha: CGFloat = 1.0

    private var panels: [UUID: PinPanel] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Pure math used by the scroll wheel handler — exposed for testing.
    static func clampedAlpha(_ alpha: CGFloat) -> CGFloat {
        min(max(alpha, minAlpha), maxAlpha)
    }

    /// Apply a delta scroll value to a current alpha. Inverted Y so scrolling
    /// up makes the pinned image more opaque.
    static func adjustedAlpha(current: CGFloat, scrollDeltaY: CGFloat) -> CGFloat {
        clampedAlpha(current + scrollDeltaY * 0.02)
    }

    func pin(item: CaptureItem, onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        guard panels[item.id] == nil else {
            if let panel = panels[item.id] {
                panel.makeKeyAndOrderFront(nil)
            }
            return
        }

        guard let image = NSImage(contentsOf: item.fileURL) else {
            SniprDiagnostics.windowing.error("PinPresenter pin failed imageLoad itemID=\(item.id.uuidString, privacy: .public)")
            return
        }

        let lastOpacity = persistedOpacity()
        let panel = PinPanel(
            image: image,
            initialAlpha: lastOpacity,
            onCopy: onCopy,
            onSave: onSave,
            onOpacityChanged: { [weak self] alpha in
                self?.persistOpacity(alpha)
            },
            onUnpin: { [weak self] in
                self?.unpin(itemID: item.id)
            }
        )
        SniprDiagnostics.disableRestoration(for: panel)
        panels[item.id] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func unpin(itemID: UUID) {
        guard let panel = panels.removeValue(forKey: itemID) else { return }
        panel.contentView = nil
        panel.orderOut(nil)
        panel.close()
    }

    func unpinAll() {
        for (_, panel) in panels {
            panel.contentView = nil
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
    }

    func persistedOpacity() -> CGFloat {
        let stored = defaults.object(forKey: Self.opacityKey) as? Double ?? Double(Self.maxAlpha)
        return Self.clampedAlpha(CGFloat(stored))
    }

    private func persistOpacity(_ alpha: CGFloat) {
        defaults.set(Double(Self.clampedAlpha(alpha)), forKey: Self.opacityKey)
    }
}

/// Borderless floating panel that shows a pinned image. Implemented in
/// AppKit because we need precise control over key-window behavior, alpha
/// per-window (not per-view), scroll wheel events, and right-click menu —
/// SwiftUI windows don't expose any of these cleanly.
final class PinPanel: NSPanel {
    private let imageView = NSImageView()
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onOpacityChanged: (CGFloat) -> Void
    private let onUnpin: () -> Void
    private var isAlwaysOnTop = true

    init(
        image: NSImage,
        initialAlpha: CGFloat,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onOpacityChanged: @escaping (CGFloat) -> Void,
        onUnpin: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        self.onSave = onSave
        self.onOpacityChanged = onOpacityChanged
        self.onUnpin = onUnpin

        let initialSize = Self.preferredSize(for: image)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        alphaValue = PinPresenter.clampedAlpha(initialAlpha)

        let host = PinHostView(frame: NSRect(origin: .zero, size: initialSize))
        host.wantsLayer = true
        host.layer?.cornerRadius = 6
        host.layer?.masksToBounds = true
        host.imageView = imageView
        host.onScroll = { [weak self] dy in self?.handleScroll(dy: dy) }
        host.onRightClick = { [weak self] in self?.showContextMenu() }

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = host.bounds
        imageView.autoresizingMask = [.width, .height]
        host.addSubview(imageView)

        contentView = host
        center()
    }

    override var canBecomeKey: Bool { true }

    private func handleScroll(dy: CGFloat) {
        let next = PinPresenter.adjustedAlpha(current: alphaValue, scrollDeltaY: dy)
        alphaValue = next
        onOpacityChanged(next)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Unpin", action: #selector(unpinAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copyAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Save…", action: #selector(saveAction), keyEquivalent: ""))
        let toggle = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        toggle.state = isAlwaysOnTop ? .on : .off
        menu.addItem(toggle)
        for item in menu.items {
            item.target = self
        }
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? imageView)
        }
    }

    @objc private func unpinAction() { onUnpin() }
    @objc private func copyAction() { onCopy() }
    @objc private func saveAction() { onSave() }
    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        level = isAlwaysOnTop ? .floating : .normal
    }

    private static func preferredSize(for image: NSImage) -> CGSize {
        let pixel = image.size
        let maxSide: CGFloat = 480
        if pixel.width <= maxSide && pixel.height <= maxSide {
            return CGSize(width: max(120, pixel.width), height: max(80, pixel.height))
        }
        let scale = min(maxSide / pixel.width, maxSide / pixel.height)
        return CGSize(width: pixel.width * scale, height: pixel.height * scale)
    }
}

private final class PinHostView: NSView {
    weak var imageView: NSImageView?
    var onScroll: ((CGFloat) -> Void)?
    var onRightClick: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
