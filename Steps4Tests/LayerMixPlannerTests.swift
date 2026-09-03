import XCTest
@testable import Steps4

final class LayerMixPlannerTests: XCTestCase {
    func testPlanUsesAudibleMobileRoleTargetsBeforeTheLimiter() {
        let plan = LayerMixPlanner.makePlan(happeningCount: 1)

        XCTAssertEqual(plan.rhythmTargetDecibels, -6)
        XCTAssertEqual(plan.harmonyTargetDecibels, -9)
        XCTAssertEqual(plan.happeningAggregateTargetDecibels, -2)
        XCTAssertEqual(plan.happeningPerVoiceTargetDecibels, -2)
        XCTAssertEqual(plan.leadTargetDecibels, -12)
        XCTAssertEqual(plan.masterTargetDecibelsBeforeLimiter, -2)
        XCTAssertEqual(plan.maximumHarmonyDuckingDecibels, 2.5)
    }

    func testSparseHappeningScheduleDoesNotReduceEachSoundAsCountIncreases() {
        for count in [0, 1, 2, 5, 10] {
            let plan = LayerMixPlanner.makePlan(happeningCount: count)
            XCTAssertEqual(plan.happeningCount, count)
            XCTAssertEqual(plan.happeningAggregateTargetDecibels, -2)
            XCTAssertEqual(plan.happeningPerVoiceTargetDecibels, -2)
        }

        XCTAssertEqual(
            LayerMixPlanner.makePlan(happeningCount: -1),
            LayerMixPlanner.makePlan(happeningCount: 0)
        )
        XCTAssertEqual(
            LayerMixPlanner.makePlan(happeningCount: Int.max),
            LayerMixPlanner.makePlan(happeningCount: 10)
        )
    }

    func testAllPublishedValuesRemainFiniteAndBoundedAcrossThePublicCountDomain() {
        for count in [Int.min, -1, 0, 1, 5, 10, 11, Int.max] {
            let plan = LayerMixPlanner.makePlan(happeningCount: count)
            let values = [
                plan.rhythmTargetDecibels,
                plan.harmonyTargetDecibels,
                plan.happeningAggregateTargetDecibels,
                plan.happeningPerVoiceTargetDecibels,
                plan.leadTargetDecibels,
                plan.masterTargetDecibelsBeforeLimiter,
                plan.maximumHarmonyDuckingDecibels
            ]
            XCTAssertTrue(values.allSatisfy(\.isFinite))
            XCTAssertTrue((0...10).contains(plan.happeningCount))
            XCTAssertTrue((-60...0).contains(plan.happeningPerVoiceTargetDecibels))
        }
    }

    func testHarmonyDuckingIsFiniteAndNeverExceedsTwoPointFiveDecibels() {
        let plan = LayerMixPlanner.makePlan(happeningCount: 10)

        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: -1), -9)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 0), -9)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 1.25), -10.25)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 2.5), -11.5)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 99), -11.5)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: .nan), -9)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: .infinity), -9)
    }
}
