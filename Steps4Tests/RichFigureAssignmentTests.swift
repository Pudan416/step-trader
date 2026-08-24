import XCTest
@testable import Steps4

final class RichFigureAssignmentTests: XCTestCase {
    func testTenElementsCoverEveryFamilyAndFill() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let specs = RichFigureAssignment.make(
            elements: elements,
            dayKey: "2026-08-16",
            shuffleNonce: 0
        )

        XCTAssertEqual(Set(specs.values.map(\.family)), Set(RichFigureFamily.allCases))
        XCTAssertEqual(Set(specs.values.map(\.fill)), Set(RichFillKind.allCases))
    }

    func testTenElementsKeepCircleAndSpindleAsSeparateFamilies() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let specs = RichFigureAssignment.make(
            elements: elements,
            dayKey: "2026-08-16",
            shuffleNonce: 0
        )
        let families = specs.values.map(\.family)

        XCTAssertEqual(families.filter { $0 == .circle }.count, 2)
        XCTAssertEqual(families.filter { $0 == .spindle }.count, 2)
    }

    func testSameNonceProducesIdenticalSpecsAndNewNonceChangesBothDecks() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let a = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 3)
        let b = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 3)
        let c = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 4)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(elements.map { a[$0.id]?.family }, elements.map { c[$0.id]?.family })
        XCTAssertNotEqual(elements.map { a[$0.id]?.fill }, elements.map { c[$0.id]?.fill })
    }

    func testAssignmentPreservesSourceColors() {
        let element = RichAssignmentFixture.elements(count: 1)[0]
        let spec = RichFigureAssignment.make(
            elements: [element], dayKey: "2026-08-16", shuffleNonce: 0
        )[element.id]

        XCTAssertEqual(spec?.primaryHex, element.hexColor)
        XCTAssertEqual(spec?.secondaryHex, element.hexColor2)
    }

    func testAssignmentUsesStableElementKeys() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let specs = RichFigureAssignment.make(
            elements: elements,
            dayKey: "2026-08-16",
            shuffleNonce: 0
        )

        XCTAssertEqual(Set(specs.keys), Set(elements.map(\.id)))
    }

    func testCrystallineStarNeverOccupiesASmallAccentRoleAcrossShuffles() {
        let elements = RichAssignmentFixture.elements(count: 10)

        for nonce in 0..<64 {
            let specs = RichFigureAssignment.make(
                elements: elements,
                dayKey: "2026-08-16",
                shuffleNonce: nonce
            )
            let stars = specs.values.filter { $0.family == .crystallineStar }

            XCTAssertFalse(stars.isEmpty, "Expected Crystalline Star at nonce \(nonce)")
            XCTAssertTrue(
                stars.allSatisfy { $0.detailTier != .accent },
                "Crystalline Star used an accent slot at nonce \(nonce)"
            )
        }
    }
}

enum RichAssignmentFixture {
    static func previewItems(count: Int, nonce: Int) -> [RichFigurePreviewItem] {
        RichFigureAssignment.previewItems(
            elements: elements(count: count),
            dayKey: "2026-08-16",
            shuffleNonce: nonce
        )
    }

    static func elements(count: Int) -> [CanvasElement] {
        (0..<count).map { index in
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
            let primaryHex = ["#102030", "#204060", "#306090", "#4080C0", "#50A0F0"][index % 5]
            let secondaryHex = ["#F0E0D0", "#E0C0A0", "#D0A070", "#C08040", "#A06020"][index % 5]
            let size = CGFloat(0.14 + Double(index) * 0.02)
            let position = CGPoint(x: 0.1 + Double(index) * 0.03, y: 0.2 + Double(index) * 0.02)
            return CanvasElement(
                id: id,
                kind: .circle,
                optionId: "rich_fixture_\(index)",
                label: "Rich fixture \(index)",
                hexColor: primaryHex,
                hexColor2: secondaryHex,
                size: size,
                basePosition: position,
                phaseOffset: Double(index) * 0.1,
                driftSpeed: 0.1,
                driftAmplitude: 0.02,
                pulseFrequency: 0.15,
                pulseAmplitude: 0.02,
                rotationSpeed: 4,
                opacity: 0.5,
                createdAt: Date(timeIntervalSince1970: Double(index)),
                shapeSeed: UInt64(index + 1)
            )
        }
    }
}
