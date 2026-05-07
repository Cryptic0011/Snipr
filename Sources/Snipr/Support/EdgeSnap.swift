import CoreGraphics
import Foundation

/// Pure snap math, lifted out of `CaptureSelectionNSView` so the OverlayPresenter
/// tests can verify behavior without simulating drag events.
enum EdgeSnap {
    /// Threshold in points: snap edges within this distance of a window edge.
    /// 8 px matches the value documented in plan.md.
    static let threshold: CGFloat = 8

    /// Snap a selection rect's edges (min/max X, min/max Y) to the nearest
    /// edge among `windowEdges` if it falls inside `threshold`.
    ///
    /// `windowEdges` is a flat list of axis-aligned candidate values produced
    /// from the on-screen window list (each window contributes minX, maxX,
    /// minY, maxY for both X and Y respectively — we keep them split so the
    /// caller can pre-bucket if needed). Returns the snapped rect.
    static func snapped(
        rect: CGRect,
        xEdges: [CGFloat],
        yEdges: [CGFloat],
        threshold: CGFloat = threshold
    ) -> CGRect {
        let snappedMinX = nearestSnap(value: rect.minX, candidates: xEdges, threshold: threshold)
        let snappedMaxX = nearestSnap(value: rect.maxX, candidates: xEdges, threshold: threshold)
        let snappedMinY = nearestSnap(value: rect.minY, candidates: yEdges, threshold: threshold)
        let snappedMaxY = nearestSnap(value: rect.maxY, candidates: yEdges, threshold: threshold)

        let minX = snappedMinX ?? rect.minX
        let maxX = snappedMaxX ?? rect.maxX
        let minY = snappedMinY ?? rect.minY
        let maxY = snappedMaxY ?? rect.maxY

        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    static func nearestSnap(value: CGFloat, candidates: [CGFloat], threshold: CGFloat) -> CGFloat? {
        var best: (candidate: CGFloat, distance: CGFloat)?
        for candidate in candidates {
            let distance = abs(candidate - value)
            if distance <= threshold {
                if let current = best {
                    if distance < current.distance {
                        best = (candidate, distance)
                    }
                } else {
                    best = (candidate, distance)
                }
            }
        }
        return best?.candidate
    }
}
