import SwiftUI

/// Staggered rows of three and two.
///
/// A flat grid leaves a ragged last row at ten items and reads as a table.
/// Offsetting the rows of two into the gaps of the rows of three keeps the
/// field structured without turning it into one.
enum HappeningTileLayout {

    static func rowCounts(for count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var rows: [Int] = []
        var remaining = count
        var wide = true
        while remaining > 0 {
            let take = min(wide ? 3 : 2, remaining)
            rows.append(take)
            remaining -= take
            wide.toggle()
        }
        return rows
    }

    static func frames(count: Int, in bounds: CGRect, tileSide: CGFloat) -> [CGRect] {
        let rows = rowCounts(for: count)
        guard !rows.isEmpty, bounds.width >= tileSide, bounds.height >= tileSide else { return [] }

        // Rows squeeze rather than overflow: at accessibility type sizes the
        // field gets a much shorter box, and tiles running off the bottom would
        // be unreachable.
        let rowStep = rows.count > 1
            ? min(tileSide + 24, (bounds.height - tileSide) / CGFloat(rows.count - 1))
            : 0
        let blockHeight = tileSide + rowStep * CGFloat(rows.count - 1)
        let firstMidY = bounds.minY + (bounds.height - blockHeight) / 2 + tileSide / 2

        // One pitch for the whole field, fixed by the widest row. Deriving it
        // per row instead would put the twos directly under the threes and lose
        // the stagger.
        let pitch = min(tileSide + 20, (bounds.width - tileSide) / 2)

        var frames: [CGRect] = []
        for (rowIndex, rowCount) in rows.enumerated() {
            let midY = firstMidY + rowStep * CGFloat(rowIndex)
            let firstMidX = bounds.midX - pitch * CGFloat(rowCount - 1) / 2
            for column in 0..<rowCount {
                frames.append(
                    CGRect(
                        x: firstMidX + pitch * CGFloat(column) - tileSide / 2,
                        y: midY - tileSide / 2,
                        width: tileSide,
                        height: tileSide
                    )
                )
            }
        }
        return frames
    }
}
