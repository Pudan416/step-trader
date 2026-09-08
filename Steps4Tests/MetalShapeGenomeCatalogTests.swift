import XCTest
@testable import Steps4

final class MetalShapeGenomeCatalogTests: XCTestCase {
    func testCatalogContainsTwelveGenomeAndEightCuratedLegacyShapes() {
        let presets = MetalShapeGenomeCatalog.presets
        XCTAssertEqual(presets.count, 20)
        XCTAssertEqual(presets.filter { $0.source == .genome }.count, 12)
        XCTAssertEqual(presets.filter { $0.source == .legacy }.count, 8)
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)

        XCTAssertEqual(
            presets.filter { $0.source == .genome }.map(\.id),
            [
                "genome.soft-orbit", "genome.soft-drift", "genome.soft-cell",
                "genome.lobed-triad", "genome.lobed-quartet", "genome.lobed-penta",
                "genome.folded-rosette-5", "genome.folded-rosette-7", "genome.folded-rosette-9",
                "genome.crystal-4", "genome.crystal-6", "genome.crystal-8",
            ]
        )
    }

    func testLegacySelectionUsesTheApprovedExistingMetalCoordinates() {
        let actual = MetalShapeGenomeCatalog.presets.compactMap { preset -> String? in
            guard case let .legacy(shape, variant) = preset.contour else { return nil }
            return "\(preset.id):\(shape):\(variant)"
        }
        XCTAssertEqual(actual, [
            "legacy.circle:0:1",
            "legacy.soft-square:6:17",
            "legacy.rounded-triangle:5:5",
            "legacy.rounded-pentagon:5:7",
            "legacy.rounded-hexagon:5:8",
            "legacy.star-3-shallow:4:1",
            "legacy.star-4-moderate:4:6",
            "legacy.star-5-restrained:4:3",
        ])
    }

    func testGenomeParametersStayInsideTheCuratedClosedContourEnvelope() throws {
        let genomes = MetalShapeGenomeCatalog.presets.compactMap { preset -> MetalShapeGenome? in
            guard case let .genome(genome) = preset.contour else { return nil }
            return genome
        }
        XCTAssertEqual(Set(genomes.map { $0.morphology }).count, 4)
        for genome in genomes {
            XCTAssertTrue((2...12).contains(Int(genome.superformula.x)))
            XCTAssertGreaterThan(genome.superformula.y, 0)
            XCTAssertLessThanOrEqual(genome.harmonics.count, 3)
            XCTAssertTrue(genome.harmonics.allSatisfy { (2...12).contains($0.frequency) })
            XCTAssertTrue(genome.harmonics.allSatisfy { abs($0.amplitude) <= 0.12 })
            XCTAssertTrue((0.82...1.18).contains(genome.anisotropy.x))
            XCTAssertTrue((0.82...1.18).contains(genome.anisotropy.y))
            XCTAssertLessThanOrEqual(abs(genome.centerOffset.x), 0.12)
            XCTAssertLessThanOrEqual(abs(genome.centerOffset.y), 0.12)
        }
    }

    func testCatalogExposesTenApprovedMaterialsAndThreeRoles() {
        XCTAssertEqual(MetalShapeMaterial.allCases.count, 10)
        XCTAssertEqual(Set(MetalShapeMaterial.allCases.map(\.rawValue)), Set([
            "solid", "sideLight", "contour", "directionalBlur", "radialTwo",
            "radialThree", "proceduralLight", "proceduralFlow", "proceduralContour",
            "eclipseGlow",
        ]))
        XCTAssertEqual(MetalShapeRole.allCases, [.primary, .supporting, .accent])
    }
}
