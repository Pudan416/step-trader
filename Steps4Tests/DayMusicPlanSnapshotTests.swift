#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayMusicPlanSnapshotTests: XCTestCase {
    private struct BoundaryFixture {
        let name: String
        let stepsProgress: Double
        let sleepProgress: Double
        let happeningCount: Int
        let spentColors: Int
        let seed: UInt64
        let expected: String
    }

    private let stepsBoundaries = [0.0, 0.15, 0.35, 0.60, 0.85, 1.0]
    private let sleepBoundaries = [0.0, 0.35, 0.70, 0.99, 1.0]
    private let happeningBoundaries = [0, 1, 5, 10]
    private let spentColorBoundaries = [0, 10, 25, 50, 100]
    private let seeds: [UInt64] = [
        0x1,
        0x2,
        0xD4A0_B1EC_75ED_0001,
        0xFFFF_FFFF_FFFF_FFFF,
    ]

    func testFocusedBoundaryPairsMatchCheckedInSwiftFixtures() {
        let fixtures = [
            BoundaryFixture(
                name: "empty-day",
                stepsProgress: 0,
                sleepProgress: 0,
                happeningCount: 0,
                spentColors: 0,
                seed: 0x1,
                expected: "seed=1|input=0/0/0/0|world=4:mixolydian:12:[4]:[12]|tempo=7200/7200|rhythm=|harmony=drone=pad.forgotten-stories,primary-pad=pad.forgotten-stories,secondary-pad-or-keys=keys.maschinenmensch,piano-or-keys-accents=felt-piano,inner-motion=keys.maschinenmensch|happenings=|lead=lead.bb-silver-screen:[59]:[81]"
            ),
            BoundaryFixture(
                name: "early-day",
                stepsProgress: 0.15,
                sleepProgress: 0.35,
                happeningCount: 1,
                spentColors: 10,
                seed: 0x2,
                expected: "seed=2|input=15/35/1/100|world=0:major-pentatonic:16:[0]:[16]|tempo=7100/7400|rhythm=low-pulse,half-time-kick|harmony=drone=pad.forgotten-stories,primary-pad=pad.forgotten-stories,secondary-pad-or-keys=keys.maschinenmensch,piano-or-keys-accents=felt-piano,inner-motion=keys.maschinenmensch|happenings=event-0:pluck:pluck.spider-filter-pluck:[4, 2, 0]:5|lead=lead.jec-softwah-2:[60]:[81]"
            ),
            BoundaryFixture(
                name: "mid-day",
                stepsProgress: 0.35,
                sleepProgress: 0.70,
                happeningCount: 5,
                spentColors: 25,
                seed: 0xD4A0_B1EC_75ED_0001,
                expected: "seed=d4a0b1ec75ed0001|input=35/70/5/625|world=0:dorian:12:[0, 5]:[6, 6]|tempo=7600/8300|rhythm=low-pulse,half-time-kick,closed-hat|harmony=drone=pad.whispering-sands,primary-pad=pad.forgotten-stories,secondary-pad-or-keys=keys.bb-slow-poly,piano-or-keys-accents=felt-piano,inner-motion=keys.bb-slow-poly|happenings=event-0:texture:pad.interstellar:[10]:3,event-1:mallet:keys.bb-slow-poly:[10, 0, 7]:5,event-2:pluck:pluck.jec-ambient-pizz-2:[0]:6,event-3:bell:keys.jec-polaroids-2:[0, 5, 9]:5,event-4:texture:pad.forgotten-stories:[9]:4|lead=lead.bb-silver-screen:[60, 57]:[81, 81]"
            ),
            BoundaryFixture(
                name: "full-happenings",
                stepsProgress: 0.60,
                sleepProgress: 0.99,
                happeningCount: 10,
                spentColors: 50,
                seed: 0xFFFF_FFFF_FFFF_FFFF,
                expected: "seed=ffffffffffffffff|input=60/99/10/2500|world=7:dorian:8:[7, 5, 0]:[3, 3, 2]|tempo=6000/7200|rhythm=low-pulse,half-time-kick,closed-hat,shaker,kick-variation,organic-percussion|harmony=drone=pad.whispering-sands,primary-pad=pad.forgotten-stories,secondary-pad-or-keys=keys.bb-slow-poly,piano-or-keys-accents=felt-piano,inner-motion=keys.jec-polaroids-2|happenings=event-0:pluck:pluck.spider-filter-pluck:[0]:5,event-1:texture:pad.interstellar:[3, 7, 0]:4,event-2:pluck:pluck.play-something-sad:[5, 7]:4,event-3:mallet:keys.jec-polaroids-2:[9]:4,event-4:soft-one-shot:keys.bb-slow-poly:[2, 0]:5,event-5:mallet:keys.jec-polaroids-2:[5]:4,event-6:soft-one-shot:pluck.play-something-sad:[7, 5]:5,event-7:mallet:keys.bb-slow-poly:[10, 0]:4,event-8:texture:pad.forgotten-stories:[2]:3,event-9:pluck:pluck.spider-filter-pluck:[0, 10, 3]:4|lead=lead.jec-softwah-2:[58, 57, 60]:[81, 81, 81]"
            ),
            BoundaryFixture(
                name: "fully-rested",
                stepsProgress: 0.85,
                sleepProgress: 1,
                happeningCount: 0,
                spentColors: 100,
                seed: 0x1,
                expected: "seed=1|input=85/100/0/10000|world=4:mixolydian:8:[4, 11, 2]:[3, 3, 2]|tempo=7200/8900|rhythm=low-pulse,half-time-kick,closed-hat,shaker,kick-variation,organic-percussion,syncopated-ghost,fills|harmony=drone=pad.forgotten-stories,primary-pad=pad.forgotten-stories,secondary-pad-or-keys=keys.maschinenmensch,piano-or-keys-accents=felt-piano,inner-motion=keys.maschinenmensch|happenings=|lead=lead.bb-silver-screen:[59, 59, 57]:[81, 81, 81]"
            ),
            BoundaryFixture(
                name: "steps-goal",
                stepsProgress: 1,
                sleepProgress: 0,
                happeningCount: 1,
                spentColors: 0,
                seed: 0x2,
                expected: "seed=2|input=100/0/1/0|world=0:major-pentatonic:16:[0]:[16]|tempo=7100/9100|rhythm=low-pulse,half-time-kick,closed-hat,shaker,kick-variation,organic-percussion,syncopated-ghost,fills|harmony=drone=pad.forgotten-stories,primary-pad=pad.forgotten-stories,secondary-pad-or-keys=keys.maschinenmensch,piano-or-keys-accents=felt-piano,inner-motion=keys.maschinenmensch|happenings=event-0:pluck:pluck.spider-filter-pluck:[4, 2, 0]:5|lead=lead.jec-softwah-2:[60]:[81]"
            ),
        ]

        for fixture in fixtures {
            let plan = DeterministicMusicDirector.makePlan(
                input: input(
                    stepsProgress: fixture.stepsProgress,
                    sleepProgress: fixture.sleepProgress,
                    happeningCount: fixture.happeningCount,
                    spentColors: fixture.spentColors
                ),
                remixSeed: fixture.seed
            )
            XCTAssertEqual(snapshot(of: plan), fixture.expected, fixture.name)
        }
    }

    func testFullCartesianBoundaryMatrixIsFiniteBoundedAndInternallyConsistent() {
        var generatedCount = 0
        for steps in stepsBoundaries {
            for sleep in sleepBoundaries {
                for happeningCount in happeningBoundaries {
                    for spentColors in spentColorBoundaries {
                        for seed in seeds {
                            let plan = DeterministicMusicDirector.makePlan(
                                input: input(
                                    stepsProgress: steps,
                                    sleepProgress: sleep,
                                    happeningCount: happeningCount,
                                    spentColors: spentColors
                                ),
                                remixSeed: seed
                            )
                            let context = "steps=\(steps) sleep=\(sleep) happenings=\(happeningCount) spent=\(spentColors) seed=\(String(seed, radix: 16))"
                            XCTAssertEqual(plan.seed, seed, context)
                            XCTAssertEqual(plan.input.stepsProgress, steps, accuracy: 0.000_000_000_001, context)
                            XCTAssertEqual(plan.input.sleepProgress, sleep, accuracy: 0.000_000_000_001, context)
                            XCTAssertEqual(
                                plan.input.glitchProgress,
                                pow(Double(spentColors) / 100, 2),
                                accuracy: 0.000_000_000_001,
                                context
                            )
                            XCTAssertEqual(plan.happenings.count, happeningCount, context)
                            XCTAssertEqual(validationFailures(in: plan), [], context)

                            let allocation = HappeningScheduleAllocator.allocate(
                                plans: plan.happenings,
                                remixSeed: plan.seed,
                                cycleCount: 1
                            )
                            if happeningCount == 0 {
                                XCTAssertTrue(allocation.events.isEmpty, context)
                                XCTAssertTrue(allocation.nextCursors.isEmpty, context)
                            } else {
                                XCTAssertEqual(allocation.nextCursors.count, happeningCount, context)
                                XCTAssertEqual(Set(allocation.events.map(\.happeningID)).count, happeningCount, context)
                            }
                            generatedCount += 1
                        }
                    }
                }
            }
        }

        XCTAssertEqual(generatedCount, 2_400)
    }

    func testLeadPitchMapIsTonalAndInRegisterForEveryModeCenterAndProgressionShape() throws {
        let centers = [0, 2, 4, 5, 7, 9]
        let cycles = [8, 12, 16]
        var worldCount = 0

        for center in centers {
            for mode in DayMusicMode.allCases {
                for progressionLength in 1...4 {
                    for cycleBars in cycles {
                        let world = try XCTUnwrap(
                            TonalWorldPlanner.makePlan(
                                centerPitchClass: center,
                                mode: mode,
                                progressionLength: progressionLength,
                                cycleBars: cycleBars
                            )
                        )
                        let lead = try XCTUnwrap(
                            LeadPlanner.makePlan(
                                tonalWorld: world,
                                instrumentDescriptors: DayObjectsInstrumentManifest.defaultDescriptors,
                                remixSeed: UInt64(worldCount)
                            )
                        )

                        for region in lead.pitchRegions {
                            XCTAssertEqual(region.midiNotesByChord.count, progressionLength)
                            for (chordIndex, note) in region.midiNotesByChord.enumerated() {
                                XCTAssertTrue(lead.register.contains(note))
                                let allowedPitchClasses = region.preference == .chordTone
                                    ? world.progression[chordIndex].chordPitchClasses
                                    : world.scalePitchClasses
                                XCTAssertTrue(allowedPitchClasses.contains(Int(note) % 12))
                            }
                        }
                        worldCount += 1
                    }
                }
            }
        }

        XCTAssertEqual(worldCount, 288)
    }

    private func input(
        stepsProgress: Double,
        sleepProgress: Double,
        happeningCount: Int,
        spentColors: Int
    ) -> DayMusicInput {
        DayMusicInput(
            countedSteps: stepsProgress * 10_000,
            stepGoal: 10_000,
            countedSleepHours: sleepProgress * 8,
            sleepGoalHours: 8,
            happeningIDs: (0..<happeningCount).map { "event-\($0)" },
            spentColors: spentColors
        )
    }

    private func validationFailures(in plan: DayMusicPlan) -> [String] {
        var failures: [String] = []
        func require(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }
        func requireFinite(_ values: [Double], _ message: String) {
            require(values.allSatisfy(\.isFinite), message)
        }
        func requireUnit(_ values: [Double], _ message: String) {
            require(values.allSatisfy { $0.isFinite && (0...1).contains($0) }, message)
        }

        requireUnit([
            plan.input.stepsProgress,
            plan.input.sleepProgress,
            plan.input.glitchProgress,
            plan.input.motionEnergy,
            plan.input.visualClarity,
        ], "normalized input bounds")
        require([0, 2, 4, 5, 7, 9].contains(plan.world.centerPitchClass), "tonal center")
        require([8, 12, 16].contains(plan.world.cycleBars), "world cycle")
        require((1...4).contains(plan.world.progression.count), "progression count")
        require(plan.world.progression.map(\.durationBars).reduce(0, +) == plan.world.cycleBars, "chord durations")
        require(plan.world.scalePitchClasses.allSatisfy { (0...11).contains($0) }, "scale pitch classes")
        for chord in plan.world.progression {
            require((0...11).contains(chord.rootPitchClass), "chord root")
            require(chord.chordPitchClasses.allSatisfy { (0...11).contains($0) }, "chord pitch classes")
            require(chord.safePassingPitchClasses == plan.world.scalePitchClasses, "safe passing tones")
            require(chord.voicedMIDINotes == chord.voicedMIDINotes.sorted(), "ascending world voicing")
            require(chord.voicedMIDINotes.allSatisfy { $0 <= 127 }, "world MIDI bounds")
        }

        requireFinite([plan.rhythm.baseTempoBPM, plan.rhythm.tempoBPM, plan.rhythm.rhythmicRichness], "rhythm finite")
        require((58...82).contains(plan.rhythm.baseTempoBPM), "base tempo")
        require((58...102).contains(plan.rhythm.tempoBPM), "final tempo")
        require(plan.rhythm.voices.count == RhythmRole.allCases.count, "rhythm roles")
        for voice in plan.rhythm.voices {
            require(voice.stepProbabilities.count == 16, "sixteen-step pattern")
            requireUnit(voice.stepProbabilities + [voice.roomSend, voice.activation.amount], "rhythm voice unit bounds")
            requireFinite([
                voice.velocityRange.lowerBound,
                voice.velocityRange.upperBound,
                voice.microtimingMilliseconds.lowerBound,
                voice.microtimingMilliseconds.upperBound,
            ], "rhythm voice finite")
            require(abs(voice.microtimingMilliseconds.lowerBound) <= 18, "microtiming lower bound")
            require(abs(voice.microtimingMilliseconds.upperBound) <= 18, "microtiming upper bound")
            if voice.isTimingAnchor {
                require(!voice.isGlitchEligible, "timing-anchor glitch exemption")
                require(voice.microtimingMilliseconds == 0...0, "timing-anchor microtiming exemption")
            }
        }

        let descriptorIDs = Set(DayObjectsInstrumentManifest.defaultDescriptors.map(\.id))
        require(plan.harmony.cycleBars == plan.world.cycleBars, "harmony cycle")
        require(plan.harmony.chordCount == plan.world.progression.count, "harmony chord count")
        requireFinite([plan.harmony.sleepProgress, plan.harmony.harmonicInformationScore], "harmony finite")
        for role in plan.harmony.roles {
            requireFinite([
                role.gain,
                role.attackSeconds,
                role.releaseSeconds,
                role.delaySend,
                role.reverbSend,
                role.activation.amount,
                role.crossfadeBars,
            ], "harmony role finite")
            require(role.gain >= 0, "harmony gain")
            requireUnit([role.delaySend, role.reverbSend, role.activation.amount], "harmony role unit bounds")
            require(role.register.lowerBound <= role.register.upperBound, "harmony register")
            switch role.instrumentTarget {
            case let .tonal(instrumentID):
                require(descriptorIDs.contains(instrumentID), "harmony tonal descriptor")
                require(role.role != .pianoOrKeysAccents, "accent must use felt piano")
            case .feltPiano:
                require(role.role == .pianoOrKeysAccents, "felt piano role")
            }
            for entry in role.chordSchedule {
                require(entry.startBar >= 0 && entry.startBar < plan.world.cycleBars, "harmony start bar")
                require(entry.durationBars > 0, "harmony duration")
                require(entry.voicedMIDINotes.allSatisfy(role.register.contains), "harmony register notes")
            }
        }

        for happening in plan.happenings {
            require(!happening.happeningID.isEmpty, "happening ID")
            require(descriptorIDs.contains(happening.instrumentID), "happening descriptor")
            require((1...3).contains(happening.motifScaleDegrees.count), "happening motif length")
            require(happening.motifScaleDegrees.allSatisfy(plan.world.mode.scaleIntervals.contains), "happening motif tones")
            requireFinite([
                happening.pan,
                happening.gain,
                happening.birthGain,
                happening.attackSeconds,
                happening.releaseSeconds,
                happening.delaySend,
                happening.reverbSend,
                happening.recurrence.floatingOffsetBeats,
            ], "happening finite")
            require((-1...1).contains(happening.pan), "happening pan")
            require(happening.gain >= HappeningMusicPlan.minimumAudibleGain, "happening gain floor")
            requireUnit([happening.gain, happening.birthGain, happening.delaySend, happening.reverbSend], "happening unit bounds")
            require(abs(happening.recurrence.floatingOffsetBeats) <= 0.5, "happening offset")
        }

        require(descriptorIDs.contains(plan.lead.instrumentID), "lead descriptor")
        require(plan.lead.maximumSimultaneousVoices == 1, "monophonic lead")
        require(plan.lead.pitchRegions.count == 21, "lead region count")
        require(plan.lead.pitchRegions.first?.normalizedRange.lowerBound == 0, "lead lower boundary")
        require(plan.lead.pitchRegions.last?.normalizedRange.upperBound == 1, "lead upper boundary")
        requireFinite([
            plan.lead.portamentoMilliseconds,
            plan.lead.attackSeconds,
            plan.lead.releaseSeconds,
            plan.lead.cutoffMultiplierRange.lowerBound,
            plan.lead.cutoffMultiplierRange.upperBound,
            plan.lead.pitchSmoothingMilliseconds,
            plan.lead.expressionSmoothingMilliseconds,
            plan.lead.maximumExpressionDepth,
            plan.lead.delaySend,
            plan.lead.reverbSend,
        ], "lead finite")
        for region in plan.lead.pitchRegions {
            require(region.midiNotesByChord.count == plan.world.progression.count, "lead chord lookup")
            require(region.midiNotesByChord.allSatisfy(plan.lead.register.contains), "lead register")
        }

        requireFinite([
            plan.glitch.progress,
            plan.glitch.wowFlutterDepth,
            plan.glitch.stereoSeparationAddition,
        ], "glitch finite")
        requireUnit([
            plan.glitch.progress,
            plan.glitch.wowFlutterDepth,
            plan.glitch.stereoSeparationAddition,
        ], "glitch unit bounds")
        require(plan.glitch.roles.map(\.role) == GlitchRole.allCases, "glitch roles")
        for rolePlan in plan.glitch.roles {
            requireFinite([
                rolePlan.pitchDriftCents,
                rolePlan.dropoutProbability,
                rolePlan.delayTimeInstability,
            ], "glitch role finite")
            requireUnit(
                [rolePlan.dropoutProbability, rolePlan.delayTimeInstability],
                "glitch role unit bounds"
            )
            let maximumPitchDrift: Double
            switch rolePlan.role {
            case .pad: maximumPitchDrift = 14
            case .happening: maximumPitchDrift = 10
            case .lead: maximumPitchDrift = 8
            case .percussion: maximumPitchDrift = 3
            case .timingAnchorKick: maximumPitchDrift = 0
            }
            require((0...maximumPitchDrift).contains(rolePlan.pitchDriftCents), "glitch pitch drift")
            require(rolePlan.dropoutProbability <= 0.06, "glitch dropout cap")
            require(rolePlan.delayTimeInstability <= 0.08, "glitch delay cap")
            if rolePlan.role == .timingAnchorKick {
                require(rolePlan == .stableKick, "glitch timing anchor")
            } else {
                require(!rolePlan.isTimingAnchor && rolePlan.isGlitchEligible, "glitch role eligibility")
            }

            if let event = plan.glitch.realizedEvent(
                for: rolePlan.role,
                cycleIndex: 0,
                stepIndex: 0
            ) {
                requireFinite(
                    [event.pitchDriftCents, event.delayTimeVariation],
                    "realized glitch finite"
                )
                require(
                    abs(event.pitchDriftCents) <= rolePlan.pitchDriftCents,
                    "realized glitch pitch bound"
                )
                require(
                    abs(event.delayTimeVariation) <= rolePlan.delayTimeInstability,
                    "realized glitch delay bound"
                )
            } else {
                require(false, "realized glitch event")
            }
        }

        requireFinite([
            plan.mix.rhythmTargetDecibels,
            plan.mix.harmonyTargetDecibels,
            plan.mix.happeningAggregateTargetDecibels,
            plan.mix.happeningPerVoiceTargetDecibels,
            plan.mix.leadTargetDecibels,
            plan.mix.masterTargetDecibelsBeforeLimiter,
            plan.mix.maximumHarmonyDuckingDecibels,
        ], "mix finite")
        require(plan.mix.happeningCount == plan.happenings.count, "mix happening count")
        require(plan.mix.maximumHarmonyDuckingDecibels == 2.5, "mix ducking cap")
        return failures
    }

    private func snapshot(of plan: DayMusicPlan) -> String {
        let harmony = plan.harmony.roles.map {
            "\(harmonyRoleName($0.role))=\(harmonyTargetName($0.instrumentTarget))"
        }.joined(separator: ",")
        let happenings = plan.happenings.map {
            "\($0.happeningID):\(familyName($0.family)):\($0.instrumentID.rawValue):\($0.motifScaleDegrees):\($0.octave)"
        }.joined(separator: ",")
        let activeRhythm = plan.rhythm.voices
            .filter { $0.activation.amount > 0 }
            .map { rhythmRoleName($0.role) }
            .joined(separator: ",")
        return [
            "seed=\(String(plan.seed, radix: 16))",
            "input=\(Int((plan.input.stepsProgress * 100).rounded()))/\(Int((plan.input.sleepProgress * 100).rounded()))/\(plan.happenings.count)/\(Int((plan.input.glitchProgress * 10_000).rounded()))",
            "world=\(plan.world.centerPitchClass):\(modeName(plan.world.mode)):\(plan.world.cycleBars):\(plan.world.progression.map(\.rootPitchClass)):\(plan.world.progression.map(\.durationBars))",
            "tempo=\(Int((plan.rhythm.baseTempoBPM * 100).rounded()))/\(Int((plan.rhythm.tempoBPM * 100).rounded()))",
            "rhythm=\(activeRhythm)",
            "harmony=\(harmony)",
            "happenings=\(happenings)",
            "lead=\(plan.lead.instrumentID.rawValue):\(plan.lead.pitchRegions.first?.midiNotesByChord ?? []):\(plan.lead.pitchRegions.last?.midiNotesByChord ?? [])",
        ].joined(separator: "|")
    }

    private func modeName(_ mode: DayMusicMode) -> String {
        switch mode {
        case .dorian: return "dorian"
        case .aeolian: return "aeolian"
        case .mixolydian: return "mixolydian"
        case .majorPentatonic: return "major-pentatonic"
        }
    }

    private func rhythmRoleName(_ role: RhythmRole) -> String {
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

    private func harmonyRoleName(_ role: HarmonyRole) -> String {
        switch role {
        case .drone: return "drone"
        case .primaryPad: return "primary-pad"
        case .secondaryPadOrKeys: return "secondary-pad-or-keys"
        case .pianoOrKeysAccents: return "piano-or-keys-accents"
        case .innerMotion: return "inner-motion"
        }
    }

    private func harmonyTargetName(_ target: HarmonyInstrumentTarget) -> String {
        switch target {
        case let .tonal(instrumentID): return instrumentID.rawValue
        case .feltPiano: return "felt-piano"
        }
    }

    private func familyName(_ family: HappeningSoundFamily) -> String {
        switch family {
        case .pluck: return "pluck"
        case .mallet: return "mallet"
        case .bell: return "bell"
        case .softOneShot: return "soft-one-shot"
        case .texture: return "texture"
        }
    }
}
#endif
