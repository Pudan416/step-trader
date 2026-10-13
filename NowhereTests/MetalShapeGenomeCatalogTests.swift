import XCTest
@testable import Nowhere

final class MetalShapeGenomeCatalogTests: XCTestCase {
    func testNewDailyCollectionsBoostMutedPigmentChroma() throws {
        let mutedPalette = ["#64819A", "#A17A72", "#718C78", "#9180A0"]
            .map { DayObjectRGB(hex: $0).linearRGB }
        let inputChroma = mutedPalette.map { color -> Float in
            let lab = DayObjectRGB(linearRGB: color).perceptualOKLab
            return hypot(lab.y, lab.z)
        }.reduce(0, +) / Float(mutedPalette.count)

        for collection in NativeAtlasDailyStyle.Collection.selectableCases {
            var recipe = NativeAtlasRecipe.makeDaily(
                dayKey: "vivid-\(collection.rawValue)",
                paletteCategories: ModernPaletteSelection.all,
                collection: collection
            )
            var style = try XCTUnwrap(recipe.dailyStyle)
            style.palette = mutedPalette
            style.neighboringPigments = mutedPalette
            recipe.dailyStyle = style
            recipe = recipe.reconciled(eventIDs: (0..<8).map { "vivid-\($0)" })

            let outputChroma = recipe.actors.map { actor -> Float in
                let lab = DayObjectRGB(linearRGB: SIMD3(actor.material.color0.x, actor.material.color0.y,
                    actor.material.color0.z)).perceptualOKLab
                return hypot(lab.y, lab.z)
            }.reduce(0, +) / Float(recipe.actors.count)
            XCTAssertGreaterThan(outputChroma, inputChroma * 1.12, collection.rawValue)
        }
    }

    func testArchivedDailyStylesKeepTheirOriginalPigmentPolicy() throws {
        let mutedPalette = ["#64819A", "#A17A72", "#718C78", "#9180A0"]
            .map { DayObjectRGB(hex: $0).linearRGB }
        let inputChroma = mutedPalette.map { color -> Float in
            let lab = DayObjectRGB(linearRGB: color).perceptualOKLab
            return hypot(lab.y, lab.z)
        }.reduce(0, +) / Float(mutedPalette.count)

        var recipe = NativeAtlasRecipe.makeDaily(
            dayKey: "archived-muted",
            paletteCategories: ModernPaletteSelection.all,
            collection: .circles
        )
        var style = try XCTUnwrap(recipe.dailyStyle)
        style.palette = mutedPalette
        style.neighboringPigments = mutedPalette
        style.pigmentChromaPolicyVersion = nil
        let data = try JSONEncoder().encode(style)
        style = try JSONDecoder().decode(NativeAtlasDailyStyle.self, from: data)
        XCTAssertNil(style.pigmentChromaPolicyVersion)
        recipe.dailyStyle = style

        recipe = recipe.reconciled(eventIDs: ["old-day-event"])
        let actor = try XCTUnwrap(recipe.actors.first)
        let lab = DayObjectRGB(linearRGB: SIMD3(actor.material.color0.x,
            actor.material.color0.y, actor.material.color0.z)).perceptualOKLab
        XCTAssertLessThan(hypot(lab.y, lab.z), inputChroma * 1.12)
    }

    func testCatalogKeepsOnlyDistinctFamiliesAndAddsTheSoftClover() {
        let presets = MetalShapeGenomeCatalog.presets
        XCTAssertEqual(presets.count, 12)
        XCTAssertEqual(presets.filter { $0.source == .genome }.count, 6)
        XCTAssertEqual(presets.filter { $0.source == .reference }.count, 2)
        XCTAssertEqual(presets.filter { $0.source == .legacy }.count, 4)
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)

        XCTAssertEqual(
            presets.filter { $0.source == .genome }.map(\.id),
            [
                "genome.soft-drift", "genome.snowflake",
                "genome.windflower", "genome.concave-square",
                "genome.soft-clover", "genome.concentric-ripple",
            ]
        )
        XCTAssertEqual(Set(presets.filter { $0.source == .reference }.map(\.id)), [
            "reference.dimpled-sphere", "reference.spiral-rays",
        ])
        XCTAssertTrue(Set([
            "genome.lobed-triad", "legacy.rounded-pentagon", "legacy.star-3-shallow",
        ]).isDisjoint(with: presets.map(\.id)))
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
            "legacy.rounded-hexagon:5:8",
        ])
    }

    func testGenomeParametersStayInsideTheCuratedClosedContourEnvelope() throws {
        let genomes = MetalShapeGenomeCatalog.presets.compactMap { preset -> MetalShapeGenome? in
            guard case let .genome(genome) = preset.contour else { return nil }
            return genome
        }
        XCTAssertEqual(Set(genomes.map { $0.morphology }), [.softRadial, .concentricRipple, .spiralRays])
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

    func testCatalogExposesThirteenApprovedMaterialsAndThreeRoles() {
        XCTAssertEqual(MetalShapeMaterial.allCases.count, 13)
        XCTAssertEqual(Set(MetalShapeMaterial.allCases.map(\.rawValue)), Set([
            "solid", "sideLight", "contour", "directionalBlur", "radialTwo",
            "radialThree", "proceduralLight", "proceduralFlow", "proceduralContour",
            "eclipseGlow", "sunset", "concentricRings", "spiralVariation",
        ]))
        XCTAssertEqual(MetalShapeRole.allCases, [.primary, .supporting, .accent])
        XCTAssertEqual(MetalShapeGenomeCatalog.presets.filter { $0.compatibility.allowed.contains(.sunset) }.map(\.id), ["legacy.circle"])
        XCTAssertEqual(MetalShapeGenomeCatalog.presets.filter { $0.compatibility.allowed.contains(.concentricRings) }.map(\.id), ["genome.concentric-ripple"])
        XCTAssertEqual(MetalShapeGenomeCatalog.presets.filter { $0.compatibility.allowed.contains(.spiralVariation) }.map(\.id), ["reference.spiral-rays"])
        XCTAssertEqual(MetalShapeGenomeCatalog.presets.filter { $0.compatibility.allowed.contains(.directionalBlur) && $0.id == "legacy.rounded-triangle" }.map(\.id), ["legacy.rounded-triangle"])
    }
}
