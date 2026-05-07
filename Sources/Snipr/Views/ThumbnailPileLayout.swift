import CoreGraphics
import Foundation

/// Pure layout math for the "physical pile of photos" stack visual.
///
/// The blueprint asks for:
/// - 3–5 px offset between cards,
/// - 0.5–1.5° rotation alternating per item,
/// - cap visible cards at 6.
///
/// This struct is deliberately free of SwiftUI imports so it can be unit
/// tested without touching the rendering layer.
struct ThumbnailPileLayout: Equatable, Sendable {
    /// Maximum number of cards drawn on the pile. Items beyond this index
    /// are still in the stack but not visualized in the collapsed pile.
    static let maxVisibleCards = 6

    /// Vertical offset per index in points.
    let verticalOffset: CGFloat
    /// Horizontal jitter per index in points (alternating sign).
    let horizontalJitter: CGFloat
    /// Maximum rotation magnitude in degrees. Sign alternates per index.
    let rotationDegrees: Double

    static let `default` = ThumbnailPileLayout(
        verticalOffset: 4,
        horizontalJitter: 2,
        rotationDegrees: 1.2
    )

    /// Per-card placement values for index `index` of `totalCount` items.
    /// `index == 0` is the topmost card (the most recent capture).
    func placement(forIndex index: Int, totalCount: Int) -> Placement {
        precondition(index >= 0, "index must be non-negative")
        precondition(totalCount > 0, "totalCount must be positive")
        let depth = max(0, min(index, Self.maxVisibleCards - 1))
        // Card 0 (top) sits flat; deeper cards tilt and slide a bit.
        let alternating: CGFloat = depth.isMultiple(of: 2) ? 1 : -1
        let yOffset = CGFloat(depth) * verticalOffset
        let xOffset = CGFloat(depth == 0 ? 0 : 1) * horizontalJitter * alternating
        let rotation = depth == 0 ? 0 : rotationDegrees * Double(alternating)
        // Slightly shrink each layer so the pile reads as having depth.
        let scale = max(0.9, 1.0 - CGFloat(depth) * 0.018)
        // Deeper cards fade slightly so the top card stays the focus.
        let opacity = max(0.5, 1.0 - Double(depth) * 0.08)
        return Placement(
            index: index,
            totalCount: totalCount,
            xOffset: xOffset,
            yOffset: yOffset,
            rotationDegrees: rotation,
            scale: scale,
            opacity: opacity,
            zIndex: Double(Self.maxVisibleCards - depth)
        )
    }

    /// How many cards the collapsed pile draws. Equal to
    /// `min(totalCount, maxVisibleCards)`.
    static func visibleCardCount(forTotal totalCount: Int) -> Int {
        max(0, min(totalCount, maxVisibleCards))
    }

    struct Placement: Equatable, Sendable {
        let index: Int
        let totalCount: Int
        let xOffset: CGFloat
        let yOffset: CGFloat
        let rotationDegrees: Double
        let scale: CGFloat
        let opacity: Double
        let zIndex: Double
    }
}
