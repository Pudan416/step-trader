#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayMusicPlanDifferTests: XCTestCase {
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

        let change = DayMusicPlanDiffer.change(from: oldPlan, to: newPlan)

        XCTAssertEqual(change.continuousPlan, newPlan)
        XCTAssertNil(change.structuralPlan)
        XCTAssertEqual(change.addedHappenings, [])
        XCTAssertEqual(change.removedHappeningIDs, [])
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

    func testAddingHappeningPlusIndependentMixChangeEmitsBothCommands() {
        let oldPlan = makePlan(happeningIDs: ["one"])
        let generatedNewPlan = makePlan(happeningIDs: ["one", "two"])
        let mix = generatedNewPlan.mix
        let changedMix = LayerMixPlan(
            rhythmTargetDecibels: mix.rhythmTargetDecibels + 0.5,
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

    func testRemovingHappeningPlusIndependentMixChangeEmitsBothCommands() {
        let oldPlan = makePlan(happeningIDs: ["one", "two"])
        let generatedNewPlan = makePlan(happeningIDs: ["one"])
        let mix = generatedNewPlan.mix
        let changedMix = LayerMixPlan(
            rhythmTargetDecibels: mix.rhythmTargetDecibels,
            harmonyTargetDecibels: mix.harmonyTargetDecibels,
            happeningAggregateTargetDecibels: mix.happeningAggregateTargetDecibels,
            happeningPerVoiceTargetDecibels: mix.happeningPerVoiceTargetDecibels,
            happeningCount: mix.happeningCount,
            leadTargetDecibels: mix.leadTargetDecibels,
            masterTargetDecibelsBeforeLimiter: mix.masterTargetDecibelsBeforeLimiter - 0.5,
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
        glitch: GlitchPlan? = nil,
        mix: LayerMixPlan? = nil
    ) -> DayMusicPlan {
        DayMusicPlan(
            seed: plan.seed,
            input: plan.input,
            world: plan.world,
            rhythm: rhythm ?? plan.rhythm,
            harmony: plan.harmony,
            happenings: plan.happenings,
            lead: plan.lead,
            glitch: glitch ?? plan.glitch,
            mix: mix ?? plan.mix
        )
    }

    private func rhythm(
        _ plan: RhythmPlan,
        voices: [RhythmVoicePlan]? = nil,
        maximumMicrotimingMilliseconds: Double? = nil,
        velocityHumanizationRange: ClosedRange<Double>? = nil,
        maximumHarmonyDuckingDecibels: Double? = nil
    ) -> RhythmPlan {
        RhythmPlan(
            baseTempoBPM: plan.baseTempoBPM,
            tempoBPM: plan.tempoBPM,
            stepsProgress: plan.stepsProgress,
            family: plan.family,
            patternOffsetSteps: plan.patternOffsetSteps,
            humanizationProfile: plan.humanizationProfile,
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
