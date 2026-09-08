import XCTest
@testable import Steps4

final class MetalShapeGenomeCatalogTests: XCTestCase {
    func testCatalogKeepsOneSoftShapeAndAddsSnowflakeAndWindflower() {
        let presets = MetalShapeGenomeCatalog.presets
        XCTAssertEqual(presets.count, 10)
        XCTAssertEqual(presets.filter { $0.source == .genome }.count, 4)
        XCTAssertEqual(presets.filter { $0.source == .legacy }.count, 6)
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)

        XCTAssertEqual(
            presets.filter { $0.source == .genome }.map(\.id),
            [
                "genome.soft-drift", "genome.lobed-triad",
                "genome.snowflake", "genome.windflower",
            ]
        )
        XCTAssertFalse(presets.map(\.id).contains("genome.soft-orbit"))
        XCTAssertFalse(presets.map(\.id).contains("genome.soft-cell"))
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
        ])
    }

    func testGenomeParametersStayInsideTheCuratedClosedContourEnvelope() throws {
        let genomes = MetalShapeGenomeCatalog.presets.compactMap { preset -> MetalShapeGenome? in
            guard case let .genome(genome) = preset.contour else { return nil }
            return genome
        }
        XCTAssertEqual(Set(genomes.map { $0.morphology }).count, 2)
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
