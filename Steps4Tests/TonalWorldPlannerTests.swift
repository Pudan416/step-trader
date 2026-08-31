import XCTest
@testable import Steps4

final class TonalWorldPlannerTests: XCTestCase {
    func testModesPublishTheExactApprovedPitchSets() {
        let expected: [(DayMusicMode, [Int])] = [
            (.dorian, [0, 2, 3, 5, 7, 9, 10]),
            (.aeolian, [0, 2, 3, 5, 7, 8, 10]),
            (.mixolydian, [0, 2, 4, 5, 7, 9, 10]),
            (.majorPentatonic, [0, 2, 4, 7, 9])
        ]

        for (mode, pitchSet) in expected {
            XCTAssertEqual(mode.scaleIntervals, pitchSet, "Unexpected pitch set for \(mode)")
        }
    }

    func testModesPublishTheExactApprovedProgressionTemplates() {
        let expected: [(DayMusicMode, [[Int]])] = [
            (.dorian, [[0], [0, 5], [0, 10, 5], [0, 3, 10, 5]]),
            (.aeolian, [[0], [0, 8], [0, 10, 8], [0, 8, 3, 10]]),
            (.mixolydian, [[0], [0, 10], [0, 7, 10], [0, 10, 5, 0]]),
            (.majorPentatonic, [[0], [0, 5], [0, 9, 5], [0, 9, 5, 7]])
        ]

        for (mode, templates) in expected {
            XCTAssertEqual(mode.progressionDegreeTemplates, templates, "Unexpected templates for \(mode)")
        }
    }

    func testGeneratedCentersAreRestrictedWithoutFixingDorianToD() {
        let allowedCenters = Set([0, 2, 4, 5, 7, 9])
        var dorianCenters = Set<Int>()

        for seed in UInt64(0)..<512 {
            let plan = TonalWorldPlanner.makePlan(input: input(sleepProgress: 1), remixSeed: seed)
            XCTAssertTrue(allowedCenters.contains(plan.centerPitchClass))
            if plan.mode == .dorian {
                dorianCenters.insert(plan.centerPitchClass)
            }
        }

        XCTAssertGreaterThan(dorianCenters.count, 1)
        XCTAssertNotEqual(dorianCenters, [2])
    }

    func testSleepBoundariesSelectTheApprovedMaximumProgressionLength() {
        for seed in UInt64(0)..<32 {
            XCTAssertEqual(plan(sleep: 0, seed: seed).progression.count, 1)
            XCTAssertEqual(plan(sleep: 0.35, seed: seed).progression.count, 1)
            XCTAssertEqual(plan(sleep: 0.350_001, seed: seed).progression.count, 2)
            XCTAssertEqual(plan(sleep: 0.70, seed: seed).progression.count, 2)
            XCTAssertEqual(plan(sleep: 0.700_001, seed: seed).progression.count, 3)
            XCTAssertEqual(plan(sleep: 0.999_999, seed: seed).progression.count, 3)
            XCTAssertTrue([3, 4].contains(plan(sleep: 1, seed: seed).progression.count))
        }
    }

    func testCompletedSleepCanSelectBothThreeAndFourChordTemplates() {
        let lengths = Set((UInt64(0)..<128).map { plan(sleep: 1, seed: $0).progression.count })

        XCTAssertEqual(lengths, [3, 4])
    }

    func testCycleLengthsAreApprovedAndLowSleepFavorsSixteenBars() {
        var lowSleepCounts: [Int: Int] = [:]

        for seed in UInt64(0)..<256 {
            let cycleBars = plan(sleep: 0.2, seed: seed).cycleBars
            XCTAssertTrue([8, 12, 16].contains(cycleBars))
            lowSleepCounts[cycleBars, default: 0] += 1
        }

        XCTAssertGreaterThan(lowSleepCounts[16, default: 0], lowSleepCounts[12, default: 0])
        XCTAssertGreaterThan(lowSleepCounts[16, default: 0], lowSleepCounts[8, default: 0])
    }

    func testChordPlansPublishChordTonesSafeModeTonesVoicingsAndCompleteCycleDurations() {
        let plan = TonalWorldPlanner.makePlan(
            centerPitchClass: 0,
            mode: .dorian,
            progressionLength: 4,
            cycleBars: 12
        )

        XCTAssertEqual(plan.scalePitchClasses, [0, 2, 3, 5, 7, 9, 10])
        XCTAssertEqual(plan.progression.map(\.modalDegree), [0, 3, 10, 5])
        XCTAssertEqual(plan.progression.map(\.rootPitchClass), [0, 3, 10, 5])
        XCTAssertEqual(
            plan.progression.map(\.chordPitchClasses),
            [[0, 3, 7], [3, 7, 10], [10, 2, 5], [5, 9, 0]]
        )
        XCTAssertTrue(plan.progression.allSatisfy { $0.safePassingPitchClasses == plan.scalePitchClasses })
        XCTAssertTrue(plan.progression.allSatisfy { !$0.voicedMIDINotes.isEmpty })
        XCTAssertEqual(plan.progression.map(\.durationBars).reduce(0, +), 12)
    }

    func testSameInputAndSeedProduceAnEqualWorld() {
        let input = input(sleepProgress: 0.82)

        XCTAssertEqual(
            TonalWorldPlanner.makePlan(input: input, remixSeed: 0xD4A0_B1EC_75ED_0001),
            TonalWorldPlanner.makePlan(input: input, remixSeed: 0xD4A0_B1EC_75ED_0001)
        )
    }

    private func plan(sleep: Double, seed: UInt64) -> TonalWorldPlan {
        TonalWorldPlanner.makePlan(input: input(sleepProgress: sleep), remixSeed: seed)
    }

    private func input(sleepProgress: Double) -> NormalizedDayMusicInput {
        NormalizedDayMusicInput(
            stepsProgress: 0.5,
            sleepProgress: sleepProgress,
            happeningIDs: [],
            glitchProgress: 0,
            motionEnergy: 0.625,
            visualClarity: 0.35 + (0.55 * sleepProgress),
            diagnostics: []
        )
    }
}
