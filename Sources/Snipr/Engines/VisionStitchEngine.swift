import Accelerate
import CoreGraphics
import Foundation

/// Default `StitchEngine` powered by row-by-row pixel correlation.
///
/// The algorithm is deliberately simple and self-contained so it stays
/// testable from offline fixtures:
///
/// 1. Convert every frame to a planar grayscale buffer (one byte per pixel)
///    — color isn't needed for vertical-shift correlation.
/// 2. For each consecutive pair (A, B), search for the largest `overlap`
///    such that the bottom `overlap` rows of A match the top `overlap` rows
///    of B (mean-absolute-error below `mismatchThreshold`).
/// 3. Reject pairs where the best `overlap < minOverlapFraction * height`
///    — that means the user scrolled too fast and we'd produce a visibly
///    misaligned seam if we forced a stitch.
/// 4. Composite kept frames into a single CGImage; the first frame is drawn
///    in full, subsequent frames are drawn with their overlap region
///    sliced off so the seam lines up.
///
/// This is the kernel — the integration layer (frame collector + progress
/// HUD) lives separately and is tested manually rather than from offline
/// fixtures, since SCStream against arbitrary windows can't be exercised in
/// a unit test.
struct VisionStitchEngine: StitchEngine {
    /// Minimum vertical overlap (as a fraction of the shorter frame's
    /// height) before we trust the correlation result. The plan calls for
    /// 20%; the default keeps that floor.
    let minOverlapFraction: Double
    /// Per-pixel mean absolute error tolerated when declaring two row sets
    /// "matching". Tuned for sRGB byte data where 0…255 is the channel
    /// range; ~6 lets through anti-aliasing differences without permitting
    /// genuinely different content to claim a match.
    let mismatchThreshold: Double

    init(minOverlapFraction: Double = 0.20, mismatchThreshold: Double = 6.0) {
        self.minOverlapFraction = minOverlapFraction
        self.mismatchThreshold = mismatchThreshold
    }

    func stitch(frames: [CGImage]) throws -> CGImage? {
        guard !frames.isEmpty else { throw StitchError.noFrames }
        if frames.count == 1 { return frames[0] }

        let width = frames[0].width
        guard frames.allSatisfy({ $0.width == width }) else {
            throw StitchError.unequalWidths
        }
        let height = frames[0].height
        guard frames.allSatisfy({ $0.height == height }) else {
            // Mixed heights mean the window resized mid-scroll. The
            // translation stitcher tolerates it; band detection needs a
            // common geometry, so skip it.
            return try stitchTranslating(frames)
        }

        // A captured window is `[static chrome band][scrolling content][maybe
        // static footer]`. Only the content is a vertical translation between
        // frames; the static bands fool the row-correlation into rejecting the
        // true (large) overlap, so it stacks near-duplicate frames and repeats
        // the chrome. Detect the static bands, stitch only the content, and
        // re-add each band exactly once.
        let bands = staticBandHeights(frames, width: width, height: height)
        guard bands.top > 0 || bands.bottom > 0 else {
            return try stitchTranslating(frames)
        }

        let dynamicHeight = height - bands.top - bands.bottom
        let dynamicRect = CGRect(x: 0, y: bands.top, width: width, height: dynamicHeight)
        let contentFrames = frames.compactMap { $0.cropping(to: dynamicRect) }
        guard contentFrames.count == frames.count else {
            return try stitchTranslating(frames)
        }
        let content: CGImage?
        do {
            content = try stitchTranslating(contentFrames)
        } catch {
            // Band detection can guess wrong (e.g. a page-wide sticky element
            // misread as chrome). Fall back to full-frame stitching, which the
            // pre-band code always used, rather than failing the whole stitch.
            return try stitchTranslating(frames)
        }
        guard let content else { return nil }

        // Re-add the static bands once: top from the first frame, footer from
        // the last (they're identical across frames by definition).
        let topBand = bands.top > 0
            ? frames.first?.cropping(to: CGRect(x: 0, y: 0, width: width, height: bands.top))
            : nil
        let bottomBand = bands.bottom > 0
            ? frames.last?.cropping(to: CGRect(x: 0, y: height - bands.bottom, width: width, height: bands.bottom))
            : nil
        return composeVertically([topBand, content, bottomBand].compactMap { $0 }, width: width)
    }

    private func stitchTranslating(_ frames: [CGImage]) throws -> CGImage? {
        guard !frames.isEmpty else { throw StitchError.noFrames }
        if frames.count == 1 { return frames[0] }

        // Common width — scrolling capture should be from the same window
        // filter at fixed resolution, so width should match. We don't try
        // to scale frames; the caller is responsible for delivering
        // consistent geometry.
        let width = frames[0].width
        guard frames.allSatisfy({ $0.width == width }) else {
            throw StitchError.unequalWidths
        }

        // Rasterize to grayscale in parallel — each frame is independent and
        // the per-frame draw is the second-biggest cost after correlation.
        var optionalBuffers = [GrayscaleBuffer?](repeating: nil, count: frames.count)
        optionalBuffers.withUnsafeMutableBufferPointer { buf in
            // Each iteration writes a distinct index, so the shared base
            // pointer is safe to hand to concurrent workers.
            nonisolated(unsafe) let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: frames.count) { i in
                base[i] = GrayscaleBuffer(image: frames[i])
            }
        }
        guard optionalBuffers.allSatisfy({ $0 != nil }) else {
            throw StitchError.unequalWidths
        }
        let unwrapped = optionalBuffers.compactMap { $0 }

        // Determine accepted overlaps for each consecutive pair. `accepted`
        // mirrors `unwrapped[1...]` — index i refers to the pair
        // (unwrapped[i], unwrapped[i + 1]). The pairs are independent, so run
        // the correlation (the dominant cost) across all cores.
        var acceptedOverlaps = [Int](repeating: -1, count: unwrapped.count - 1)
        acceptedOverlaps.withUnsafeMutableBufferPointer { buf in
            // Distinct index per iteration → the shared base pointer is safe.
            nonisolated(unsafe) let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: buf.count) { index in
                let top = unwrapped[index]
                let bottom = unwrapped[index + 1]
                let overlap = bestVerticalOverlap(top: top, bottom: bottom, threshold: mismatchThreshold)
                let minRequired = Int(Double(min(top.height, bottom.height)) * minOverlapFraction)
                // Reject (-1) a pair whose overlap is below the floor — a fast
                // scroll just means a longer wait until the user slows down.
                base[index] = (overlap >= minRequired && overlap > 0) ? overlap : -1
            }
        }

        // If every pair was rejected we have only the first frame to show.
        // Better to surface the failure than emit a single frame masquerading
        // as a "scrolling capture" — the user expects a tall composite.
        if acceptedOverlaps.allSatisfy({ $0 < 0 }) {
            throw StitchError.allFramesRejected
        }

        // Build the output canvas. Heights of frames we keep, with each
        // subsequent frame contributing (height − overlap).
        var keptFrames: [CGImage] = [frames[0]]
        var keptOverlaps: [Int] = []
        for (index, overlap) in acceptedOverlaps.enumerated() where overlap >= 0 {
            keptFrames.append(frames[index + 1])
            keptOverlaps.append(overlap)
        }

        let totalHeight = keptFrames.first!.height +
            zip(keptFrames.dropFirst(), keptOverlaps).reduce(0) { acc, pair in
                acc + (pair.0.height - pair.1)
            }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Core Graphics origin is bottom-left. We draw top-aligned by
        // walking the kept frames and tracking the y-cursor from the top
        // of the canvas.
        var consumed = 0
        let firstHeight = keptFrames[0].height
        // First frame: drawn in full at the very top.
        context.draw(
            keptFrames[0],
            in: CGRect(x: 0, y: totalHeight - firstHeight, width: width, height: firstHeight)
        )
        consumed += firstHeight

        for (offset, overlap) in keptOverlaps.enumerated() {
            let frame = keptFrames[offset + 1]
            // The bottom `overlap` rows of the previous frame already cover
            // the top `overlap` rows of `frame`; we draw `frame` starting
            // `overlap` rows below the previous frame's bottom edge.
            let drawHeight = frame.height - overlap
            // Crop the top `overlap` rows of `frame` (in CG coords those are
            // the bottom rows of `frame.cropping(to:)` because of the
            // bottom-left origin). Easiest: draw the whole `frame` shifted
            // up by `overlap` rows.
            let drawY = totalHeight - consumed - drawHeight + overlap
            // Adjust: we want the top of `frame` to land directly under the
            // previously drawn frame's last unique row. Since draw uses CG
            // coords, the top of `frame` is at y = drawY + frame.height.
            // We compute drawY so that the top is at consumed - overlap from
            // top, equivalently y = totalHeight - (consumed - overlap) - frame.height.
            let correctedY = totalHeight - (consumed - overlap) - frame.height
            context.draw(
                frame,
                in: CGRect(x: 0, y: correctedY, width: width, height: frame.height)
            )
            consumed += drawHeight
            _ = drawY  // Reserved variable retained for future debug
        }

        return context.makeImage()
    }

    /// Search overlaps from the largest plausible value down; first match
    /// wins. We cap the search at `min(top.height, bottom.height) - 1` to
    /// avoid the trivial 100% overlap case (which would mean "no scroll
    /// happened").
    private func bestVerticalOverlap(top: GrayscaleBuffer, bottom: GrayscaleBuffer, threshold: Double) -> Int {
        let maxOverlap = min(top.height, bottom.height) - 1
        guard maxOverlap > 0 else { return 0 }

        // The MAE surface is a sharp dip at the true alignment: candidates even
        // a few px off read as noise on high-frequency content. Stepping the
        // *overlap* coarsely therefore walks straight past the dip and rejects
        // stitchable pairs. Instead, test every overlap but make each test
        // cheap by subsampling columns (~96 of them) — rows stay exact, so the
        // dip is still visible — then refine full-width around the hit.
        let coarseStride = max(1, top.width / 96)   // sample ~96 columns

        var coarseHit = -1
        var overlap = maxOverlap
        while overlap > 0 {
            if meanAbsoluteError(topRows: top, bottomRows: bottom, rows: overlap, columnStride: coarseStride) <= threshold {
                coarseHit = overlap
                break
            }
            overlap -= 1
        }
        guard coarseHit >= 0 else { return 0 }

        // Refine at full precision in a window around the subsampled hit and
        // take the *best-aligned* overlap (minimum error), not merely the first
        // under threshold. Several overlaps near a smooth seam can pass the
        // threshold; the largest of them over-claims the overlap and drops a
        // sliver of content — that's the residual tearing. The error minimum is
        // the true pixel alignment. Search a little wide on the low side in
        // case the subsampled pass over-estimated the overlap.
        let hi = min(maxOverlap, coarseHit + 2)
        let lo = max(1, coarseHit - 12)
        var bestOverlap = -1
        var bestError = Double.greatestFiniteMagnitude
        var fine = hi
        while fine >= lo {
            let mae = meanAbsoluteError(topRows: top, bottomRows: bottom, rows: fine, columnStride: 1)
            if mae < bestError {
                bestError = mae
                bestOverlap = fine
            }
            fine -= 1
        }
        return (bestError <= threshold && bestOverlap > 0) ? bestOverlap : 0
    }

    private func meanAbsoluteError(topRows top: GrayscaleBuffer, bottomRows bottom: GrayscaleBuffer, rows: Int, columnStride: Int = 1) -> Double {
        // Compare `rows` rows from the bottom of `top` against the top
        // `rows` rows of `bottom`. Both buffers have the same `width`.
        // `columnStride` samples every Nth column (full rows are always kept,
        // so the recovered overlap stays vertically exact).
        let width = top.width
        let topStart = (top.height - rows) * width

        var sum: Double = 0
        var count = 0
        top.bytes.withUnsafeBufferPointer { topPtr in
            bottom.bytes.withUnsafeBufferPointer { bottomPtr in
                var row = 0
                while row < rows {
                    let topBase = topStart + row * width
                    let bottomBase = row * width
                    var col = 0
                    while col < width {
                        let a = Int(topPtr[topBase + col])
                        let b = Int(bottomPtr[bottomBase + col])
                        sum += Double(abs(a - b))
                        count += 1
                        col += columnStride
                    }
                    row += 1
                }
            }
        }
        return count == 0 ? .greatestFiniteMagnitude : sum / Double(count)
    }

    /// Detect the contiguous static (non-scrolling) bands at the top and
    /// bottom of the frames — browser chrome, sticky headers, fixed footers.
    /// A row is "static" when it stays within `mismatchThreshold` across a
    /// handful of frames sampled across the whole capture. Coordinates are in
    /// top-left pixel space (row 0 = visual top).
    private func staticBandHeights(_ frames: [CGImage], width: Int, height: Int) -> (top: Int, bottom: Int) {
        guard frames.count >= 2, width > 0, height > 0 else { return (0, 0) }

        // Sample up to 6 frames spread across the capture so we compare frames
        // that actually scrolled relative to each other.
        let sampleCount = min(6, frames.count)
        let step = max(1, (frames.count - 1) / max(1, sampleCount - 1))
        let samples = stride(from: 0, to: frames.count, by: step).map { frames[$0] }
        let rasters = samples.compactMap { Self.topLeftGrayscale($0, width: width, height: height) }
        guard rasters.count >= 2, let reference = rasters.first else { return (0, 0) }

        func rowIsStatic(_ y: Int) -> Bool {
            let base = y * width
            for raster in rasters.dropFirst() {
                var sum = 0
                for x in 0..<width {
                    sum += abs(Int(reference[base + x]) - Int(raster[base + x]))
                }
                if Double(sum) / Double(width) > mismatchThreshold { return false }
            }
            return true
        }

        var top = 0
        while top < height, rowIsStatic(top) { top += 1 }
        var bottom = 0
        while bottom < height - top, rowIsStatic(height - 1 - bottom) { bottom += 1 }

        // If the dynamic region is tiny the heuristic is unreliable (e.g. the
        // user barely scrolled, so most rows look static). Fall back to the
        // plain translation stitcher rather than crop away real content.
        guard height - top - bottom >= height / 4 else { return (0, 0) }
        return (top, bottom)
    }

    /// Rasterize an image to single-channel grayscale. Drawing a CGImage into
    /// a fresh bitmap context yields byte row 0 == the visual top edge, which
    /// matches `CGImage.cropping(to:)`'s top-left rect convention.
    private static func topLeftGrayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard image.width == width, image.height == height else { return nil }
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
        return ok ? pixels : nil
    }

    /// Stack images top-to-bottom into one canvas, in array order.
    private func composeVertically(_ images: [CGImage], width: Int) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let totalHeight = images.reduce(0) { $0 + $1.height }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CG origin is bottom-left; walk a top offset and draw each piece.
        var topOffset = 0
        for image in images {
            context.draw(
                image,
                in: CGRect(x: 0, y: totalHeight - topOffset - image.height, width: width, height: image.height)
            )
            topOffset += image.height
        }
        return context.makeImage()
    }
}

/// Planar 8-bit grayscale buffer used by the row-correlation kernel. We
/// rasterize each frame once at construction time and keep the bytes around
/// so consecutive comparisons don't redecode the source.
private struct GrayscaleBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        let success = pixels.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }

        self.width = width
        self.height = height
        self.bytes = pixels
    }
}
