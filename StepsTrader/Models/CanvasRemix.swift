import Foundation

/// Restyles every decorative element on a canvas in one pass.
///
/// Remix is a request for a different-looking day, not a different day. Shape,
/// silhouette seed, colours, size and motion personality are re-rolled inside
/// the day's own composition; identity, arrangement and count are carried
/// through untouched, so the canvas still records the same happenings in the
/// same places.
enum CanvasRemix {

    /// - Parameters:
    ///   - elements: the canvas in arrival order. Order is preserved because
    ///     rank drives size, colour and texture.
    ///   - composition: the day's composition, so a remix cannot leave the
    ///     day's palette or archetype.
    ///   - allowedShapes: the user's allowed shape set.
    ///   - date: one instant stamped on the whole batch, so last-write-wins
    ///     merging treats the remix as a single edit.
    static func remixed(
        _ elements: [CanvasElement],
        composition: DayComposition,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        at date: Date = .now
    ) -> [CanvasElement] {
        elements.enumerated().map { rank, element in
            var copy = element
            copy.reroll(
                rank: rank,
                composition: composition,
                allowedShapes: allowedShapes,
                at: date
            )
            return copy
        }
    }
}
