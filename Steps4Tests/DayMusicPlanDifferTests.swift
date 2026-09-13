#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayMusicPlanDifferTests: XCTestCase {
    func testWorldGroupCalibrationChangesAreContinuousIncludingWithHappeningAddition() {
        let old = makePlan(happeningIDs: ["one", "two"])
        var mix = old.mix
        mix.worldGroupCalibration = .init(masterMakeupDB: 5, reverbSendScale: 0.5)
        let updated = replacing(old, mix: mix)
        let change = DayMusicPlanDiffer.change(from: old, to: updated)
        XCTAssertEqual(change.continuousPlan, updated)
        XCTAssertNil(change.structuralPlan)
        XCTAssertTrue(change.addedHappenings.isEmpty)
        XCTAssertTrue(change.removedHappeningIDs.isEmpty)
        let added = makePlan(happeningIDs: ["one", "two", "three"])
        var addedMix = added.mix
        addedMix.worldGroupCalibration = mix.worldGroupCalibration
        let withAddition = replacing(added, mix: addedMix)
        let combined = DayMusicPlanDiffer.change(from: old, to: withAddition)
        XCTAssertEqual(combined.continuousPlan, withAddition)
        XCTAssertNil(combined.structuralPlan)
        XCTAssertEqual(combined.addedHappenings.map(\.happeningID), ["three"])
    }

    func testKitOnlyChangeIsStructural() {
        let old = makePlan()
        let new = replacing(old, rhythm: rhythm(old.rhythm, kitID: "acoustic.skin-and-wood"))
        let change = DayMusicPlanDiffer.change(from: old, to: new)
        XCTAssertEqual(change.structuralPlan, new)
        XCTAssertNil(change.continuousPlan)
    }
    func testWorldMoodAndKitAreStructuralWhileWorldHealthUpdatesStayContinuous() {
        let old = WorldArrangementFixture.plan(.electricDream, .moving, steps: 0.5, sleep: 0.5)
        for new in [
            WorldArrangementFixture.plan(.livingField, .moving, steps: 0.5, sleep: 0.5),
            WorldArrangementFixture.plan(.electricDream, .strange, steps: 0.5, sleep: 0.5)
        ] {
            XCTAssertEqual(DayMusicPlanDiffer.change(from: old, to: new).structuralPlan, new)
        }
        let health = WorldArrangementFixture.plan(.electricDream, .moving, steps: 0.6, sleep: 0.6)
        let change = DayMusicPlanDiffer.change(from: old, to: health)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.continuousPlan, health)
    }
    private let seed: UInt64 = 0xD4A0_B1EC_75ED_0001

    func testIdenticalPlansProduceNoPlaybackCommands() {
        let plan = makePlan()

        let change = DayMusicPlanDiffer.change(from: plan, to: plan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testStepsChangeIsContinuousWithoutReplacingRhythmStructure() {
        let oldPlan = makePlan(stepsProgress: 0.15)
        let newPlan = makePlan(stepsProgress: 0.85)
        XCTAssertEqual(oldPlan.rhythm.family, newPlan.rhythm.family)
        XCTAssertEqual(oldPlan.rhythm.patternOffsetSteps, newPlan.rhythm.patternOffsetSteps)
        XCTAssertEqual(oldPlan.rhythm.realization, newPlan.rhythm.realization)
        XCTAssertEqual(oldPlan.groove.mode, newPlan.groove.mode)
        XCTAssertEqual(oldPlan.bass?.instrumentID, newPlan.bass?.instrumentID)
        XCTAssertEqual(
            oldPlan.bass?.events.map(\.stableID),
            newPlan.bass?.events.map(\.stableID)
        )

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testChangingPublishedBassInstrumentIsStructuralEvenWhenContinuousBassValuesMatch() throws {
        let oldPlan = try planWithBass()
        let alternateInstrument = try XCTUnwrap(
            DayObjectsInstrumentManifest.defaultDescriptors.first {
                $0.category == .bass && $0.id != oldPlan.bass?.instrumentID
            }
        )
        let oldBass = try XCTUnwrap(oldPlan.bass)
        let newBass = BassPlan(
            mode: oldBass.mode,
            instrumentID: alternateInstrument.id,
            register: oldBass.register,
            articulation: oldBass.articulation,
            stepsProgress: oldBass.stepsProgress,
            cutoffMultiplier: oldBass.cutoffMultiplier,
            glideMilliseconds: oldBass.glideMilliseconds,
            reverbSend: oldBass.reverbSend,
            ducking: oldBass.ducking,
            events: oldBass.events
        )
        let newPlan = replacing(oldPlan, bass: newBass)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
    }

    func testBassStructuralDifferenceSuppressesBassContinuousUpdate() throws {
        let oldPlan = try planWithBass()
        let oldBass = try XCTUnwrap(oldPlan.bass)
        let alternateInstrument = try XCTUnwrap(
            DayObjectsInstrumentManifest.defaultDescriptors.first {
                $0.category == .bass && $0.id != oldBass.instrumentID
            }
        )
        let newBass = BassPlan(
            mode: oldBass.mode,
            instrumentID: alternateInstrument.id,
            register: oldBass.register,
            articulation: oldBass.articulation,
            stepsProgress: 1,
            cutoffMultiplier: oldBass.cutoffMultiplier + 0.1,
            glideMilliseconds: oldBass.glideMilliseconds + 1,
            reverbSend: oldBass.reverbSend + 0.01,
            ducking: BassDuckingPlan(
                maximumAttenuationDecibels: oldBass.ducking.maximumAttenuationDecibels + 0.1,
                attackSeconds: oldBass.ducking.attackSeconds,
                holdSeconds: oldBass.ducking.holdSeconds,
                releaseSeconds: oldBass.ducking.releaseSeconds
            ),
            events: oldBass.events.enumerated().map { index, event in
                BassEventPlan(
                    stableID: event.stableID,
                    chordIndex: event.chordIndex,
                    startSubdivision: event.startSubdivision,
                    durationSubdivisions: event.durationSubdivisions,
                    midiNote: event.midiNote,
                    velocity: event.velocity + 0.1,
                    activationThreshold: index == 0 ? 0 : event.activationThreshold,
                    allowedPitchClasses: event.allowedPitchClasses
                )
            }
        )

        let change = DayMusicPlanDiffer.change(
            from: oldPlan,
            to: replacing(oldPlan, bass: newBass)
        )

        XCTAssertNil(change.continuousPlan)
        XCTAssertNotNil(change.structuralPlan)
    }

    func testBassAppearanceAndDisappearanceAreStructuralOnly() throws {
        let oldPlan = try planWithBass()
        let withoutBass = replacing(oldPlan, bass: nil, preservesBass: false)

        for (from, to) in [(oldPlan, withoutBass), (withoutBass, oldPlan)] {
            let change = DayMusicPlanDiffer.change(from: from, to: to)
            XCTAssertNil(change.continuousPlan)
            XCTAssertEqual(change.structuralPlan, to)
        }
    }

    func testBassStructuralChangeAndIndependentMixChangeEmitBothPlans() throws {
        let oldPlan = try planWithBass()
        let oldBass = try XCTUnwrap(oldPlan.bass)
        let alternateInstrument = try XCTUnwrap(
            DayObjectsInstrumentManifest.defaultDescriptors.first {
                $0.category == .bass && $0.id != oldBass.instrumentID
            }
        )
        let changedBass = BassPlan(
            mode: oldBass.mode,
            instrumentID: alternateInstrument.id,
            register: oldBass.register,
            articulation: oldBass.articulation,
            stepsProgress: oldBass.stepsProgress,
            cutoffMultiplier: oldBass.cutoffMultiplier,
            glideMilliseconds: oldBass.glideMilliseconds,
            reverbSend: oldBass.reverbSend,
            ducking: oldBass.ducking,
            events: oldBass.events
        )
        let changedMix = LayerMixPlan(
            rhythmTargetDecibels: oldPlan.mix.rhythmTargetDecibels,
            bassTargetDecibels: oldPlan.mix.bassTargetDecibels,
            harmonyTargetDecibels: oldPlan.mix.harmonyTargetDecibels,
            happeningAggregateTargetDecibels: oldPlan.mix.happeningAggregateTargetDecibels,
            happeningPerVoiceTargetDecibels: oldPlan.mix.happeningPerVoiceTargetDecibels,
            happeningCount: oldPlan.mix.happeningCount,
            leadTargetDecibels: oldPlan.mix.leadTargetDecibels,
            masterTargetDecibelsBeforeLimiter: oldPlan.mix.masterTargetDecibelsBeforeLimiter - 0.1,
            maximumHarmonyDuckingDecibels: oldPlan.mix.maximumHarmonyDuckingDecibels
        )
        let newPlan = replacing(oldPlan, bass: changedBass, mix: changedMix)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
    }

    func testChangingPublishedGrooveModeIsStructuralEvenWhenBassCandidatesMatch() throws {
        let oldPlan = try planWithBass()
        let alternateMode: GrooveMode = oldPlan.groove.mode == .bassPulse ? .bassArp : .bassPulse
        let alternateGroove = GroovePlan(
            mode: alternateMode,
            auxiliaryRetention: oldPlan.groove.auxiliaryRetention,
            maximumAnchorKicksPerBar: oldPlan.groove.maximumAnchorKicksPerBar,
            thinningSeed: oldPlan.groove.thinningSeed
        )
        let newPlan = replacing(oldPlan, groove: alternateGroove)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
    }

    func testEveryGrooveFieldIsStructuralEvenWhenModeIsUnchanged() throws {
        let oldPlan = try planWithBass()
        let oldGroove = oldPlan.groove
        let mutations = [
            GroovePlan(
                mode: oldGroove.mode,
                auxiliaryRetention: oldGroove.auxiliaryRetention - 0.01,
                maximumAnchorKicksPerBar: oldGroove.maximumAnchorKicksPerBar,
                thinningSeed: oldGroove.thinningSeed
            ),
            GroovePlan(
                mode: oldGroove.mode,
                auxiliaryRetention: oldGroove.auxiliaryRetention,
                maximumAnchorKicksPerBar: oldGroove.maximumAnchorKicksPerBar + 1,
                thinningSeed: oldGroove.thinningSeed
            ),
            GroovePlan(
                mode: oldGroove.mode,
                auxiliaryRetention: oldGroove.auxiliaryRetention,
                maximumAnchorKicksPerBar: oldGroove.maximumAnchorKicksPerBar,
                thinningSeed: oldGroove.thinningSeed &+ 1
            ),
        ]

        for groove in mutations {
            let newPlan = replacing(oldPlan, groove: groove)
            let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)
            XCTAssertNil(change.continuousPlan)
            XCTAssertEqual(change.structuralPlan, newPlan)
        }
    }

    func testBassCandidateAndDuckingStructureMutationsAreStructuralOnly() throws {
        let oldPlan = try planWithBass()
        let oldBass = try XCTUnwrap(oldPlan.bass)
        let changedEvent = try XCTUnwrap(oldBass.events.first)
        let changedCandidates = oldBass.events.enumerated().map { index, event in
            guard index == 0 else { return event }
            return BassEventPlan(
                stableID: event.stableID,
                chordIndex: event.chordIndex,
                startSubdivision: event.startSubdivision,
                durationSubdivisions: event.durationSubdivisions,
                midiNote: event.midiNote &+ 1,
                velocity: event.velocity,
                activationThreshold: event.activationThreshold,
                allowedPitchClasses: event.allowedPitchClasses
            )
        }
        XCTAssertNotEqual(changedCandidates.first, changedEvent)
        let variants = [
            BassPlan(
                mode: oldBass.mode == .bassPulse ? .bassArp : .bassPulse,
                instrumentID: oldBass.instrumentID,
                register: oldBass.register,
                articulation: oldBass.articulation,
                stepsProgress: oldBass.stepsProgress,
                cutoffMultiplier: oldBass.cutoffMultiplier,
                glideMilliseconds: oldBass.glideMilliseconds,
                reverbSend: oldBass.reverbSend,
                ducking: oldBass.ducking,
                events: oldBass.events
            ),
            BassPlan(
                mode: oldBass.mode,
                instrumentID: oldBass.instrumentID,
                register: 24...48,
                articulation: oldBass.articulation,
                stepsProgress: oldBass.stepsProgress,
                cutoffMultiplier: oldBass.cutoffMultiplier,
                glideMilliseconds: oldBass.glideMilliseconds,
                reverbSend: oldBass.reverbSend,
                ducking: oldBass.ducking,
                events: oldBass.events
            ),
            BassPlan(
                mode: oldBass.mode,
                instrumentID: oldBass.instrumentID,
                register: oldBass.register,
                articulation: oldBass.articulation == .pulse ? .arpeggio : .pulse,
                stepsProgress: oldBass.stepsProgress,
                cutoffMultiplier: oldBass.cutoffMultiplier,
                glideMilliseconds: oldBass.glideMilliseconds,
                reverbSend: oldBass.reverbSend,
                ducking: oldBass.ducking,
                events: oldBass.events
            ),
            BassPlan(
                mode: oldBass.mode,
                instrumentID: oldBass.instrumentID,
                register: oldBass.register,
                articulation: oldBass.articulation,
                stepsProgress: oldBass.stepsProgress,
                cutoffMultiplier: oldBass.cutoffMultiplier,
                glideMilliseconds: oldBass.glideMilliseconds,
                reverbSend: oldBass.reverbSend,
                ducking: oldBass.ducking,
                events: changedCandidates
            ),
            BassPlan(
                mode: oldBass.mode,
                instrumentID: oldBass.instrumentID,
                register: oldBass.register,
                articulation: oldBass.articulation,
                stepsProgress: oldBass.stepsProgress,
                cutoffMultiplier: oldBass.cutoffMultiplier,
                glideMilliseconds: oldBass.glideMilliseconds,
                reverbSend: oldBass.reverbSend,
                ducking: BassDuckingPlan(
                    maximumAttenuationDecibels: oldBass.ducking.maximumAttenuationDecibels,
                    attackSeconds: oldBass.ducking.attackSeconds + 0.01,
                    holdSeconds: oldBass.ducking.holdSeconds,
                    releaseSeconds: oldBass.ducking.releaseSeconds
                ),
                events: oldBass.events
            ),
            BassPlan(
                mode: oldBass.mode,
                instrumentID: oldBass.instrumentID,
                register: oldBass.register,
                articulation: oldBass.articulation,
                stepsProgress: oldBass.stepsProgress,
                cutoffMultiplier: oldBass.cutoffMultiplier,
                glideMilliseconds: oldBass.glideMilliseconds,
                reverbSend: oldBass.reverbSend,
                ducking: BassDuckingPlan(
                    maximumAttenuationDecibels: oldBass.ducking.maximumAttenuationDecibels,
                    attackSeconds: oldBass.ducking.attackSeconds,
                    holdSeconds: oldBass.ducking.holdSeconds + 0.01,
                    releaseSeconds: oldBass.ducking.releaseSeconds
                ),
                events: oldBass.events
            ),
            BassPlan(
                mode: oldBass.mode,
                instrumentID: oldBass.instrumentID,
                register: oldBass.register,
                articulation: oldBass.articulation,
                stepsProgress: oldBass.stepsProgress,
                cutoffMultiplier: oldBass.cutoffMultiplier,
                glideMilliseconds: oldBass.glideMilliseconds,
                reverbSend: oldBass.reverbSend,
                ducking: BassDuckingPlan(
                    maximumAttenuationDecibels: oldBass.ducking.maximumAttenuationDecibels,
                    attackSeconds: oldBass.ducking.attackSeconds,
                    holdSeconds: oldBass.ducking.holdSeconds,
                    releaseSeconds: oldBass.ducking.releaseSeconds + 0.01
                ),
                events: oldBass.events
            ),
        ]

        for bass in variants {
            let change = DayMusicPlanDiffer.change(from: oldPlan, to: replacing(oldPlan, bass: bass))
            XCTAssertNil(change.continuousPlan)
            XCTAssertNotNil(change.structuralPlan)
        }
    }

    func testSpentColorsChangeIsContinuousGlitchOnly() {
        let oldPlan = makePlan(spentColors: 0)
        let newPlan = makePlan(spentColors: 50)
        XCTAssertNotEqual(oldPlan.glitch, newPlan.glitch)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testGlitchRealizationOnlyChangeIsStructuralOnly() {
        let oldPlan = makePlan(spentColors: 50)
        let oldGlitch = oldPlan.glitch
        let newGlitch = GlitchPlan(
            progress: oldGlitch.progress,
            roles: oldGlitch.roles,
            wowFlutterDepth: oldGlitch.wowFlutterDepth,
            stereoSeparationAddition: oldGlitch.stereoSeparationAddition,
            realization: GlitchRealizationState(
                dropoutSeed: oldGlitch.realization.dropoutSeed &+ 1,
                variationSeed: oldGlitch.realization.variationSeed &+ 1,
                cycleKey: oldGlitch.realization.cycleKey &+ 1,
                counterMapping: oldGlitch.realization.counterMapping
            )
        )
        let newPlan = replacing(oldPlan, glitch: newGlitch)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
    }

    func testGlitchEligibilityOnlyChangeIsStructuralOnly() throws {
        let oldPlan = makePlan(spentColors: 50)
        let oldRole = try XCTUnwrap(oldPlan.glitch.roles.first)
        let changedRole = GlitchRolePlan(
            role: oldRole.role,
            isTimingAnchor: oldRole.isTimingAnchor,
            isGlitchEligible: !oldRole.isGlitchEligible,
            pitchDriftCents: oldRole.pitchDriftCents,
            dropoutProbability: oldRole.dropoutProbability,
            delayTimeInstability: oldRole.delayTimeInstability,
            saturationAmount: oldRole.saturationAmount,
            timingDriftMilliseconds: oldRole.timingDriftMilliseconds
        )
        var roles = oldPlan.glitch.roles
        roles[0] = changedRole
        let newGlitch = GlitchPlan(
            progress: oldPlan.glitch.progress,
            roles: roles,
            wowFlutterDepth: oldPlan.glitch.wowFlutterDepth,
            stereoSeparationAddition: oldPlan.glitch.stereoSeparationAddition,
            realization: oldPlan.glitch.realization
        )
        let newPlan = replacing(oldPlan, glitch: newGlitch)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
    }

    func testDirectorOwnedSaturationAndPercussionTimingChangesAreContinuous() throws {
        let oldPlan = makePlan(spentColors: 50)

        for role in [GlitchRole.lead, .percussion] {
            var roles = oldPlan.glitch.roles
            let index = try XCTUnwrap(roles.firstIndex { $0.role == role })
            let oldRole = roles[index]
            roles[index] = GlitchRolePlan(
                role: oldRole.role,
                isTimingAnchor: oldRole.isTimingAnchor,
                isGlitchEligible: oldRole.isGlitchEligible,
                pitchDriftCents: oldRole.pitchDriftCents,
                dropoutProbability: oldRole.dropoutProbability,
                delayTimeInstability: oldRole.delayTimeInstability,
                saturationAmount: oldRole.saturationAmount + (role == .lead ? 0.01 : 0),
                timingDriftMilliseconds: oldRole.timingDriftMilliseconds + (role == .percussion ? 0.01 : 0)
            )
            let changedGlitch = GlitchPlan(
                progress: oldPlan.glitch.progress,
                roles: roles,
                wowFlutterDepth: oldPlan.glitch.wowFlutterDepth,
                stereoSeparationAddition: oldPlan.glitch.stereoSeparationAddition,
                realization: oldPlan.glitch.realization
            )
            let newPlan = replacing(oldPlan, glitch: changedGlitch)

            let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

            XCTAssertEqual(change.continuousPlan, newPlan)
            XCTAssertNil(change.structuralPlan)
        }
    }

    func testLayerMixOnlyChangeIsContinuousOnly() {
        let oldPlan = makePlan()
        let oldMix = oldPlan.mix
        let newMix = LayerMixPlan(
            rhythmTargetDecibels: oldMix.rhythmTargetDecibels + 0.5,
            bassTargetDecibels: oldMix.bassTargetDecibels,
            harmonyTargetDecibels: oldMix.harmonyTargetDecibels,
            happeningAggregateTargetDecibels: oldMix.happeningAggregateTargetDecibels,
            happeningPerVoiceTargetDecibels: oldMix.happeningPerVoiceTargetDecibels,
            happeningCount: oldMix.happeningCount,
            leadTargetDecibels: oldMix.leadTargetDecibels,
            masterTargetDecibelsBeforeLimiter: oldMix.masterTargetDecibelsBeforeLimiter,
            maximumHarmonyDuckingDecibels: oldMix.maximumHarmonyDuckingDecibels
        )
        let newPlan = replacing(oldPlan, mix: newMix)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
    }

    func testPlanAwareGainDensityChangeRemainsContinuousWithoutStructuralRestart() throws {
        let seed = try XCTUnwrap(
            (UInt64(0)..<10_000).first {
                GroovePlanner.makePlan(remixSeed: $0).mode == .bassPulse
            }
        )
        let oldPlan = makePlan(stepsProgress: 0, remixSeed: seed)
        let newPlan = makePlan(stepsProgress: 1, remixSeed: seed)
        XCTAssertEqual(oldPlan.groove.mode, .bassPulse)
        XCTAssertEqual(newPlan.groove.mode, .bassPulse)
        XCTAssertNotEqual(
            DayObjectsPlanAwareGainCalibration.make(
                grooveMode: oldPlan.groove.mode,
                stepsActivityDensity: oldPlan.rhythm.stepsProgress
            ),
            DayObjectsPlanAwareGainCalibration.make(
                grooveMode: newPlan.groove.mode,
                stepsActivityDensity: newPlan.rhythm.stepsProgress
            )
        )

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
    }

    func testRhythmPlaybackLimitsAreContinuousOnly() {
        let oldPlan = makePlan()
        let variants = [
            rhythm(
                oldPlan.rhythm,
                maximumMicrotimingMilliseconds: oldPlan.rhythm.maximumMicrotimingMilliseconds + 1
            ),
            rhythm(
                oldPlan.rhythm,
                velocityHumanizationRange: -0.04...0.04
            ),
            rhythm(
                oldPlan.rhythm,
                maximumHarmonyDuckingDecibels: oldPlan.rhythm.maximumHarmonyDuckingDecibels + 0.25
            ),
        ]

        for newRhythm in variants {
            let newPlan = replacing(oldPlan, rhythm: newRhythm)
            let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)
            XCTAssertEqual(change.continuousPlan, newPlan)
            XCTAssertNil(change.structuralPlan)
        }
    }

    func testRhythmProbabilityOnlyChangeIsContinuousWithoutStructuralReplacement() throws {
        let oldPlan = makePlan()
        let oldVoice = try XCTUnwrap(oldPlan.rhythm.voices.first)
        var probabilities = oldVoice.stepProbabilities
        probabilities[0] = max(0, probabilities[0] - 0.1)
        let changedVoice = RhythmVoicePlan(
            role: oldVoice.role,
            drumVoice: oldVoice.drumVoice,
            stepProbabilities: probabilities,
            velocityRange: oldVoice.velocityRange,
            microtimingMilliseconds: oldVoice.microtimingMilliseconds,
            roomSend: oldVoice.roomSend,
            activation: oldVoice.activation,
            isTimingAnchor: oldVoice.isTimingAnchor,
            isGlitchEligible: oldVoice.isGlitchEligible
        )
        var voices = oldPlan.rhythm.voices
        voices[0] = changedVoice
        let newRhythm = rhythm(oldPlan.rhythm, voices: voices)
        let newPlan = replacing(oldPlan, rhythm: newRhythm)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
    }

    func testSleepGainChangeWithinOneProgressionBandIsContinuousOnly() {
        let oldPlan = makePlan(sleepProgress: 0.50)
        let newPlan = makePlan(sleepProgress: 0.60)
        XCTAssertEqual(oldPlan.world, newPlan.world)
        XCTAssertNotEqual(oldPlan.harmony, newPlan.harmony)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
    }

    func testSleepThresholdCrossingEmitsContinuousAndStructuralNewestPlan() {
        let oldPlan = makePlan(sleepProgress: 0.35)
        let newPlan = makePlan(sleepProgress: 0.36)
        XCTAssertNotEqual(oldPlan.world.progression, newPlan.world.progression)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testRemixEmitsStructuralPlanAndKeepsExistingHappeningChangesOutOfAddRemove() {
        let oldPlan = makePlan(remixSeed: 0x1)
        let newPlan = makePlan(remixSeed: 0x2)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testExistingHappeningIdentityChangeIsStructuralWithoutLookingLikeAnAddition() {
        let oldPlan = makePlan(remixSeed: 0x1)
        let alternatePlan = makePlan(remixSeed: 0x2)
        let newPlan = DayMusicPlan(
            seed: oldPlan.seed,
            input: oldPlan.input,
            world: oldPlan.world,
            rhythm: oldPlan.rhythm,
            groove: oldPlan.groove,
            bass: oldPlan.bass,
            harmony: oldPlan.harmony,
            happenings: alternatePlan.happenings,
            lead: oldPlan.lead,
            glitch: oldPlan.glitch,
            mix: oldPlan.mix
        )

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testAddingHappeningsUsesOnlyDedicatedCommandsInNewPlanOrder() {
        let oldPlan = makePlan(happeningIDs: ["one", "two"])
        let newPlan = makePlan(happeningIDs: ["one", "two", "three", "four"])

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, Array(newPlan.happenings.suffix(2)))
        XCTAssertEqual(change.addedHappenings.map(\.happeningID), ["three", "four"])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testAddingHappeningPlusBassOnlyMixChangeEmitsBothCommands() {
        let oldPlan = makePlan(happeningIDs: ["one"])
        let generatedNewPlan = makePlan(happeningIDs: ["one", "two"])
        let mix = generatedNewPlan.mix
        let changedMix = LayerMixPlan(
            rhythmTargetDecibels: mix.rhythmTargetDecibels,
            bassTargetDecibels: mix.bassTargetDecibels - 0.5,
            harmonyTargetDecibels: mix.harmonyTargetDecibels,
            happeningAggregateTargetDecibels: mix.happeningAggregateTargetDecibels,
            happeningPerVoiceTargetDecibels: mix.happeningPerVoiceTargetDecibels,
            happeningCount: mix.happeningCount,
            leadTargetDecibels: mix.leadTargetDecibels,
            masterTargetDecibelsBeforeLimiter: mix.masterTargetDecibelsBeforeLimiter,
            maximumHarmonyDuckingDecibels: mix.maximumHarmonyDuckingDecibels
        )
        let newPlan = replacing(generatedNewPlan, mix: changedMix)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings.map(\.happeningID), ["two"])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    func testRemovingHappeningsUsesOnlyDedicatedCommandsInOldPlanOrder() {
        let oldPlan = makePlan(happeningIDs: ["one", "two", "three", "four"])
        let newPlan = makePlan(happeningIDs: ["one", "two"])

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertNil(change.continuousPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, ["three", "four"])
    }

    func testRemovingHappeningPlusBassOnlyMixChangeEmitsBothCommands() {
        let oldPlan = makePlan(happeningIDs: ["one", "two"])
        let generatedNewPlan = makePlan(happeningIDs: ["one"])
        let mix = generatedNewPlan.mix
        let changedMix = LayerMixPlan(
            rhythmTargetDecibels: mix.rhythmTargetDecibels,
            bassTargetDecibels: mix.bassTargetDecibels - 0.5,
            harmonyTargetDecibels: mix.harmonyTargetDecibels,
            happeningAggregateTargetDecibels: mix.happeningAggregateTargetDecibels,
            happeningPerVoiceTargetDecibels: mix.happeningPerVoiceTargetDecibels,
            happeningCount: mix.happeningCount,
            leadTargetDecibels: mix.leadTargetDecibels,
            masterTargetDecibelsBeforeLimiter: mix.masterTargetDecibelsBeforeLimiter,
            maximumHarmonyDuckingDecibels: mix.maximumHarmonyDuckingDecibels
        )
        let newPlan = replacing(generatedNewPlan, mix: changedMix)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, ["two"])
    }

    func testDuplicateHappeningRecordsEmitOneStableDedicatedCommand() throws {
        let oldPlan = makePlan(happeningIDs: [])
        let oneHappeningPlan = makePlan(happeningIDs: ["one"])
        let happening = try XCTUnwrap(oneHappeningPlan.happenings.first)
        let duplicatePlan = DayMusicPlan(
            seed: oneHappeningPlan.seed,
            input: oneHappeningPlan.input,
            world: oneHappeningPlan.world,
            rhythm: oneHappeningPlan.rhythm,
            groove: oneHappeningPlan.groove,
            bass: oneHappeningPlan.bass,
            harmony: oneHappeningPlan.harmony,
            happenings: [happening, happening],
            lead: oneHappeningPlan.lead,
            glitch: oneHappeningPlan.glitch,
            mix: oneHappeningPlan.mix
        )

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: duplicatePlan)

        XCTAssertEqual(change.addedHappenings.map(\.happeningID), ["one"])
    }

    func testStepChangeAndRemixEmitBothNewestPlanExactlyOnce() {
        let oldPlan = makePlan(stepsProgress: 0.15, remixSeed: 0x1)
        let newPlan = makePlan(stepsProgress: 0.85, remixSeed: 0x2)

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertEqual(change.structuralPlan, newPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
    }

    private func makePlan(
        stepsProgress: Double = 0.60,
        sleepProgress: Double = 0.70,
        happeningIDs: [String] = ["one", "two"],
        spentColors: Int = 0,
        remixSeed: UInt64? = nil
    ) -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: DayMusicInput(
                countedSteps: stepsProgress * 10_000,
                stepGoal: 10_000,
                countedSleepHours: sleepProgress * 8,
                sleepGoalHours: 8,
                happeningIDs: happeningIDs,
                spentColors: spentColors
            ),
            remixSeed: remixSeed ?? seed
        )
    }

    private func replacing(
        _ plan: DayMusicPlan,
        rhythm: RhythmPlan? = nil,
        groove: GroovePlan? = nil,
        bass: BassPlan? = nil,
        preservesBass: Bool = true,
        glitch: GlitchPlan? = nil,
        mix: LayerMixPlan? = nil
    ) -> DayMusicPlan {
        DayMusicPlan(
            seed: plan.seed,
            input: plan.input,
            world: plan.world,
            rhythm: rhythm ?? plan.rhythm,
            groove: groove ?? (rhythm ?? plan.rhythm).groove,
            bass: preservesBass ? (bass ?? plan.bass) : bass,
            harmony: plan.harmony,
            happenings: plan.happenings,
            lead: plan.lead,
            glitch: glitch ?? plan.glitch,
            mix: mix ?? plan.mix
        )
    }

    private func planWithBass() throws -> DayMusicPlan {
        for remixSeed in UInt64(0)..<10_000 {
            let plan = makePlan(remixSeed: remixSeed)
            if plan.bass != nil { return plan }
        }
        throw XCTSkip("No Bass Groove seed found")
    }

    private func rhythm(
        _ plan: RhythmPlan,
        kitID: String? = nil,
        voices: [RhythmVoicePlan]? = nil,
        maximumMicrotimingMilliseconds: Double? = nil,
        velocityHumanizationRange: ClosedRange<Double>? = nil,
        maximumHarmonyDuckingDecibels: Double? = nil
    ) -> RhythmPlan {
        RhythmPlan(
            kitID: kitID ?? plan.kitID,
            baseTempoBPM: plan.baseTempoBPM,
            tempoBPM: plan.tempoBPM,
            stepsProgress: plan.stepsProgress,
            family: plan.family,
            patternOffsetSteps: plan.patternOffsetSteps,
            humanizationProfile: plan.humanizationProfile,
            groove: plan.groove,
            realization: plan.realization,
            voices: voices ?? plan.voices,
            maximumSimultaneousAttacks: plan.maximumSimultaneousAttacks,
            maximumFillsPerWindow: plan.maximumFillsPerWindow,
            fillWindowBars: plan.fillWindowBars,
            maximumMicrotimingMilliseconds: maximumMicrotimingMilliseconds
                ?? plan.maximumMicrotimingMilliseconds,
            velocityHumanizationRange: velocityHumanizationRange
                ?? plan.velocityHumanizationRange,
            maximumHarmonyDuckingDecibels: maximumHarmonyDuckingDecibels
                ?? plan.maximumHarmonyDuckingDecibels
        )
    }
}
#endif
