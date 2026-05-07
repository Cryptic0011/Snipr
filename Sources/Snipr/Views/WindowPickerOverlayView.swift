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
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let hovered else { return }

        // Punch a clear hole through the dim layer so the hovered window
        // shows through full-brightness, then tint with system blue. This
        // mirrors macOS Screenshot.app's window-pick highlight.
        NSColor.clear.setFill()
        hovered.frame.fill(using: .copy)

        let path = NSBezierPath(rect: hovered.frame)
        NSColor.systemBlue.withAlphaComponent(0.28).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 3
        path.stroke()

        drawLabel(for: hovered)
    }

    private func drawLabel(for entry: WindowEntry) {
        let primary = entry.appName ?? "Window"
        let secondary = entry.title ?? ""
        let text = "📷  " + (secondary.isEmpty ? primary : "\(primary) — \(secondary)")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()

        let pillPadding = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        let pillSize = NSSize(
            width: textSize.width + pillPadding.left + pillPadding.right,
            height: textSize.height + pillPadding.top + pillPadding.bottom
        )
        // Default to placing the label above the window; if the window is
        // near the top edge, slot it inside the top of the window instead.
        var origin = CGPoint(
            x: max(8, entry.frame.minX),
            y: entry.frame.minY - pillSize.height - 8
        )
        if origin.y < 8 {
            origin.y = entry.frame.minY + 8
        }

        let pillRect = CGRect(origin: origin, size: pillSize)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.82).setFill()
        pillPath.fill()

        attributed.draw(at: CGPoint(
            x: origin.x + pillPadding.left,
            y: origin.y + pillPadding.top
        ))
    }

    private func windowAt(point: CGPoint) -> WindowEntry? {
        // Topmost-first list is supplied; first hit wins.
        windows.first { $0.frame.contains(point) }
    }
}
