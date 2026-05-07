import AppKit
import XCTest
@testable import Snipr

final class AnnotationRendererTests: XCTestCase {
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

    func testRendererExportsAnnotatedPNG() throws {
        let sourceURL = tempRoot.appending(path: "source.png")
        try makePNG(size: CGSize(width: 80, height: 60)).write(to: sourceURL)

        let annotations = [
            AnnotationLayer(
                kind: .arrow,
                start: CGPoint(x: 10, y: 10),
                end: CGPoint(x: 70, y: 50),
                ink: .red
            ),
            AnnotationLayer(
                kind: .blur,
                start: CGPoint(x: 20, y: 15),
                end: CGPoint(x: 44, y: 34),
                ink: .white
            )
        ]

        let output = try XCTUnwrap(AnnotationRenderer.pngData(baseURL: sourceURL, annotations: annotations))

        XCTAssertTrue(output.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertGreaterThan(output.count, 100)
    }

    func testAspectFitPointConversionRoundTrips() throws {
        let displayRect = ImagePresentationGeometry.aspectFitRect(
            imageSize: CGSize(width: 400, height: 200),
            containerSize: CGSize(width: 300, height: 300)
        )
        XCTAssertEqual(displayRect, CGRect(x: 0, y: 75, width: 300, height: 150))

        let imagePoint = try XCTUnwrap(
            ImagePresentationGeometry.imagePoint(
                from: CGPoint(x: 150, y: 150),
                imageSize: CGSize(width: 400, height: 200),
                displayRect: displayRect
            )
        )
        XCTAssertEqual(imagePoint.x, 200, accuracy: 0.001)
        XCTAssertEqual(imagePoint.y, 100, accuracy: 0.001)

        let viewPoint = ImagePresentationGeometry.viewPoint(
            from: imagePoint,
            imageSize: CGSize(width: 400, height: 200),
            displayRect: displayRect
        )
        XCTAssertEqual(viewPoint.x, 150, accuracy: 0.001)
        XCTAssertEqual(viewPoint.y, 150, accuracy: 0.001)
    }

    private func makePNG(size: CGSize) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.22, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.white.setFill()
        NSRect(x: 10, y: 10, width: 30, height: 20).fill()
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
