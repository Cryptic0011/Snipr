import AppKit
import CoreGraphics

/// Single home for `NSScreen` ↔ `CGDirectDisplayID` ↔ pixel-rect math used by
/// the capture and recording engines. Keeping this in one place avoids the
/// per-call rewrites of the same `displayBounds.width / screen.frame.width`
/// scaling that sprinkled the old service files.
enum DisplayGeometry {
    /// Scales a rect expressed in `NSScreen` display points (top-left origin
    /// when `screen.isFlipped`-style consumers use it) into the display's
    /// native pixel coordinate space.
    ///
    /// Both `ScreenCaptureKit` (`SCStreamConfiguration.sourceRect`) and the
    /// legacy `CGDisplayCreateImage` rect take pixel coordinates relative to
    /// the display, so all callers funnel through this one routine.
    static func pixelRect(
        forDisplayPointsRect rect: CGRect,
        displayID: CGDirectDisplayID,
        screen: NSScreen
    ) -> CGRect {
        let displayBounds = CGDisplayBounds(displayID)
        let scaleX = displayBounds.width / screen.frame.width
        let scaleY = displayBounds.height / screen.frame.height

        return CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
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
