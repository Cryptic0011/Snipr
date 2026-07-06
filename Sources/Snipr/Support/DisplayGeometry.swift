import AppKit
import CoreGraphics

/// Single home for `NSScreen` ↔ `CGDirectDisplayID` ↔ pixel-rect math used by
/// the capture and recording engines. Keeping this in one place avoids the
/// per-call rewrites of the same `displayBounds.width / screen.frame.width`
/// scaling that sprinkled the old service files.
enum DisplayGeometry {
    /// Scales a rect expressed in `NSScreen` display points into the display's
    /// native pixel coordinate space via the screen's `backingScaleFactor`.
    ///
    /// Use this for `SCStreamConfiguration.width`/`height` (output pixel
    /// dimensions) so ScreenCaptureKit doesn't downsample to 1× on Retina.
    /// `SCStreamConfiguration.sourceRect` stays in display points — pass the
    /// original points rect there, not this.
    static func pixelRect(
        forDisplayPointsRect rect: CGRect,
        displayID: CGDirectDisplayID,
        screen: NSScreen
    ) -> CGRect {
        let scale = screen.backingScaleFactor

        return CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
    }
}

extension NSScreen {
    /// Resolves the underlying `CGDirectDisplayID` for the screen, if AppKit
    /// has populated the device description. Hidden / external screens that
    /// have just been disconnected can briefly return `nil`.
    var sniprDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
