import AppKit
import CoreGraphics
import SwiftUI

final class CaptureSelectionNSView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    /// Backing scale of the screen this view sits on; used by the loupe to
    /// translate cursor points → source-image pixels.
    var sourceScale: CGFloat = 2.0 {
        didSet { loupe.sourceScale = sourceScale }
    }

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    /// Set when the user holds option mid-drag, applied through `EdgeSnap`.
    private var snapEdgesX: [CGFloat] = []
    private var snapEdgesY: [CGFloat] = []
    private var trackingArea: NSTrackingArea?
    private var loupeContainer: NSView!
    private var loupe: MagnifierLoupeView!
    private var hexLabel: NSTextField!
    private var coordLabel: NSTextField!
    private var entryPanel: NSPanel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        installLoupe()
        installCoordReadout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        installLoupe()
        installCoordReadout()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

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
        updateCoordReadout(at: point)
        moveLoupe(to: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        currentPoint = applySnapping(rawPoint: raw, modifiers: event.modifierFlags)
        updateCoordReadout(at: raw)
        moveLoupe(to: raw)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        currentPoint = applySnapping(rawPoint: raw, modifiers: event.modifierFlags)

        guard let selectionRect, selectionRect.width >= 4, selectionRect.height >= 4 else {
            onCancel?()
            return
        }

        onComplete?(selectionRect)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        moveLoupe(to: point)
        updateCoordReadout(at: point)
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right-click cancels selection anywhere on the overlay.
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 17: // T
            presentNumericalEntry()
        default:
            super.keyDown(with: event)
        }
    }

    /// Apply window-edge snapping when the user holds Option (alt) while
    /// dragging. Without the modifier we return the raw point untouched —
    /// snapping is opt-in to avoid surprising pixel-perfect users.
    private func applySnapping(rawPoint: CGPoint, modifiers: NSEvent.ModifierFlags) -> CGPoint {
        guard modifiers.contains(.option) else { return rawPoint }
        guard let start = startPoint else { return rawPoint }

        let raw = CGRect(
            x: min(start.x, rawPoint.x),
            y: min(start.y, rawPoint.y),
            width: abs(rawPoint.x - start.x),
            height: abs(rawPoint.y - start.y)
        )
        let snapped = EdgeSnap.snapped(rect: raw, xEdges: snapEdgesX, yEdges: snapEdgesY)
        // Translate the snapped corner back to a "currentPoint" relative to
        // the start, preserving drag direction (so the dimension text still
        // tracks the correct corner).
        let signX: CGFloat = rawPoint.x >= start.x ? 1 : -1
        let signY: CGFloat = rawPoint.y >= start.y ? 1 : -1
        let dx = snapped.width * signX
        let dy = snapped.height * signY
        return CGPoint(x: start.x + dx, y: start.y + dy)
    }

    func setSnapEdges(_ rectsInScreenPoints: [CGRect]) {
        var xs: [CGFloat] = []
        var ys: [CGFloat] = []
        for rect in rectsInScreenPoints {
            xs.append(rect.minX)
            xs.append(rect.maxX)
            ys.append(rect.minY)
            ys.append(rect.maxY)
        }
        snapEdgesX = xs
        snapEdgesY = ys
    }

    func setSourceImage(_ image: CGImage) {
        loupe.sourceImage = image
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
        let text = "\(Int(rect.width)) × \(Int(rect.height))   \(Int(rect.minX)), \(Int(rect.minY))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72)
        ]
        let size = text.size(withAttributes: attributes)
        let point = CGPoint(x: rect.minX, y: max(8, rect.minY - size.height - 8))
        text.draw(at: point, withAttributes: attributes)
    }

    private func installLoupe() {
        let dimension = MagnifierLoupeView.dimension
        let container = FlippedContainerView(frame: NSRect(x: 0, y: 0, width: dimension, height: dimension + 22))
        container.wantsLayer = true
        container.isHidden = true

        let loupe = MagnifierLoupeView(frame: NSRect(x: 0, y: 0, width: dimension, height: dimension))
        let hexLabel = NSTextField(labelWithString: "—")
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        hexLabel.textColor = .white
        hexLabel.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        hexLabel.drawsBackground = true
        hexLabel.alignment = .center
        // Container is flipped (top-left origin). Loupe sits at the top, hex
        // readout sits 2 px below it. Without the flip the loupe would render
        // at the *bottom* of the container — visually ~22 px below the cursor.
        hexLabel.frame = NSRect(x: 0, y: dimension + 2, width: dimension, height: 18)

        container.addSubview(loupe)
        container.addSubview(hexLabel)

        addSubview(container)
        loupeContainer = container
        self.loupe = loupe
        self.hexLabel = hexLabel
    }

    private func installCoordReadout() {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        label.drawsBackground = true
        label.alignment = .center
        label.isHidden = true
        addSubview(label)
        coordLabel = label
    }

    private func moveLoupe(to point: CGPoint) {
        loupe.cursorPoint = point
        hexLabel.stringValue = loupe.hexReadout
        let offset: CGFloat = 12
        var origin = CGPoint(x: point.x + offset, y: point.y + offset)
        let size = loupeContainer.frame.size
        if origin.x + size.width > bounds.maxX {
            origin.x = point.x - offset - size.width
        }
        if origin.y + size.height > bounds.maxY {
            origin.y = point.y - offset - size.height
        }
        loupeContainer.frame = NSRect(origin: origin, size: size)
        loupeContainer.isHidden = false
    }

    private func updateCoordReadout(at point: CGPoint) {
        // Standalone crosshair coords readout (separate from the in-rect
        // dimensions text) so the user always sees the cursor coordinate
        // even before the first click.
        guard startPoint == nil else {
            coordLabel.isHidden = true
            return
        }
        let text = "\(Int(point.x)), \(Int(point.y))"
        coordLabel.stringValue = " \(text) "
        coordLabel.sizeToFit()
        var origin = CGPoint(x: point.x + 14, y: point.y - coordLabel.frame.height - 14)
        if origin.y < 0 { origin.y = point.y + 14 }
        coordLabel.frame.origin = origin
        coordLabel.isHidden = false
    }

    private func presentNumericalEntry() {
        guard entryPanel == nil else { return }
        let panel = NumericalEntryPanel(
            initialText: "",
            onSubmit: { [weak self] text in
                guard let self else { return }
                self.entryPanel?.close()
                self.entryPanel = nil
                if let rect = NumericalEntryParser.parse(text) {
                    self.onComplete?(rect)
                }
            },
            onCancel: { [weak self] in
                self?.entryPanel?.close()
                self?.entryPanel = nil
            }
        )
        // Center on this screen's overlay window.
        if let host = window {
            var frame = panel.frame
            frame.origin = CGPoint(
                x: host.frame.midX - frame.width / 2,
                y: host.frame.midY - frame.height / 2
            )
            panel.setFrame(frame, display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        entryPanel = panel
    }
}

/// SwiftUI shim retained for any callers that still use `CaptureOverlayView`
/// directly. The presenter now constructs `CaptureSelectionNSView` itself,
/// but keeping the wrapper compiling avoids churn in unrelated views.
struct CaptureOverlayView: NSViewRepresentable {
    let screen: NSScreen
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureSelectionNSView {
        let view = CaptureSelectionNSView()
        view.onComplete = onComplete
        view.onCancel = onCancel
        view.sourceScale = screen.backingScaleFactor
        return view
    }

    func updateNSView(_ nsView: CaptureSelectionNSView, context: Context) {
        nsView.onComplete = onComplete
        nsView.onCancel = onCancel
    }
}

/// `NSView` subclass with `isFlipped = true` so child positions are
/// interpreted top-down. Used as the loupe container so its `frame.origin`
/// matches the surrounding flipped capture overlay coordinate space.
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}
