import CoreGraphics
import XCTest
@testable import Snipr

/// The salvage contract: a failed stitch degrades to the first collected
/// frame instead of throwing the whole session away.
final class ScrollingStitchJobTests: XCTestCase {
    private struct ThrowingStitchEngine: StitchEngine {
        func stitch(frames: [CGImage]) throws -> CGImage? { throw StitchError.allFramesRejected }
    }

    private struct NilStitchEngine: StitchEngine {
        func stitch(frames: [CGImage]) throws -> CGImage? { nil }
    }

    private struct FirstFrameStitchEngine: StitchEngine {
        func stitch(frames: [CGImage]) throws -> CGImage? { frames.first }
    }

    func testSuccessfulStitchHasNoSalvageReason() throws {
        let frame = makeSolid(width: 40, height: 30)
        let job = ScrollingStitchJob(frames: [frame], stitchEngine: FirstFrameStitchEngine(), format: .png)
        let output = try job.run()
        XCTAssertNil(output.salvageReason)
        XCTAssertEqual(output.pixelSize, CGSize(width: 40, height: 30))
        XCTAssertFalse(output.data.isEmpty)
    }

    func testFailedStitchSalvagesFirstFrame() throws {
        let first = makeSolid(width: 64, height: 48)
        let second = makeSolid(width: 64, height: 48)
        let job = ScrollingStitchJob(frames: [first, second], stitchEngine: ThrowingStitchEngine(), format: .png)
        let output = try job.run()
        XCTAssertNotNil(output.salvageReason)
        XCTAssertEqual(output.pixelSize, CGSize(width: 64, height: 48))
        XCTAssertFalse(output.data.isEmpty)
    }

    func testNilStitchResultAlsoSalvages() throws {
        let frame = makeSolid(width: 32, height: 32)
        let job = ScrollingStitchJob(frames: [frame], stitchEngine: NilStitchEngine(), format: .png)
        let output = try job.run()
        XCTAssertNotNil(output.salvageReason)
        XCTAssertEqual(output.pixelSize, CGSize(width: 32, height: 32))
    }

    func testNoFramesStillThrows() {
        let job = ScrollingStitchJob(frames: [], stitchEngine: ThrowingStitchEngine(), format: .png)
        XCTAssertThrowsError(try job.run())
    }

    private func makeSolid(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
