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

    /// Regression for the "repeated browser chrome" bug: each frame is a
    /// static chrome band on top of scrolling content. A naive overlap search
    /// rejects the true overlap (the static band poisons it) and stacks the
    /// chrome many times. The band-aware stitcher must emit the chrome once and
    /// a continuous content strip.
    func testStitchEmitsStaticChromeBandOnlyOnce() throws {
        let width = 64
        let chrome = 30          // static top band
        let frameHeight = 120
        let contentVisible = frameHeight - chrome
        let scrollStep = 20      // content scrolls 20px per frame
        let frameCount = 6

        // Tall content strip the window scrolls through.
        let totalContent = contentVisible + scrollStep * (frameCount - 1)
        let contentStrip = makeGradient(width: width, height: totalContent)
        let chromeBand = makeCheckerboard(width: width, height: chrome, cellSize: 5)

        var frames: [CGImage] = []
        for i in 0..<frameCount {
            // Content window for this frame, then chrome composited on top.
            let slice = try crop(contentStrip, rect: CGRect(x: 0, y: i * scrollStep, width: width, height: contentVisible))
            frames.append(composeTopLeft([chromeBand, slice], width: width))
        }

        let engine = VisionStitchEngine(minOverlapFraction: 0.10, mismatchThreshold: 6.0)
        let stitched = try XCTUnwrap(try engine.stitch(frames: frames))

        // Expected: chrome once + full scrolled content = chrome + totalContent.
        // The coarse overlap search can drift a few px per seam, so allow ~10%;
        // the point is the chrome collapses to a single band, not the exact px.
        let expected = chrome + totalContent
        XCTAssertEqual(stitched.width, width)
        XCTAssertGreaterThanOrEqual(stitched.height, Int(Double(expected) * 0.9))
        XCTAssertLessThanOrEqual(stitched.height, expected + 8)
        // Without the fix the chrome repeats per frame and the height balloons
        // toward frameCount * frameHeight. Prove we're nowhere near that.
        XCTAssertLessThan(stitched.height, frameCount * frameHeight - chrome)
    }

    /// Height assertions alone can pass while the content is scrambled. This
    /// fixture reconstructs a reference gradient from overlapping slices and
    /// verifies the *pixels*: rows must stay monotonically ordered and span
    /// the full reference range, i.e. no repeated, dropped, or reordered
    /// content at the seams.
    func testStitchReconstructsReferenceContentPixels() throws {
        let width = 64
        let frameHeight = 100
        let scrollStep = 30      // 70% overlap between consecutive frames
        let frameCount = 5

        let totalHeight = frameHeight + scrollStep * (frameCount - 1)
        let reference = makeGradient(width: width, height: totalHeight)
        let frames = try (0..<frameCount).map { i in
            try crop(reference, rect: CGRect(x: 0, y: i * scrollStep, width: width, height: frameHeight))
        }

        let engine = VisionStitchEngine(minOverlapFraction: 0.10, mismatchThreshold: 6.0)
        let stitched = try XCTUnwrap(try engine.stitch(frames: frames))
        let rows = try XCTUnwrap(grayscaleRowMeans(stitched))

        // Content integrity: the gradient must come back out as a gradient.
        // Monotonic rows prove nothing was duplicated or reordered at a seam;
        // matching endpoints prove nothing was cropped off either edge. The
        // gradient's direction depends on CG's bottom-left origin, so take
        // the expected ordering from the reference itself.
        let tolerance = 6.0
        let referenceRows = try XCTUnwrap(grayscaleRowMeans(reference))
        let descending = referenceRows.first! > referenceRows.last!
        for pair in zip(rows, rows.dropFirst()) {
            if descending {
                XCTAssertGreaterThanOrEqual(pair.0 + tolerance, pair.1, "rows out of order — seam duplicated or misaligned content")
            } else {
                XCTAssertLessThanOrEqual(pair.0, pair.1 + tolerance, "rows out of order — seam duplicated or misaligned content")
            }
        }
        XCTAssertEqual(rows.first!, referenceRows.first!, accuracy: tolerance)
        XCTAssertEqual(rows.last!, referenceRows.last!, accuracy: tolerance)
    }

    /// Regression for the field-reported "shredded stripes" bug: a rejected
    /// pair (scroll jump) breaks the alignment chain, because the overlap of
    /// the pair *after* the gap was measured against the dropped frame. The
    /// engine must stitch the tallest consecutively-aligned run instead of
    /// pretending the chain survived the gap.
    func testRejectedPairMidCaptureDoesNotShearAlignment() throws {
        let width = 64
        let frameHeight = 100

        let reference = makeGradient(width: width, height: 420)
        // Two clean runs separated by a jump: [0,30,60] then [230,260,290,320].
        let offsets = [0, 30, 60, 230, 260, 290, 320]
        let frames = try offsets.map { y in
            try crop(reference, rect: CGRect(x: 0, y: y, width: width, height: frameHeight))
        }

        let engine = VisionStitchEngine(minOverlapFraction: 0.10, mismatchThreshold: 6.0)
        let stitched = try XCTUnwrap(try engine.stitch(frames: frames))

        // Tallest run is the second one: 100 + 3 × 30 = 190 rows.
        XCTAssertEqual(stitched.width, width)
        XCTAssertGreaterThanOrEqual(stitched.height, 185)
        XCTAssertLessThanOrEqual(stitched.height, 195)

        // No shear: the output must be a continuous slice of the gradient —
        // adjacent row means may differ by at most a few gray levels. The
        // pre-fix chain bug splices distant document regions together, which
        // shows up as a ~60-gray-level cliff at the bad seam.
        let rows = try XCTUnwrap(grayscaleRowMeans(stitched))
        for (index, pair) in zip(rows, rows.dropFirst()).enumerated() {
            XCTAssertLessThanOrEqual(
                abs(pair.0 - pair.1), 4.0,
                "content cliff at row \(index) — alignment sheared across a rejected pair"
            )
        }
    }

    /// Regression for the "over-claimed overlap" field bug: on low-signal
    /// content (sparse text on a flat background) *every* overlap candidate
    /// passes the error threshold, and taking the first one from the top
    /// collapses each frame to a sliver. The true alignment is the error
    /// *minimum* — an exact pixel match — and must win.
    func testSparseContentDoesNotOverClaimOverlap() throws {
        let width = 400
        let frameHeight = 300
        let scrollStep = 30
        let frameCount = 6

        let docHeight = frameHeight + scrollStep * (frameCount - 1)
        let doc = makeSparseDocument(width: width, height: docHeight, background: 0.05, ink: 0.7)
        let frames = try (0..<frameCount).map { i in
            try crop(doc, rect: CGRect(x: 0, y: i * scrollStep, width: width, height: frameHeight))
        }

        let engine = VisionStitchEngine()
        let stitched = try XCTUnwrap(try engine.stitch(frames: frames))

        // Correct: full document reconstructed (450px). Over-claim collapses
        // to barely more than one frame (~305px).
        let expected = docHeight
        XCTAssertGreaterThanOrEqual(stitched.height, expected - 10, "overlap over-claimed — content collapsed to slivers")
        XCTAssertLessThanOrEqual(stitched.height, expected + 10)
    }

    /// Regression for the dark-theme scrolling capture field report: static
    /// chrome over near-black sparse content. The loose static-row threshold
    /// read the *scrolling* content as static (a moved text line barely nudges
    /// the row mean), band detection gave up, and the full-frame path stacked
    /// chrome slivers. Static detection must demand pixel-identical rows.
    func testDarkThemeSparseContentStitchesTall() throws {
        let width = 400
        let frameHeight = 300
        let chrome = 40
        let scrollStep = 30
        let frameCount = 6

        let contentVisible = frameHeight - chrome
        let docHeight = contentVisible + scrollStep * (frameCount - 1)
        // Left-aligned dashes (like a real table) deny band detection the
        // easy signal of text at shifting x positions, and aperiodic chrome
        // denies the full-frame path an accidental chrome-on-chrome match.
        let doc = makeSparseDocument(width: width, height: docHeight, background: 0.05, ink: 0.7, fixedDashX: 20)
        let chromeBand = makeAperiodicStripes(width: width, height: chrome)
        let frames = try (0..<frameCount).map { i in
            let slice = try crop(doc, rect: CGRect(x: 0, y: i * scrollStep, width: width, height: contentVisible))
            return composeTopLeft([chromeBand, slice], width: width)
        }

        let engine = VisionStitchEngine()
        let stitched = try XCTUnwrap(try engine.stitch(frames: frames))

        // Correct: chrome once + the full document. The field failure mode
        // produced ~one frame's height of stacked chrome slivers.
        let expected = chrome + docHeight
        XCTAssertGreaterThanOrEqual(stitched.height, expected - 12, "dark sparse content collapsed — chrome sliver stacking")
        XCTAssertLessThanOrEqual(stitched.height, expected + 12)
    }

    /// A static app sidebar doesn't scroll with the content. It stays in the
    /// output at full window width (user preference), but must be excluded
    /// from the row correlation — its static pixels otherwise poison the
    /// alignment into rejecting every pair.
    func testStaticSidebarStaysInOutputWithoutPoisoningAlignment() throws {
        let width = 400
        let sidebar = 80
        let frameHeight = 300
        let scrollStep = 30
        let frameCount = 5

        let docHeight = frameHeight + scrollStep * (frameCount - 1)
        let doc = makeGradient(width: width - sidebar, height: docHeight)
        let sidebarBand = makeAperiodicStripes(width: sidebar, height: frameHeight)
        let frames = try (0..<frameCount).map { i -> CGImage in
            let slice = try crop(doc, rect: CGRect(x: 0, y: i * scrollStep, width: width - sidebar, height: frameHeight))
            return composeLeftToRight([sidebarBand, slice], height: frameHeight)
        }

        let engine = VisionStitchEngine()
        let stitched = try XCTUnwrap(try engine.stitch(frames: frames))

        // Full window width kept (sidebar included), content reconstructed
        // tall — proving alignment came from the content columns.
        XCTAssertEqual(stitched.width, width, "sidebar must stay in the output")
        XCTAssertGreaterThanOrEqual(stitched.height, docHeight - 10)
        XCTAssertLessThanOrEqual(stitched.height, docHeight + 10)
    }

    /// A scrollbar thumb moves *against* the content, so it can't be stitched
    /// — left in, it smears (field report). The thumb-bearing right-edge
    /// strip must be shaved from the output.
    func testScrollbarThumbStripIsShaved() throws {
        let width = 400
        let track = 16
        let frameHeight = 300
        let scrollStep = 30
        let frameCount = 5

        let docHeight = frameHeight + scrollStep * (frameCount - 1)
        let doc = makeGradient(width: width - track, height: docHeight)
        let frames = try (0..<frameCount).map { i -> CGImage in
            let slice = try crop(doc, rect: CGRect(x: 0, y: i * scrollStep, width: width - track, height: frameHeight))
            let trackBand = makeScrollbarTrack(width: track, height: frameHeight, thumbTop: 10 + i * scrollStep, thumbHeight: 40)
            return composeLeftToRight([slice, trackBand], height: frameHeight)
        }

        let engine = VisionStitchEngine()
        let stitched = try XCTUnwrap(try engine.stitch(frames: frames))

        XCTAssertEqual(stitched.width, width - track, "scrollbar strip not shaved — the thumb would smear")
        XCTAssertGreaterThanOrEqual(stitched.height, docHeight - 10)
        XCTAssertLessThanOrEqual(stitched.height, docHeight + 10)
    }

    // MARK: - Helpers

    /// Place images side by side, left to right.
    private func composeLeftToRight(_ images: [CGImage], height: Int) -> CGImage {
        let totalWidth = images.reduce(0) { $0 + $1.width }
        let context = CGContext(
            data: nil,
            width: totalWidth,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        var x = 0
        for image in images {
            context.draw(image, in: CGRect(x: x, y: 0, width: image.width, height: image.height))
            x += image.width
        }
        return context.makeImage()!
    }

    /// Scrollbar-like strip: flat track with a darker thumb block at a given
    /// vertical position.
    private func makeScrollbarTrack(width: Int, height: Int, thumbTop: Int, thumbHeight: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        // Visual thumbTop → CG bottom-left flip.
        context.fill(CGRect(x: 2, y: height - thumbTop - thumbHeight, width: width - 4, height: thumbHeight))
        return context.makeImage()!
    }

    /// Near-flat "document": `background` everywhere, with a thin 3-row text
    /// dash every 40 rows covering ~3% of the width — misaligned rows differ
    /// by ~5 mean gray levels, under the correlation threshold of 6, which is
    /// what makes low-signal content adversarial.
    private func makeSparseDocument(width: Int, height: Int, background: CGFloat, ink: CGFloat, fixedDashX: Int? = nil) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: background, green: background, blue: background, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dashWidth = width * 3 / 100
        var lineIndex = 0
        for y in stride(from: 8, to: height - 3, by: 40) {
            let x = fixedDashX ?? (lineIndex * 53) % (width - dashWidth)
            context.setFillColor(red: ink, green: ink, blue: ink, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: dashWidth, height: 3))
            lineIndex += 1
        }
        return context.makeImage()!
    }

    /// Horizontal stripes with irregular heights and grays — static "chrome"
    /// that can't accidentally self-align at a wrong offset.
    private func makeAperiodicStripes(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        var y = 0
        var index = 0
        while y < height {
            let stripeHeight = 3 + (index * 7) % 9
            let gray = 0.3 + CGFloat((index * 31) % 60) / 100.0
            context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
            context.fill(CGRect(x: 0, y: y, width: width, height: stripeHeight))
            y += stripeHeight
            index += 1
        }
        return context.makeImage()!
    }

    /// Mean gray value of each row, top row first.
    private func grayscaleRowMeans(_ image: CGImage) -> [Double]? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return (0..<height).map { y in
            let row = pixels[(y * width)..<((y + 1) * width)]
            return row.reduce(0.0) { $0 + Double($1) } / Double(width)
        }
    }

    /// Stack images top-to-bottom (first = top) into one CGImage.
    private func composeTopLeft(_ images: [CGImage], width: Int) -> CGImage {
        let totalHeight = images.reduce(0) { $0 + $1.height }
        let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        var topOffset = 0
        for image in images {
            context.draw(image, in: CGRect(x: 0, y: totalHeight - topOffset - image.height, width: width, height: image.height))
            topOffset += image.height
        }
        return context.makeImage()!
    }

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
