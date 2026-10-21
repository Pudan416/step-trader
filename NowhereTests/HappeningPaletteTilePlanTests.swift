import XCTest
@testable import Nowhere

final class HappeningPaletteTilePlanTests: XCTestCase {
    func testSurvivingTilesKeepWorldFramesAcrossPanAndEdgeTilesKeepFullSize() {
        let world = CGSize(width: 1100, height: 1400)
        let first = HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: CGRect(x: 350, y: 400, width: 390, height: 844))
        let second = HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: CGRect(x: 420, y: 460, width: 390, height: 844))
        let common = Set(first).intersection(second)
        XCTAssertFalse(common.isEmpty)
        for tile in common {
            XCTAssertEqual(first.first { $0.id == tile.id }?.frame, second.first { $0.id == tile.id }?.frame)
        }
        for tile in first + second {
            XCTAssertEqual(tile.frame.size, CGSize(width: 256, height: 256))
            XCTAssertEqual(tile.frame.origin, CGPoint(x: CGFloat(tile.column) * 256, y: CGFloat(tile.row) * 256))
        }
        let edge = HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: CGRect(x: 1050, y: 1350, width: 100, height: 100))
        XCTAssertEqual(edge.last?.frame, CGRect(x: 1024, y: 1280, width: 256, height: 256))
    }

    func testOverscrollIsClampedAndOutputIsStableRowMajor() {
        let world = CGSize(width: 800, height: 900)
        let negative = HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: CGRect(x: -40, y: -70, width: 390, height: 844))
        XCTAssertFalse(negative.isEmpty)
        XCTAssertTrue(negative.allSatisfy { $0.column >= 0 && $0.row >= 0 })
        XCTAssertEqual(negative, negative.sorted { $0.row == $1.row ? $0.column < $1.column : $0.row < $1.row })
        XCTAssertEqual(Set(negative).count, negative.count)
        XCTAssertTrue(HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: CGRect(x: -1000, y: -1000, width: 100, height: 100)).isEmpty)
        XCTAssertTrue(HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: CGRect(x: 2000, y: 2000, width: 100, height: 100)).isEmpty)
    }

    func testScaleBudgetsWorstCaseResidentPixelsAndDoesNotChangeDuringPan() {
        let world = CGSize(width: 100_000, height: 100_000)
        for viewport in [CGSize(width: 390, height: 844), CGSize(width: 1366, height: 1024), CGSize(width: 16384, height: 16384)] {
            let scale = HappeningPaletteTilePlan.displayScale(viewportSize: viewport, nativeScale: 3)
            XCTAssertGreaterThan(scale, 0)
            XCTAssertLessThanOrEqual(scale, 3)
            for origin in [CGPoint.zero, CGPoint(x: 193, y: 251), CGPoint(x: 500, y: 500)] {
                let tiles = HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: CGRect(origin: origin, size: viewport))
                let pixels = CGFloat(tiles.count) * pow(HappeningPaletteTilePlan.tileSide * scale, 2)
                XCTAssertLessThanOrEqual(pixels, HappeningPaletteTilePlan.maximumResidentPixels + 0.001)
                XCTAssertEqual(scale, HappeningPaletteTilePlan.displayScale(viewportSize: viewport, nativeScale: 3))
            }
        }
        XCTAssertLessThan(HappeningPaletteTilePlan.displayScale(viewportSize: CGSize(width: 16384, height: 16384), nativeScale: 3), 1)
    }

    func testHostileGeometryIsRejectedWithoutUnboundedEnumeration() {
        let rect = CGRect(x: 0, y: 0, width: 390, height: 844)
        for world in [CGSize.zero, CGSize(width: -1, height: 900), CGSize(width: CGFloat.infinity, height: 900)] {
            XCTAssertTrue(HappeningPaletteTilePlan.tiles(worldSize: world, visibleRect: rect).isEmpty)
        }
        for invalid in [CGRect(x: CGFloat.nan, y: 0, width: 390, height: 844), CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 844), CGRect(x: 0, y: 0, width: 20000, height: 20000)] {
            XCTAssertTrue(HappeningPaletteTilePlan.tiles(worldSize: CGSize(width: 1e100, height: 1e100), visibleRect: invalid).isEmpty)
        }
        XCTAssertEqual(HappeningPaletteTilePlan.displayScale(viewportSize: .zero, nativeScale: 3), 1)
    }

    func testProjectionPreservesWorldReconstructionAndAllActorState() throws {
        let assignment = try makeAssignment()
        let source = HappeningFieldLayout.Source(index: 7, center: CGPoint(x: 620, y: 730), radius: 64, appearanceScale: 0.7)
        let slot = HappeningPaletteRenderSlot(happeningID: "event", assignment: assignment, visualState: .removalPreview, source: source)
        let tile = HappeningPaletteTilePlan.Tile(column: 2, row: 2)
        let projected = try XCTUnwrap(HappeningPaletteTilePlan.slots(in: tile, from: [slot]).first)
        XCTAssertEqual(projected.source.center, CGPoint(x: 108, y: 218))
        XCTAssertEqual(projected.source.radius, source.radius)
        XCTAssertEqual(projected.source.appearanceScale, source.appearanceScale)
        XCTAssertEqual(projected.source.index, source.index)
        XCTAssertEqual(projected.assignment, assignment)
        XCTAssertEqual(projected.visualState, slot.visualState)
        let controls = HappeningPaletteRenderControls.target(for: .removalPreview)
        let sample = HappeningPaletteRenderSample(slots: [.init(happeningID: "event", assignment: assignment, source: source, controls: controls)])
        let local = try XCTUnwrap(HappeningPaletteTilePlan.projectedSample(sample, to: tile).slots.first)
        XCTAssertEqual(local.source, projected.source)
        XCTAssertEqual(local.controls, controls)
        XCTAssertEqual(local.assignment, assignment)
        XCTAssertEqual(local.happeningID, "event")
        XCTAssertEqual(local.source.center.x + tile.frame.minX, source.center.x)
        XCTAssertEqual(local.source.center.y + tile.frame.minY, source.center.y)
    }

    func testCullIncludesPreviewContourFarOutsideNominalCircleAndExcludesDistantActor() throws {
        let assignment = try makeAssignment()
        let tile = HappeningPaletteTilePlan.Tile(column: 0, row: 0)
        let near = HappeningPaletteRenderSlot(happeningID: "near", assignment: assignment, visualState: .additionPreview,
            source: .init(index: 0, center: CGPoint(x: 470, y: 128), radius: 64))
        let far = HappeningPaletteRenderSlot(happeningID: "far", assignment: assignment, visualState: .added,
            source: .init(index: 1, center: CGPoint(x: 2000, y: 2000), radius: 64))
        XCTAssertEqual(HappeningPaletteTilePlan.slots(in: tile, from: [near, far]).map(\.happeningID), ["near"])
    }

    private func makeAssignment() throws -> HappeningEditorialAssignment {
        let happening = Happening(id: "event", title: "Event", isBuiltIn: true)
        let input = DayObjectSceneInput(dayKey: "2026-10-21", identity: "tile-plan", eventIDs: [], motionEnergy: 0.625,
            visualClarity: 0.625, canvasCoverage: .fullCanvas, paletteCategories: ModernPaletteSelection.all,
            usesEditorialField: true, editorialBackground: .dark, lowSleep: true,
            editorialLabConfiguration: DayObjectEditorialLabConfiguration(materialMode: .generativeDNA, placement: .depthField))
        return try XCTUnwrap(HappeningEditorialAssignmentResolver.assignments(happenings: [happening], baseInput: input, colorNonce: 7)["event"])
    }
}
