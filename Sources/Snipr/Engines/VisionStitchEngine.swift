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

        // Common width — scrolling capture should be from the same window
        // filter at fixed resolution, so width should match. We don't try
        // to scale frames; the caller is responsible for delivering
        // consistent geometry.
        let width = frames[0].width
        guard frames.allSatisfy({ $0.width == width }) else {
            throw StitchError.unequalWidths
        }

        let buffers = frames.map { GrayscaleBuffer(image: $0) }
        guard buffers.allSatisfy({ $0 != nil }) else {
            throw StitchError.unequalWidths
        }
        let unwrapped = buffers.compactMap { $0 }

        // Determine accepted overlaps for each consecutive pair. `accepted`
        // mirrors `unwrapped[1...]` — index i refers to the pair
        // (unwrapped[i], unwrapped[i + 1]).
        var acceptedOverlaps: [Int] = []
        acceptedOverlaps.reserveCapacity(unwrapped.count - 1)

        for index in 0..<(unwrapped.count - 1) {
            let top = unwrapped[index]
            let bottom = unwrapped[index + 1]
            let overlap = bestVerticalOverlap(top: top, bottom: bottom, threshold: mismatchThreshold)
            let minRequired = Int(Double(min(top.height, bottom.height)) * minOverlapFraction)
            if overlap >= minRequired, overlap > 0 {
                acceptedOverlaps.append(overlap)
            } else {
                // Reject this pair. Keep the previous frame, drop the new
                // one. Practically this means a fast scroll just causes a
                // longer wait until the user slows down again.
                acceptedOverlaps.append(-1)
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

        // Walk from the largest plausible overlap down to 1. The first
        // overlap whose mean-absolute-error is below `threshold` is the
        // answer. Walking from large→small biases toward "more of the new
        // frame is duplicate" which is what slow scrolling produces.
        var overlap = maxOverlap
        while overlap > 0 {
            let mae = meanAbsoluteError(
                topRows: top,
                bottomRows: bottom,
                rows: overlap
            )
            if mae <= threshold {
                return overlap
            }
            // Coarse search at large overlaps (step by 4) for speed; the
            // closer we get to no-overlap the harder the alignment is to
            // find by chance, so step finer near the bottom.
            overlap -= overlap > 32 ? 2 : 1
        }
        return 0
    }

    private func meanAbsoluteError(topRows top: GrayscaleBuffer, bottomRows bottom: GrayscaleBuffer, rows: Int) -> Double {
        // Compare `rows` rows from the bottom of `top` against the top
        // `rows` rows of `bottom`. Both buffers have the same `width`.
        let width = top.width
        let topStart = (top.height - rows) * width
        let bottomStart = 0
        let pixelCount = rows * width

        var sum: Double = 0
        top.bytes.withUnsafeBufferPointer { topPtr in
            bottom.bytes.withUnsafeBufferPointer { bottomPtr in
                for i in 0..<pixelCount {
                    let a = Int(topPtr[topStart + i])
                    let b = Int(bottomPtr[bottomStart + i])
                    sum += Double(abs(a - b))
                }
            }
        }
        return sum / Double(pixelCount)
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
