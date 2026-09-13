import XCTest
@testable import Steps4

final class TonalWorldPlannerTests: XCTestCase {
    func testEqualInputWorldsDifferInProgressionOrVoicing() {
        for mood in DayObjectsSoundMood.allCases {
            for seed in UInt64(0)..<80 {
                let plans = DayObjectsSoundWorld.allCases.map {
                    TonalWorldPlanner.makePlan(input: input(sleepProgress: 1), remixSeed: seed, world: $0, mood: mood)
                }
                XCTAssertEqual(Set(plans.map(\.musicalFingerprint)).count, 4, "\(mood), seed \(seed)")
            }
        }
    }

    func testWorldGrammarConstrainsActualModesExtensionsRegistersAndDurations() {
        for world in DayObjectsSoundWorld.allCases {
            for mood in DayObjectsSoundMood.allCases {
                let grammar = DayObjectsHarmonyGrammar.for(world: world, mood: mood)
                for seed in UInt64(0)..<24 {
                    let plan = TonalWorldPlanner.makePlan(input: input(sleepProgress: 1), remixSeed: seed, world: world, mood: mood)
                    XCTAssertTrue(grammar.allowedModes.contains(plan.mode))
                    XCTAssertTrue(grammar.cycleBarChoices.contains(plan.cycleBars))
                    XCTAssertEqual(plan.progression.map(\.durationBars).reduce(0, +), plan.cycleBars)
                    for chord in plan.progression {
                        XCTAssertTrue(chord.durationBars > 0)
                        XCTAssertFalse(chord.voicedMIDINotes.isEmpty)
                        XCTAssertLessThanOrEqual(chord.voicedMIDINotes.count, grammar.maximumChordTones)
                        XCTAssertTrue(chord.voicedMIDINotes.allSatisfy(grammar.register.contains))
                        XCTAssertEqual(Set(chord.voicedMIDINotes.map { Int($0) % 12 }), Set(chord.chordPitchClasses))
                        XCTAssertTrue(chord.chordPitchClasses.allSatisfy {
                            $0 == chord.rootPitchClass || grammar.allowedExtensions.contains(($0 - chord.rootPitchClass + 12) % 12)
                        })
                    }
                    XCTAssertEqual(plan, TonalWorldPlanner.makePlan(input: input(sleepProgress: 1), remixSeed: seed, world: world, mood: mood))
                }
            }
        }
    }

    func testMoodsChangeMusicalOutputWithoutChangingSleepChordCount() {
        for world in DayObjectsSoundWorld.allCases {
            let plans = DayObjectsSoundMood.allCases.map {
                TonalWorldPlanner.makePlan(input: input(sleepProgress: 1), remixSeed: 77, world: world, mood: $0)
            }
            XCTAssertEqual(Set(plans.map(\.musicalFingerprint)).count, 3, "\(world)")
            XCTAssertEqual(Set(plans.map { $0.progression.count }).count, 1)
        }
    }

    func testFingerprintTracksSoundingNotesDegreesModeAndDurations() {
        let chord = ChordPlan(modalDegree: 0, rootPitchClass: 0, chordPitchClasses: [0, 7], safePassingPitchClasses: [0, 7], voicedMIDINotes: [48, 55], durationBars: 8)
        let baseline = TonalWorldPlan(centerPitchClass: 0, mode: .dorian, scalePitchClasses: [0, 7], progression: [chord], cycleBars: 8)
        let variants = [
            ChordPlan(modalDegree: 7, rootPitchClass: 0, chordPitchClasses: [0, 7], safePassingPitchClasses: [0, 7], voicedMIDINotes: [48, 55], durationBars: 8),
            ChordPlan(modalDegree: 0, rootPitchClass: 0, chordPitchClasses: [0, 7], safePassingPitchClasses: [0, 7], voicedMIDINotes: [55, 60], durationBars: 8),
            ChordPlan(modalDegree: 0, rootPitchClass: 0, chordPitchClasses: [0, 7], safePassingPitchClasses: [0, 7], voicedMIDINotes: [48, 55], durationBars: 12)
        ].map { TonalWorldPlan(centerPitchClass: 0, mode: .dorian, scalePitchClasses: [0, 7], progression: [$0], cycleBars: $0.durationBars) }
        XCTAssertTrue(variants.allSatisfy { $0.musicalFingerprint != baseline.musicalFingerprint })
        XCTAssertNotEqual(baseline.musicalFingerprint, TonalWorldPlan(centerPitchClass: 0, mode: .aeolian, scalePitchClasses: [0, 7], progression: [chord], cycleBars: 8).musicalFingerprint)
    }

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

    func testDirectConstructionRejectsCentersCyclesAndProgressionLengthsOutsideTheApprovedSets() {
        XCTAssertNil(TonalWorldPlanner.makePlan(
            centerPitchClass: 1,
            mode: .dorian,
            progressionLength: 1,
            cycleBars: 8
        ))
        XCTAssertNil(TonalWorldPlanner.makePlan(
            centerPitchClass: 0,
            mode: .dorian,
            progressionLength: 1,
            cycleBars: 13
        ))
        XCTAssertNil(TonalWorldPlanner.makePlan(
            centerPitchClass: 0,
            mode: .dorian,
            progressionLength: 0,
            cycleBars: 8
        ))
        XCTAssertNil(TonalWorldPlanner.makePlan(
            centerPitchClass: 0,
            mode: .dorian,
            progressionLength: 5,
            cycleBars: 8
        ))

        for center in [0, 2, 4, 5, 7, 9] {
            for cycleBars in [8, 12, 16] {
                XCTAssertNotNil(TonalWorldPlanner.makePlan(
                    centerPitchClass: center,
                    mode: .dorian,
                    progressionLength: 4,
                    cycleBars: cycleBars
                ))
            }
        }
    }

    func testMajorPentatonicTemplatesUseExactApprovedChordQualities() throws {
        let plan = try XCTUnwrap(TonalWorldPlanner.makePlan(
            centerPitchClass: 0,
            mode: .majorPentatonic,
            progressionLength: 4,
            cycleBars: 12
        ))

        XCTAssertEqual(plan.progression.map(\.modalDegree), [0, 9, 5, 7])
        XCTAssertEqual(plan.progression.map(\.rootPitchClass), [0, 9, 5, 7])
        XCTAssertEqual(
            plan.progression.map(\.chordPitchClasses),
            [
                [0, 7],       // I5
                [9, 4, 7],    // vi7(no3)
                [5, 7, 0],    // IVsus2
                [7, 0, 2]     // Vsus
            ]
        )
    }

    func testChordPlansPublishChordTonesSafeModeTonesVoicingsAndCompleteCycleDurations() throws {
        let plan = try XCTUnwrap(TonalWorldPlanner.makePlan(
            centerPitchClass: 0,
            mode: .dorian,
            progressionLength: 4,
            cycleBars: 12
        ))

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
