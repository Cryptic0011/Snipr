import AppKit
import CoreGraphics
import XCTest
@testable import Snipr

final class AnnotationToolTests: XCTestCase {
    private func makeContext(width: Int = 80, height: Int = 60) -> (AnnotationDrawingContext, CGContext, CGImage) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let drawCtx = AnnotationDrawingContext(
            context: context,
            baseImage: image,
            imageHeight: CGFloat(height),
            imageWidth: CGFloat(width)
        )
        return (drawCtx, context, image)
    }

    private func makeLayer(
        kind: AnnotationKind,
        start: CGPoint = CGPoint(x: 10, y: 10),
        end: CGPoint = CGPoint(x: 50, y: 40),
        ink: AnnotationInk = .red,
        text: String = "",
        stepNumber: Int = 1
    ) -> AnnotationLayer {
        AnnotationLayer(
            kind: kind,
            start: start,
            end: end,
            ink: ink,
            text: text,
            stepNumber: stepNumber
        )
    }

    // MARK: - Registry

    func testRegistryHasOneToolPerKind() {
        for kind in AnnotationKind.allCases {
            XCTAssertNotNil(AnnotationToolRegistry.tool(for: kind), "Missing tool for \(kind)")
            XCTAssertEqual(AnnotationToolRegistry.tool(for: kind)?.kind, kind)
        }
    }

    func testEditorToolsExcludeCropButKeepOtherTools() {
        XCTAssertFalse(AnnotationKind.editorTools.contains(.crop))
        XCTAssertTrue(AnnotationKind.allCases.contains(.crop))
        XCTAssertTrue(AnnotationKind.editorTools.contains(.pixelate))
        XCTAssertTrue(AnnotationKind.editorTools.contains(.blur))
    }

    func testLiveEffectPreviewIncludesPixelateAndBlur() {
        XCTAssertTrue(AnnotationEffectPreview.supportsLivePreview(.blur))
        XCTAssertTrue(AnnotationEffectPreview.supportsLivePreview(.pixelate))
        XCTAssertFalse(AnnotationEffectPreview.supportsLivePreview(.rectangle))
    }

    // MARK: - Draw — happy paths just need to not crash and to mutate the context.
    func testEachToolDrawsWithoutCrashing() {
        for kind in AnnotationKind.allCases {
            let (ctx, _, _) = makeContext()
            let tool = AnnotationToolRegistry.tool(for: kind)!
            let layer = makeLayer(kind: kind, text: "x", stepNumber: 7)
            tool.draw(layer, in: ctx)
        }
    }

    // MARK: - Hit testing

    func testArrowHitTestSnapsAlongSegment() {
        let tool = ArrowTool()
        let layer = makeLayer(kind: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 50, y: 0)))
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 50, y: 5)))
        XCTAssertFalse(tool.hitTest(layer, point: CGPoint(x: 50, y: 50)))
    }

    func testRectangleHitTestStrokeOnly() {
        let tool = RectangleTool()
        let layer = makeLayer(kind: .rectangle, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100))
        // On the stroke
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 0, y: 50)))
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 50, y: 100)))
        // Inside the rectangle but away from the stroke is not hit
        XCTAssertFalse(tool.hitTest(layer, point: CGPoint(x: 50, y: 50)))
    }

    func testEllipseHitTestNearPerimeter() {
        let tool = EllipseTool()
        let layer = makeLayer(kind: .ellipse, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100))
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 100, y: 50))) // right vertex
        XCTAssertFalse(tool.hitTest(layer, point: CGPoint(x: 50, y: 50)))  // dead center
    }

    func testStepHitTestInsideRadius() {
        let tool = StepTool()
        let layer = makeLayer(kind: .step, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50))
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(tool.hitTest(layer, point: CGPoint(x: 200, y: 200)))
    }

    func testTextHitTestRequiresContent() {
        let tool = TextTool()
        let empty = makeLayer(kind: .text, start: CGPoint(x: 5, y: 5), text: "")
        XCTAssertFalse(tool.hitTest(empty, point: CGPoint(x: 6, y: 6)))
        let filled = makeLayer(kind: .text, start: CGPoint(x: 5, y: 5), text: "hello")
        XCTAssertTrue(tool.hitTest(filled, point: CGPoint(x: 8, y: 6)))
    }

    func testHighlightHitTestUsesBounds() {
        let tool = HighlightTool()
        let layer = makeLayer(kind: .highlight, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 50))
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 25, y: 25)))
        XCTAssertFalse(tool.hitTest(layer, point: CGPoint(x: 200, y: 200)))
    }

    func testCropHitTestUsesBounds() {
        let tool = CropTool()
        let layer = makeLayer(kind: .crop, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 50))
        XCTAssertTrue(tool.hitTest(layer, point: CGPoint(x: 25, y: 25)))
    }

    // MARK: - Encoding

    func testEncodeIncludesKindAndCoordinates() {
        let tool = ArrowTool()
        let layer = makeLayer(kind: .arrow)
        let data = tool.encode(layer)
        XCTAssertEqual(data.kind, .arrow)
        XCTAssertEqual(data.payload["startX"], "10.0")
        XCTAssertEqual(data.payload["startY"], "10.0")
        XCTAssertEqual(data.payload["endX"], "50.0")
        XCTAssertEqual(data.payload["endY"], "40.0")
        XCTAssertEqual(data.payload["ink"], "red")
    }

    func testEncodeRoundTripsThroughJSON() throws {
        let tool = TextTool()
        let layer = makeLayer(kind: .text, text: "hello")
        let data = tool.encode(layer)
        let json = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(AnnotationData.self, from: json)
        XCTAssertEqual(decoded, data)
    }

    // MARK: - Renderer end-to-end with multiple tools

    func testRendererDrawsAllToolsOntoImage() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: temp) }
        try makePNG(size: CGSize(width: 200, height: 120)).write(to: temp)

        let layers: [AnnotationLayer] = [
            makeLayer(kind: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 80, y: 60)),
            makeLayer(kind: .rectangle, start: CGPoint(x: 30, y: 20), end: CGPoint(x: 90, y: 70)),
            makeLayer(kind: .ellipse, start: CGPoint(x: 100, y: 30), end: CGPoint(x: 160, y: 80)),
            makeLayer(kind: .blur, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 50)),
            makeLayer(kind: .pixelate, start: CGPoint(x: 70, y: 50), end: CGPoint(x: 110, y: 90)),
            makeLayer(kind: .highlight, start: CGPoint(x: 130, y: 40), end: CGPoint(x: 180, y: 80), ink: .amber),
            makeLayer(kind: .text, start: CGPoint(x: 20, y: 100), text: "label"),
            makeLayer(kind: .step, start: CGPoint(x: 150, y: 100), end: CGPoint(x: 150, y: 100), stepNumber: 3)
        ]

        let png = try XCTUnwrap(AnnotationRenderer.pngData(baseURL: temp, annotations: layers))
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testRendererCropsImageWhenCropLayerPresent() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: temp) }
        try makePNG(size: CGSize(width: 200, height: 200)).write(to: temp)

        let layers: [AnnotationLayer] = [
            makeLayer(kind: .crop, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100))
        ]
        let image = try XCTUnwrap(AnnotationRenderer.renderImage(baseURL: temp, annotations: layers))
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("Expected a CGImage from renderer")
            return
        }
        XCTAssertEqual(cg.width, 100)
        XCTAssertEqual(cg.height, 100)
    }

    private func makePNG(size: CGSize) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.22, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
