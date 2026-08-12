import XCTest
@testable import Steps4

final class CanvasElementSpawnFigureTests: XCTestCase {

    private let figure = HappeningShapeAssignment(
        shapeType: .snowflake,
        colorHex: "#EF9F27",
        seed: 99,
        rotation: 1.25
    )

    func testSpawnUsesTheSuppliedFigure() {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            color: "#000000",
            label: "Walk",
            existingElements: [],
            dayKey: "2026-08-10",
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
            color: "#000000",
            label: "Time outside",
            existingElements: [],
            dayKey: "2026-08-10",
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
            color: "#000000",
            label: "Walk",
            existingElements: [],
            allowedShapeTypes: [.circle],
            dayKey: "2026-08-10",
            figure: figure
        )

        XCTAssertEqual(element.frozenShapeType, .snowflake)
    }

    /// Without a figure, spawn must behave exactly as it did before this change
    /// — every other caller still depends on it rolling its own.
    func testSpawnWithoutAFigureStillRollsItsOwn() {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            color: "#AABBCC",
            label: "Walk",
            existingElements: [],
            allowedShapeTypes: [.circle],
            dayKey: "2026-08-10"
        )

        XCTAssertEqual(element.frozenShapeType, .circle)
        XCTAssertEqual(element.hexColor, "#AABBCC")
        XCTAssertEqual(
            element.shapeSeed,
            CanvasElement.makeSeed(optionId: "happening_walk", dayKey: "2026-08-10", index: 0)
        )
        XCTAssertEqual(element.userRotation, 0, accuracy: 0.0001)
    }

    /// The promise covers the figure, not the size: spawn keeps rolling size,
    /// opacity and motion so the canvas stays varied.
    func testSuppliedFigureDoesNotFreezeTheSize() {
        let sizes = Set(
            (0..<24).map { _ in
                CanvasElement.spawn(
                    optionId: "happening_walk",
                    color: "#000000",
                    label: "Walk",
                    existingElements: [],
                    dayKey: "2026-08-10",
                    figure: figure
                ).size
            }
        )

        XCTAssertGreaterThan(sizes.count, 1)
    }
}
