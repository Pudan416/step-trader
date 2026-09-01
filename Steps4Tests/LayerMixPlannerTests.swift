import XCTest
@testable import Steps4

final class LayerMixPlannerTests: XCTestCase {
    func testPlanUsesAudibleMobileRoleTargetsBeforeTheLimiter() {
        let plan = LayerMixPlanner.makePlan(happeningCount: 1)

        XCTAssertEqual(plan.rhythmTargetDecibels, -6)
        XCTAssertEqual(plan.harmonyTargetDecibels, -9)
        XCTAssertEqual(plan.happeningAggregateTargetDecibels, -10)
        XCTAssertEqual(plan.happeningPerVoiceTargetDecibels, -10)
        XCTAssertEqual(plan.leadTargetDecibels, -8)
        XCTAssertEqual(plan.masterTargetDecibelsBeforeLimiter, -2)
        XCTAssertEqual(plan.maximumHarmonyDuckingDecibels, 2.5)
    }

    func testHappeningCompensationKeepsTheAggregateTargetInsteadOfSummingFullLevelVoices() {
        let fixtures: [(count: Int, perVoiceDB: Double)] = [
            (0, -10),
            (1, -10),
            (2, -13.010_299_956_639_813),
            (5, -16.989_700_043_360_187),
            (10, -20)
        ]

        for fixture in fixtures {
            let plan = LayerMixPlanner.makePlan(happeningCount: fixture.count)
            XCTAssertEqual(plan.happeningCount, fixture.count)
            XCTAssertEqual(plan.happeningAggregateTargetDecibels, -10)
            XCTAssertEqual(plan.happeningPerVoiceTargetDecibels, fixture.perVoiceDB, accuracy: 1e-12)
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
