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

    var highlightedWindowID: CGWindowID? {
        hovered?.scWindowID
    }

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

    func setWindows(_ entries: [WindowEntry], excludingWindowIDs excludedIDs: Set<CGWindowID> = []) {
        // Sort topmost-first so the picker honors window stacking.
        windows = entries.filter { !excludedIDs.contains($0.scWindowID) && $0.appName != "Dock" }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let entry = windowEntry(at: point) else {
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
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        guard let hovered else { return }

        NSColor.clear.setFill()
        hovered.frame.fill(using: .copy)

        drawWindowFrame(hovered.frame)
        drawLabel(for: hovered)
    }

    private func drawWindowFrame(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor.white.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.46).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawLabel(for entry: WindowEntry) {
        let text = Self.labelText(for: entry)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()

        let pillPadding = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        let maxPillWidth = max(44, min(bounds.width - 16, 420))
        let pillSize = NSSize(
            width: min(textSize.width + pillPadding.left + pillPadding.right, maxPillWidth),
            height: textSize.height + pillPadding.top + pillPadding.bottom
        )

        var origin = CGPoint(
            x: min(max(8, entry.frame.minX), max(8, bounds.maxX - pillSize.width - 8)),
            y: entry.frame.minY - pillSize.height - 8
        )
        if origin.y < 8 {
            origin.y = entry.frame.minY + 8
        }

        let pillRect = CGRect(origin: origin, size: pillSize)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.78).setFill()
        pillPath.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        pillPath.lineWidth = 0.5
        pillPath.stroke()

        attributed.draw(in: CGRect(
            x: origin.x + pillPadding.left,
            y: origin.y + pillPadding.top,
            width: pillSize.width - pillPadding.left - pillPadding.right,
            height: textSize.height
        ))
    }

    static func labelText(for entry: WindowEntry) -> String {
        let primary = entry.appName ?? "Window"
        guard let title = entry.title, !title.isEmpty else {
            return primary
        }
        return "\(primary) - \(title)"
    }

    func windowEntry(at point: CGPoint) -> WindowEntry? {
        // Topmost-first list is supplied; first hit wins.
        windows.first { $0.frame.contains(point) }
    }

    func updateHover(at point: CGPoint) {
        hovered = windowEntry(at: point)
        needsDisplay = true
    }

    func clearHover() {
        hovered = nil
        needsDisplay = true
    }
}
