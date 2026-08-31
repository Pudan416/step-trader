import XCTest
@testable import Steps4

final class GlitchPlannerTests: XCTestCase {
    func testEveryEffectUsesTheExactQuadraticSpentColorsCurveWithoutASecondThreshold() {
        let fixtures: [(spentColors: Int, progress: Double)] = [
            (0, 0),
            (1, 0.0001),
            (5, 0.0025),
            (10, 0.01),
            (25, 0.0625),
            (50, 0.25),
            (100, 1)
        ]

        for fixture in fixtures {
            let input = DayMusicInput(
                countedSteps: 0,
                stepGoal: 10_000,
                countedSleepHours: 0,
                sleepGoalHours: 8,
                happeningIDs: [],
                spentColors: fixture.spentColors
            ).normalized()
            let plan = GlitchPlanner.makePlan(input: input)

            XCTAssertEqual(plan.progress, fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.padPitchDriftCents, 14 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.happeningPitchDriftCents, 10 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.leadPitchDriftCents, 8 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.wowFlutterDepth, 0.18 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.delayTimeInstability, 0.08 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.stereoSeparationAddition, 0.22 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.softDropoutProbability, 0.06 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.percussionPitchDriftCents, 3 * fixture.progress, accuracy: 1e-12)
            XCTAssertTrue(plan.timingAnchorKick.isTimingAnchor)
            XCTAssertEqual(plan.timingAnchorKick.pitchDriftCents, 0)
            XCTAssertEqual(plan.timingAnchorKick.dropoutProbability, 0)
            XCTAssertEqual(plan.timingAnchorKick.delayTimeInstability, 0)
        }

        XCTAssertGreaterThan(makePlan(progress: 0.0001).padPitchDriftCents, 0)
        XCTAssertGreaterThan(makePlan(progress: 0.0025).softDropoutProbability, 0)
    }

    func testZeroIsExactlyNeutralSoPlaybackCanBypassEveryGlitchNode() {
        let plan = makePlan(progress: 0)

        XCTAssertTrue(plan.isNeutral)
        XCTAssertEqual(plan, .neutral)
    }

    func testPlannerDefensivelyClampsInvalidOrNonFiniteProgress() {
        XCTAssertEqual(makePlan(progress: -1), .neutral)
        XCTAssertEqual(makePlan(progress: .nan), .neutral)
        XCTAssertEqual(makePlan(progress: .infinity), .neutral)
        XCTAssertEqual(makePlan(progress: 2), makePlan(progress: 1))
    }

    private func makePlan(progress: Double) -> GlitchPlan {
        GlitchPlanner.makePlan(
            input: NormalizedDayMusicInput(
                stepsProgress: 0,
                sleepProgress: 0,
                happeningIDs: [],
                glitchProgress: progress,
                motionEnergy: 0.25,
                visualClarity: 0.35,
                diagnostics: []
            )
        )
    }
}
