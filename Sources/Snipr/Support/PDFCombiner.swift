import AppKit
import Foundation
import PDFKit

/// Combines multiple image files into a single PDF where each image is one
/// page sized to that image's pixel dimensions.
///
/// This is intentionally batch-only: video items are silently skipped — the
/// caller filters them ahead of time, but we tolerate stray inputs rather
/// than throwing.
enum PDFCombiner {
    enum Failure: LocalizedError {
        case noImages
        case writeFailed(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noImages:
                "No images to combine."
            case .writeFailed(let url, let underlying):
                "Could not write PDF to \(url.path): \(underlying.localizedDescription)"
            }
        }
    }

    /// Combine `imageURLs` into a PDF written to `destination`. Returns the
    /// number of pages written (one per successfully decoded image).
    @discardableResult
    static func combine(imageURLs: [URL], to destination: URL) throws -> Int {
        let document = PDFDocument()
        var pageIndex = 0
        for url in imageURLs {
            guard let image = NSImage(contentsOf: url),
                  let page = PDFPage(image: image) else {
                continue
            }
            document.insert(page, at: pageIndex)
            pageIndex += 1
        }

        guard pageIndex > 0 else {
            throw Failure.noImages
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            guard document.write(to: destination) else {
                // PDFKit returns false for generic write failure with no
                // error vended. Surface a synthetic NSError so callers get
                // a useful message.
                throw NSError(
                    domain: "PDFCombiner",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "PDFKit refused to write the document."]
                )
            }
        } catch {
            throw Failure.writeFailed(destination, underlying: error)
        }

        return pageIndex
    }
}
