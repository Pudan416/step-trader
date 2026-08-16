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
}
