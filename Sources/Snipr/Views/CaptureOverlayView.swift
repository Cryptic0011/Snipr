import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class CaptureOverlaySelectionCoordinator {
    var onChange: (() -> Void)?

    private var startScreenPoint: CGPoint?
    private var currentScreenPoint: CGPoint?

    var isSelecting: Bool {
        startScreenPoint != nil && currentScreenPoint != nil
    }

    func begin(at point: CGPoint) {
        startScreenPoint = point
        currentScreenPoint = point
        onChange?()
    }

    func update(to point: CGPoint) {
        guard startScreenPoint != nil else { return }
        currentScreenPoint = point
        onChange?()
    }

    func reset() {
        startScreenPoint = nil
        currentScreenPoint = nil
        onChange?()
    }

    func selectionRect(inScreenFrame screenFrame: CGRect) -> CGRect? {
        guard let globalRect else { return nil }
        return Self.selectionRect(forGlobalRect: globalRect, inScreenFrame: screenFrame)
    }

    static func selectionRect(forGlobalRect globalRect: CGRect, inScreenFrame screenFrame: CGRect) -> CGRect? {
        let clipped = globalRect.intersection(screenFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return nil
        }

        return CGRect(
            x: clipped.minX - screenFrame.minX,
            y: screenFrame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
    }

    var globalRect: CGRect? {
        guard let startScreenPoint, let currentScreenPoint else {
            return nil
        }

        return CGRect(
            x: min(startScreenPoint.x, currentScreenPoint.x),
            y: min(startScreenPoint.y, currentScreenPoint.y),
            width: abs(currentScreenPoint.x - startScreenPoint.x),
            height: abs(currentScreenPoint.y - startScreenPoint.y)
        )
    }
}

final class CaptureSelectionNSView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCompleteInScreenCoordinates: ((CGRect, CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    var onPointerPreviewActivated: ((CaptureSelectionNSView) -> Void)?
    var selectionCoordinator: CaptureOverlaySelectionCoordinator?
    var showsMagnifier = false {
        didSet {
            if !showsMagnifier {
                loupe?.isHidden = true
                hexLabel?.isHidden = true
            }
        }
    }

    /// Backing scale of the screen this view sits on; used by the loupe to
    /// translate cursor points → source-image pixels.
    var sourceScale: CGFloat = 2.0 {
        didSet { loupe.sourceScale = sourceScale }
    }

    /// Freeze-screen mode: draw the captured display still behind the dim
    /// layer so on-screen motion can't shift under the crosshair. The image
    /// arrives asynchronously via `setSourceImage` (same still the loupe uses).
    var showsCoordinates = false
    var freezesBackground = false
    private var frozenBackground: NSImage?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    /// Set when the user holds option mid-drag, applied through `EdgeSnap`.
    private var snapEdgesX: [CGFloat] = []
    private var snapEdgesY: [CGFloat] = []
    private var trackingArea: NSTrackingArea?
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
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
        frozenBackground?.draw(in: bounds)

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selectionRect else {
            return
        }

        if let frozenBackground {
            // Re-paint the frozen still un-dimmed inside the selection —
            // punching through with .clear would show the live screen and
            // break the freeze illusion.
            let source = NSRect(
                x: selectionRect.minX,
                y: bounds.height - selectionRect.maxY,
                width: selectionRect.width,
                height: selectionRect.height
            )
            frozenBackground.draw(in: selectionRect, from: source, operation: .sourceOver, fraction: 1)
        } else {
            NSColor.clear.setFill()
            selectionRect.fill(using: .clear)
        }
        drawSelectionFrame(selectionRect)

        drawDimensions(for: selectionRect)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        selectionCoordinator?.begin(at: screenPoint(forLocalPoint: point))
        updateCoordReadout(at: point)
        activatePointerPreview()
        moveLoupe(to: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let snapped = applySnapping(rawPoint: raw, modifiers: event.modifierFlags)
        currentPoint = snapped
        selectionCoordinator?.update(to: screenPoint(forLocalPoint: snapped))
        updateCoordReadout(at: raw)
        activatePointerPreview()
        moveLoupe(to: raw)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let snapped = applySnapping(rawPoint: raw, modifiers: event.modifierFlags)
        currentPoint = snapped
        selectionCoordinator?.update(to: screenPoint(forLocalPoint: snapped))

        if let globalRect = selectionCoordinator?.globalRect {
            guard globalRect.width >= 4, globalRect.height >= 4 else {
                onCancel?()
                return
            }
            onCompleteInScreenCoordinates?(globalRect, screenPoint(forLocalPoint: snapped))
            return
        }

        guard let selectionRect, selectionRect.width >= 4, selectionRect.height >= 4 else {
            onCancel?()
            return
        }

        onComplete?(selectionRect)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        activatePointerPreview()
        moveLoupe(to: point)
        updateCoordReadout(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        hidePointerPreview()
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
        if freezesBackground {
            frozenBackground = NSImage(cgImage: image, size: bounds.size)
            needsDisplay = true
        }
    }

    private var selectionRect: CGRect? {
        if let selectionCoordinator, let window {
            return selectionCoordinator.selectionRect(inScreenFrame: window.frame)
        }

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
        guard showsCoordinates else { return }
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

    private func drawSelectionFrame(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor.white.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.42).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func installLoupe() {
        let dimension = MagnifierLoupeView.dimension

        let loupe = MagnifierLoupeView(frame: NSRect(x: 0, y: 0, width: dimension, height: dimension))
        loupe.isHidden = true

        let hexLabel = NSTextField(labelWithString: "—")
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        hexLabel.textColor = .white
        hexLabel.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        hexLabel.drawsBackground = true
        hexLabel.alignment = .center
        hexLabel.isHidden = true

        // Add loupe and hex label directly to the flipped overlay so each owns
        // its own frame in the parent's coordinate space — no nested
        // unflipped/flipped container to invert their positions.
        addSubview(loupe)
        addSubview(hexLabel)

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

    func hidePointerPreview() {
        loupe.isHidden = true
        hexLabel.isHidden = true
        coordLabel.isHidden = true
    }

    private func activatePointerPreview() {
        onPointerPreviewActivated?(self)
    }

    private func moveLoupe(to point: CGPoint) {
        guard showsMagnifier else {
            loupe.isHidden = true
            hexLabel.isHidden = true
            return
        }

        loupe.sourceViewSize = bounds.size
        loupe.cursorPoint = point
        hexLabel.stringValue = loupe.hexReadout
        let offset: CGFloat = 12
        let dim = MagnifierLoupeView.dimension
        let labelHeight: CGFloat = 18
        let labelGap: CGFloat = 2

        // Place the loupe directly at cursor + offset.
        var loupeOrigin = CGPoint(x: point.x + offset, y: point.y + offset)
        if loupeOrigin.x + dim > bounds.maxX {
            loupeOrigin.x = point.x - offset - dim
        }
        if loupeOrigin.y + dim + labelGap + labelHeight > bounds.maxY {
            loupeOrigin.y = point.y - offset - dim - labelGap - labelHeight
        }
        loupe.frame = NSRect(origin: loupeOrigin, size: NSSize(width: dim, height: dim))

        // Hex label sits just below the loupe, sized to fit the readout.
        hexLabel.sizeToFit()
        let labelWidth = max(dim, hexLabel.frame.width + 8)
        hexLabel.frame = NSRect(
            x: loupeOrigin.x + (dim - labelWidth) / 2,
            y: loupeOrigin.y + dim + labelGap,
            width: labelWidth,
            height: labelHeight
        )

        loupe.isHidden = false
        hexLabel.isHidden = false
    }

    private func updateCoordReadout(at point: CGPoint) {
        // Standalone crosshair coords readout (separate from the in-rect
        // dimensions text) so the user always sees the cursor coordinate
        // even before the first click.
        guard showsCoordinates, startPoint == nil, selectionCoordinator?.isSelecting != true else {
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

    private func screenPoint(forLocalPoint point: CGPoint) -> CGPoint {
        guard let window else { return point }
        return CGPoint(
            x: window.frame.minX + point.x,
            y: window.frame.maxY - point.y
        )
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
