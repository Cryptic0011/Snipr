import CoreGraphics
import Foundation

enum OCRError: LocalizedError {
    case noTextFound
    case failed(any Error)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            "Snipr could not recognize any text in the selected region."
        case .failed(let error):
            error.localizedDescription
        }
    }
}

/// Pluggable OCR surface. The default Vision-backed engine is injected by
/// `SniprAppModel`; tests substitute a fake to keep them off the system OCR
/// stack.
protocol OCREngine: Sendable {
    /// Recognize text in the given image. Returns the joined recognized
    /// text — newline-separated by observation order — or throws on failure.
    func recognizeText(in image: CGImage) async throws -> String
}
