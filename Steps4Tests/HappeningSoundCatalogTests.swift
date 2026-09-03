#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class HappeningSoundCatalogTests: XCTestCase {
    func testCatalogHasAllThirtyStableIDsAndLabelsInOrder() {
        let recipes = HappeningSoundCatalog.recipes

        XCTAssertEqual(recipes.map(\.id.rawValue), Array(1...30))
        XCTAssertEqual(recipes.map(\.label), (1...30).map { String(format: "%02d", $0) })
        XCTAssertEqual(recipes.map(\.id).count, Set(recipes.map(\.id)).count)
        XCTAssertNil(HappeningSoundRecipeID(rawValue: 0))
        XCTAssertNil(HappeningSoundRecipeID(rawValue: 31))
    }

    func testRecipeIDDecodingRejectsValuesOutsideTheValidatedBoundary() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(HappeningSoundRecipeID.self, from: Data("1".utf8)),
            HappeningSoundRecipeID(rawValue: 1)
        )
        XCTAssertThrowsError(try JSONDecoder().decode(HappeningSoundRecipeID.self, from: Data("0".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(HappeningSoundRecipeID.self, from: Data("31".utf8)))
    }

    func testRetimbreCatalogHasExactIdentityPaletteAndTopology() {
        let recipes = HappeningSoundCatalog.recipes
        let expectedNames = [
            "Warm analog ping", "Glass FM droplet", "Muted pulse pluck",
            "Hollow string", "Air reed blip", "Reverse pluck bloom",
            "Wooden kalimba", "Ceramic knock", "Soft marimba", "Balafon brush",
            "Muted vibraphone", "Felt key", "Soft metal bowl", "Glass tap bloom",
            "Chorus kalimba", "Nylon pizzicato", "Dark tubular bell", "Distant chime",
            "Sub bloom", "Analog filter ping", "Vocal droplet", "Phase-distortion bead",
            "Rubber FM bubble", "Bowed harmonic stab", "Breath resonator",
            "Bowed glass cloud", "Granular shimmer", "Reverse glass gesture",
            "Soft dust impact", "Airy exhale",
        ]
        let expectedTopologies = [
            "analog-ping", "fm-droplet", "pulse-pluck", "waveguide-string", "reed-blip",
            "reverse-pluck", "kalimba-modal", "ceramic-modal", "vcsl-marimba-dark",
            "vcsl-balafon-dry", "vcsl-vibe-chorus", "felt-key", "metal-bowl-modal",
            "glass-reverse", "chorus-kalimba", "nylon-waveguide", "vcsl-tubular-dark",
            "vcsl-chime-dark", "sub-bloom", "filter-ping", "formant-droplet",
            "phase-distortion", "rubber-fm", "harmonic-stab", "breath-resonator",
            "modal-glass-cloud", "granular-shimmer", "reverse-glass-unpitched",
            "dust-impact", "breath-exhale",
        ]
        let synthIDs: Set<Int> = [1, 2, 3, 4, 5, 8, 19, 20, 21, 22]
        let organicIDs: Set<Int> = [7, 9, 10, 12, 16, 17, 18, 28, 29, 30]
        let expectedPaletteKinds: [HappeningPaletteKind] = (1...30).map {
            synthIDs.contains($0) ? .synth : organicIDs.contains($0) ? .organic : .hybrid
        }

        XCTAssertEqual(recipes.map(\.workingName), expectedNames)
        XCTAssertEqual(recipes.map(\.paletteKind), expectedPaletteKinds)
        XCTAssertEqual(recipes.map(\.topology), expectedTopologies)
        XCTAssertEqual(Dictionary(grouping: recipes, by: \.paletteKind).mapValues(\.count),
                       [.synth: 10, .organic: 10, .hybrid: 10])
        XCTAssertEqual(Set(recipes.map(\.topology)).count, 30)
        XCTAssertEqual(Set(recipes.map { "\($0.attackTopology)|\($0.tailTopology)" }).count, 30)
        XCTAssertTrue(recipes.allSatisfy { !$0.workingName.isEmpty })
        XCTAssertTrue(recipes.allSatisfy { !$0.topology.isEmpty && $0.topology != "test-fixture" })
        XCTAssertTrue(recipes.allSatisfy { !$0.attackTopology.isEmpty && $0.attackTopology != "test-attack" })
        XCTAssertTrue(recipes.allSatisfy { !$0.tailTopology.isEmpty && $0.tailTopology != "test-tail" })
    }

    func testCatalogSourcesHaveUniquePathsAndChecksums() {
        let sources = HappeningSoundCatalog.recipes.flatMap(\.sources)

        XCTAssertEqual(sources.map(\.resourceName).count, Set(sources.map(\.resourceName)).count)
        XCTAssertEqual(sources.map(\.sha256).count, Set(sources.map(\.sha256)).count)
        XCTAssertTrue(sources.allSatisfy { $0.resourceName.hasPrefix("Happenings/") })
        XCTAssertTrue(sources.allSatisfy { $0.sha256.count == 64 })
    }

    func testCatalogParametersStayWithinSafeProductionBounds() {
        for recipe in HappeningSoundCatalog.recipes {
            XCTAssertTrue((-24.0...0.0).contains(recipe.gainDB), recipe.label)
            XCTAssertTrue((0.0...0.5).contains(recipe.attackSeconds), recipe.label)
            XCTAssertTrue((0.05...6.0).contains(recipe.releaseSeconds), recipe.label)
            XCTAssertTrue((0.0...1.0).contains(recipe.delayMix), recipe.label)
            XCTAssertTrue((0.0...0.7).contains(recipe.delayFeedback), recipe.label)
            XCTAssertTrue((0.0...1.0).contains(recipe.reverbMix), recipe.label)
            XCTAssertTrue((80.0...18_000.0).contains(recipe.filterStartHz), recipe.label)
            XCTAssertTrue((80.0...18_000.0).contains(recipe.filterEndHz), recipe.label)
        }
    }

    func testRenderedTailRecipesUseDarkSpatialRuntimeGlue() {
        for recipe in HappeningSoundCatalog.recipes {
            XCTAssertLessThanOrEqual(recipe.delayMix, 0.10, recipe.label)
            XCTAssertLessThanOrEqual(recipe.delayFeedback, 0.18, recipe.label)
            XCTAssertTrue((0.55...0.78).contains(recipe.reverbMix), recipe.label)

            let bounds: (ClosedRange<Double>, ClosedRange<Double>)
            switch recipe.id.rawValue {
            case 1...6: bounds = (0.02...0.08, 0.06...0.15)
            case 7...12: bounds = (0.01...0.06, 0.04...0.12)
            case 13...18: bounds = (0.02...0.07, 0.05...0.14)
            case 19...24: bounds = (0.02...0.08, 0.06...0.15)
            default: bounds = (0.01...0.06, 0.04...0.12)
            }
            XCTAssertTrue(bounds.0.contains(recipe.delayMix), recipe.label)
            XCTAssertTrue(bounds.1.contains(recipe.delayFeedback), recipe.label)
        }
        XCTAssertLessThanOrEqual(HappeningSoundCatalog.recipes[16].filterEndHz, 7_500)
        XCTAssertLessThanOrEqual(HappeningSoundCatalog.recipes[17].filterEndHz, 7_500)
    }

    func testEveryTonalRecipeCoversItsPreferredOctaveWithinTwoSemitones() {
        for recipe in HappeningSoundCatalog.recipes {
            guard case let .tonal(preferredRange) = recipe.pitch else { continue }

            let rootPitchClasses = recipe.sources.map { Int($0.rootMIDI % 12) }
            for note in preferredRange {
                let pitchClass = Int(note % 12)
                let nearestDistance = rootPitchClasses
                    .map { min(abs($0 - pitchClass), 12 - abs($0 - pitchClass)) }
                    .min()
                XCTAssertLessThanOrEqual(nearestDistance ?? .max, 2, "\(recipe.label) misses \(note)")
            }
        }
    }

    func testPitchBehaviorAndSourceCountsMatchTheStableRecipePartition() {
        let recipes = HappeningSoundCatalog.recipes

        for recipe in recipes.prefix(24) {
            guard case .tonal = recipe.pitch else {
                return XCTFail("\(recipe.label) must be tonal")
            }
            XCTAssertEqual(recipe.sources.count, 4, recipe.label)
            XCTAssertEqual(Set(recipe.sources.map { $0.rootMIDI % 12 }), Set([0, 3, 6, 9]), recipe.label)
        }
        for recipe in recipes[24..<27] {
            guard case let .resonantNoise(_, preferredRange, resonatorTargetPitchClasses) = recipe.pitch else {
                return XCTFail("\(recipe.label) must be resonant noise")
            }
            XCTAssertEqual(recipe.sources.count, 1, recipe.label)
            XCTAssertEqual(resonatorTargetPitchClasses.count, 4, recipe.label)
            XCTAssertEqual(Set(resonatorTargetPitchClasses).count, 4, recipe.label)
            XCTAssertTrue(resonatorTargetPitchClasses.allSatisfy { (0...11).contains($0) }, recipe.label)
            let preferredPitchClasses = Set(preferredRange.map { $0 % 12 })
            XCTAssertTrue(preferredPitchClasses.isSuperset(of: Set(resonatorTargetPitchClasses)), recipe.label)
        }
        for recipe in recipes.suffix(3) {
            guard case .unpitched = recipe.pitch else {
                return XCTFail("\(recipe.label) must be unpitched")
            }
            XCTAssertEqual(recipe.sources.count, 1, recipe.label)
        }
    }

    func testResonantTexturesDeclareTheFourStableResonatorTargets() {
        let resonantRecipes = HappeningSoundCatalog.recipes[24..<27]

        XCTAssertEqual(resonantRecipes.map(\.label), ["25", "26", "27"])
        for recipe in resonantRecipes {
            guard case let .resonantNoise(referenceMIDI, _, resonatorTargetPitchClasses) = recipe.pitch else {
                return XCTFail("\(recipe.label) must be resonant noise")
            }
            XCTAssertEqual(referenceMIDI, 60, recipe.label)
            XCTAssertEqual(resonatorTargetPitchClasses, [0, 3, 6, 9], recipe.label)
        }
    }
}
#endif
