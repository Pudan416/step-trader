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

    func testCatalogKeepsSixRecipesInEachStableFamilyBlock() {
        let recipes = HappeningSoundCatalog.recipes
        let expectedFamilies: [HappeningRecipeFamily] = [
            .synthPluck, .acousticMallet, .acousticBell, .softOneShot, .texture,
        ]

        XCTAssertEqual(
            recipes.map(\.family),
            expectedFamilies.flatMap { Array(repeating: $0, count: 6) }
        )
        for family in expectedFamilies {
            XCTAssertEqual(recipes.filter { $0.family == family }.count, 6)
        }
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
