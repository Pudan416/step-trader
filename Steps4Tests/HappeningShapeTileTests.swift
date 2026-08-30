import SwiftUI
import XCTest
@testable import Steps4

final class HappeningShapeTileTests: XCTestCase {

    func testPreviewUsesNeutralGradientUntilCanvasRankIsKnown() {
        XCTAssertEqual(HappeningShapeTile.previewTextureSpec.kind, .gradient)
    }

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
        XCTAssertEqual(element.size, HappeningShapeTile.previewSize(for: .circle), accuracy: 0.0001)
    }

    /// One size for all four types renders a filled circle beside a speck of
    /// rays — each renderer reads `size` differently, which is why `spawn`
    /// carries a different random range per type too.
    func testEachShapeTypeGetsItsOwnPreviewSize() {
        // Two types landing on the same number is fine — what matters is that
        // the ones which read differently at the same value are separated.
        XCTAssertGreaterThan(
            HappeningShapeTile.previewSize(for: .rays),
            HappeningShapeTile.previewSize(for: .circle),
            "Rays lose over half their scale to the aspect-preserving fit"
        )
        for shape in CanvasShapeType.selectableCases {
            XCTAssertGreaterThan(HappeningShapeTile.previewSize(for: shape), 0)
            XCTAssertLessThanOrEqual(
                HappeningShapeTile.previewSize(for: shape),
                0.45,
                "\(shape.rawValue) clips into a square block past this"
            )
        }
    }

    @MainActor
    func testSnowflakePreviewHasComparableRenderedBoundsToOtherClosedShapes() throws {
        let circleBounds = try renderedBounds(shapeType: .circle, seed: 42)
        let blobBounds = try renderedBounds(shapeType: .organicBlob, seed: 42)
        let circleDiameter = max(circleBounds.width, circleBounds.height)
        let blobDiameter = max(blobBounds.width, blobBounds.height)
        let lowerBound = min(circleDiameter, blobDiameter) * 0.8
        let upperBound = max(circleDiameter, blobDiameter) * 1.2

        for seed in (0..<128).map(UInt64.init) {
            let snowflakeBounds = try renderedBounds(shapeType: .snowflake, seed: seed)
            let snowflakeDiameter = max(snowflakeBounds.width, snowflakeBounds.height)
            XCTAssertGreaterThanOrEqual(
                snowflakeDiameter,
                lowerBound,
                "Snowflake seed \(seed) rendered too small beside circle/blob"
            )
            XCTAssertLessThanOrEqual(
                snowflakeDiameter,
                upperBound,
                "Snowflake seed \(seed) rendered too large beside circle/blob"
            )
        }
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

    /// The assignment's rotation has to reach the element, or rays tiles all
    /// point the same way — the renderer derives cone direction from the vector
    /// to the canvas centre, and a tile sits exactly on it.
    func testPreviewElementCarriesTheAssignedRotation() {
        let element = HappeningShapeTile.previewElement(
            optionId: "happening_outside",
            label: "Time outside",
            shapeType: .rays,
            colorHex: "#BA7517",
            seed: 3,
            rotation: 1.25
        )

        XCTAssertEqual(element.userRotation, 1.25, accuracy: 0.0001)
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

    @MainActor
    private func renderedBounds(
        shapeType: CanvasShapeType,
        seed: UInt64
    ) throws -> CGRect {
        let side = 100
        let element = HappeningShapeTile.previewElement(
            optionId: "visual-size",
            label: "Visual size",
            shapeType: shapeType,
            colorHex: "#FFFFFF",
            seed: seed
        )
        let renderer = ImageRenderer(content: HappeningShapeTile(element: element, side: CGFloat(side)))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var minimumX = side
        var minimumY = side
        var maximumX = -1
        var maximumY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[(y * side + x) * 4 + 3] > 8 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maximumX, minimumX)
        XCTAssertGreaterThanOrEqual(maximumY, minimumY)
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }
}
