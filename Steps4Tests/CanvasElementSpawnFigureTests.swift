import XCTest
@testable import Steps4

final class CanvasElementSpawnFigureTests: XCTestCase {

    private let dayKey = "2026-08-10"

    private var composition: DayComposition {
        DayComposition.forDay(dayKey: dayKey, happeningCount: 0)
    }

    private let figure = HappeningShapeAssignment(
        shapeType: .snowflake,
        colorHex: "#EF9F27",
        seed: 99,
        rotation: 1.25
    )

    func testSpawnUsesTheSuppliedFigure() {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            label: "Walk",
            existingElements: [],
            dayKey: dayKey,
            composition: composition,
            figure: figure
        )

        XCTAssertEqual(element.frozenShapeType, .snowflake)
        XCTAssertEqual(element.hexColor, "#EF9F27")
        XCTAssertEqual(element.shapeSeed, 99)
        XCTAssertEqual(element.userRotation, 1.25, accuracy: 0.0001)
    }

    /// The figure decides the shape, so it must also decide the element kind —
    /// rays render through a different path than the closed shapes.
    func testSuppliedRaysFigureSetsTheRayKind() {
        let element = CanvasElement.spawn(
            optionId: "happening_outside",
            label: "Time outside",
            existingElements: [],
            dayKey: dayKey,
            composition: composition,
            figure: HappeningShapeAssignment(
                shapeType: .rays, colorHex: "#378ADD", seed: 3, rotation: 0.5
            )
        )

        XCTAssertEqual(element.kind, .ray)
    }

    /// A supplied figure must win over `allowedShapeTypes`. The palette has
    /// already applied the user's allowed set when it rolled the figure, and a
    /// second roll here would show the user one shape and spawn another.
    func testSuppliedFigureOverridesTheAllowedTypes() {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            label: "Walk",
            existingElements: [],
            allowedShapeTypes: [.circle],
            dayKey: dayKey,
            composition: composition,
            figure: figure
        )

        XCTAssertEqual(element.frozenShapeType, .snowflake)
    }

    /// Without a figure, spawn must behave exactly as it did before this change
    /// — every other caller still depends on it rolling its own.
    func testSpawnWithoutAFigureStillRollsItsOwn() {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            label: "Walk",
            existingElements: [],
            allowedShapeTypes: [.circle],
            dayKey: dayKey,
            composition: composition
        )

        XCTAssertEqual(element.frozenShapeType, .circle)
        XCTAssertEqual(element.hexColor, composition.color(forRank: 0))
        XCTAssertEqual(
            element.shapeSeed,
            CanvasElement.makeSeed(optionId: "happening_walk", dayKey: dayKey, index: 0)
        )
        XCTAssertEqual(element.userRotation, 0, accuracy: 0.0001)
    }

    /// The palette figure owns its seed, so identical inputs must still obey
    /// the current canvas contract and produce a deterministic size.
    func testSuppliedFigureKeepsTheSizeDeterministic() {
        let first = CanvasElement.spawn(
            optionId: "happening_walk",
            label: "Walk",
            existingElements: [],
            dayKey: dayKey,
            composition: composition,
            figure: figure
        )
        let second = CanvasElement.spawn(
            optionId: "happening_walk",
            label: "Walk",
            existingElements: [],
            dayKey: dayKey,
            composition: composition,
            figure: figure
        )

        XCTAssertEqual(first.size, second.size, accuracy: 0.0001)
    }
}
