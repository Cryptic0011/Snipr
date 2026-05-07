import AppKit
import CoreGraphics
import Foundation

/// PNG-encoded still capture produced by a `CaptureEngine`. The shape matches
/// what `CaptureStore.addCapture` already expects, so engine swaps don't
/// ripple into storage.
struct CapturedImage: Sendable {
    let pngData: Data
    let pixelSize: CGSize
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
}
