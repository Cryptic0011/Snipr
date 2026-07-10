import XCTest
@testable import Snipr

final class CursorSamplerTests: XCTestCase {
    func testMapToVideoPixelsFlipsYAndScales() {
        // Region: 100pt-wide, 50pt-tall region whose bottom-left global
        // corner is (10, 20). 2x display → video pixels are 200×100.
        let region = CGRect(x: 10, y: 20, width: 100, height: 50)
        // Bottom-left corner of the region → (0, maxYPixels)
        XCTAssertEqual(
            CursorPath.mapToVideoPixels(CGPoint(x: 10, y: 20), region: region, scale: 2),
            CGPoint(x: 0, y: 100)
        )
        // Top-left corner → origin in top-left video space
        XCTAssertEqual(
            CursorPath.mapToVideoPixels(CGPoint(x: 10, y: 70), region: region, scale: 2),
            CGPoint(x: 0, y: 0)
        )
        // Center maps to center
        XCTAssertEqual(
            CursorPath.mapToVideoPixels(CGPoint(x: 60, y: 45), region: region, scale: 2),
            CGPoint(x: 100, y: 50)
        )
    }

    func testThinnedKeepsFirstAndLastAndStride() {
        let samples = (0..<10).map { CursorSample(time: Double($0), location: CGPoint(x: Double($0), y: 0)) }
        let thinned = CursorPath.thinned(samples, stride: 4)
        XCTAssertEqual(thinned.map(\.time), [0, 4, 8, 9])   // every 4th + last
        XCTAssertEqual(CursorPath.thinned(samples, stride: 1), samples)
        XCTAssertEqual(CursorPath.thinned([], stride: 4), [])
    }

    @MainActor
    func testSamplerCollectsSamplesWhileRunning() async throws {
        let sampler = CursorSampler()
        sampler.start()
        XCTAssertTrue(sampler.isSampling)
        try await Task.sleep(nanoseconds: 200_000_000)   // ~12 ticks at 60 Hz
        let samples = sampler.stop()
        XCTAssertFalse(sampler.isSampling)
        XCTAssertGreaterThan(samples.count, 3)
        // Times are monotonically nondecreasing and start near zero.
        XCTAssertEqual(samples.map(\.time), samples.map(\.time).sorted())
        XCTAssertLessThan(samples[0].time, 0.1)
    }
}
