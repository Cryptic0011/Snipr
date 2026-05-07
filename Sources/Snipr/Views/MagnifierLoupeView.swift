import AppKit
import CoreGraphics

/// Floating loupe that magnifies pixels around the cursor. The host view feeds
/// a cached `CGImage` of the underlying display (captured once when the
/// overlay opens — re-capturing at 60 Hz through SCK would jank), and a
/// running cursor location in the host view's coordinate space.
final class MagnifierLoupeView: NSView {
    /// Side length of the loupe (square). Ends up as ~120×120 like plan.md.
    static let dimension: CGFloat = 120
    /// Pixel multiplier — each source pixel renders 8× zoomed.
    static let zoom: CGFloat = 8

    /// Cached display image. The host view sets this when the overlay opens
    /// and the SCK snapshot resolves. Until then the loupe draws a neutral
    /// placeholder rather than nothing — confirms it's wired but not flashy.
    var sourceImage: CGImage? {
        didSet { needsDisplay = true }
    }

    /// Backing scale factor for the source image. NSScreen returns
    /// `backingScaleFactor` 2.0 on Retina, so points→pixels is ×2 on a HiDPI
    /// display. We need it to translate the cursor's point coordinates to
    /// pixel offsets within the cached image.
    var sourceScale: CGFloat = 2.0

    /// Cursor location in the loupe's superview coordinate space (top-left
    /// origin like the rest of the overlay).
    var cursorPoint: CGPoint = .zero {
        didSet {
            sampledRGB = sampleRGB(at: cursorPoint)
            needsDisplay = true
        }
    }

    /// Most recent sampled hex value, exposed so the host view can render it
    /// alongside the dimensions readout if desired.
    private(set) var sampledRGB: (UInt8, UInt8, UInt8)?

    var hexReadout: String {
        guard let sampledRGB else { return "—" }
        return String(format: "#%02X%02X%02X", sampledRGB.0, sampledRGB.1, sampledRGB.2)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current?.cgContext
        let frame = bounds

        context?.saveGState()
        defer { context?.restoreGState() }

        // Round clip + outer chrome.
        let clipPath = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        clipPath.addClip()
        NSColor.black.setFill()
        frame.fill()

        if let sourceImage {
            drawZoomedSource(sourceImage, in: frame, context: context)
        }

        drawCrosshair(in: frame, context: context)
        drawBorder(in: frame, context: context)
    }

    private func drawZoomedSource(_ source: CGImage, in frame: NSRect, context: CGContext?) {
        // Sample a small box around the cursor (in pixels of the source)
        // and stretch it to fill the loupe.
        let pixelsPerSide = Self.dimension / Self.zoom // points
        let pixelSampleSide = pixelsPerSide * sourceScale
        let center = pixelLocation(for: cursorPoint)

        let sampleRect = CGRect(
            x: center.x - pixelSampleSide / 2,
            y: center.y - pixelSampleSide / 2,
            width: pixelSampleSide,
            height: pixelSampleSide
        )

        // CGImage cropping uses pixel coordinates with origin at top-left.
        let intRect = sampleRect.integral
        guard intRect.width > 0, intRect.height > 0,
              let cropped = source.cropping(to: intRect) else {
            return
        }

        context?.interpolationQuality = .none
        context?.draw(cropped, in: frame)
    }

    private func drawCrosshair(in frame: NSRect, context: CGContext?) {
        guard let context else { return }
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        let pixelInLoupe = Self.zoom

        // Cell box around the focused pixel.
        let cell = CGRect(
            x: mid.x - pixelInLoupe / 2,
            y: mid.y - pixelInLoupe / 2,
            width: pixelInLoupe,
            height: pixelInLoupe
        )
        context.stroke(cell)

        context.setStrokeColor(NSColor.systemCyan.withAlphaComponent(0.85).cgColor)
        context.move(to: CGPoint(x: 0, y: mid.y))
        context.addLine(to: CGPoint(x: frame.width, y: mid.y))
        context.move(to: CGPoint(x: mid.x, y: 0))
        context.addLine(to: CGPoint(x: mid.x, y: frame.height))
        context.strokePath()
    }

    private func drawBorder(in frame: NSRect, context: CGContext?) {
        guard let context else { return }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
    }

    private func pixelLocation(for point: CGPoint) -> CGPoint {
        // Cursor point is in overlay coordinates (top-left origin already
        // because the overlay view is flipped). Convert to source pixel
        // coordinates with a top-left origin to match `CGImage.cropping`.
        CGPoint(x: point.x * sourceScale, y: point.y * sourceScale)
    }

    private func sampleRGB(at point: CGPoint) -> (UInt8, UInt8, UInt8)? {
        guard let sourceImage else { return nil }
        let pixel = pixelLocation(for: point)
        let x = Int(pixel.x.rounded())
        let y = Int(pixel.y.rounded())
        guard x >= 0, y >= 0, x < sourceImage.width, y < sourceImage.height else {
            return nil
        }

        // Pull a single pixel by drawing into a 1×1 RGBA8 context. Cheap
        // enough at mouseMove rates and avoids assumptions about the source
        // image's color space / bit depth.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: -CGFloat(x), y: -CGFloat(sourceImage.height - 1 - y))
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
        return (data[0], data[1], data[2])
    }
}
