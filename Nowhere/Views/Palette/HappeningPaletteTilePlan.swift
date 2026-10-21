import Foundation

/// Fixed world-space tiles. Scrolling changes residency, never a tile's frame
/// or its source projection, so old pixels retain the same world coordinates.
enum HappeningPaletteTilePlan {
    static let tileSide: CGFloat = 256
    static let overscan: CGFloat = 64
    /// Budget for resident output pixels; renderer scratch/drawable multiplicity
    /// must be budgeted separately by the host.
    static let maximumResidentPixels: CGFloat = 12 * 1024 * 1024

    // A corrupt geometry value must not enumerate an unbounded grid. This is
    // well above supported phone/iPad windows; at most 66 x 66 tiles qualify.
    private static let maximumViewportDimension: CGFloat = 16_384
    private static let maximumWorldDimension: CGFloat = 1_000_000_000

    struct Tile: Hashable, Identifiable {
        let column: Int
        let row: Int
        var id: Self { self }
        var frame: CGRect {
            CGRect(x: CGFloat(column) * tileSide, y: CGFloat(row) * tileSide,
                   width: tileSide, height: tileSide)
        }
    }

    static func tiles(worldSize: CGSize, visibleRect: CGRect) -> [Tile] {
        guard valid(worldSize), worldSize.width <= maximumWorldDimension,
              worldSize.height <= maximumWorldDimension,
              valid(visibleRect.size), visibleRect.width <= maximumViewportDimension,
              visibleRect.height <= maximumViewportDimension,
              visibleRect.origin.x.isFinite, visibleRect.origin.y.isFinite else { return [] }
        let covered = visibleRect.insetBy(dx: -overscan, dy: -overscan)
            .intersection(CGRect(origin: .zero, size: worldSize))
        guard !covered.isNull, !covered.isEmpty else { return [] }
        let firstColumn = max(0, Int(floor(covered.minX / tileSide)))
        let lastColumn = Int(ceil(covered.maxX / tileSide)) - 1
        let firstRow = max(0, Int(floor(covered.minY / tileSide)))
        let lastRow = Int(ceil(covered.maxY / tileSide)) - 1
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return [] }
        return (firstRow...lastRow).flatMap { row in
            (firstColumn...lastColumn).map { Tile(column: $0, row: row) }
        }
    }

    /// Depends only on viewport size, not pan phase or the current world edge.
    /// The extra tile per axis covers the least favorable grid alignment.
    static func displayScale(viewportSize: CGSize, nativeScale: CGFloat) -> CGFloat {
        guard valid(viewportSize) else { return 1 }
        let native = nativeScale.isFinite && nativeScale > 0 ? nativeScale : 1
        let columns = ceil((viewportSize.width + 2 * overscan) / tileSide) + 1
        let rows = ceil((viewportSize.height + 2 * overscan) / tileSide) + 1
        // Divide successively rather than multiplying counts: even very large
        // finite viewports cannot overflow the intermediate pixel count.
        let budgetScale = sqrt(maximumResidentPixels) / tileSide / sqrt(columns) / sqrt(rows)
        return min(native, budgetScale)
    }

    static func slots(in tile: Tile, from slots: [HappeningPaletteRenderSlot]) -> [HappeningPaletteRenderSlot] {
        slots.compactMap { slot in
            guard intersects(tile, source: slot.source, assignment: slot.assignment) else { return nil }
            return HappeningPaletteRenderSlot(happeningID: slot.happeningID, assignment: slot.assignment,
                visualState: slot.visualState, source: projected(slot.source, to: tile))
        }
    }

    /// Sample the shared world timeline once before calling this for each tile.
    /// Culling/projection must never restart, resample or alter actor controls.
    static func projectedSample(_ sample: HappeningPaletteRenderSample, to tile: Tile) -> HappeningPaletteRenderSample {
        HappeningPaletteRenderSample(slots: sample.slots.compactMap { slot in
            guard intersects(tile, source: slot.source, assignment: slot.assignment,
                             scale: slot.controls.scale) else { return nil }
            return .init(happeningID: slot.happeningID, assignment: slot.assignment,
                         source: projected(slot.source, to: tile), controls: slot.controls)
        })
    }

    private static func projected(_ source: HappeningFieldLayout.Source, to tile: Tile) -> HappeningFieldLayout.Source {
        .init(index: source.index,
              center: CGPoint(x: source.center.x - tile.frame.minX, y: source.center.y - tile.frame.minY),
              radius: source.radius, appearanceScale: source.appearanceScale)
    }

    private static func intersects(_ tile: Tile, source: HappeningFieldLayout.Source,
                                   assignment: HappeningEditorialAssignment, scale: Double = 1.06) -> Bool {
        guard source.center.x.isFinite, source.center.y.isFinite,
              source.radius.isFinite, source.radius > 0 else { return false }
        // A circular envelope is rotation independent and deliberately exceeds
        // the frozen native contour (including anisotropy/offset and material
        // fringe), the nominal picker and the peak confirmation breath. Keep
        // this inexpensive: no contour generation or cache locks per tile.
        let aspect = CGFloat(assignment.silhouette.aspect)
        let extent = source.radius * 3 * (aspect.isFinite ? max(1, abs(aspect)) : 1)
            * CGFloat(max(1.06, scale)) * CGFloat(HappeningPaletteRenderControls.maximumConfirmationBreath) + 16
        guard extent.isFinite else { return false }
        return tile.frame.intersects(CGRect(x: source.center.x - extent, y: source.center.y - extent,
                                           width: extent * 2, height: extent * 2))
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
