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

        // Rows scroll; columns don't. A static app sidebar or a scrollbar
        // thumb (which moves *against* the content) can never be vertically
        // stitched. The sidebar stays in the OUTPUT (users want the whole
        // window), but must stay out of the CORRELATION — its static pixels
        // poison the row alignment. The scrollbar strip is shaved from the
        // output too: a smeared thumb is pure noise.
        let columns = sideCropRange(frames, width: width, height: height)
        var workingFrames = frames          // output frames (keep sidebar)
        var workingWidth = width
        if columns.upperBound < width {     // right side: scrollbar shave only
            let rect = CGRect(x: 0, y: 0, width: columns.upperBound, height: height)
            let cropped = frames.compactMap { $0.cropping(to: rect) }
            if cropped.count == frames.count {
                workingFrames = cropped
                workingWidth = columns.upperBound
            }
        }
        var correlationFrames = workingFrames
        var correlationWidth = workingWidth
        if columns.lowerBound > 0 {         // left side: exclude from correlation
            let rect = CGRect(x: columns.lowerBound, y: 0, width: workingWidth - columns.lowerBound, height: height)
            let cropped = workingFrames.compactMap { $0.cropping(to: rect) }
            if cropped.count == workingFrames.count {
                correlationFrames = cropped
                correlationWidth = workingWidth - columns.lowerBound
            }
        }

        // A captured window is `[static chrome band][scrolling content][maybe
        // static footer]`. Only the content is a vertical translation between
        // frames; the static bands fool the row-correlation into rejecting the
        // true (large) overlap, so it stacks near-duplicate frames and repeats
        // the chrome. Detect the static bands, stitch only the content, and
        // re-add each band exactly once.
        let bands = staticBandHeights(correlationFrames, width: correlationWidth, height: height)
        guard bands.top > 0 || bands.bottom > 0 else {
            return try stitchTranslating(workingFrames, correlating: correlationFrames)
        }

        let dynamicHeight = height - bands.top - bands.bottom
        let dynamicRect = CGRect(x: 0, y: bands.top, width: workingWidth, height: dynamicHeight)
        let contentFrames = workingFrames.compactMap { $0.cropping(to: dynamicRect) }
        let correlationRect = CGRect(x: 0, y: bands.top, width: correlationWidth, height: dynamicHeight)
        let contentCorrelation = correlationFrames.compactMap { $0.cropping(to: correlationRect) }
        guard contentFrames.count == workingFrames.count,
              contentCorrelation.count == contentFrames.count else {
            return try stitchTranslating(workingFrames, correlating: correlationFrames)
        }
        let content: CGImage?
        do {
            content = try stitchTranslating(contentFrames, correlating: contentCorrelation)
        } catch {
            // Band detection can guess wrong (e.g. a page-wide sticky element
            // misread as chrome). Fall back to full-frame stitching, which the
            // pre-band code always used, rather than failing the whole stitch.
            return try stitchTranslating(workingFrames, correlating: correlationFrames)
        }
        guard let content else { return nil }

        // Re-add the static bands once: top from the first frame, footer from
        // the last (they're identical across frames by definition).
        let topBand = bands.top > 0
            ? workingFrames.first?.cropping(to: CGRect(x: 0, y: 0, width: workingWidth, height: bands.top))
            : nil
        let bottomBand = bands.bottom > 0
            ? workingFrames.last?.cropping(to: CGRect(x: 0, y: height - bands.bottom, width: workingWidth, height: bands.bottom))
            : nil
        return composeVertically([topBand, content, bottomBand].compactMap { $0 }, width: workingWidth)
    }

    /// Detect the scrolling column range. Edge columns that are
    /// pixel-identical across sampled frames (app sidebars, window padding)
    /// are excluded, as is a right-edge scrollbar strip — identifiable as a
    /// strip that is static except for a bounded run of thumb rows.
    private func sideCropRange(_ frames: [CGImage], width: Int, height: Int) -> Range<Int> {
        let rasters = sampledRasters(frames, width: width, height: height)
        guard rasters.count >= 2, let reference = rasters.first else { return 0..<width }
        let staticThreshold = 1.0

        func columnIsStatic(_ x: Int) -> Bool {
            for raster in rasters.dropFirst() {
                var sum = 0
                var y = 0
                while y < height {
                    sum += abs(Int(reference[y * width + x]) - Int(raster[y * width + x]))
                    y += 1
                }
                if Double(sum) / Double(height) > staticThreshold { return false }
            }
            return true
        }

        var left = 0
        while left < width, columnIsStatic(left) { left += 1 }
        var right = width
        while right > left, columnIsStatic(right - 1) { right -= 1 }
        // A mostly-static width means the heuristic is unreliable (barely any
        // scroll, or a tiny scrolled pane) — keep the full frame.
        guard right - left >= width / 4 else { return 0..<width }

        // Overlay scrollbars hug the right edge of the pane. A thumb column is
        // "dynamic" but, unlike content, differs on only a bounded fraction of
        // rows (its positions across samples). Walk the thumb-like run in from
        // the right edge and shave it, plus any track margin it was hiding. A
        // run wider than a plausible scrollbar means sparse content — keep it.
        // ponytail: fraction heuristic; build a real thumb tracker if this
        // misfires.
        func columnDifferingFraction(_ x: Int) -> Double {
            var maxFraction = 0.0
            for raster in rasters.dropFirst() {
                var differingRows = 0
                for y in 0..<height where abs(Int(reference[y * width + x]) - Int(raster[y * width + x])) > 2 {
                    differingRows += 1
                }
                maxFraction = max(maxFraction, Double(differingRows) / Double(height))
            }
            return maxFraction
        }
        let maxScrollbarWidth = max(20, width / 80)
        var thumbRun = 0
        while thumbRun <= maxScrollbarWidth, right - thumbRun > left {
            let fraction = columnDifferingFraction(right - thumbRun - 1)
            guard fraction > 0, fraction <= 0.6 else { break }
            thumbRun += 1
        }
        if thumbRun > 0, thumbRun <= maxScrollbarWidth, right - left - thumbRun >= width / 4 {
            right -= thumbRun
            while right > left, columnIsStatic(right - 1) { right -= 1 }
        }
        return left..<right
    }

    /// Up to 6 frames spread across the capture, rasterized to top-left
    /// grayscale. Shared by the static-band and static-column detectors.
    private func sampledRasters(_ frames: [CGImage], width: Int, height: Int) -> [[UInt8]] {
        guard frames.count >= 2, width > 0, height > 0 else { return [] }
        let sampleCount = min(6, frames.count)
        let step = max(1, (frames.count - 1) / max(1, sampleCount - 1))
        let samples = stride(from: 0, to: frames.count, by: step).map { frames[$0] }
        return samples.compactMap { Self.topLeftGrayscale($0, width: width, height: height) }
    }

    /// - Parameter correlationFrames: optional column-cropped variants of
    ///   `frames` (same order, same heights) used for overlap detection only.
    ///   Lets static side columns (sidebars) stay in the composited output
    ///   without poisoning the row correlation.
    private func stitchTranslating(_ frames: [CGImage], correlating correlationFrames: [CGImage]? = nil) throws -> CGImage? {
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
        let correlationSource = correlationFrames ?? frames
        guard correlationSource.count == frames.count,
              correlationSource.allSatisfy({ $0.width == correlationSource[0].width }) else {
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
                base[i] = GrayscaleBuffer(image: correlationSource[i])
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

        // A rejected pair breaks the alignment chain: each accepted overlap is
        // measured against the immediately preceding frame, so once a frame is
        // dropped, the overlaps after the gap are meaningless relative to the
        // last kept frame. Splicing across the gap shears the composite (the
        // "shredded stripes" field bug). Stitch the tallest run of
        // consecutively-accepted pairs instead.
        var runs: [(start: Int, overlaps: [Int])] = []
        var current: (start: Int, overlaps: [Int]) = (0, [])
        for (index, overlap) in acceptedOverlaps.enumerated() {
            if overlap >= 0 {
                current.overlaps.append(overlap)
            } else {
                runs.append(current)
                current = (index + 1, [])
            }
        }
        runs.append(current)

        func runHeight(_ run: (start: Int, overlaps: [Int])) -> Int {
            frames[run.start].height + run.overlaps.enumerated().reduce(0) { acc, pair in
                acc + frames[run.start + pair.offset + 1].height - pair.element
            }
        }
        let best = runs.max { runHeight($0) < runHeight($1) }!
        let keptFrames = (best.start...(best.start + best.overlaps.count)).map { frames[$0] }
        let keptOverlaps = best.overlaps

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
        // a few px off read as noise on high-frequency content. Scan EVERY
        // overlap and take the global error minimum. Accepting the first
        // candidate under the threshold instead is the field-reported sliver
        // bug: on low-signal content (dark themes, sparse text, blank pages)
        // nearly every misalignment stays under the threshold, so the scan
        // from the top "matches" at an absurdly large overlap and each frame
        // contributes only a sliver. The true alignment is an exact pixel
        // match — the minimum — even when the threshold can't discriminate.
        // Each candidate is cheap: subsample columns (~96) and rows (≤128);
        // sampled rows still align exactly, so the dip survives sampling.
        let coarseStride = max(1, top.width / 96)   // sample ~96 columns

        var coarseHit = -1
        var coarseBest = Double.greatestFiniteMagnitude
        var overlap = maxOverlap
        while overlap > 0 {
            // Strict `<` scanning from the largest overlap: ties (flat
            // regions where any alignment matches) keep the larger overlap,
            // which de-duplicates frames captured while the user paused.
            let mae = meanAbsoluteError(topRows: top, bottomRows: bottom, rows: overlap, columnStride: coarseStride, maxSampledRows: 128)
            if mae < coarseBest {
                coarseBest = mae
                coarseHit = overlap
            }
            overlap -= 1
        }
        guard coarseHit >= 0, coarseBest <= threshold else { return 0 }

        // Refine at full precision around the subsampled minimum.
        let hi = min(maxOverlap, coarseHit + 12)
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

    private func meanAbsoluteError(topRows top: GrayscaleBuffer, bottomRows bottom: GrayscaleBuffer, rows: Int, columnStride: Int = 1, maxSampledRows: Int = .max) -> Double {
        // Compare `rows` rows from the bottom of `top` against the top
        // `rows` rows of `bottom`. Both buffers have the same `width`.
        // `columnStride` samples every Nth column and `maxSampledRows` caps
        // the rows compared (evenly strided); sampled rows keep their exact
        // vertical position, so the recovered overlap stays exact.
        let width = top.width
        let topStart = (top.height - rows) * width
        let rowStride = max(1, rows / max(1, maxSampledRows))

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
                    row += rowStride
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
        let rasters = sampledRasters(frames, width: width, height: height)
        guard rasters.count >= 2, let reference = rasters.first else { return (0, 0) }

        // Truly static rows (chrome, sidebars) are pixel-identical across
        // frames — SCK delivers exact pixels, nothing dithers. The loose
        // correlation threshold must NOT be reused here: on dark themes a
        // *scrolled* sparse text row only nudges the row mean by a few gray
        // levels, so under the loose threshold the whole content region reads
        // "static", band detection gives up, and the full-frame path stacks
        // chrome slivers (field-reported bug).
        let staticRowThreshold = 1.0
        func rowIsStatic(_ y: Int) -> Bool {
            let base = y * width
            for raster in rasters.dropFirst() {
                var sum = 0
                for x in 0..<width {
                    sum += abs(Int(reference[base + x]) - Int(raster[base + x]))
                }
                if Double(sum) / Double(width) > staticRowThreshold { return false }
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
