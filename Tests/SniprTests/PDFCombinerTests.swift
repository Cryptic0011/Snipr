import AppKit
import PDFKit
import XCTest
@testable import Snipr

final class PDFCombinerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    func testCombineTwoImagesProducesTwoPagePDF() throws {
        let urlA = try writeFixturePNG(size: CGSize(width: 320, height: 200), color: .systemBlue, named: "a.png")
        let urlB = try writeFixturePNG(size: CGSize(width: 480, height: 270), color: .systemRed, named: "b.png")
        let dest = tempRoot.appending(path: "combined.pdf")

        let pageCount = try PDFCombiner.combine(imageURLs: [urlA, urlB], to: dest)

        XCTAssertEqual(pageCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))

        let document = try XCTUnwrap(PDFDocument(url: dest))
        XCTAssertEqual(document.pageCount, 2)

        // Page bounds should approximately match the image pixel sizes
        // (PDFKit may scale by 72-dpi, but ratios stay sane). We only
        // check that page 1 is shorter than page 2's height ratio match.
        let pageA = try XCTUnwrap(document.page(at: 0))
        let pageB = try XCTUnwrap(document.page(at: 1))
        let boundsA = pageA.bounds(for: .mediaBox)
        let boundsB = pageB.bounds(for: .mediaBox)
        XCTAssertGreaterThan(boundsA.width, 0)
        XCTAssertGreaterThan(boundsB.width, 0)
        XCTAssertEqual(boundsA.width / boundsA.height, 320.0 / 200.0, accuracy: 0.05)
        XCTAssertEqual(boundsB.width / boundsB.height, 480.0 / 270.0, accuracy: 0.05)
    }

    func testCombineEmptyArrayThrows() {
        let dest = tempRoot.appending(path: "empty.pdf")
        XCTAssertThrowsError(try PDFCombiner.combine(imageURLs: [], to: dest))
    }

    func testCombineSkipsUndecodableURLs() throws {
        let urlA = try writeFixturePNG(size: CGSize(width: 100, height: 100), color: .systemGreen, named: "a.png")
        let bogus = tempRoot.appending(path: "missing.png")
        let dest = tempRoot.appending(path: "skipped.pdf")

        let pageCount = try PDFCombiner.combine(imageURLs: [bogus, urlA], to: dest)
        XCTAssertEqual(pageCount, 1)
    }

    private func writeFixturePNG(size: CGSize, color: NSColor, named name: String) throws -> URL {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "PDFCombinerTests", code: 1)
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PDFCombinerTests", code: 2)
        }
        let url = tempRoot.appending(path: name)
        try png.write(to: url, options: [.atomic])
        return url
    }
}
