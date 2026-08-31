#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DeterministicMusicDirectorTests: XCTestCase {
    func testSameInputAndSeedReproduceTheEntirePlanExactly() {
        let input = representativeInput()

        let first = DeterministicMusicDirector.makePlan(
            input: input,
            remixSeed: 0xD4A0_B1EC_75ED_0001
        )
        let second = DeterministicMusicDirector.makePlan(
            input: input,
            remixSeed: 0xD4A0_B1EC_75ED_0001
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.seed, 0xD4A0_B1EC_75ED_0001)
        XCTAssertEqual(first.input, input.normalized())
        XCTAssertEqual(first.happenings.map(\.happeningID), ["morning", "work", "evening"])
    }

    func testRemixSeedChangesMusicalChoicesWithoutChangingNormalizedDayValues() {
        let input = representativeInput()
        let first = DeterministicMusicDirector.makePlan(input: input, remixSeed: 0x1)
        let remixed = DeterministicMusicDirector.makePlan(input: input, remixSeed: 0x2)

        XCTAssertEqual(first.input, remixed.input)
        XCTAssertEqual(first.input, input.normalized())
        XCTAssertNotEqual(first.seed, remixed.seed)

        let tonalWorldChanged = first.world != remixed.world
        let instrumentsChanged = selectedInstrumentIDs(in: first) != selectedInstrumentIDs(in: remixed)
        let rhythmPatternChanged = first.rhythm.voices.map(\.stepProbabilities)
            != remixed.rhythm.voices.map(\.stepProbabilities)
        XCTAssertTrue(
            tonalWorldChanged || instrumentsChanged || rhythmPatternChanged,
            "A Remix seed must alter at least the tonal world, instruments, or rhythm pattern"
        )
    }

    func testDirectorAssemblesEveryPlannerFromOneNormalizedInputAndExplicitSeed() throws {
        let input = representativeInput()
        let seed: UInt64 = 0xFFFF_FFFF_FFFF_FFFF
        let normalized = input.normalized()
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        let world = TonalWorldPlanner.makePlan(input: normalized, remixSeed: seed)
        let expectedHappenings = HappeningMusicPlanner.makePlans(
            input: normalized,
            tonalWorld: world,
            instrumentDescriptors: descriptors,
            remixSeed: seed
        )
        let plan = DeterministicMusicDirector.makePlan(input: input, remixSeed: seed)

        XCTAssertEqual(plan.world, world)
        XCTAssertEqual(plan.rhythm, RhythmPlanner.makePlan(input: normalized, remixSeed: seed))
        XCTAssertEqual(
            plan.harmony,
            HarmonyPlanner.makePlan(
                input: normalized,
                tonalWorld: world,
                instrumentDescriptors: descriptors,
                remixSeed: seed
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(plan.harmony.role(for: .pianoOrKeysAccents)).instrumentTarget,
            .feltPiano
        )
        XCTAssertEqual(plan.happenings, expectedHappenings)
        XCTAssertEqual(
            plan.lead,
            try XCTUnwrap(
                LeadPlanner.makePlan(
                    tonalWorld: world,
                    instrumentDescriptors: descriptors,
                    remixSeed: seed
                )
            )
        )
        XCTAssertEqual(plan.glitch, GlitchPlanner.makePlan(input: normalized))
        XCTAssertEqual(plan.mix, LayerMixPlanner.makePlan(happeningCount: expectedHappenings.count))
    }

    func testGoalOverachievementCannotAddMusicalComplexity() {
        let atGoal = DayMusicInput(
            countedSteps: 10_000,
            stepGoal: 10_000,
            countedSleepHours: 8,
            sleepGoalHours: 8,
            happeningIDs: ["event-0", "event-1"],
            spentColors: 100
        )
        let overGoal = DayMusicInput(
            countedSteps: 50_000,
            stepGoal: 10_000,
            countedSleepHours: 24,
            sleepGoalHours: 8,
            happeningIDs: ["event-0", "event-1"],
            spentColors: 500
        )

        XCTAssertEqual(
            DeterministicMusicDirector.makePlan(input: atGoal, remixSeed: 0x2),
            DeterministicMusicDirector.makePlan(input: overGoal, remixSeed: 0x2)
        )
    }

    func testHappeningIdentitiesSurviveAdditionsAndRemovals() {
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001
        let smaller = input(happeningIDs: ["bravo", "delta"])
        let larger = input(happeningIDs: ["alpha", "bravo", "charlie", "delta"])
        let smallerPlan = DeterministicMusicDirector.makePlan(input: smaller, remixSeed: seed)
        let largerPlan = DeterministicMusicDirector.makePlan(input: larger, remixSeed: seed)
        let largerByID = Dictionary(uniqueKeysWithValues: largerPlan.happenings.map {
            ($0.happeningID, $0)
        })

        for happening in smallerPlan.happenings {
            XCTAssertEqual(happening, largerByID[happening.happeningID])
        }
    }

    private func representativeInput() -> DayMusicInput {
        DayMusicInput(
            countedSteps: 8_500,
            stepGoal: 10_000,
            countedSleepHours: 7,
            sleepGoalHours: 8,
            happeningIDs: ["morning", "work", "evening"],
            spentColors: 25
        )
    }

    private func input(happeningIDs: [String]) -> DayMusicInput {
        DayMusicInput(
            countedSteps: 6_000,
            stepGoal: 10_000,
            countedSleepHours: 5.6,
            sleepGoalHours: 8,
            happeningIDs: happeningIDs,
            spentColors: 50
        )
    }

    private func selectedInstrumentIDs(in plan: DayMusicPlan) -> [String] {
        plan.harmony.roles.map { role in
            switch role.instrumentTarget {
            case let .tonal(instrumentID): return instrumentID.rawValue
            case .feltPiano: return "felt-piano"
            }
        }
            + plan.happenings.map(\.instrumentID.rawValue)
            + [plan.lead.instrumentID.rawValue]
    }
}
#endif
