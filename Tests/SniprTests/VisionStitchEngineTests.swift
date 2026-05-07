import CoreGraphics
import XCTest
@testable import Snipr

final class VisionStitchEngineTests: XCTestCase {
    /// Two programmatically-generated frames with a known overlap region.
    /// We render a tall reference image, slice two overlapping windows out
    /// of it, then verify the stitched result has the expected total height.
    func testStitchTwoOverlappingFramesReducesByOverlap() throws {
        let width = 64
        let frameHeight = 100
        let overlap = 40

        // Reference image carries a vertical gradient of unique row values
        // so the row-correlation has plenty of signal.
        let reference = makeGradient(width: width, height: frameHeight + (frameHeight - overlap))

        let top = try crop(reference, rect: CGRect(x: 0, y: 0, width: width, height: frameHeight))
        let bottom = try crop(reference, rect: CGRect(x: 0, y: frameHeight - overlap, width: width, height: frameHeight))

        let engine = VisionStitchEngine(minOverlapFraction: 0.10, mismatchThreshold: 6.0)
        let stitched = try engine.stitch(frames: [top, bottom])
        XCTAssertNotNil(stitched)
        let result = try XCTUnwrap(stitched)

        // Sum of input heights minus detected overlap. The row-correlation
        // kernel walks coarsely from large overlaps down, so the recovered
        // overlap may be a few rows off the ground truth. We assert the
        // result is within a small tolerance and matches the
        // "sum minus overlap" shape.
        let expected = frameHeight + frameHeight - overlap
        XCTAssertGreaterThanOrEqual(result.height, expected - 5)
        XCTAssertLessThanOrEqual(result.height, expected + 5)
        XCTAssertEqual(result.width, width)
    }

    func testStitchSingleFrameReturnsItself() throws {
        let engine = VisionStitchEngine()
        let frame = makeGradient(width: 32, height: 32)
        let result = try engine.stitch(frames: [frame])
        XCTAssertEqual(result?.width, 32)
        XCTAssertEqual(result?.height, 32)
    }

    func testStitchEmptyThrows() {
        let engine = VisionStitchEngine()
        XCTAssertThrowsError(try engine.stitch(frames: []))
    }

    func testStitchUnequalWidthsThrows() {
        let engine = VisionStitchEngine()
        let a = makeGradient(width: 32, height: 32)
        let b = makeGradient(width: 16, height: 32)
        XCTAssertThrowsError(try engine.stitch(frames: [a, b]))
    }

    func testStitchRejectsAllPairsWhenScrolledTooFast() {
        // Two completely unrelated frames — high-contrast checkerboard and
        // gradient. With a strict 50% overlap floor and a tight mismatch
        // tolerance, the engine should refuse to fabricate a seam.
        let a = makeCheckerboard(width: 32, height: 32, cellSize: 4)
        let b = makeGradient(width: 32, height: 32)
        let engine = VisionStitchEngine(minOverlapFraction: 0.50, mismatchThreshold: 1.0)
        XCTAssertThrowsError(try engine.stitch(frames: [a, b]))
    }

    // MARK: - Helpers

    /// Build a vertical gradient where each row has a unique gray value
    /// derived from its y-coordinate. Gives the row-correlation kernel
    /// strong signal.
    private func makeGradient(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in 0..<height {
            let value = CGFloat(y) / CGFloat(max(1, height - 1))
            context.setFillColor(red: value, green: value, blue: value, alpha: 1)
            // CG origin bottom-left; row y in our coord system corresponds
            // to height - 1 - y in CG. We don't care which way the gradient
            // runs, just that adjacent rows are unique.
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return context.makeImage()!
    }

    private func makeCheckerboard(width: Int, height: Int, cellSize: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in stride(from: 0, to: height, by: cellSize) {
            for x in stride(from: 0, to: width, by: cellSize) {
                let isBlack = ((x / cellSize) + (y / cellSize)) % 2 == 0
                let value: CGFloat = isBlack ? 0 : 1
                context.setFillColor(red: value, green: value, blue: value, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: cellSize, height: cellSize))
            }
        }
        return context.makeImage()!
    }

    private func crop(_ image: CGImage, rect: CGRect) throws -> CGImage {
        guard let cropped = image.cropping(to: rect) else {
            throw NSError(domain: "VisionStitchEngineTests", code: 1)
        }
        return cropped
    }
}
