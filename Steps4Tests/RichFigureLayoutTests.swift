import XCTest
@testable import Steps4

final class RichFigureLayoutTests: XCTestCase {
    func testFootprintsAreStableAcrossShuffle() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let a = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 0)
        let b = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 9)
        let layoutA = RichFigureLayout.make(elements: elements, styles: a)
        let layoutB = RichFigureLayout.make(elements: elements, styles: b)

        for element in elements {
            let diameterA = try! XCTUnwrap(layoutA[element.id]?.targetDiameterFraction)
            let diameterB = try! XCTUnwrap(layoutB[element.id]?.targetDiameterFraction)
            XCTAssertEqual(diameterA, diameterB, accuracy: 0.000_001)
            XCTAssertEqual(layoutA[element.id]?.center, layoutB[element.id]?.center)
        }
    }

    func testOnlySmallestSlotMayBeBelowMediumFloor() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let styles = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 0)
        let values = RichFigureLayout.make(elements: elements, styles: styles)
            .values.map(\.targetDiameterFraction).sorted()
        XCTAssertEqual(try! XCTUnwrap(values.first), 0.19, accuracy: 0.000_001)
        XCTAssertTrue(values.dropFirst().allSatisfy { $0 >= 0.22 && $0 <= 0.34 })
    }

    func testTightlyGroupedSourcesUseUniformSlots() {
        var elements = RichAssignmentFixture.elements(count: 2)
        elements[1].size = elements[0].size
        let styles = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 0)
        let values = RichFigureLayout.make(elements: elements, styles: styles)
            .values.map(\.targetDiameterFraction).sorted()

        XCTAssertEqual(values, [0.26, 0.26])
    }

    func testStarOpticalScaleExceedsOrganicScale() {
        XCTAssertGreaterThan(RichFigureLayout.opticalScale(for: .crystallineStar),
                             RichFigureLayout.opticalScale(for: .luminousOrganic))
    }

    func testBoundaryEnvelopeContainsLargestStarFootprintOverscanAndDriftExtrema() {
        let canvasSize = CGSize(width: 390, height: 844)
        let layout = RichFigureLayoutSpec(
            center: CGPoint(x: 0.08, y: 0.91),
            targetDiameterFraction: 0.34,
            opticalScale: RichFigureLayout.opticalScale(for: .crystallineStar),
            overscanFraction: 0.14
        )

        let envelope = RichFigureLayout.edgeSafeEnvelope(
            for: layout,
            canvasSize: canvasSize
        )

        XCTAssertEqual(envelope.sourceCenter.x, 31.2, accuracy: 0.000_001)
        XCTAssertEqual(envelope.sourceCenter.y, 768.04, accuracy: 0.000_001)
        XCTAssertLessThan(envelope.effectiveTargetDiameter, 132.6)
        XCTAssertGreaterThanOrEqual(
            envelope.maximumContentRadius,
            envelope.effectiveTargetDiameter * 1.12 / 2
        )
        XCTAssertGreaterThanOrEqual(
            envelope.effectReserve,
            envelope.effectiveTargetDiameter * 0.14 / 2
        )

        for proposedCenter in [
            CGPoint(x: -390, y: -844),
            envelope.sourceCenter,
            CGPoint(x: 780, y: 1_688)
        ] {
            let center = envelope.constrainedCenter(proposedCenter)
            XCTAssertGreaterThanOrEqual(
                center.x - envelope.totalRadius,
                -0.000_001
            )
            XCTAssertLessThanOrEqual(
                center.x + envelope.totalRadius,
                canvasSize.width + 0.000_001
            )
            XCTAssertGreaterThanOrEqual(
                center.y - envelope.totalRadius,
                -0.000_001
            )
            XCTAssertLessThanOrEqual(
                center.y + envelope.totalRadius,
                canvasSize.height + 0.000_001
            )
        }
    }

    func testEdgeSafeEnvelopeIsStableAcrossShuffleFamilyChanges() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let first = RichFigureAssignment.previewItems(
            elements: elements,
            dayKey: "2026-08-16",
            shuffleNonce: 3
        )
        let shuffled = RichFigureAssignment.previewItems(
            elements: elements,
            dayKey: "2026-08-16",
            shuffleNonce: 4
        )
        let canvasSize = CGSize(width: 390, height: 844)

        XCTAssertNotEqual(first.map(\.style.family), shuffled.map(\.style.family))
        let firstEnvelopes = Dictionary(uniqueKeysWithValues: first.map {
            ($0.id, RichFigureLayout.edgeSafeEnvelope(for: $0.layout, canvasSize: canvasSize))
        })
        let shuffledEnvelopes = Dictionary(uniqueKeysWithValues: shuffled.map {
            ($0.id, RichFigureLayout.edgeSafeEnvelope(for: $0.layout, canvasSize: canvasSize))
        })

        XCTAssertEqual(firstEnvelopes, shuffledEnvelopes)
    }

    func testEdgeSafeTargetPreservesMonotonicIntentUntilItReachesEdgeCap() {
        let canvasSize = CGSize(width: 390, height: 844)
        func envelope(targetFraction: CGFloat) -> RichFigureEdgeEnvelope {
            RichFigureLayout.edgeSafeEnvelope(
                for: RichFigureLayoutSpec(
                    center: CGPoint(x: 0.25, y: 0.5),
                    targetDiameterFraction: targetFraction,
                    opticalScale: 1,
                    overscanFraction: 0.14
                ),
                canvasSize: canvasSize
            )
        }

        let small = envelope(targetFraction: 0.10)
        let medium = envelope(targetFraction: 0.20)
        let large = envelope(targetFraction: 0.34)
        let oversized = envelope(targetFraction: 0.68)

        XCTAssertEqual(small.effectiveTargetDiameter, 39, accuracy: 0.000_001)
        XCTAssertEqual(medium.effectiveTargetDiameter, 78, accuracy: 0.000_001)
        XCTAssertGreaterThan(large.effectiveTargetDiameter, medium.effectiveTargetDiameter)
        XCTAssertLessThan(large.effectiveTargetDiameter, 132.6)
        XCTAssertEqual(
            large.effectiveTargetDiameter,
            oversized.effectiveTargetDiameter,
            accuracy: 0.000_001
        )
    }

    func testFittedScaleFallsBackForNaNWidth() {
        let scale = RichFigureLayout.fittedScale(
            canonicalBounds: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 4),
            targetDiameter: 0.4,
            opticalScale: 1.12
        )

        XCTAssertEqual(scale, 0.2, accuracy: 0.000_001)
    }

    func testFittedScaleFallsBackForNaNHeight() {
        let scale = RichFigureLayout.fittedScale(
            canonicalBounds: CGRect(x: 0, y: 0, width: 4, height: CGFloat.nan),
            targetDiameter: 0.4,
            opticalScale: 1.12
        )

        XCTAssertEqual(scale, 0.2, accuracy: 0.000_001)
    }
}
