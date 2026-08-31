#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayMusicPlanDifferTests: XCTestCase {
    private let seed: UInt64 = 0xD4A0_B1EC_75ED_0001

    func testIdenticalPlansProduceNoPlaybackCommands() {
        let plan = makePlan()

        let change = DayMusicPlanDiffer.change(from: plan, to: plan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testStepsChangeIsContinuousWithoutReplacingRhythmStructure() {
        let oldPlan = makePlan(stepsProgress: 0.15)
        let newPlan = makePlan(stepsProgress: 0.85)
        XCTAssertEqual(oldPlan.rhythm.family, newPlan.rhythm.family)
        XCTAssertEqual(oldPlan.rhythm.patternOffsetSteps, newPlan.rhythm.patternOffsetSteps)
        XCTAssertEqual(oldPlan.rhythm.realization, newPlan.rhythm.realization)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testSpentColorsChangeIsContinuousGlitchOnly() {
        let oldPlan = makePlan(spentColors: 0)
        let newPlan = makePlan(spentColors: 50)
        XCTAssertNotEqual(oldPlan.glitch, newPlan.glitch)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testSleepGainChangeWithinOneProgressionBandIsContinuousOnly() {
        let oldPlan = makePlan(sleepProgress: 0.50)
        let newPlan = makePlan(sleepProgress: 0.60)
        XCTAssertEqual(oldPlan.world, newPlan.world)
        XCTAssertNotEqual(oldPlan.harmony, newPlan.harmony)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
    }

    func testSleepThresholdCrossingEmitsContinuousAndStructuralNewestPlan() {
        let oldPlan = makePlan(sleepProgress: 0.35)
        let newPlan = makePlan(sleepProgress: 0.36)
        XCTAssertNotEqual(oldPlan.world.progression, newPlan.world.progression)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testRemixEmitsStructuralPlanAndKeepsExistingHappeningChangesOutOfAddRemove() {
        let oldPlan = makePlan(remixSeed: 0x1)
        let newPlan = makePlan(remixSeed: 0x2)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testExistingHappeningIdentityChangeIsStructuralWithoutLookingLikeAnAddition() {
        let oldPlan = makePlan(remixSeed: 0x1)
        let alternatePlan = makePlan(remixSeed: 0x2)
        let newPlan = DayMusicPlan(
            seed: oldPlan.seed,
            input: oldPlan.input,
            world: oldPlan.world,
            rhythm: oldPlan.rhythm,
            harmony: oldPlan.harmony,
            happenings: alternatePlan.happenings,
            lead: oldPlan.lead,
            glitch: oldPlan.glitch,
            mix: oldPlan.mix
        )

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testAddingHappeningsUsesOnlyDedicatedCommandsInNewPlanOrder() {
        let oldPlan = makePlan(happeningIDs: ["one", "two"])
        let newPlan = makePlan(happeningIDs: ["one", "two", "three", "four"])

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, Array(newPlan.happenings.suffix(2)))
        XCTAssertEqual(change.addedHappenings.map(\.happeningID), ["three", "four"])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testRemovingHappeningsUsesOnlyDedicatedCommandsInOldPlanOrder() {
        let oldPlan = makePlan(happeningIDs: ["one", "two", "three", "four"])
        let newPlan = makePlan(happeningIDs: ["one", "two"])

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, ["three", "four"])
    }

    func testDuplicateHappeningRecordsEmitOneStableDedicatedCommand() throws {
        let oldPlan = makePlan(happeningIDs: [])
        let oneHappeningPlan = makePlan(happeningIDs: ["one"])
        let happening = try XCTUnwrap(oneHappeningPlan.happenings.first)
        let duplicatePlan = DayMusicPlan(
            seed: oneHappeningPlan.seed,
            input: oneHappeningPlan.input,
            world: oneHappeningPlan.world,
            rhythm: oneHappeningPlan.rhythm,
            harmony: oneHappeningPlan.harmony,
            happenings: [happening, happening],
            lead: oneHappeningPlan.lead,
            glitch: oneHappeningPlan.glitch,
            mix: oneHappeningPlan.mix
        )

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: duplicatePlan)

        XCTAssertEqual(change.addedHappenings.map(\.happeningID), ["one"])
    }

    func testStepChangeAndRemixEmitBothNewestPlanExactlyOnce() {
        let oldPlan = makePlan(stepsProgress: 0.15, remixSeed: 0x1)
        let newPlan = makePlan(stepsProgress: 0.85, remixSeed: 0x2)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    private func makePlan(
        stepsProgress: Double = 0.60,
        sleepProgress: Double = 0.70,
        happeningIDs: [String] = ["one", "two"],
        spentColors: Int = 0,
        remixSeed: UInt64? = nil
    ) -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: DayMusicInput(
                countedSteps: stepsProgress * 10_000,
                stepGoal: 10_000,
                countedSleepHours: sleepProgress * 8,
                sleepGoalHours: 8,
                happeningIDs: happeningIDs,
                spentColors: spentColors
            ),
            remixSeed: remixSeed ?? seed
        )
    }
}
#endif
