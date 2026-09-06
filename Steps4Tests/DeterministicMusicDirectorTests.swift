#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DeterministicMusicDirectorTests: XCTestCase {
    func testSameDayAndSeedAreDeterministicInsideEachSoundWorld() {
        for soundWorld in DayObjectsSoundWorld.allCases {
            let first = makeWorldPlan(soundWorld: soundWorld)
            let repeated = makeWorldPlan(soundWorld: soundWorld)

            XCTAssertEqual(first, repeated)
            XCTAssertEqual(first.soundWorld, soundWorld)
        }
    }

    func testWorldsUseContrastingGrooveLeadAndHarmonyPalettes() {
        let felt = makeWorldPlan(soundWorld: .feltAndWood)
        let metal = makeWorldPlan(soundWorld: .metalAndCurrent)

        XCTAssertTrue([GrooveMode.percussion, .bassBed].contains(felt.groove.mode))
        XCTAssertTrue([GrooveMode.bassPulse, .bassArp].contains(metal.groove.mode))
        XCTAssertNotEqual(felt.lead.instrumentID, metal.lead.instrumentID)
        XCTAssertNotEqual(tonalInstrumentIDs(in: felt), tonalInstrumentIDs(in: metal))
        XCTAssertNotEqual(felt.happenings.map(\.recipeID), metal.happenings.map(\.recipeID))
    }

    func testWorldChangeKeepsTheMeasuredDayInputsUntouched() {
        let felt = makeWorldPlan(soundWorld: .feltAndWood)
        let metal = makeWorldPlan(soundWorld: .metalAndCurrent)

        XCTAssertEqual(felt.input, metal.input)
        XCTAssertEqual(felt.world, metal.world)
        XCTAssertEqual(felt.glitch, metal.glitch)
    }

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
        let soundsChanged = selectedSoundIDs(in: first) != selectedSoundIDs(in: remixed)
        let rhythmPatternChanged = first.rhythm.voices.map(\.stepProbabilities)
            != remixed.rhythm.voices.map(\.stepProbabilities)
        XCTAssertTrue(
            tonalWorldChanged || soundsChanged || rhythmPatternChanged,
            "A Remix seed must alter at least the tonal world, sounds, or rhythm pattern"
        )
    }

    func testDirectorAssemblesEveryPlannerFromOneNormalizedInputAndExplicitSeed() throws {
        let input = representativeInput()
        let seed: UInt64 = 0xFFFF_FFFF_FFFF_FFFF
        let normalized = input.normalized()
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        let world = TonalWorldPlanner.makePlan(input: normalized, remixSeed: seed)
        let groove = GroovePlanner.makePlan(remixSeed: seed)
        let bass = BassPlanner.makePlan(
            input: normalized,
            tonalWorld: world,
            groove: groove,
            instrumentDescriptors: descriptors,
            remixSeed: seed
        )
        let expectedHappenings = HappeningMusicPlanner.makePlans(
            input: normalized,
            tonalWorld: world,
            remixSeed: seed
        )
        let plan = DeterministicMusicDirector.makePlan(input: input, remixSeed: seed)

        XCTAssertEqual(plan.world, world)
        XCTAssertEqual(plan.groove, groove)
        XCTAssertEqual(plan.bass, bass)
        XCTAssertEqual(
            plan.rhythm,
            RhythmPlanner.makePlan(input: normalized, remixSeed: seed, groove: groove)
        )
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
        XCTAssertEqual(
            plan.glitch,
            GlitchPlanner.makePlan(input: normalized, remixSeed: seed)
        )
        XCTAssertEqual(plan.mix, LayerMixPlanner.makePlan(happeningCount: expectedHappenings.count))
    }

    func testMissingBassDescriptorFallsBackToPercussionAndReplansRhythm() throws {
        let seed = seedProducingBass()
        let input = representativeInput()
        let descriptorsWithoutBass = DayObjectsInstrumentManifest.defaultDescriptors.filter {
            $0.category != .bass
        }
        let plan = DeterministicMusicDirector.makePlan(
            input: input,
            instrumentDescriptors: descriptorsWithoutBass,
            remixSeed: seed
        )

        XCTAssertEqual(GroovePlanner.makePlan(remixSeed: seed).usesBass, true)
        XCTAssertEqual(plan.groove, GroovePlan.percussion)
        XCTAssertNil(plan.bass)
        XCTAssertEqual(
            plan.rhythm,
            RhythmPlanner.makePlan(
                input: input.normalized(),
                remixSeed: seed,
                groove: .percussion
            )
        )
    }

    func testHappeningCountCannotChangePublishedGrooveOrBassCandidates() throws {
        let seed = seedProducingBass()
        let sharedDay = DayMusicInput(
            countedSteps: 8_500,
            stepGoal: 10_000,
            countedSleepHours: 7,
            sleepGoalHours: 8,
            happeningIDs: [],
            spentColors: 25
        )
        let sparse = DeterministicMusicDirector.makePlan(input: sharedDay, remixSeed: seed)
        let crowded = DeterministicMusicDirector.makePlan(
            input: DayMusicInput(
                countedSteps: sharedDay.countedSteps,
                stepGoal: sharedDay.stepGoal,
                countedSleepHours: sharedDay.countedSleepHours,
                sleepGoalHours: sharedDay.sleepGoalHours,
                happeningIDs: (0..<10).map { "event-\($0)" },
                spentColors: sharedDay.spentColors
            ),
            remixSeed: seed
        )

        XCTAssertEqual(sparse.groove, crowded.groove)
        XCTAssertEqual(
            try XCTUnwrap(sparse.bass).instrumentID,
            try XCTUnwrap(crowded.bass).instrumentID
        )
        XCTAssertEqual(
            try XCTUnwrap(sparse.bass).events,
            try XCTUnwrap(crowded.bass).events
        )
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

    func testSpentColorsIsAContinuousGlitchChangeAndDoesNotMutateStructuralPlans() {
        let clearInput = DayMusicInput(
            countedSteps: 8_500,
            stepGoal: 10_000,
            countedSleepHours: 7,
            sleepGoalHours: 8,
            happeningIDs: ["morning", "work", "evening"],
            spentColors: 0
        )
        let damagedInput = DayMusicInput(
            countedSteps: 8_500,
            stepGoal: 10_000,
            countedSleepHours: 7,
            sleepGoalHours: 8,
            happeningIDs: ["morning", "work", "evening"],
            spentColors: 50
        )
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001
        let clear = DeterministicMusicDirector.makePlan(input: clearInput, remixSeed: seed)
        let damaged = DeterministicMusicDirector.makePlan(input: damagedInput, remixSeed: seed)

        XCTAssertEqual(clear.world, damaged.world)
        XCTAssertEqual(clear.rhythm, damaged.rhythm)
        XCTAssertEqual(clear.harmony, damaged.harmony)
        XCTAssertEqual(clear.happenings, damaged.happenings)
        XCTAssertEqual(clear.lead, damaged.lead)
        XCTAssertEqual(clear.mix, damaged.mix)
        XCTAssertNotEqual(clear.glitch, damaged.glitch)
        XCTAssertEqual(clear.glitch.progress, 0)
        XCTAssertEqual(damaged.glitch.progress, 0.25)
    }

    func testHappeningRecipeBindingsAreDeterministicStableForPrefixesAndRemixable() {
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001
        let smaller = input(happeningIDs: ["event-0", "event-1"])
        let larger = input(happeningIDs: ["event-0", "event-1", "event-2", "event-3"])
        let smallerPlan = DeterministicMusicDirector.makePlan(input: smaller, remixSeed: seed)
        let repeatedPlan = DeterministicMusicDirector.makePlan(input: smaller, remixSeed: seed)
        let largerPlan = DeterministicMusicDirector.makePlan(input: larger, remixSeed: seed)
        let remixedPlan = DeterministicMusicDirector.makePlan(input: smaller, remixSeed: seed &+ 1)

        XCTAssertEqual(smallerPlan.happenings, repeatedPlan.happenings)
        XCTAssertEqual(
            smallerPlan.happenings,
            Array(largerPlan.happenings.prefix(smallerPlan.happenings.count))
        )
        XCTAssertNotEqual(
            smallerPlan.happenings.map(\.recipeID),
            remixedPlan.happenings.map(\.recipeID)
        )
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

    private func makeWorldPlan(soundWorld: DayObjectsSoundWorld) -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: DayMusicInput(
                countedSteps: 7_500,
                stepGoal: 10_000,
                countedSleepHours: 6.5,
                sleepGoalHours: 8,
                happeningIDs: (0..<10).map { "event-\($0)" },
                spentColors: 35
            ),
            remixSeed: 0xD4A0_B1EC_75ED_0001,
            soundWorld: soundWorld
        )
    }

    private func tonalInstrumentIDs(in plan: DayMusicPlan) -> [DayObjectsInstrumentID] {
        plan.harmony.roles.compactMap { role in
            guard case let .tonal(id) = role.instrumentTarget else { return nil }
            return id
        }
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

    private func seedProducingBass() -> UInt64 {
        for seed in UInt64(0)..<10_000 where GroovePlanner.makePlan(remixSeed: seed).usesBass {
            return seed
        }
        XCTFail("No Bass Groove seed found")
        return 0
    }

    private func selectedSoundIDs(in plan: DayMusicPlan) -> [String] {
        plan.harmony.roles.map { role in
            switch role.instrumentTarget {
            case let .tonal(instrumentID): return instrumentID.rawValue
            case .feltPiano: return "felt-piano"
            }
        }
            + plan.happenings.map { "happening-recipe-\($0.recipeID.rawValue)" }
            + [plan.lead.instrumentID.rawValue]
    }
}
#endif
