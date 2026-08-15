import XCTest
@testable import Steps4

final class HappeningShapeAssignmentTests: XCTestCase {

    private let ids = (0..<10).map { "happening_\($0)" }

    private func roll(
        nonce: UInt64,
        dayKey: String = "2026-08-10",
        allowed: [CanvasShapeType] = CanvasShapeType.selectableCases
    ) -> [String: HappeningShapeAssignment] {
        HappeningShapeRoll.assignments(
            for: ids,
            dayKey: dayKey,
            nonce: nonce,
            allowedShapes: allowed,
            palette: CanvasColorPalette.paletteHex
        )
    }

    func testEveryHappeningGetsAnAssignment() {
        XCTAssertEqual(Set(roll(nonce: 0).keys), Set(ids))
    }

    func testSameInputsProduceTheSameFigures() {
        XCTAssertEqual(roll(nonce: 7), roll(nonce: 7))
    }

    func testColoursAreDistinctWithinASet() {
        let colours = roll(nonce: 3).values.map(\.colorHex)
        XCTAssertEqual(Set(colours).count, ids.count)
    }

    func testShapeTypesComeOnlyFromTheAllowedSet() {
        let assignments = roll(nonce: 1, allowed: [.organicBlob])
        XCTAssertTrue(assignments.values.allSatisfy { $0.shapeType == .organicBlob })
    }

    /// A single allowed type is a legitimate configuration. The tiles must still
    /// differ, and the seed is what makes that true.
    func testOneAllowedTypeStillGivesDistinctSeeds() {
        let assignments = roll(nonce: 1, allowed: [.organicBlob])
        XCTAssertEqual(Set(assignments.values.map(\.seed)).count, ids.count)
    }

    func testANewNonceChangesTheFigures() {
        XCTAssertNotEqual(roll(nonce: 1), roll(nonce: 2))
    }

    func testANewDayChangesTheFigures() {
        XCTAssertNotEqual(roll(nonce: 1, dayKey: "2026-08-10"), roll(nonce: 1, dayKey: "2026-08-11"))
    }

    /// The seed must not depend on how many happenings are left in the field.
    /// `CanvasElement.spawn` derives its own from `existingElements.count`, which
    /// would shift every remaining tile's silhouette after each pick.
    func testSeedDoesNotDependOnHowManyHappeningsRemain() {
        let full = roll(nonce: 5)
        let shortened = HappeningShapeRoll.assignments(
            for: Array(ids.prefix(4)),
            dayKey: "2026-08-10",
            nonce: 5,
            allowedShapes: CanvasShapeType.selectableCases,
            palette: CanvasColorPalette.paletteHex
        )

        for id in ids.prefix(4) {
            XCTAssertEqual(full[id]?.seed, shortened[id]?.seed)
            XCTAssertEqual(full[id]?.shapeType, shortened[id]?.shapeType)
            XCTAssertEqual(full[id]?.rotation, shortened[id]?.rotation)
        }
    }

    func testEmptyAllowedSetFallsBackToCircleRatherThanCrashing() {
        let assignments = HappeningShapeRoll.assignments(
            for: ["a"], dayKey: "2026-08-10", nonce: 0,
            allowedShapes: [], palette: CanvasColorPalette.paletteHex
        )
        XCTAssertEqual(assignments["a"]?.shapeType, .circle)
    }

    func testEmptyPaletteFallsBackToTheGoldRatherThanCrashing() {
        let assignments = HappeningShapeRoll.assignments(
            for: ["a"], dayKey: "2026-08-10", nonce: 0,
            allowedShapes: CanvasShapeType.selectableCases, palette: []
        )
        XCTAssertEqual(assignments["a"]?.colorHex, AppColors.goldFallbackHex)
    }

    // MARK: - Rotation
    //
    // `RayShapeRenderer` takes its cone direction from the vector between the
    // element and the canvas centre. A palette tile puts the element *at* the
    // centre, so that vector is zero and every rays tile came out pointing the
    // same way — seed changed nothing. Rotation carried on the assignment gives
    // the renderer the direction it cannot compute for itself.

    func testRotationIsWithinOneTurn() {
        for assignment in roll(nonce: 4).values {
            XCTAssertGreaterThanOrEqual(assignment.rotation, 0)
            XCTAssertLessThan(assignment.rotation, 2 * .pi)
        }
    }

    func testRotationVariesAcrossHappenings() {
        let rotations = roll(nonce: 4).values.map(\.rotation)
        XCTAssertGreaterThan(Set(rotations.map { Int($0 * 1000) }).count, 1)
    }

    func testRotationIsStableForTheSameInputs() {
        XCTAssertEqual(
            roll(nonce: 9).mapValues(\.rotation),
            roll(nonce: 9).mapValues(\.rotation)
        )
    }
}
