import XCTest
@testable import Steps4

final class RhythmPlannerTests: XCTestCase {
    func testPlanPublishesExplicitFamilyProfileAndCounterRealizationState() {
        let plan = makePlan(stepsProgress: 1, remixSeed: 0x1)

        XCTAssertEqual(plan.family, .orbiting)
        XCTAssertEqual(plan.patternOffsetSteps, 0)
        XCTAssertEqual(plan.humanizationProfile, .loose)
        XCTAssertEqual(plan.realization.patternSeed, 0x5D60_90C5_A9B0_926A)
        XCTAssertEqual(plan.realization.humanizationSeed, 0x04C3_A9BD_2712_5544)
        XCTAssertEqual(plan.realization.cycleKey, 0x9A29_3113_F703_40D7)
        XCTAssertEqual(plan.realization.counterMapping, .roleCycleStepParameterV1)
    }

    func testFixedRealizedEventVectorsAreAudibleAndRepeatable() {
        let fixtures: [(UInt64, [String])] = [
            (0x1, [
                "0:0:low-pulse:6227:-6347",
                "0:0:half-time-kick:8624:0",
                "0:0:closed-hat:4526:-4065",
                "0:1:organic-percussion:4606:2527",
                "0:7:shaker:4172:4673",
                "0:8:half-time-kick:8928:0",
                "0:8:closed-hat:5593:8882",
                "0:10:closed-hat:5566:-1019",
                "0:11:syncopated-ghost:3904:-13481",
                "0:12:closed-hat:4408:-9835",
                "0:13:shaker:4333:2439",
                "0:14:kick-variation:7744:-4098",
                "0:15:shaker:3470:-5675",
                "0:15:syncopated-ghost:4000:2184",
                "1:0:low-pulse:6518:2063",
                "1:0:half-time-kick:9106:0",
                "1:2:closed-hat:4428:-4171",
                "1:5:shaker:3657:3978",
                "1:6:closed-hat:4791:-1959",
                "1:7:shaker:3433:-9690",
                "1:9:organic-percussion:5333:351",
                "1:10:closed-hat:4943:-2380",
                "1:11:syncopated-ghost:3600:5370",
                "1:12:closed-hat:4405:-3819",
                "1:14:kick-variation:7069:-4907",
                "1:15:shaker:3845:12254",
            ]),
            (0x2, [
                "0:0:half-time-kick:8479:0",
                "0:0:closed-hat:5005:3628",
                "0:5:syncopated-ghost:3596:5401",
                "0:8:low-pulse:5764:-4602",
                "0:8:half-time-kick:8386:0",
                "0:8:closed-hat:5177:6054",
                "0:9:shaker:4065:8244",
                "0:9:syncopated-ghost:3357:-6184",
                "0:13:shaker:3956:-2447",
                "1:0:half-time-kick:8791:0",
                "1:1:shaker:3840:-7786",
                "1:2:closed-hat:5142:-995",
                "1:2:kick-variation:7230:2853",
                "1:6:closed-hat:5093:4546",
                "1:7:shaker:3765:4670",
                "1:7:organic-percussion:5560:9686",
                "1:8:low-pulse:5631:-5093",
                "1:8:half-time-kick:8574:0",
                "1:10:closed-hat:5221:7048",
                "1:13:syncopated-ghost:3629:9733",
                "1:14:closed-hat:5194:2353",
                "1:15:organic-percussion:5312:-9770",
            ]),
        ]

        for (seed, expected) in fixtures {
            let plan = makePlan(stepsProgress: 1, remixSeed: seed)
            XCTAssertEqual(realizedEventVector(plan, cycles: 0..<2), expected)
            XCTAssertEqual(realizedEventVector(plan, cycles: 0..<2), expected)
        }
    }

    func testRealizationIsCallOrderIndependentAndEnforcesPublishedAttackAndFillCaps() {
        let plan = makePlan(stepsProgress: 1, remixSeed: 0xD4A0_B1EC_75ED_0001)
        let coordinates = (0..<24).flatMap { cycle in (0..<16).map { (cycle, $0) } }
        let forward = Dictionary(uniqueKeysWithValues: coordinates.map {
            ("\($0.0):\($0.1)", plan.realizedEvents(cycleIndex: $0.0, stepIndex: $0.1))
        })
        let reverse = Dictionary(uniqueKeysWithValues: coordinates.reversed().map {
            ("\($0.0):\($0.1)", plan.realizedEvents(cycleIndex: $0.0, stepIndex: $0.1))
        })

        XCTAssertEqual(forward, reverse)
        XCTAssertTrue(forward.values.allSatisfy { $0.count <= plan.maximumSimultaneousAttacks })
        XCTAssertTrue(forward.values.flatMap { $0 }.allSatisfy { event in
            guard let voice = plan.voice(for: event.role) else { return false }
            return voice.velocityRange.contains(event.velocity)
                && abs(event.microtimingMilliseconds) <= plan.maximumMicrotimingMilliseconds
                && (!voice.isTimingAnchor || event.microtimingMilliseconds == 0)
        })
        for windowStart in stride(from: 0, to: 24, by: plan.fillWindowBars) {
            let fillCount = (windowStart..<(windowStart + plan.fillWindowBars)).reduce(0) { count, cycle in
                count + (0..<16).reduce(0) { stepCount, step in
                    stepCount + plan.realizedEvents(cycleIndex: cycle, stepIndex: step)
                        .filter { $0.role == .fills }.count
                }
            }
            XCTAssertLessThanOrEqual(fillCount, plan.maximumFillsPerWindow)
        }
        XCTAssertTrue(plan.realizedEvents(cycleIndex: -1, stepIndex: 0).isEmpty)
        XCTAssertTrue(plan.realizedEvents(cycleIndex: 0, stepIndex: -1).isEmpty)
        XCTAssertTrue(plan.realizedEvents(cycleIndex: 0, stepIndex: 16).isEmpty)
    }

    func testBassGroovesKeepAtMostOneKickPerPositionAndAnchorsOnGridAcrossEightBars() {
        let remixSeed = seedProducing(.bassBed)
        let groove = GroovePlanner.makePlan(remixSeed: remixSeed)
        let plan = RhythmPlanner.makePlan(
            input: normalizedInput(stepsProgress: 1),
            remixSeed: remixSeed,
            groove: groove
        )

        for cycle in 0..<8 {
            var anchorKickCount = 0
            for step in 0..<16 {
                let events = plan.realizedEvents(cycleIndex: cycle, stepIndex: step)
                let kickEvents = events.filter { [.halfTimeKick, .kickVariation].contains($0.role) }

                XCTAssertLessThanOrEqual(kickEvents.count, 1, "Duplicate kick at \(cycle):\(step)")
                for event in events where plan.voice(for: event.role)?.isTimingAnchor == true {
                    XCTAssertEqual(event.microtimingMilliseconds, 0, accuracy: 1e-12)
                    anchorKickCount += 1
                }
            }
            XCTAssertLessThanOrEqual(anchorKickCount, groove.maximumAnchorKicksPerBar)
        }
    }

    func testRemixChangesRhythmFamilyPatternAndHumanizationWithoutChangingDayInput() {
        let first = makePlan(stepsProgress: 1, remixSeed: 0x1)
        let remixed = makePlan(stepsProgress: 1, remixSeed: 0x2)

        XCTAssertEqual(first.stepsProgress, remixed.stepsProgress)
        XCTAssertNotEqual(first.family, remixed.family)
        XCTAssertNotEqual(first.voices.map(\.stepProbabilities), remixed.voices.map(\.stepProbabilities))
        XCTAssertNotEqual(first.realization.patternSeed, remixed.realization.patternSeed)
        XCTAssertNotEqual(first.humanizationProfile, remixed.humanizationProfile)
        XCTAssertNotEqual(first.realization.humanizationSeed, remixed.realization.humanizationSeed)
        XCTAssertNotEqual(
            realizedEventVector(first, cycles: 0..<2),
            realizedEventVector(remixed, cycles: 0..<2)
        )
    }

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
        XCTAssertEqual(
            nonFinite,
            makePlan(stepsProgress: .infinity, glitchProgress: 0, remixSeed: 42)
        )
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
            }
        }
    }

    func testSpentColorsNeverMutatesTheStructuralRhythmPlan() {
        let clear = makePlan(stepsProgress: 0.73, glitchProgress: 0, remixSeed: 0xABCD)
        let damaged = makePlan(stepsProgress: 0.73, glitchProgress: 1, remixSeed: 0xABCD)

        XCTAssertEqual(clear, damaged)
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
            remixSeed: remixSeed,
            groove: .percussion
        )
    }

    private func normalizedInput(stepsProgress: Double) -> NormalizedDayMusicInput {
        NormalizedDayMusicInput(
            stepsProgress: stepsProgress,
            sleepProgress: 0.5,
            happeningIDs: [],
            glitchProgress: 0,
            motionEnergy: 0.625,
            visualClarity: 0.625,
            diagnostics: []
        )
    }

    private func seedProducing(_ mode: GrooveMode) -> UInt64 {
        for seed in UInt64(0)..<10_000 where GroovePlanner.makePlan(remixSeed: seed).mode == mode {
            return seed
        }
        XCTFail("No seed found for \(mode)")
        return 0
    }

    private func realizedEventVector(_ plan: RhythmPlan, cycles: Range<Int>) -> [String] {
        cycles.flatMap { cycle in
            (0..<16).flatMap { step in
                plan.realizedEvents(cycleIndex: cycle, stepIndex: step).map { event in
                    let velocity = Int((event.velocity * 10_000).rounded())
                    let microtiming = Int((event.microtimingMilliseconds * 1_000).rounded())
                    return "\(cycle):\(step):\(roleName(event.role)):\(velocity):\(microtiming)"
                }
            }
        }
    }

    private func roleName(_ role: RhythmRole) -> String {
        switch role {
        case .lowPulse: return "low-pulse"
        case .halfTimeKick: return "half-time-kick"
        case .closedHat: return "closed-hat"
        case .shaker: return "shaker"
        case .kickVariation: return "kick-variation"
        case .organicPercussion: return "organic-percussion"
        case .syncopatedGhost: return "syncopated-ghost"
        case .fills: return "fills"
        }
    }
}
