import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Result of a still capture. Carries both the raw `CGImage` (so the flow
/// presenter can sample / reencode under the user's chosen format) and a
/// pre-encoded PNG snapshot (so callers that just want bytes don't pay for a
/// round-trip).
struct CapturedImage: Sendable {
    let cgImage: CGImage
    let pngData: Data
    let pixelSize: CGSize

    /// Encode the underlying `CGImage` into the requested format. Returns
    /// `nil` if `ImageIO` can't satisfy the destination type — caller should
    /// fall back to `pngData` in that case.
    func encode(as format: CaptureFormat) -> Data? {
        if case .png = format {
            return pngData
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        var properties: [CFString: Any] = [:]
        if let quality = format.quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}

enum ScreenCaptureError: LocalizedError {
    case imageCreationFailed
    case pngEncodingFailed
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .imageCreationFailed:
            "Snipr could not capture the selected display region."
        case .pngEncodingFailed:
            "Snipr captured the region but could not encode it as PNG."
        case .displayNotFound:
            "Snipr could not find the display being captured."
        }
    }
}

/// Pluggable still-capture surface. The default ScreenCaptureKit engine is
/// injected by `SniprAppModel`; tests substitute a fake to assert orchestration
/// without touching the system capture stack.
///
/// The protocol is `@MainActor`-isolated because callers hand us an
/// `NSScreen`, which AppKit only guarantees thread-safe on the main actor.
@MainActor
protocol CaptureEngine: Sendable {
    func capture(
        displayID: CGDirectDisplayID,
        rectInDisplayPoints: CGRect,
        screen: NSScreen
    ) async throws -> CapturedImage

    /// Capture exactly the pixels of the given on-screen window. Implementations
    /// build a desktop-independent SCK filter scoped to the window so overlapping
    /// content (other windows, menu bar) doesn't bleed into the result.
    func captureWindow(scWindowID: CGWindowID) async throws -> CapturedImage
}
