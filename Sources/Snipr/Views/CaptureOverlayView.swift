import AppKit
import SwiftUI

struct CaptureOverlayView: NSViewRepresentable {
    let screen: NSScreen
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureSelectionNSView {
        let view = CaptureSelectionNSView()
        view.onComplete = onComplete
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: CaptureSelectionNSView, context: Context) {
        nsView.onComplete = onComplete
        nsView.onCancel = onCancel
    }
}

final class CaptureSelectionNSView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selectionRect else {
            return
        }

        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)

        NSColor.systemCyan.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2
        path.stroke()

        drawDimensions(for: selectionRect)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let selectionRect, selectionRect.width >= 4, selectionRect.height >= 4 else {
            onCancel?()
            return
        }

        onComplete?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func drawDimensions(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72)
        ]
        let size = text.size(withAttributes: attributes)
        let point = CGPoint(x: rect.minX, y: max(8, rect.minY - size.height - 8))
        text.draw(at: point, withAttributes: attributes)
    }
}
