import CoreGraphics
import Foundation
import Vision

enum QRScanError: LocalizedError {
    case noCodeFound
    case failed(any Error)

    var errorDescription: String? {
        switch self {
        case .noCodeFound:
            "No QR code or barcode found in the selection."
        case .failed(let error):
            error.localizedDescription
        }
    }
}

/// Vision-backed barcode reader used by the "Scan QR Code" flow. Detects any
/// barcode symbology, not just QR — a selection around an EAN or Code128
/// works too.
enum QRCodeScanner {
    static func payload(in image: CGImage) throws -> String {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw QRScanError.failed(error)
        }

        guard let payload = (request.results ?? [])
            .compactMap(\.payloadStringValue)
            .first(where: { !$0.isEmpty }) else {
            throw QRScanError.noCodeFound
        }
        return payload
    }
}
