import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Per-screen window-picker overlay. Highlights the topmost window under the
/// cursor with a tint + label (app name, window title) and reports the click
/// back to the presenter.
final class WindowPickerNSView: NSView {
    /// Snapshot of one on-screen window the picker can highlight. Frame is
    /// already in this overlay's coordinate space (top-left origin, points).
    struct WindowEntry: Sendable {
        let frame: CGRect
        let scWindowID: CGWindowID
        let title: String?
        let appName: String?
    }

    var onPick: ((WindowEntry, CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var windows: [WindowEntry] = []
    private var hovered: WindowEntry?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func setWindows(_ entries: [WindowEntry]) {
        // Sort topmost-first so the picker honors window stacking.
        windows = entries
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hovered = windowAt(point: point)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let entry = windowAt(point: point) else {
            onCancel?()
            return
        }
        onPick?(entry, entry.frame)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        guard let hovered else { return }

        let path = NSBezierPath(rect: hovered.frame)
        NSColor.systemCyan.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.systemCyan.setStroke()
        path.lineWidth = 2
        path.stroke()

        drawLabel(for: hovered)
    }

    private func drawLabel(for entry: WindowEntry) {
        let primary = entry.appName ?? "Window"
        let secondary = entry.title ?? ""
        let text = secondary.isEmpty ? primary : "\(primary) — \(secondary)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.78)
        ]
        let textSize = text.size(withAttributes: attributes)
        let origin = CGPoint(
            x: max(8, entry.frame.minX),
            y: max(8, entry.frame.minY - textSize.height - 8)
        )
        text.draw(at: origin, withAttributes: attributes)
    }

    private func windowAt(point: CGPoint) -> WindowEntry? {
        // Topmost-first list is supplied; first hit wins.
        windows.first { $0.frame.contains(point) }
    }
}
