import CoreGraphics
import Foundation

/// Pluggable scrolling-stitch surface. Phase 4 ships a `VisionStitchEngine`
/// using vImage row-correlation; tests substitute a fake to verify the
/// presenter wiring without driving SCStream.
///
/// The engine consumes a sequence of frames captured at 8–10 fps from a
/// single window and produces one tall composite. Frames where consecutive
/// vertical overlap is < 20% (the user scrolled too fast) are rejected
/// rather than misregistered.
protocol StitchEngine: Sendable {
    /// Stitch the given frames into a single tall image.
    ///
    /// - Parameter frames: Captured frames in temporal order; the first
    ///   frame is the top of the composite, subsequent frames append below.
    /// - Returns: A single CGImage whose height equals the sum of input
    ///   heights minus detected overlap. Returns `nil` if `frames` is empty
    ///   or no usable overlap could be found across consecutive frames.
    func stitch(frames: [CGImage]) throws -> CGImage?
}

enum StitchError: LocalizedError {
    case noFrames
    case unequalWidths
    case allFramesRejected

    var errorDescription: String? {
        switch self {
        case .noFrames:
            "No frames were captured."
        case .unequalWidths:
            "Frames must share a common width to be stitched."
        case .allFramesRejected:
            "Snipr could not align any consecutive frames — try scrolling more slowly."
        }
    }
}
