#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsLabMusicViewModelTests: XCTestCase {
    func testFreshStateUsesApprovedDayDefaults() {
        let state = DayObjectsLabMusicState()

        XCTAssertEqual(state.steps, 10_000)
        XCTAssertEqual(state.stepGoal, 10_000)
        XCTAssertEqual(state.sleepHours, 8)
        XCTAssertEqual(state.sleepGoalHours, 8)
        XCTAssertEqual(state.happeningCount, 8)
        XCTAssertEqual(state.spentColors, 0)
        XCTAssertEqual(state.remixSeed, 0xD4A0_B1EC_75ED_0001)
        XCTAssertEqual(state.soundWorld, .feltAndWood)
    }

    func testUIEditsClampToApprovedLabRanges() {
        let model = DayObjectsLabMusicViewModel()

        model.setSteps(-1)
        XCTAssertEqual(model.state.steps, 0)
        model.setSteps(10_001)
        XCTAssertEqual(model.state.steps, 10_000)

        model.setSleepHours(-1)
        XCTAssertEqual(model.state.sleepHours, 0)
        model.setSleepHours(9)
        XCTAssertEqual(model.state.sleepHours, 8)

        model.setHappeningCount(-1)
        XCTAssertEqual(model.state.happeningCount, 0)
        model.setHappeningCount(11)
        XCTAssertEqual(model.state.happeningCount, 10)

        model.setSpentColors(-1)
        XCTAssertEqual(model.state.spentColors, 0)
        model.setSpentColors(101)
        XCTAssertEqual(model.state.spentColors, 100)
    }

    func testHappeningCountUsesStableOneBasedIdentifiers() {
        let model = DayObjectsLabMusicViewModel()

        model.setHappeningCount(3)
        let three = model.happeningIDs
        XCTAssertEqual(three, [
            "lab-happening-01",
            "lab-happening-02",
            "lab-happening-03",
        ])

        model.setHappeningCount(5)
        XCTAssertEqual(Array(model.happeningIDs.prefix(3)), three)
        XCTAssertEqual(model.happeningIDs.suffix(2), [
            "lab-happening-04",
            "lab-happening-05",
        ])

        model.setHappeningCount(2)
        XCTAssertEqual(model.happeningIDs, Array(three.prefix(2)))
    }

    func testZeroHappeningsProducesNoIdentifiers() {
        let model = DayObjectsLabMusicViewModel()

        model.setHappeningCount(0)

        XCTAssertEqual(model.happeningIDs, [])
        XCTAssertEqual(model.dayMusicInput.happeningIDs, [])
    }

    func testDayMusicInputReceivesTheStableDayValuesAndHappeningIDs() {
        let model = DayObjectsLabMusicViewModel()
        model.setSteps(4_321)
        model.setSleepHours(6.5)
        model.setHappeningCount(2)
        model.setSpentColors(37)

        XCTAssertEqual(model.dayMusicInput, DayMusicInput(
            countedSteps: 4_321,
            stepGoal: 10_000,
            countedSleepHours: 6.5,
            sleepGoalHours: 8,
            happeningIDs: ["lab-happening-01", "lab-happening-02"],
            spentColors: 37
        ))
    }

    func testSpentColorsRemainTheDigitalDamageInput() {
        let model = DayObjectsLabMusicViewModel()

        model.setSpentColors(50)

        XCTAssertEqual(model.digitalImpact.spentColors, 50)
        XCTAssertEqual(model.digitalImpact.damage, 0.5, accuracy: 0.000_001)
    }

    func testRemixAdvancesTheSeedWithoutChangingDayInputs() {
        let model = DayObjectsLabMusicViewModel()
        let originalState = model.state

        model.remix()

        XCTAssertEqual(model.state.remixSeed, originalState.remixSeed &+ 1)
        XCTAssertEqual(model.state.steps, originalState.steps)
        XCTAssertEqual(model.state.sleepHours, originalState.sleepHours)
        XCTAssertEqual(model.state.happeningCount, originalState.happeningCount)
        XCTAssertEqual(model.state.spentColors, originalState.spentColors)
        XCTAssertFalse(model.worldSummary.isEmpty)
    }

    func testSoundWorldSelectionAndUndoRestoreThePreviousMusicalVariant() {
        let model = DayObjectsLabMusicViewModel()
        let original = model.state

        model.selectSoundWorld(.metalAndCurrent)
        model.remix()

        XCTAssertEqual(model.musicPlan.soundWorld, .metalAndCurrent)
        XCTAssertTrue(model.canUndoMusicRemix)

        model.undoMusicRemix()
        XCTAssertEqual(model.state.soundWorld, .metalAndCurrent)
        XCTAssertEqual(model.state.remixSeed, original.remixSeed)

        model.undoMusicRemix()
        XCTAssertEqual(model.state.soundWorld, original.soundWorld)
        XCTAssertEqual(model.state.remixSeed, original.remixSeed)
        XCTAssertFalse(model.canUndoMusicRemix)
        XCTAssertEqual(model.state.steps, original.steps)
        XCTAssertEqual(model.state.sleepHours, original.sleepHours)
        XCTAssertEqual(model.state.happeningCount, original.happeningCount)
        XCTAssertEqual(model.state.spentColors, original.spentColors)
    }
}
#endif
