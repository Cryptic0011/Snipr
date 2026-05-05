import AppKit
import CoreGraphics
import UniformTypeIdentifiers

struct CapturedImage {
    let pngData: Data
    let pixelSize: CGSize
}

enum ScreenCaptureError: LocalizedError {
    case imageCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageCreationFailed:
            "Snipr could not capture the selected display region."
        case .pngEncodingFailed:
            "Snipr captured the region but could not encode it as PNG."
        }
    }
}

struct ScreenCaptureService {
    func capture(displayID: CGDirectDisplayID, rectInDisplayPoints: CGRect, screen: NSScreen) throws -> CapturedImage {
        let displayBounds = CGDisplayBounds(displayID)
        let scaleX = displayBounds.width / screen.frame.width
        let scaleY = displayBounds.height / screen.frame.height

        let pixelRect = CGRect(
            x: rectInDisplayPoints.minX * scaleX,
            y: rectInDisplayPoints.minY * scaleY,
            width: rectInDisplayPoints.width * scaleX,
            height: rectInDisplayPoints.height * scaleY
        ).integral

        guard let cgImage = CGDisplayCreateImage(displayID, rect: pixelRect) else {
            throw ScreenCaptureError.imageCreationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
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

extension NSScreen {
    var sniprDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
