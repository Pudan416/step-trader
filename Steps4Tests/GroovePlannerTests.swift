import XCTest
@testable import Steps4

enum WorldArrangementFixture {
    static let catalog = try! DayObjectsSoundWorldCatalog.load(from: Bundle(for: GroovePlannerTests.self))

    static func group(_ world: DayObjectsSoundWorld, _ mood: DayObjectsSoundMood) -> DayObjectsCompatibilityGroup {
        catalog.groups.first { $0.world == world && $0.mood == mood }!
    }

    static func runtimeIDs(_ ids: [DayObjectsInstrumentID], mood: DayObjectsSoundMood) -> Set<DayObjectsInstrumentID> {
        Set(catalog.recipes.filter { ids.contains($0.id) }.map { $0.resolvedInstrumentID(for: mood) })
    }

    static func plan(
        _ world: DayObjectsSoundWorld, _ mood: DayObjectsSoundMood, seed: UInt64 = 77,
        steps: Double = 1, sleep: Double = 1, allowGuest: Bool = false,
        happenings: [String] = ["one", "two"],
        descriptors: [DayObjectsInstrumentDescriptor]? = nil
    ) -> DayMusicPlan {
        let selected = DayObjectsWorldSelector.makeSelection(remixSeed: seed, forcedWorld: world, forcedMood: mood)
        return DeterministicMusicDirector.makePlan(
            input: .init(countedSteps: steps * 10_000, stepGoal: 10_000,
                         countedSleepHours: sleep * 8, sleepGoalHours: 8,
                         happeningIDs: happenings, spentColors: 0),
            instrumentDescriptors: descriptors ?? catalog.descriptors,
            remixSeed: seed,
            selection: .init(world: world, mood: mood, guestWorld: allowGuest ? selected.guestWorld : nil)
        )
    }
}

final class GroovePlannerTests: XCTestCase {
    func testWorldsBiasPulseArpeggioAndSparseRoleBudget() {
        for mood in DayObjectsSoundMood.allCases {
            let modes = DayObjectsSoundWorld.allCases.map { world in
                (0..<512).map { GroovePlanner.makePlan(remixSeed: UInt64($0), soundWorld: world, mood: mood).mode }
            }
            if mood == .sparse {
                XCTAssertTrue(modes.flatMap { $0 }.allSatisfy { $0 == .percussion })
            } else {
                XCTAssertGreaterThan(modes[2].filter { $0 == .bassPulse }.count, modes[3].filter { $0 == .bassPulse }.count)
                XCTAssertGreaterThan(modes[3].filter { $0 == .bassArp }.count, modes[2].filter { $0 == .bassArp }.count)
                XCTAssertTrue(modes[1].allSatisfy { $0 == .percussion || $0 == .bassBed })
            }
        }
    }
    func testEveryHundredBucketsUseExactDistribution() {
        let modes = (0..<100).map(GroovePlanner.mode(forBucket:))

        XCTAssertEqual(modes.filter { $0 == .percussion }.count, 40)
        XCTAssertEqual(modes.filter { $0 == .bassPulse }.count, 25)
        XCTAssertEqual(modes.filter { $0 == .bassArp }.count, 20)
        XCTAssertEqual(modes.filter { $0 == .bassBed }.count, 15)
    }

    func testEveryModePublishesItsExactRetentionAndAnchorKickCap() {
        let expected: [(GrooveMode, Double, Int)] = [
            (.percussion, 1.00, 2),
            (.bassPulse, 0.65, 2),
            (.bassArp, 0.40, 1),
            (.bassBed, 0.50, 1)
        ]

        for (mode, retention, anchorKickCap) in expected {
            let plan = GroovePlanner.makePlan(remixSeed: seedProducing(mode))

            XCTAssertEqual(plan.auxiliaryRetention, retention, accuracy: 1e-12)
            XCTAssertEqual(plan.maximumAnchorKicksPerBar, anchorKickCap)
        }
    }

    func testSameSeedProducesAnIndependentRepeatableThinningPlan() {
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001
        let first = GroovePlanner.makePlan(remixSeed: seed)
        let second = GroovePlanner.makePlan(remixSeed: seed)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.thinningSeed, seed)
    }

    private func seedProducing(_ mode: GrooveMode) -> UInt64 {
        for seed in UInt64(0)..<10_000 where GroovePlanner.makePlan(remixSeed: seed).mode == mode {
            return seed
        }
        XCTFail("No seed found for \(mode)")
        return 0
    }
}
