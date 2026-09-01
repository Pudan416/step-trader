import XCTest
@testable import Steps4

final class GlitchPlannerTests: XCTestCase {
    func testEveryEffectUsesTheExactQuadraticSpentColorsCurveWithoutASecondThreshold() throws {
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
            let plan = GlitchPlanner.makePlan(input: input, remixSeed: 0xA11CE)

            XCTAssertEqual(plan.progress, fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.pad, in: plan).pitchDriftCents, 14 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.happening, in: plan).pitchDriftCents, 10 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.lead, in: plan).pitchDriftCents, 8 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.percussion, in: plan).pitchDriftCents, 3 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.wowFlutterDepth, 0.18 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(plan.stereoSeparationAddition, 0.22 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.pad, in: plan).dropoutProbability, 0, accuracy: 1e-12)
            XCTAssertEqual(try role(.pad, in: plan).delayTimeInstability, 0.08 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.happening, in: plan).dropoutProbability, 0.06 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.happening, in: plan).delayTimeInstability, 0.04 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.lead, in: plan).dropoutProbability, 0, accuracy: 1e-12)
            XCTAssertEqual(try role(.lead, in: plan).delayTimeInstability, 0, accuracy: 1e-12)
            XCTAssertEqual(try role(.lead, in: plan).saturationAmount, 0.18 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.percussion, in: plan).dropoutProbability, 0, accuracy: 1e-12)
            XCTAssertEqual(try role(.percussion, in: plan).delayTimeInstability, 0, accuracy: 1e-12)
            XCTAssertEqual(try role(.percussion, in: plan).timingDriftMilliseconds, 0.32 * fixture.progress, accuracy: 1e-12)
            XCTAssertEqual(try role(.timingAnchorKick, in: plan), .stableKick)
        }

        XCTAssertGreaterThan(try role(.pad, in: makePlan(progress: 0.0001)).pitchDriftCents, 0)
        XCTAssertGreaterThan(try role(.happening, in: makePlan(progress: 0.0025)).dropoutProbability, 0)
        XCTAssertGreaterThan(try role(.lead, in: makePlan(progress: 0.0025)).saturationAmount, 0)
        XCTAssertGreaterThan(try role(.percussion, in: makePlan(progress: 0.0025)).timingDriftMilliseconds, 0)
    }

    func testRolePlansAreTheSingleNumericAuthorityAndKeepKickExactlyStable() throws {
        let plan = makePlan(progress: 1)
        let expected: [(GlitchRole, Double, Double, Double, Double, Double, Bool, Bool)] = [
            (.pad, 14, 0, 0.08, 0, 0, false, true),
            (.happening, 10, 0.06, 0.04, 0, 0, false, true),
            (.lead, 8, 0, 0, 0.18, 0, false, true),
            (.percussion, 3, 0, 0, 0, 0.32, false, true),
            (.timingAnchorKick, 0, 0, 0, 0, 0, true, false)
        ]

        XCTAssertEqual(plan.roles.map(\.role), GlitchRole.allCases)
        for (glitchRole, pitchDrift, dropout, delay, saturation, timing, isTimingAnchor, isGlitchEligible) in expected {
            let rolePlan = try role(glitchRole, in: plan)
            XCTAssertEqual(rolePlan.pitchDriftCents, pitchDrift)
            XCTAssertEqual(rolePlan.dropoutProbability, dropout)
            XCTAssertEqual(rolePlan.delayTimeInstability, delay)
            XCTAssertEqual(rolePlan.saturationAmount, saturation)
            XCTAssertEqual(rolePlan.timingDriftMilliseconds, timing)
            XCTAssertEqual(rolePlan.isTimingAnchor, isTimingAnchor)
            XCTAssertEqual(rolePlan.isGlitchEligible, isGlitchEligible)
            XCTAssertEqual(rolePlan, glitchRole.safeLimits.scaled(by: 1))
        }
    }

    func testFixedGlitchRealizationVectorPinsSeedsAndAudibleDecisions() throws {
        let plan = makePlan(progress: 1, remixSeed: 1)

        XCTAssertEqual(plan.realization.dropoutSeed, 9_876_473_895_713_353_902)
        XCTAssertEqual(plan.realization.variationSeed, 4_962_057_094_216_630_878)
        XCTAssertEqual(plan.realization.cycleKey, 17_100_666_527_999_801_207)
        XCTAssertEqual(plan.realization.counterMapping, .roleCycleStepParameterV1)

        let coordinates: [(GlitchRole, Int, Int)] = [
            (.pad, 0, 0),
            (.happening, 0, 0),
            (.lead, 0, 0),
            (.percussion, 0, 0),
            (.timingAnchorKick, 0, 0),
            (.pad, 0, 8),
        ]
        let vector = try coordinates.map { glitchRole, cycleIndex, stepIndex in
            compactVector(
                try XCTUnwrap(
                    plan.realizedEvent(
                        for: glitchRole,
                        cycleIndex: cycleIndex,
                        stepIndex: stepIndex
                    )
                )
            )
        }

        XCTAssertEqual(vector, [
            "pad:0:0:0:3351:-32813:0",
            "happening:0:0:0:3681:-20967:0",
            "lead:0:0:0:7133:0:0",
            "percussion:0:0:0:1681:0:-218",
            "timingAnchorKick:0:0:0:0:0:0",
            "pad:0:8:0:8411:-1729:0",
        ])
    }

    func testRealizationIsCounterBasedCallOrderIndependentAndBounded() throws {
        let plan = makePlan(progress: 1, remixSeed: 1)
        let coordinates = GlitchRole.allCases.flatMap { glitchRole in
            (0..<8).flatMap { cycleIndex in
                (0..<16).map { (glitchRole, cycleIndex, $0) }
            }
        }

        let forward = try coordinates.map {
            try XCTUnwrap(plan.realizedEvent(for: $0.0, cycleIndex: $0.1, stepIndex: $0.2))
        }
        let reversed = try coordinates.reversed().map {
            try XCTUnwrap(plan.realizedEvent(for: $0.0, cycleIndex: $0.1, stepIndex: $0.2))
        }.reversed()

        XCTAssertEqual(forward, Array(reversed))
        XCTAssertTrue(forward.contains(where: \.shouldDropOut))
        for event in forward {
            let rolePlan = try role(event.role, in: plan)
            XCTAssertLessThanOrEqual(abs(event.pitchDriftCents), rolePlan.pitchDriftCents + 1e-12)
            XCTAssertLessThanOrEqual(abs(event.delayTimeVariation), rolePlan.delayTimeInstability + 1e-12)
            XCTAssertLessThanOrEqual(abs(event.timingDriftMilliseconds), rolePlan.timingDriftMilliseconds + 1e-12)
            if event.role == .timingAnchorKick {
                XCTAssertFalse(event.shouldDropOut)
                XCTAssertEqual(event.pitchDriftCents, 0)
                XCTAssertEqual(event.delayTimeVariation, 0)
                XCTAssertEqual(event.timingDriftMilliseconds, 0)
            }
        }

        XCTAssertNil(plan.realizedEvent(for: .pad, cycleIndex: -1, stepIndex: 0))
        XCTAssertNil(plan.realizedEvent(for: .pad, cycleIndex: 0, stepIndex: -1))
        XCTAssertNil(plan.realizedEvent(for: .pad, cycleIndex: 0, stepIndex: 16))
    }

    func testRemixChangesOnlyRealizationStateWhenDayInputIsUnchanged() {
        let first = makePlan(progress: 0.25, remixSeed: 1)
        let remixed = makePlan(progress: 0.25, remixSeed: 2)

        XCTAssertEqual(first.progress, remixed.progress)
        XCTAssertEqual(first.roles, remixed.roles)
        XCTAssertEqual(first.wowFlutterDepth, remixed.wowFlutterDepth)
        XCTAssertEqual(first.stereoSeparationAddition, remixed.stereoSeparationAddition)
        XCTAssertNotEqual(first.realization, remixed.realization)
        XCTAssertNotEqual(
            first.realizedEvent(for: .pad, cycleIndex: 0, stepIndex: 0),
            remixed.realizedEvent(for: .pad, cycleIndex: 0, stepIndex: 0)
        )
    }

    func testZeroIsExactlyNeutralSoPlaybackCanBypassEveryGlitchNode() throws {
        let plan = makePlan(progress: 0)

        XCTAssertTrue(plan.isNeutral)
        XCTAssertEqual(plan.progress, 0)
        XCTAssertEqual(plan.wowFlutterDepth, 0)
        XCTAssertEqual(plan.stereoSeparationAddition, 0)
        for rolePlan in plan.roles {
            XCTAssertEqual(rolePlan.pitchDriftCents, 0)
            XCTAssertEqual(rolePlan.dropoutProbability, 0)
            XCTAssertEqual(rolePlan.delayTimeInstability, 0)
            XCTAssertEqual(rolePlan.saturationAmount, 0)
            XCTAssertEqual(rolePlan.timingDriftMilliseconds, 0)
        }
        for glitchRole in GlitchRole.allCases {
            let event = try XCTUnwrap(
                plan.realizedEvent(for: glitchRole, cycleIndex: 0, stepIndex: 0)
            )
            XCTAssertFalse(event.shouldDropOut)
            XCTAssertEqual(event.pitchDriftCents, 0)
            XCTAssertEqual(event.delayTimeVariation, 0)
            XCTAssertEqual(event.timingDriftMilliseconds, 0)
        }
    }

    func testPlannerDefensivelyClampsInvalidOrNonFiniteProgress() {
        XCTAssertEqual(makePlan(progress: -1), makePlan(progress: .nan))
        XCTAssertEqual(makePlan(progress: .infinity), makePlan(progress: .nan))
        XCTAssertEqual(makePlan(progress: 2), makePlan(progress: 1))
        XCTAssertTrue(makePlan(progress: -1).isNeutral)
    }

    private func makePlan(
        progress: Double,
        remixSeed: UInt64 = 0xD4A0_B1EC_75ED_0001
    ) -> GlitchPlan {
        GlitchPlanner.makePlan(
            input: NormalizedDayMusicInput(
                stepsProgress: 0,
                sleepProgress: 0,
                happeningIDs: [],
                glitchProgress: progress,
                motionEnergy: 0.25,
                visualClarity: 0.35,
                diagnostics: []
            ),
            remixSeed: remixSeed
        )
    }

    private func role(_ role: GlitchRole, in plan: GlitchPlan) throws -> GlitchRolePlan {
        try XCTUnwrap(plan.role(for: role))
    }

    private func compactVector(_ event: GlitchRealizedEvent) -> String {
        let dropout = event.shouldDropOut ? 1 : 0
        let pitchMilliCents = Int((event.pitchDriftCents * 1_000).rounded())
        let delayMillionths = Int((event.delayTimeVariation * 1_000_000).rounded())
        let timingMicroseconds = Int((event.timingDriftMilliseconds * 1_000).rounded())
        return "\(roleName(event.role)):\(event.cycleIndex):\(event.stepIndex):\(dropout):\(pitchMilliCents):\(delayMillionths):\(timingMicroseconds)"
    }

    private func roleName(_ role: GlitchRole) -> String {
        switch role {
        case .pad: return "pad"
        case .happening: return "happening"
        case .lead: return "lead"
        case .percussion: return "percussion"
        case .timingAnchorKick: return "timingAnchorKick"
        }
    }
}
