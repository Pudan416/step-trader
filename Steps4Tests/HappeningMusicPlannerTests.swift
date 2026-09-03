import XCTest
@testable import Steps4

final class HappeningMusicPlannerTests: XCTestCase {
    func testCountsZeroThroughTenAssignCatalogRecipesWithoutReplacement() throws {
        for count in 0...10 {
            let plans = makePlans(ids: ids(count: count))
            XCTAssertEqual(plans.count, count, "count=\(count)")
            XCTAssertEqual(Set(plans.map(\.recipeID)).count, count, "count=\(count)")
            XCTAssertTrue(plans.allSatisfy { HappeningSoundCatalog.recipe(for: $0.recipeID) != nil })
        }
    }

    func testSameRemixSeedIsStableAndDifferentSeedChangesRecipePermutation() {
        let happeningIDs = ids(count: 10)
        let first = makePlans(ids: happeningIDs, remixSeed: 0xD4A0_B1EC_75ED_0001)
        let repeated = makePlans(ids: happeningIDs, remixSeed: 0xD4A0_B1EC_75ED_0001)
        let remixed = makePlans(ids: happeningIDs, remixSeed: 0xD4A0_B1EC_75ED_0002)

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first.map(\.recipeID), remixed.map(\.recipeID))
    }

    func testIncreasingCountKeepsEverySurvivingHappeningRecipeStable() throws {
        let allIDs = ids(count: 10)
        let smaller = makePlans(ids: Array(allIDs.prefix(4)))
        let larger = makePlans(ids: allIDs)

        for plan in smaller {
            XCTAssertEqual(
                try XCTUnwrap(larger.first(where: { $0.happeningID == plan.happeningID })).recipeID,
                plan.recipeID
            )
        }
    }

    func testFourOrMoreHappeningsRepresentAtLeastFourRecipeFamilies() throws {
        for count in 4...10 {
            let plans = makePlans(ids: ids(count: count))
            let families = try Set(plans.map { plan in
                try XCTUnwrap(HappeningSoundCatalog.recipe(for: plan.recipeID)).family
            })
            XCTAssertGreaterThanOrEqual(families.count, 4, "count=\(count)")
        }
    }

    func testTenHappeningsUseAtLeastSixDistinctSourceIdentities() throws {
        let plans = makePlans(ids: ids(count: 10))
        let sourceIdentities = try Set(plans.map { plan in
            try XCTUnwrap(HappeningSoundCatalog.recipe(for: plan.recipeID)).sources[0].resourceName
        })

        XCTAssertGreaterThanOrEqual(sourceIdentities.count, 6)
    }

    func testAdjacentBirthsAvoidTheSameFamilyWhileAnotherFamilyIsAvailable() throws {
        let plans = makePlans(ids: ids(count: 10))
        let families = try plans.map { plan in
            try XCTUnwrap(HappeningSoundCatalog.recipe(for: plan.recipeID)).family
        }

        for pair in zip(families, families.dropFirst()) {
            XCTAssertNotEqual(pair.0, pair.1)
        }
    }

    func testPlanFamilyMatchesRecipeAndPerEventGainsRemainBounded() throws {
        let plans = makePlans(ids: ids(count: 10))

        for plan in plans {
            let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: plan.recipeID))
            XCTAssertEqual(plan.family, soundFamily(for: recipe.family))
            XCTAssertTrue(plan.pan.isFinite && (-0.85...0.85).contains(plan.pan))
            XCTAssertTrue(plan.gain.isFinite && (0.62...0.80).contains(plan.gain))
            XCTAssertTrue(plan.birthGain.isFinite && (plan.gain...0.95).contains(plan.birthGain))
            XCTAssertNotEqual(plan.recurrence.scheduleSeed, 0)
            XCTAssertTrue((0.25...0.50).contains(abs(plan.recurrence.floatingOffsetBeats)))
        }
        XCTAssertLessThan(plans.reduce(0) { $0 + $1.gain }, 8.01)
        XCTAssertLessThan(plans.reduce(0) { $0 + $1.birthGain }, 9.51)
    }

    func testOversizedArbitraryOrderedInputUsesOnlyItsFirstTenIDs() {
        let ordered = ["zulu", "alpha", "echo", "bravo", "hotel", "charlie", "golf", "delta", "india", "foxtrot", "kilo", "juliet"]

        let plans = makePlans(ids: ordered)

        XCTAssertEqual(plans.map(\.happeningID), Array(ordered.prefix(10)))
        XCTAssertEqual(Set(plans.map(\.recipeID)).count, 10)
    }

    func testRecipeMigrationPreservesFrozenPreMigrationIdentityAndScheduleValues() throws {
        struct Fixture {
            let id: String
            let pan: Double
            let gain: Double
            let birthGain: Double
            let scheduleSeed: UInt64
            let alignmentRank: UInt64
            let floatingOffset: Double
        }
        let fixtures = [
            Fixture(id: "event-0", pan: -0.41656545531320505, gain: 0.6708402129303254, birthGain: 0.8082854798206942, scheduleSeed: 18_087_808_294_331_211_280, alignmentRank: 14_812_916_986_981_494_135, floatingOffset: -0.5),
            Fixture(id: "event-4", pan: 0.43740676647220422, gain: 0.7597215944202744, birthGain: 0.8658758610730725, scheduleSeed: 2_137_261_057_161_796_335, alignmentRank: 10_822_951_049_026_308_331, floatingOffset: -0.5),
            Fixture(id: "morning", pan: -0.2539172236500712, gain: 0.7639082859033759, birthGain: 0.9231251759109533, scheduleSeed: 17_792_516_803_595_872_528, alignmentRank: 17_815_431_101_816_481_277, floatingOffset: 0.25),
        ]
        let plans = makePlans(ids: fixtures.map(\.id))

        for fixture in fixtures {
            let plan = try XCTUnwrap(plans.first { $0.happeningID == fixture.id })
            XCTAssertEqual(plan.pan, fixture.pan, accuracy: 1e-15, fixture.id)
            XCTAssertEqual(plan.gain, fixture.gain, accuracy: 1e-15, fixture.id)
            XCTAssertEqual(plan.birthGain, fixture.birthGain, accuracy: 1e-15, fixture.id)
            XCTAssertEqual(plan.recurrence.scheduleSeed, fixture.scheduleSeed, fixture.id)
            XCTAssertEqual(plan.recurrence.alignmentRank, fixture.alignmentRank, fixture.id)
            XCTAssertEqual(plan.recurrence.floatingOffsetBeats, fixture.floatingOffset, fixture.id)
        }
    }

    private let defaultSeed: UInt64 = 0xD4A0_B1EC_75ED_0001

    private func makePlans(ids: [String], remixSeed: UInt64? = nil) -> [HappeningMusicPlan] {
        let seed = remixSeed ?? defaultSeed
        let input = NormalizedDayMusicInput(
            stepsProgress: 0.61,
            sleepProgress: 0.74,
            happeningIDs: ids,
            glitchProgress: 0.31,
            motionEnergy: 0.625,
            visualClarity: 0.625,
            diagnostics: []
        )
        return HappeningMusicPlanner.makePlans(
            input: input,
            tonalWorld: TonalWorldPlanner.makePlan(input: input, remixSeed: seed),
            remixSeed: seed
        )
    }

    private func ids(count: Int) -> [String] {
        (0..<count).map { "event-\($0)" }
    }

    private func soundFamily(for family: HappeningRecipeFamily) -> HappeningSoundFamily {
        switch family {
        case .synthPluck: return .pluck
        case .acousticMallet: return .mallet
        case .acousticBell: return .bell
        case .softOneShot: return .softOneShot
        case .texture: return .texture
        }
    }
}
