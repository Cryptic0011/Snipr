import AppKit
import CoreGraphics

/// Per-screen overlay that lets the user hover the cursor over the desktop and
/// click to sample a pixel color. Reuses `MagnifierLoupeView` for the loupe
/// preview; reports the clicked pixel back to the presenter via `onSample`.
final class ColorPickerOverlayView: NSView {
    struct SampleResult {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    var onSample: ((SampleResult) -> Void)?
    var onCancel: (() -> Void)?
    var sourceScale: CGFloat = 2.0 {
        didSet { loupe.sourceScale = sourceScale }
    }

    private var loupe: MagnifierLoupeView!
    private var hexLabel: NSTextField!
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        installLoupe()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        installLoupe()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    func setSourceImage(_ image: CGImage) {
        loupe.sourceImage = image
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

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        loupe.cursorPoint = point
        positionLoupe(near: point)
        hexLabel.stringValue = loupe.hexReadout
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let pixel = CGPoint(x: point.x * sourceScale, y: point.y * sourceScale)
        guard let image = loupe.sourceImage,
              let sample = ColorPicker.sample(image: image, at: pixel) else {
            onCancel?()
            return
        }
        onSample?(SampleResult(
            red: sample.red,
            green: sample.green,
            blue: sample.blue,
            alpha: sample.alpha
        ))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            // Esc — cancel
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    private func installLoupe() {
        let size = NSSize(width: MagnifierLoupeView.dimension, height: MagnifierLoupeView.dimension)
        loupe = MagnifierLoupeView(frame: NSRect(origin: .zero, size: size))
        addSubview(loupe)

        hexLabel = NSTextField(labelWithString: "—")
        hexLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        hexLabel.textColor = .white
        hexLabel.backgroundColor = NSColor(white: 0, alpha: 0.65)
        hexLabel.drawsBackground = true
        hexLabel.isBezeled = false
        hexLabel.isEditable = false
        hexLabel.alignment = .center
        addSubview(hexLabel)
    }

    private func positionLoupe(near point: CGPoint) {
        let size = loupe.frame.size
        var origin = CGPoint(x: point.x + 24, y: point.y + 24)
        if origin.x + size.width > bounds.width { origin.x = point.x - size.width - 24 }
        if origin.y + size.height > bounds.height { origin.y = point.y - size.height - 24 }
        loupe.frame = NSRect(origin: origin, size: size)
        hexLabel.frame = NSRect(x: origin.x, y: origin.y + size.height + 4, width: size.width, height: 20)
    }
}
