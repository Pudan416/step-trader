import SwiftUI

/// Pure layout maths for the palette's metaball cluster.
///
/// No view and no state, so the two rules that matter — 7–8 blobs visible
/// without scrolling, and enough overlap for the metaball contour to merge —
/// are unit-testable.
enum HappeningBlobLayout {

    struct Blob: Equatable {
        let index: Int
        let center: CGPoint
        let radius: CGFloat
    }

    /// Rows fit per viewport height. Paired with `radiusRatio`, this is what
    /// pins the 7–8-visible rule; the layout test fails if either drifts.
    private static let rowsPerViewport: CGFloat = 4
    private static let radiusRatio: CGFloat = 0.19

    /// How much a blob's radius may vary from the base, as a fraction.
    /// Deterministic per index — the cluster reads organic without jittering.
    private static let radiusJitter: CGFloat = 0.22

    /// Column centres, as fractions of width. Deliberately closer together than
    /// a diameter: staggered neighbours have to overlap or the metaball contour
    /// renders as separate circles instead of one cluster.
    private static let leftColumn: CGFloat = 0.41
    private static let rightColumn: CGFloat = 0.59

    /// Horizontal wander, as a fraction of width. Small enough that even two
    /// minimum-radius neighbours nudged apart still overlap.
    private static let horizontalWander: CGFloat = 0.04

    static func blobs(count: Int, in size: CGSize) -> [Blob] {
        guard count > 0, size.width > 0, size.height > 0 else { return [] }

        let baseRadius = size.width * radiusRatio
        let rowHeight = size.height / rowsPerViewport
        let topInset = rowHeight * 0.55

        return (0..<count).map { index in
            let row = CGFloat(index / 2)
            let isRight = index % 2 == 1
            let wobble = variation(for: index)

            let radius = baseRadius * (1 - radiusJitter / 2 + radiusJitter * wobble)
            let column = size.width * (isRight ? rightColumn : leftColumn)
            let nudge = (wobble - 0.5) * size.width * horizontalWander
            let x = min(max(column + nudge, radius), size.width - radius)
            let y = topInset + row * rowHeight + (isRight ? rowHeight * 0.5 : 0)

            return Blob(index: index, center: CGPoint(x: x, y: y), radius: radius)
        }
    }

    /// Scrollable content height for `count` blobs, with room below the lowest
    /// one so it is never clipped.
    static func contentHeight(count: Int, in size: CGSize) -> CGFloat {
        guard count > 0, size.height > 0 else { return size.height }
        let lowest = blobs(count: count, in: size)
            .map { $0.center.y + $0.radius }.max() ?? size.height
        return max(size.height, lowest + size.height * 0.12)
    }

    /// A stable pseudo-random value in 0..<1, derived from the index alone.
    /// Knuth's multiplicative hash — depends only on `index`, so a blob keeps
    /// its size and offset no matter how many neighbours appear later.
    private static func variation(for index: Int) -> CGFloat {
        CGFloat((index &* 2_654_435_761) % 1_000) / 1_000
    }
}
