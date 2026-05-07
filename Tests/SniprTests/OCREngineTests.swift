import AppKit
import CoreGraphics
import XCTest
@testable import Snipr

final class OCREngineTests: XCTestCase {
    /// Render a PNG that contains `text` so the recognizer has a high-contrast
    /// target. We render rather than ship a fixture so the assertion controls
    /// exactly what's expected without binary diff noise.
    private func renderImage(text: String) throws -> CGImage {
        let size = CGSize(width: 480, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        ))
        image.unlockFocus()

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return cgImage
    }

    func testVisionEngineRecognizesRenderedText() async throws {
        let image = try renderImage(text: "HELLO")
        let engine = VisionOCREngine(recognitionLanguages: ["en-US"], usesLanguageCorrection: false)
        let recognized = try await engine.recognizeText(in: image)
        XCTAssertTrue(
            recognized.uppercased().contains("HELLO"),
            "Expected recognition to contain HELLO, got \(recognized)"
        )
    }

    func testVisionEngineThrowsForBlankCanvas() async throws {
        let size = CGSize(width: 80, height: 60)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        let engine = VisionOCREngine(recognitionLanguages: ["en-US"], usesLanguageCorrection: false)
        do {
            _ = try await engine.recognizeText(in: cg)
            XCTFail("Expected OCRError.noTextFound")
        } catch let error as OCRError {
            if case .noTextFound = error {
                // expected
            } else {
                XCTFail("Unexpected OCRError: \(error)")
            }
        } catch {
            XCTFail("Unexpected non-OCRError: \(error)")
        }
    }
}
