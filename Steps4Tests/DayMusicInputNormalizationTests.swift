import XCTest
@testable import Steps4

final class DayMusicInputNormalizationTests: XCTestCase {
    func testProgressAndDerivedVisualsUseGoalRelativeBoundaries() {
        XCTAssertEqual(normalized(steps: 0, sleep: 0).stepsProgress, 0)
        XCTAssertEqual(normalized(steps: 0, sleep: 0).sleepProgress, 0)
        XCTAssertEqual(normalized(steps: 2_500, sleep: 2).stepsProgress, 0.5)
        XCTAssertEqual(normalized(steps: 2_500, sleep: 2).sleepProgress, 0.5)
        XCTAssertEqual(normalized(steps: 5_000, sleep: 4).stepsProgress, 1)
        XCTAssertEqual(normalized(steps: 5_000, sleep: 4).sleepProgress, 1)
        XCTAssertEqual(normalized(steps: 10_000, sleep: 8).stepsProgress, 1)
        XCTAssertEqual(normalized(steps: 10_000, sleep: 8).sleepProgress, 1)

        let fiveThousandGoal = DayMusicInput(
            countedSteps: 5_000,
            stepGoal: 5_000,
            countedSleepHours: 4,
            sleepGoalHours: 4,
            happeningIDs: [],
            spentColors: 0
        ).normalized()
        let tenThousandGoal = DayMusicInput(
            countedSteps: 10_000,
            stepGoal: 10_000,
            countedSleepHours: 8,
            sleepGoalHours: 8,
            happeningIDs: [],
            spentColors: 0
        ).normalized()
        XCTAssertEqual(fiveThousandGoal, tenThousandGoal)

        let half = normalized(steps: 2_500, sleep: 2)
        XCTAssertEqual(half.motionEnergy, 0.625)
        XCTAssertEqual(half.visualClarity, 0.625)
    }

    func testInvalidCountsAndGoalsBecomeZeroInFieldOrder() {
        let normalized = DayMusicInput(
            countedSteps: -.infinity,
            stepGoal: .nan,
            countedSleepHours: -1,
            sleepGoalHours: 0,
            happeningIDs: [],
            spentColors: 0
        ).normalized()

        XCTAssertEqual(normalized.stepsProgress, 0)
        XCTAssertEqual(normalized.sleepProgress, 0)
        XCTAssertEqual(
            normalized.diagnostics,
            [.invalidCountedSteps, .invalidStepGoal, .invalidCountedSleepHours, .invalidSleepGoal]
        )

        XCTAssertEqual(
            DayMusicInput(
                countedSteps: .nan,
                stepGoal: .infinity,
                countedSleepHours: .infinity,
                sleepGoalHours: -.infinity,
                happeningIDs: [],
                spentColors: 0
            ).normalized().diagnostics,
            [.invalidCountedSteps, .invalidStepGoal, .invalidCountedSleepHours, .invalidSleepGoal]
        )
    }

    func testSpentColorsClampBeforeQuadraticGlitchMapping() {
        XCTAssertEqual(normalized(spentColors: -10).glitchProgress, 0)
        XCTAssertEqual(normalized(spentColors: 50).glitchProgress, 0.25)
        XCTAssertEqual(normalized(spentColors: 100).glitchProgress, 1)
        XCTAssertEqual(normalized(spentColors: 1_000).glitchProgress, 1)
    }

    func testHappeningIDsDeduplicateDiscardEmptyValuesAndTruncateAfterTen() {
        let normalized = DayMusicInput(
            countedSteps: 0,
            stepGoal: 1,
            countedSleepHours: 0,
            sleepGoalHours: 1,
            happeningIDs: ["first", "", "second", "first"] + (3...12).map(String.init),
            spentColors: 0
        ).normalized()

        XCTAssertEqual(
            normalized.happeningIDs,
            ["first", "second", "3", "4", "5", "6", "7", "8", "9", "10"]
        )
        XCTAssertEqual(
            normalized.diagnostics,
            [.emptyHappeningID, .happeningIDLimitReached, .happeningIDLimitReached]
        )
    }

    func testNormalizationIsFullyDeterministic() {
        let input = DayMusicInput(
            countedSteps: -5,
            stepGoal: 0,
            countedSleepHours: .infinity,
            sleepGoalHours: .nan,
            happeningIDs: ["", "alpha", "alpha"] + (0...10).map { "event-\($0)" },
            spentColors: 101
        )

        XCTAssertEqual(input.normalized(), input.normalized())
    }

    private func normalized(
        steps: Double = 0,
        sleep: Double = 0,
        spentColors: Int = 0
    ) -> NormalizedDayMusicInput {
        DayMusicInput(
            countedSteps: steps,
            stepGoal: 5_000,
            countedSleepHours: sleep,
            sleepGoalHours: 4,
            happeningIDs: [],
            spentColors: spentColors
        ).normalized()
    }
}
