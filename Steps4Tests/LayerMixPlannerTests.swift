import XCTest
@testable import Steps4

final class LayerMixPlannerTests: XCTestCase {
    func testPlanUsesConservativeFiveRoleTargetsWithSixDecibelsOfMasterHeadroom() {
        let plan = LayerMixPlanner.makePlan(happeningCount: 1)

        XCTAssertEqual(plan.rhythmTargetDecibels, -10)
        XCTAssertEqual(plan.bassTargetDecibels, -12)
        XCTAssertEqual(plan.harmonyTargetDecibels, -10)
        XCTAssertEqual(plan.happeningAggregateTargetDecibels, -8)
        XCTAssertEqual(plan.happeningPerVoiceTargetDecibels, -8)
        XCTAssertEqual(plan.leadTargetDecibels, -9)
        XCTAssertEqual(plan.masterTargetDecibelsBeforeLimiter, -6)
        XCTAssertEqual(plan.maximumHarmonyDuckingDecibels, 2.5)
    }

    func testHappeningPerVoiceTargetDropsThreeDBPerDoublingUpToPoolLimit() {
        XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 1).happeningPerVoiceTargetDecibels, -8, accuracy: 0.01)
        XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 2).happeningPerVoiceTargetDecibels, -11, accuracy: 0.01)
        XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 4).happeningPerVoiceTargetDecibels, -14, accuracy: 0.01)
        XCTAssertEqual(LayerMixPlanner.makePlan(happeningCount: 10).happeningPerVoiceTargetDecibels, -14, accuracy: 0.01)

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
                plan.bassTargetDecibels,
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

        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: -1), -10)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 0), -10)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 1.25), -11.25)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 2.5), -12.5)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: 99), -12.5)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: .nan), -10)
        XCTAssertEqual(plan.harmonyTargetDecibels(applyingDucking: .infinity), -10)
    }
}
