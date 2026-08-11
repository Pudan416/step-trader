import XCTest
@testable import Steps4

final class HappeningShapeTileTests: XCTestCase {

    func testPreviewElementCarriesTheAssignedFigure() {
        let element = HappeningShapeTile.previewElement(
            optionId: "happening_walk",
            label: "Walk",
            shapeType: .snowflake,
            colorHex: "#EF9F27",
            seed: 42
        )

        XCTAssertEqual(element.frozenShapeType, .snowflake)
        XCTAssertEqual(element.hexColor, "#EF9F27")
        XCTAssertEqual(element.shapeSeed, 42)
        XCTAssertEqual(element.optionId, "happening_walk")
    }

    /// The tile is a fixed square. A preview element must sit dead centre and
    /// at a fixed size, or tiles of different shape types would render at
    /// different scales and the grid would look ragged.
    func testPreviewElementIsCentredAndFixedSize() {
        let element = HappeningShapeTile.previewElement(
            optionId: "happening_read",
            label: "Read",
            shapeType: .circle,
            colorHex: "#378ADD",
            seed: 7
        )

        XCTAssertEqual(element.basePosition.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(element.basePosition.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(element.size, HappeningShapeTile.previewSize, accuracy: 0.0001)
    }

    /// Two tiles of the same type must differ when their seeds differ — that is
    /// the whole reason ten tiles can share four shape types.
    func testSameTypeDifferentSeedProducesDifferentElements() {
        let a = HappeningShapeTile.previewElement(
            optionId: "a", label: "A", shapeType: .organicBlob, colorHex: "#1D9E75", seed: 1
        )
        let b = HappeningShapeTile.previewElement(
            optionId: "b", label: "B", shapeType: .organicBlob, colorHex: "#1D9E75", seed: 2
        )

        XCTAssertNotEqual(a.shapeSeed, b.shapeSeed)
        XCTAssertEqual(a.frozenShapeType, b.frozenShapeType)
    }

    /// Rays render through a different path than the closed shapes, so the
    /// element kind has to follow the assigned type.
    func testRaysPreviewElementUsesTheRayKind() {
        let element = HappeningShapeTile.previewElement(
            optionId: "happening_outside",
            label: "Time outside",
            shapeType: .rays,
            colorHex: "#BA7517",
            seed: 3
        )

        XCTAssertEqual(element.kind, .ray)
    }

    /// A preview is a still frame. Anything that animates would make the tile
    /// drift away from the figure it is promising.
    func testPreviewElementDoesNotMove() {
        let element = HappeningShapeTile.previewElement(
            optionId: "happening_walk",
            label: "Walk",
            shapeType: .circle,
            colorHex: "#378ADD",
            seed: 11
        )

        XCTAssertEqual(element.driftSpeed, 0, accuracy: 0.0001)
        XCTAssertEqual(element.driftAmplitude, 0, accuracy: 0.0001)
        XCTAssertEqual(element.pulseAmplitude, 0, accuracy: 0.0001)
        XCTAssertEqual(element.rotationSpeed, 0, accuracy: 0.0001)
    }
}
