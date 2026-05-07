import AppKit
import ImageIO
import XCTest
@testable import Snipr

final class VerticalStitcherTests: XCTestCase {
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

    func testStitchTwoImagesProducesSummedHeight() throws {
        let urlA = try writeFixturePNG(size: CGSize(width: 200, height: 120), color: .systemBlue, named: "a.png")
        let urlB = try writeFixturePNG(size: CGSize(width: 200, height: 80), color: .systemOrange, named: "b.png")
        let dest = tempRoot.appending(path: "stitched.png")

        let size = try VerticalStitcher.stitchVertically(imageURLs: [urlA, urlB], to: dest)
        XCTAssertEqual(size.width, 200, accuracy: 0.1)
        XCTAssertEqual(size.height, 200, accuracy: 0.1)

        let pixelSize = try pixelSize(of: dest)
        XCTAssertEqual(pixelSize.width, 200)
        XCTAssertEqual(pixelSize.height, 200)
    }

    func testStitchUsesWidestImageAsCanvasWidth() throws {
        let urlA = try writeFixturePNG(size: CGSize(width: 100, height: 60), color: .systemBlue, named: "a.png")
        let urlB = try writeFixturePNG(size: CGSize(width: 250, height: 60), color: .systemRed, named: "b.png")
        let dest = tempRoot.appending(path: "wide.png")

        let size = try VerticalStitcher.stitchVertically(imageURLs: [urlA, urlB], to: dest)
        XCTAssertEqual(size.width, 250, accuracy: 0.1)
        XCTAssertEqual(size.height, 120, accuracy: 0.1)
    }

    func testStitchEmptyArrayThrows() {
        XCTAssertThrowsError(try VerticalStitcher.stitchVertically(imageURLs: [], to: tempRoot.appending(path: "x.png")))
    }

    private func pixelSize(of url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "VerticalStitcherTests", code: 1)
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
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
            throw NSError(domain: "VerticalStitcherTests", code: 2)
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "VerticalStitcherTests", code: 3)
        }
        let url = tempRoot.appending(path: name)
        try png.write(to: url, options: [.atomic])
        return url
    }
}
