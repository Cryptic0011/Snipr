import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Default `CaptureEngine` powered by ScreenCaptureKit's `SCScreenshotManager`.
/// Encoding stays via `CGImageDestination` so the public `CapturedImage`
/// shape is unchanged.
struct SCKCaptureEngine: CaptureEngine {
    func capture(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen
    ) async throws -> CapturedImage {
        let pixelRect = DisplayGeometry.pixelRect(
            forDisplayPointsRect: rectInDisplayPoints,
            displayID: displayID,
            screen: screen
        )

        // Discover the SCDisplay matching this CGDirectDisplayID. Pass
        // `excludingDesktopWindows(false, onScreenWindowsOnly: true)` so we
        // capture the same content the user sees, including the desktop.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = pixelRect
        configuration.width = max(2, Int(pixelRect.width.rounded()))
        configuration.height = max(2, Int(pixelRect.height.rounded()))
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw ScreenCaptureError.imageCreationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureError.pngEncodingFailed
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.pngEncodingFailed
        }

        return CapturedImage(
            pngData: data as Data,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
