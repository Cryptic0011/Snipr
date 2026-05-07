import CoreGraphics
import Foundation
import Vision

/// Vision-backed OCR. Uses `VNRecognizeTextRequest` with `.accurate` for
/// blueprint-quality recognition; language correction is on so common typos in
/// recognized snippets are smoothed out.
struct VisionOCREngine: OCREngine {
    /// Languages the recognizer should consider, ordered by priority. Defaults
    /// to the system primary locale plus English fallback.
    let recognitionLanguages: [String]
    /// `true` runs the recognizer with system language correction. Off by
    /// default for tests so fixture text isn't autocorrected.
    let usesLanguageCorrection: Bool

    init(recognitionLanguages: [String]? = nil, usesLanguageCorrection: Bool = true) {
        if let recognitionLanguages {
            self.recognitionLanguages = recognitionLanguages
        } else {
            let primary = Locale.current.language.languageCode?.identifier ?? "en-US"
            self.recognitionLanguages = primary == "en" ? ["en-US"] : [primary, "en-US"]
        }
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.failed(error))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: "\n")
                if joined.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: joined)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = usesLanguageCorrection
            request.recognitionLanguages = recognitionLanguages

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.failed(error))
            }
        }
    }
}
