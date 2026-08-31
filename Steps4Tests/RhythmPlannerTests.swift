import XCTest
@testable import Steps4

final class RhythmPlannerTests: XCTestCase {
    func testSeededBaseTempoStaysAmbientAndFinalTempoUsesExactCappedFormula() {
        let seeds: [UInt64] = [0, 1, 0xD4A0_B1EC_75ED_0001, .max]
        let progressValues = [0.0, 0.15, 0.35, 0.6, 0.85, 1.0]

        for seed in seeds {
            for progress in progressValues {
                let plan = makePlan(stepsProgress: progress, remixSeed: seed)
                XCTAssertTrue((58...82).contains(plan.baseTempoBPM))
                XCTAssertEqual(
                    plan.tempoBPM,
                    min(102, plan.baseTempoBPM + (20 * progress)),
                    accuracy: 1e-12
                )
            }
        }
    }

    func testProgressIsDefensivelyCappedBeforeTempoAndActivationPlanning() {
        let below = makePlan(stepsProgress: -1, remixSeed: 42)
        let above = makePlan(stepsProgress: 2, remixSeed: 42)
        let nonFinite = makePlan(stepsProgress: .infinity, glitchProgress: .nan, remixSeed: 42)

        XCTAssertEqual(below.stepsProgress, 0)
        XCTAssertEqual(below.tempoBPM, below.baseTempoBPM)
        XCTAssertEqual(above.stepsProgress, 1)
        XCTAssertEqual(above.tempoBPM, min(102, above.baseTempoBPM + 20))
        XCTAssertTrue(above.voices.allSatisfy { $0.activation.amount == 1 })
        XCTAssertEqual(nonFinite.stepsProgress, 0)
        XCTAssertTrue(nonFinite.voices.allSatisfy { $0.glitch == .neutral })
    }

    func testEveryRolePublishesTheExactApprovedActivationWindow() throws {
        let plan = makePlan(stepsProgress: 0.5)
        let expected: [(RhythmRole, Double, Double)] = [
            (.lowPulse, 0.00, 0.20),
            (.halfTimeKick, 0.10, 0.35),
            (.closedHat, 0.30, 0.60),
            (.shaker, 0.38, 0.68),
            (.kickVariation, 0.45, 0.72),
            (.organicPercussion, 0.55, 0.85),
            (.syncopatedGhost, 0.65, 0.92),
            (.fills, 0.82, 1.00)
        ]

        XCTAssertEqual(plan.voices.map(\.role), expected.map(\.0))
        for (role, start, full) in expected {
            let voice = try XCTUnwrap(plan.voices.first { $0.role == role })
            XCTAssertEqual(voice.activation.startProgress, start)
            XCTAssertEqual(voice.activation.fullProgress, full)
        }
    }

    func testRepresentativeStepsAddExpectedRolesAndNeverReduceRichness() {
        let fixtures: [(Double, Set<RhythmRole>)] = [
            (0.00, []),
            (0.15, [.lowPulse, .halfTimeKick]),
            (0.35, [.lowPulse, .halfTimeKick, .closedHat]),
            (0.60, [.lowPulse, .halfTimeKick, .closedHat, .shaker, .kickVariation, .organicPercussion]),
            (0.85, Set(RhythmRole.allCases)),
            (1.00, Set(RhythmRole.allCases))
        ]
        var previousRichness = -Double.infinity

        for (progress, expectedActiveRoles) in fixtures {
            let plan = makePlan(stepsProgress: progress)
            let activeRoles = Set(plan.voices.filter { $0.activation.amount > 0 }.map(\.role))
            XCTAssertEqual(activeRoles, expectedActiveRoles, "Unexpected roles at \(progress)")
            XCTAssertGreaterThanOrEqual(plan.rhythmicRichness, previousRichness)
            previousRichness = plan.rhythmicRichness
        }
    }

    func testRoleActivationHasNoHardJumpAtStartOrFullThresholds() {
        let epsilon = 0.000_001
        let reference = makePlan(stepsProgress: 0.5)

        for voice in reference.voices {
            let aroundStart = [voice.activation.startProgress - epsilon, voice.activation.startProgress + epsilon]
                .map { makePlan(stepsProgress: $0).voice(for: voice.role)!.activation.amount }
            let aroundFull = [voice.activation.fullProgress - epsilon, voice.activation.fullProgress + epsilon]
                .map { makePlan(stepsProgress: $0).voice(for: voice.role)!.activation.amount }

            XCTAssertLessThan(abs(aroundStart[1] - aroundStart[0]), 1e-8, "Start jump for \(voice.role)")
            XCTAssertLessThan(abs(aroundFull[1] - aroundFull[0]), 1e-8, "Full jump for \(voice.role)")
        }
    }

    func testVoicePlansAreDeclarativeFiniteAndRespectEveryRhythmCap() throws {
        let plan = makePlan(stepsProgress: 1, glitchProgress: 1)

        XCTAssertEqual(plan.maximumSimultaneousAttacks, 3)
        XCTAssertEqual(plan.maximumFillsPerWindow, 1)
        XCTAssertEqual(plan.fillWindowBars, 8)
        XCTAssertEqual(plan.maximumMicrotimingMilliseconds, 18)
        XCTAssertEqual(plan.velocityHumanizationRange, -0.08...0.08)
        XCTAssertEqual(plan.maximumHarmonyDuckingDecibels, 2.5)
        XCTAssertEqual(plan.voices.count, RhythmRole.allCases.count)
        XCTAssertEqual(plan.voices.filter(\.isTimingAnchor).count, 1)

        for voice in plan.voices {
            XCTAssertEqual(voice.stepProbabilities.count, 16)
            XCTAssertTrue(voice.stepProbabilities.allSatisfy { $0.isFinite && (0...1).contains($0) })
            XCTAssertTrue((0...1).contains(voice.velocityRange.lowerBound))
            XCTAssertTrue((0...1).contains(voice.velocityRange.upperBound))
            XCTAssertLessThanOrEqual(voice.velocityRange.upperBound - voice.velocityRange.lowerBound, 0.16 + 1e-12)
            XCTAssertGreaterThanOrEqual(voice.microtimingMilliseconds.lowerBound, -18)
            XCTAssertLessThanOrEqual(voice.microtimingMilliseconds.upperBound, 18)
            XCTAssertTrue(voice.roomSend.isFinite && (0...1).contains(voice.roomSend))
            XCTAssertTrue(voice.activation.amount.isFinite && (0...1).contains(voice.activation.amount))
            XCTAssertEqual(voice.isGlitchEligible, !voice.isTimingAnchor)
            XCTAssertTrue(voice.glitch.pitchDriftCents.isFinite && (0...3).contains(voice.glitch.pitchDriftCents))
            XCTAssertTrue(voice.glitch.dropoutProbability.isFinite && (0...0.06).contains(voice.glitch.dropoutProbability))
            XCTAssertTrue(voice.glitch.delayInstability.isFinite && (0...0.08).contains(voice.glitch.delayInstability))
        }

        for step in 0..<16 {
            let plannedAttacks = plan.voices.filter { $0.effectiveProbability(at: step) > 0 }.count
            XCTAssertLessThanOrEqual(plannedAttacks, 3, "Too many planned attacks at step \(step)")
        }

        let fills = try XCTUnwrap(plan.voice(for: .fills))
        XCTAssertLessThanOrEqual(fills.stepProbabilities.filter { $0 > 0 }.count, 1)
    }

    func testPrimaryKickRemainsAnExactTimingAnchorForEveryStepsAndGlitchPercent() throws {
        let progressValues = (0...100).map { Double($0) / 100 } + [-1, 2, .nan, .infinity]
        let glitchValues = (0...100).map { Double($0) / 100 } + [-1, 2, .nan, .infinity]

        for stepsProgress in progressValues {
            for glitchProgress in glitchValues {
                let kick = try XCTUnwrap(
                    makePlan(stepsProgress: stepsProgress, glitchProgress: glitchProgress)
                        .voice(for: .halfTimeKick)
                )
                XCTAssertEqual(kick.drumVoice, .kickSoft)
                XCTAssertTrue(kick.isTimingAnchor)
                XCTAssertFalse(kick.isGlitchEligible)
                XCTAssertEqual(kick.microtimingMilliseconds, 0...0)
                XCTAssertEqual(kick.glitch.pitchDriftCents, 0)
                XCTAssertEqual(kick.glitch.dropoutProbability, 0)
                XCTAssertEqual(kick.glitch.delayInstability, 0)
            }
        }
    }

    func testSameInputAndSeedProduceAnEqualRhythmPlan() {
        let first = makePlan(stepsProgress: 0.73, glitchProgress: 0.41, remixSeed: 0xABCD)
        let second = makePlan(stepsProgress: 0.73, glitchProgress: 0.41, remixSeed: 0xABCD)

        XCTAssertEqual(first, second)
    }

    private func makePlan(
        stepsProgress: Double,
        glitchProgress: Double = 0,
        remixSeed: UInt64 = 0xD4A0_B1EC_75ED_0001
    ) -> RhythmPlan {
        RhythmPlanner.makePlan(
            input: NormalizedDayMusicInput(
                stepsProgress: stepsProgress,
                sleepProgress: 0.5,
                happeningIDs: [],
                glitchProgress: glitchProgress,
                motionEnergy: 0.625,
                visualClarity: 0.625,
                diagnostics: []
            ),
            remixSeed: remixSeed
        )
    }
}
