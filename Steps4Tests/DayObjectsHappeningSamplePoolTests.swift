#if DEBUG || INTERNAL_BUILD
import AudioKit
import AVFoundation
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsHappeningSamplePoolTests: XCTestCase {
    func testNewPoolStartsWithAmbientTailDefaultEffects() throws {
        let harness = try preparedHarness()

        assertEffects(harness.pool.metrics.effects, equalTo: .init(
            filterCutoffHz: 7_200,
            delayMix: 0.04,
            delayFeedback: 0.12,
            reverbMix: 0.84
        ))
    }

    func testFourMaximumWetRecipesCannotExceedRecipeBounds() throws {
        let harness = try preparedHarness()
        let maximum = HappeningEffectCommand(
            filterCutoffHz: 7_500,
            delayMix: 0.10,
            delayFeedback: 0.18,
            reverbMix: 0.14
        )

        for recipeID in 1...4 {
            _ = try harness.pool.play(
                sound(id: recipeID, resource: "\(recipeID).wav"),
                gain: 1,
                priority: .birth,
                effects: maximum
            )
        }

        XCTAssertLessThanOrEqual(harness.pool.metrics.effects.delayMix, 0.10)
        XCTAssertLessThanOrEqual(harness.pool.metrics.effects.delayFeedback, 0.18)
        XCTAssertLessThanOrEqual(harness.pool.metrics.effects.reverbMix, 0.14)
        assertEffects(harness.pool.metrics.effects, equalTo: maximum)
    }

    func testStaleHandleCannotStopOrUpdateManualVoiceThatStoleItsSlot() throws {
        let harness = try preparedHarness()
        let automatic = try (1...4).map {
            try harness.pool.play(
                sound(id: $0, resource: "\($0).wav"),
                gain: 0.5,
                priority: .recurrence,
                effects: effects(Double($0))
            )
        }
        let stolen = automatic[0]
        let manual = try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.8,
            priority: .manualAudition,
            effects: effects(5)
        )

        XCTAssertEqual(manual.voiceID, stolen.voiceID)
        XCTAssertNotEqual(manual.generation, stolen.generation)
        let updateCount = harness.voices[manual.voiceID].updateCalls.count

        harness.pool.update(stolen, gain: 0.1, playbackRate: 0.5)
        harness.pool.stop(stolen)

        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 4)
        XCTAssertEqual(harness.voices[manual.voiceID].updateCalls.count, updateCount)
        XCTAssertEqual(harness.voices[manual.voiceID].releaseCount, 0)
    }

    func testOverlappingRecipeEffectsAggregateIndependentOfAttackOrder() throws {
        let firstEffects = effects(1)
        let secondEffects = effects(2)
        let forward = try preparedHarness()
        _ = try forward.pool.play(sound(id: 1, resource: "1.wav"), gain: 1, priority: .birth, effects: firstEffects)
        _ = try forward.pool.play(sound(id: 2, resource: "2.wav"), gain: 1, priority: .manualAudition, effects: secondEffects)

        let reverse = try preparedHarness()
        _ = try reverse.pool.play(sound(id: 2, resource: "2.wav"), gain: 1, priority: .manualAudition, effects: secondEffects)
        _ = try reverse.pool.play(sound(id: 1, resource: "1.wav"), gain: 1, priority: .birth, effects: firstEffects)

        let expected = HappeningEffectCommand(
            filterCutoffHz: 1_500,
            delayMix: 0.15,
            delayFeedback: 0.075,
            reverbMix: 0.225
        )
        assertEffects(forward.pool.metrics.effects, equalTo: expected)
        assertEffects(reverse.pool.metrics.effects, equalTo: expected)
    }

    func testStoppingAndReusingHandlesRecomputesActiveEffectAggregate() throws {
        var now = 10.0
        let harness = try makeHarness(
            recipes: (1...6).map {
                makeRecipe(id: $0, resources: ["\($0).wav"], releaseSeconds: 0.2)
            },
            clock: { now }
        )
        try harness.pool.prepare(recipeIDs: Set((1...6).map(id)))
        let first = try harness.pool.play(sound(id: 1, resource: "1.wav"), gain: 1, priority: .birth, effects: effects(1))
        _ = try harness.pool.play(sound(id: 2, resource: "2.wav"), gain: 1, priority: .manualAudition, effects: effects(2))

        harness.pool.stop(first)
        assertEffects(harness.pool.metrics.effects, equalTo: .init(
            filterCutoffHz: 1_500,
            delayMix: 0.15,
            delayFeedback: 0.075,
            reverbMix: 0.225
        ))

        now += 0.21
        XCTAssertEqual(harness.pool.metrics.effects, effects(2))

        _ = try harness.pool.play(sound(id: 3, resource: "3.wav"), gain: 1, priority: .birth, effects: effects(3))
        XCTAssertEqual(harness.pool.metrics.effects, .init(
            filterCutoffHz: 2_500,
            delayMix: 0.25,
            delayFeedback: 0.125,
            reverbMix: 0.375
        ))
    }

    func testDecodedAttackLevelsAreAttenuatedToOneCommonCeiling() throws {
        let targetAmplitude = Float(pow(10, -25.0 / 20.0))
        let recipes = [
            makeRecipe(id: 1, resources: ["loud.wav"]),
            makeRecipe(id: 2, resources: ["reference.wav"]),
        ]
        let harness = try makeHarness(
            recipes: recipes,
            bufferAmplitudes: [
                "loud.wav": 0.2,
                "reference.wav": targetAmplitude,
            ]
        )
        try harness.pool.prepare(recipeIDs: Set(recipes.map(\.id)))

        let loud = try harness.pool.play(
            sound(id: 1, resource: "loud.wav"),
            gain: 1,
            priority: .manualAudition
        )
        let reference = try harness.pool.play(
            sound(id: 2, resource: "reference.wav"),
            gain: 1,
            priority: .manualAudition
        )
        let loudGain = try XCTUnwrap(harness.voices[loud.voiceID].playCalls.last?.gain)
        let referenceGain = try XCTUnwrap(harness.voices[reference.voiceID].playCalls.last?.gain)

        XCTAssertEqual(loudGain * 0.2, referenceGain * Double(targetAmplitude), accuracy: 0.000_001)
        XCTAssertLessThan(loudGain, referenceGain)
    }

    func testRejectedPlayLeavesSharedEffectAggregateUnchanged() throws {
        let harness = try preparedHarness()
        for recipeID in 1...4 {
            _ = try harness.pool.play(
                sound(id: recipeID, resource: "\(recipeID).wav"),
                gain: 1,
                priority: .manualAudition,
                effects: effects(Double(recipeID))
            )
        }
        let before = harness.pool.metrics.effects

        XCTAssertThrowsError(try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 1,
            priority: .recurrence,
            effects: .init(filterCutoffHz: 18_000, delayMix: 1, delayFeedback: 0.9, reverbMix: 1)
        ))

        XCTAssertEqual(harness.pool.metrics.effects, before)
    }

    func testExplicitGlobalEffectUpdateDoesNotSuppressLaterHandleAggregation() throws {
        let harness = try preparedHarness()
        harness.pool.applyEffects(effects(6), rampSeconds: 0.25)

        _ = try harness.pool.play(
            sound(id: 1, resource: "1.wav"),
            gain: 1,
            priority: .birth,
            effects: effects(1)
        )

        XCTAssertEqual(harness.pool.metrics.effects, effects(1))
    }

    func testHandleUpdateChangesGainAndRateNonCumulativelyAndStaleUpdateIsIgnored() throws {
        let harness = try preparedHarness()
        let original = try harness.pool.play(
            sound(id: 1, resource: "1.wav"),
            gain: 0.5,
            priority: .recurrence,
            effects: effects(1)
        )
        harness.pool.update(original, gain: 0.25, playbackRate: 1.01)
        let update = try XCTUnwrap(harness.voices[original.voiceID].updateCalls.last)
        XCTAssertEqual(update.gain, 0.25 * pow(10, -4.5 / 20), accuracy: 1e-12)
        XCTAssertEqual(update.playbackRate, 1.01, accuracy: 1e-12)

        for recipeID in 2...4 {
            _ = try harness.pool.play(sound(id: recipeID, resource: "\(recipeID).wav"), gain: 1, priority: .recurrence, effects: effects(Double(recipeID)))
        }
        let replacement = try harness.pool.play(sound(id: 5, resource: "5.wav"), gain: 1, priority: .manualAudition, effects: effects(5))
        let count = harness.voices[replacement.voiceID].updateCalls.count
        harness.pool.update(original, gain: 0, playbackRate: 2)
        XCTAssertEqual(harness.voices[replacement.voiceID].updateCalls.count, count)
    }

    func testAllocatesExactlyFourPlayersAndNeverCreatesAFifthOnPlay() throws {
        let harness = try makeHarness(recipes: [makeRecipe(id: 1, resources: ["one.wav"])])

        XCTAssertEqual(harness.pool.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(harness.voices.count, 4)
        let identities = harness.pool.metrics.fixedPlayerIdentities

        try harness.pool.prepare(recipeIDs: [id(1)])
        for _ in 0..<20 {
            let voiceID = try harness.pool.play(sound(id: 1, resource: "one.wav"), gain: 0.5, priority: .manualAudition)
            harness.pool.stop(voiceID)
        }

        XCTAssertEqual(harness.voices.count, 4)
        XCTAssertEqual(harness.pool.metrics.fixedPlayerIdentities, identities)
    }

    func testReleasedVoiceIsReusedBeforeAnActiveVoiceIsStolen() throws {
        let harness = try preparedHarness()
        let voiceIDs = try (1...4).map {
            try harness.pool.play(sound(id: $0, resource: "\($0).wav"), gain: 0.5)
        }
        harness.pool.stop(voiceIDs[2])

        let reused = try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.7,
            priority: .birth
        )

        XCTAssertEqual(reused.voiceID, voiceIDs[2].voiceID)
        XCTAssertNotEqual(reused.generation, voiceIDs[2].generation)
        XCTAssertEqual(harness.pool.metrics.stealCount, 0)
    }

    func testBirthAndManualAuditionStealTheOldestEligibleRecurrences() throws {
        let harness = try preparedHarness()
        let recurrenceIDs = try (1...4).map {
            try harness.pool.play(sound(id: $0, resource: "\($0).wav"), gain: 0.5)
        }

        let birth = try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.6,
            priority: .birth
        )
        let manual = try harness.pool.play(
            sound(id: 6, resource: "6.wav"),
            gain: 0.7,
            priority: .manualAudition
        )

        XCTAssertEqual(birth.voiceID, recurrenceIDs[0].voiceID)
        XCTAssertEqual(manual.voiceID, recurrenceIDs[1].voiceID)
        XCTAssertEqual(harness.pool.metrics.stealCount, 2)
    }

    func testRecurrenceCannotStealEqualOrHigherPriorityVoices() throws {
        let harness = try preparedHarness()
        for recipeID in 1...4 {
            _ = try harness.pool.play(
                sound(id: recipeID, resource: "\(recipeID).wav"),
                gain: 0.7,
                priority: recipeID == 1 ? .manualAudition : .birth
            )
        }

        XCTAssertThrowsError(try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.4,
            priority: .recurrence
        )) {
            XCTAssertEqual($0 as? HappeningSamplePoolError, .noEligibleVoice)
        }
        XCTAssertEqual(harness.pool.metrics.stealCount, 0)
    }

    func testCompatibilityPlayDefaultsToRecurrencePriority() throws {
        let harness = try preparedHarness()
        for recipeID in 1...4 {
            _ = try harness.pool.play(sound(id: recipeID, resource: "\(recipeID).wav"), gain: 0.5)
        }

        XCTAssertThrowsError(try harness.pool.play(
            sound(id: 5, resource: "5.wav"),
            gain: 0.5,
            priority: .recurrence
        )) {
            XCTAssertEqual($0 as? HappeningSamplePoolError, .noEligibleVoice)
        }
    }

    func testPreparationReusesDecodedBuffersAndAccountsBytesOnce() throws {
        let recipes = [
            makeRecipe(id: 1, resources: ["shared.wav", "one.wav"]),
            makeRecipe(id: 2, resources: ["shared.wav", "two.wav"]),
        ]
        let harness = try makeHarness(recipes: recipes, bytesPerResource: 4_096)

        try harness.pool.prepare(recipeIDs: [id(1), id(2)])
        try harness.pool.prepare(recipeIDs: [id(1), id(2)])

        XCTAssertEqual(harness.decodeCounts, [
            "one.wav": 1,
            "shared.wav": 1,
            "two.wav": 1,
        ])
        XCTAssertEqual(harness.pool.metrics.decodedBufferCount, 3)
        XCTAssertEqual(harness.pool.metrics.decodedByteCount, 12_288)
        XCTAssertEqual(harness.pool.metrics.availableRecipeIDs, [id(1), id(2)])
    }

    func testDecodeFailureIsIsolatedToItsRecipe() throws {
        let recipes = [
            makeRecipe(id: 1, resources: ["good.wav"]),
            makeRecipe(id: 2, resources: ["bad.wav"]),
        ]
        let harness = try makeHarness(recipes: recipes, failingResources: ["bad.wav"])

        try harness.pool.prepare(recipeIDs: [id(1), id(2)])

        XCTAssertEqual(harness.pool.metrics.availableRecipeIDs, [id(1)])
        XCTAssertEqual(harness.pool.metrics.unavailableRecipeIDs, [id(2)])
        XCTAssertNoThrow(try harness.pool.play(sound(id: 1, resource: "good.wav"), gain: 0.5))
        XCTAssertThrowsError(try harness.pool.play(sound(id: 2, resource: "bad.wav"), gain: 0.5)) {
            XCTAssertEqual($0 as? HappeningSamplePoolError, .recipeUnavailable(id(2)))
        }
    }

    func testReleaseAllStopsEveryVoiceAndClearsActiveMetrics() throws {
        let harness = try preparedHarness()
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 0)
        for recipeID in 1...4 {
            _ = try harness.pool.play(sound(id: recipeID, resource: "\(recipeID).wav"), gain: 0.5)
        }

        harness.pool.releaseAll()

        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 0)
        XCTAssertTrue(harness.voices.allSatisfy { $0.stopCount == 1 })
    }

    func testGracefulStopWithCompletedReleaseConvergesToIdle() throws {
        let recipe = makeRecipe(id: 1, resources: ["one.wav"], releaseSeconds: 0)
        let harness = try makeHarness(recipes: [recipe])
        try harness.pool.prepare(recipeIDs: [recipe.id])
        let voiceID = try harness.pool.play(sound(id: 1, resource: "one.wav"), gain: 0.5)

        harness.pool.stop(voiceID)

        XCTAssertEqual(harness.pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 0)
        XCTAssertEqual(harness.voices[voiceID.voiceID].releaseCount, 1)
        XCTAssertEqual(harness.voices[voiceID.voiceID].stopCount, 1)
    }

    func testGracefulStopUsesInjectedMonotonicDeadlineBeforeConvergingToIdle() throws {
        var now = 10.0
        let recipe = makeRecipe(id: 1, resources: ["one.wav"], releaseSeconds: 0.25)
        let harness = try makeHarness(recipes: [recipe], clock: { now })
        try harness.pool.prepare(recipeIDs: [recipe.id])
        let voiceID = try harness.pool.play(sound(id: 1, resource: "one.wav"), gain: 0.5)

        harness.pool.stop(voiceID)
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 1)
        XCTAssertEqual(harness.voices[voiceID.voiceID].stopCount, 0)

        now += 0.24
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 1)
        now += 0.02
        XCTAssertEqual(harness.pool.metrics.releasingVoiceCount, 0)
        XCTAssertEqual(harness.voices[voiceID.voiceID].stopCount, 1)
    }

    func testProductionHandleUpdateTransposesFundamentalToResolvedTarget() throws {
        let previousChannelCount = Settings.channelCount
        Settings.channelCount = 1
        defer { Settings.channelCount = previousChannelCount }
        let recipeID = id(1)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let source = try XCTUnwrap(recipe.sources.first(where: { $0.rootMIDI == 72 }))
        let targetMIDI: UInt8 = 74
        let targetRate = pow(2, Double(Int(targetMIDI) - Int(source.rootMIDI)) / 12)
        let pool = DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))
        try pool.prepare(recipeIDs: [recipeID])
        let dryEffects = HappeningEffectCommand(
            filterCutoffHz: 18_000,
            delayMix: 0,
            delayFeedback: 0,
            reverbMix: 0
        )

        let engine = AudioEngine()
        engine.output = pool.output
        _ = engine.startTest(totalDuration: 0.6)
        let handle = try pool.play(.init(
            recipeID: recipeID,
            resourceName: source.resourceName,
            sourceRootMIDI: source.rootMIDI,
            targetMIDI: targetMIDI,
            playbackRate: 1,
            resonantFilterHz: nil
        ), gain: 1, priority: .manualAudition, effects: dryEffects)
        pool.update(handle, gain: 1, playbackRate: targetRate)

        let rendered = engine.render(duration: 0.6)
        let sourceHz = midiFrequency(source.rootMIDI)
        let targetHz = midiFrequency(targetMIDI)

        XCTAssertGreaterThan(spectralMagnitude(rendered, frequency: targetHz),
                             spectralMagnitude(rendered, frequency: sourceHz) * 1.5)
        XCTAssertGreaterThan(rms(rendered), 0.000_1)
    }

    func testProductionSharedDelayAndReverbCreateAudibleTail() throws {
        let recipeID = id(1)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let source = try XCTUnwrap(recipe.sources.first)
        let sound = ResolvedHappeningSound(
            recipeID: recipeID,
            resourceName: source.resourceName,
            sourceRootMIDI: source.rootMIDI,
            targetMIDI: source.rootMIDI,
            playbackRate: 1,
            resonantFilterHz: nil
        )
        let dry = try renderProduction(
            recipeIDs: [recipeID],
            sounds: [sound],
            duration: 1.5,
            effects: .init(filterCutoffHz: 18_000, delayMix: 0, delayFeedback: 0, reverbMix: 0)
        )
        let wet = try renderProduction(
            recipeIDs: [recipeID],
            sounds: [sound],
            duration: 1.5,
            effects: .init(filterCutoffHz: 18_000, delayMix: 0.8, delayFeedback: 0.65, reverbMix: 0.8)
        )

        let tailStart = Int(1.1 * wet.format.sampleRate)
        XCTAssertGreaterThan(rms(wet, startingAt: tailStart), 0.000_1)
        XCTAssertGreaterThan(differenceRMS(wet, dry), 0.001)
    }

    func testProductionSpatialMixPushesTheDryTransientBehindTheReverb() throws {
        let recipeID = id(1)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let source = try XCTUnwrap(recipe.sources.first)
        let sound = ResolvedHappeningSound(
            recipeID: recipeID,
            resourceName: source.resourceName,
            sourceRootMIDI: source.rootMIDI,
            targetMIDI: source.rootMIDI,
            playbackRate: 1,
            resonantFilterHz: nil
        )
        let dry = try renderProduction(
            recipeIDs: [recipeID],
            sounds: [sound],
            duration: 1,
            effects: .init(filterCutoffHz: 18_000, delayMix: 0, delayFeedback: 0, reverbMix: 0)
        )
        let spatial = try renderProduction(
            recipeIDs: [recipeID],
            sounds: [sound],
            duration: 1,
            effects: .init(
                filterCutoffHz: recipe.filterEndHz,
                delayMix: recipe.delayMix,
                delayFeedback: recipe.delayFeedback,
                reverbMix: recipe.reverbMix
            )
        )

        XCTAssertLessThan(
            rms(spatial, from: 0, to: 0.25),
            rms(dry, from: 0, to: 0.25) * 0.45
        )
    }

    func testProductionCatalogReverbRemainsAudibleSevenSecondsAfterAttack() throws {
        let recipeID = id(1)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let source = try XCTUnwrap(recipe.sources.first)
        let sound = ResolvedHappeningSound(
            recipeID: recipeID,
            resourceName: source.resourceName,
            sourceRootMIDI: source.rootMIDI,
            targetMIDI: source.rootMIDI,
            playbackRate: 1,
            resonantFilterHz: nil
        )
        let spatial = try renderProduction(
            recipeIDs: [recipeID],
            sounds: [sound],
            duration: 8,
            effects: .init(
                filterCutoffHz: recipe.filterEndHz,
                delayMix: recipe.delayMix,
                delayFeedback: recipe.delayFeedback,
                reverbMix: recipe.reverbMix
            )
        )

        XCTAssertGreaterThan(rms(spatial, from: 7, to: 8), 0.000_01)
    }

    func testSharedEffectsAreSanitizedAndRampWithoutAllocatingPlayers() throws {
        let harness = try preparedHarness()
        let identities = harness.pool.metrics.fixedPlayerIdentities

        harness.pool.applyEffects(.init(
            filterCutoffHz: .infinity,
            delayMix: -1,
            delayFeedback: 99,
            reverbMix: 2
        ), rampSeconds: 99)

        XCTAssertEqual(harness.pool.metrics.effects, .init(
            filterCutoffHz: 80,
            delayMix: 0,
            delayFeedback: DayObjectsAudioParameters.maximumDelayFeedback,
            reverbMix: 1
        ))
        XCTAssertEqual(harness.pool.metrics.lastEffectRampSeconds, 2)
        XCTAssertEqual(harness.pool.metrics.fixedPlayerIdentities, identities)
        XCTAssertEqual(harness.voices.count, 4)
    }

    func testBackendReceivesPreparedBufferRateGainAndEnvelope() throws {
        let recipe = makeRecipe(id: 1, resources: ["one.wav"], releaseSeconds: 0.4)
        let harness = try makeHarness(recipes: [recipe])
        try harness.pool.prepare(recipeIDs: [recipe.id])
        let resolved = ResolvedHappeningSound(
            recipeID: recipe.id,
            resourceName: "one.wav",
            sourceRootMIDI: 60,
            targetMIDI: 64,
            playbackRate: 1.25,
            resonantFilterHz: nil
        )

        let voiceID = try harness.pool.play(resolved, gain: 0.5, priority: .birth)
        let call = try XCTUnwrap(harness.voices[voiceID.voiceID].playCalls.last)

        XCTAssertTrue(call.buffer === harness.loadedBuffers["one.wav"])
        XCTAssertEqual(call.playbackRate, 1.25, accuracy: 1e-12)
        XCTAssertEqual(
            call.gain,
            0.5 * pow(10, -4.5 / 20),
            accuracy: 1e-12,
            "Happening sources must retain 4.5 dB of ambient headroom"
        )
        XCTAssertEqual(call.attackSeconds, recipe.attackSeconds, accuracy: 1e-12)
        XCTAssertEqual(call.releaseSeconds, 0.4, accuracy: 1e-12)
        XCTAssertNil(call.resonantFilterHz)
    }

    func testResonantTargetsArePerVoiceAndNonResonantReuseResetsTheBackend() throws {
        let harness = try preparedHarness()
        let low = ResolvedHappeningSound(recipeID: id(1), resourceName: "1.wav", sourceRootMIDI: nil, targetMIDI: 60, playbackRate: 1, resonantFilterHz: 261.63)
        let high = ResolvedHappeningSound(recipeID: id(2), resourceName: "2.wav", sourceRootMIDI: nil, targetMIDI: 67, playbackRate: 1, resonantFilterHz: 392)

        let lowVoice = try harness.pool.play(low, gain: 0.5, priority: .birth)
        let highVoice = try harness.pool.play(high, gain: 0.5, priority: .birth)
        XCTAssertEqual(harness.voices[lowVoice.voiceID].playCalls.last?.resonantFilterHz, 261.63)
        XCTAssertEqual(harness.voices[highVoice.voiceID].playCalls.last?.resonantFilterHz, 392)

        harness.pool.stop(lowVoice)
        let reused = try harness.pool.play(
            sound(id: 3, resource: "3.wav"),
            gain: 0.5,
            priority: .manualAudition
        )
        XCTAssertEqual(reused.voiceID, lowVoice.voiceID)
        XCTAssertNotEqual(reused.generation, lowVoice.generation)
        XCTAssertNil(harness.voices[reused.voiceID].playCalls.last?.resonantFilterHz)
        XCTAssertEqual(harness.voices[highVoice.voiceID].playCalls.last?.resonantFilterHz, 392)
    }

    func testProductionResonantVoicesCreateIndependentPeaks() throws {
        let recipeID = id(25)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let source = try XCTUnwrap(recipe.sources.first)
        let lowTarget = 261.63
        let highTarget = 392.00
        let base = ResolvedHappeningSound(
            recipeID: recipeID,
            resourceName: source.resourceName,
            sourceRootMIDI: nil,
            targetMIDI: nil,
            playbackRate: 1,
            resonantFilterHz: nil
        )
        let baseline = try renderProduction(
            recipeIDs: [recipeID],
            sounds: [base, base],
            duration: 0.8
        )
        let resonant = try renderProduction(
            recipeIDs: [recipeID],
            sounds: [
                .init(recipeID: recipeID, resourceName: source.resourceName, sourceRootMIDI: nil, targetMIDI: 60, playbackRate: 1, resonantFilterHz: lowTarget),
                .init(recipeID: recipeID, resourceName: source.resourceName, sourceRootMIDI: nil, targetMIDI: 67, playbackRate: 1, resonantFilterHz: highTarget),
            ],
            duration: 0.8
        )

        XCTAssertGreaterThan(spectralMagnitude(resonant, frequency: lowTarget),
                             spectralMagnitude(baseline, frequency: lowTarget) * 1.5)
        XCTAssertGreaterThan(spectralMagnitude(resonant, frequency: highTarget),
                             spectralMagnitude(baseline, frequency: highTarget) * 1.5)
    }

    func testProductionCatalogDecodesWithinFortyEightMiB() throws {
        let pool = DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))

        try pool.prepare(recipeIDs: Set(HappeningSoundCatalog.recipes.map(\.id)))

        XCTAssertEqual(pool.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(pool.metrics.availableRecipeIDs.count, 30)
        XCTAssertEqual(pool.metrics.unavailableRecipeIDs, [])
        XCTAssertEqual(pool.metrics.decodedBufferCount, 102)
        XCTAssertLessThanOrEqual(pool.metrics.decodedByteCount, 48 * 1_024 * 1_024)
    }

    private func preparedHarness() throws -> PoolHarness {
        let recipes = (1...6).map { makeRecipe(id: $0, resources: ["\($0).wav"]) }
        let harness = try makeHarness(recipes: recipes)
        try harness.pool.prepare(recipeIDs: Set(recipes.map(\.id)))
        return harness
    }

    private func makeHarness(
        recipes: [HappeningSoundRecipe],
        bytesPerResource: Int = 1_024,
        failingResources: Set<String> = [],
        bufferAmplitudes: [String: Float] = [:],
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) throws -> PoolHarness {
        try PoolHarness(
            recipes: recipes,
            bytesPerResource: bytesPerResource,
            failingResources: failingResources,
            bufferAmplitudes: bufferAmplitudes,
            clock: clock
        )
    }

    private func makeRecipe(
        id rawID: Int,
        resources: [String],
        releaseSeconds: Double = 0.2
    ) -> HappeningSoundRecipe {
        HappeningSoundRecipe(
            id: id(rawID),
            label: String(format: "%02d", rawID),
            family: .texture,
            sources: resources.enumerated().map { index, resource in
                .init(resourceName: resource, rootMIDI: UInt8(60 + index), sha256: String(repeating: "a", count: 64))
            },
            pitch: .unpitched,
            gainDB: -12,
            attackSeconds: 0.01,
            releaseSeconds: releaseSeconds,
            delayMix: 0.1,
            delayFeedback: 0.2,
            reverbMix: 0.15,
            filterStartHz: 8_000,
            filterEndHz: 4_000
        )
    }

    private func sound(id rawID: Int, resource: String) -> ResolvedHappeningSound {
        .init(
            recipeID: id(rawID),
            resourceName: resource,
            sourceRootMIDI: nil,
            targetMIDI: nil,
            playbackRate: 1,
            resonantFilterHz: nil
        )
    }

    private func id(_ rawValue: Int) -> HappeningSoundRecipeID {
        HappeningSoundRecipeID(rawValue: rawValue)!
    }

    private func effects(_ value: Double) -> HappeningEffectCommand {
        .init(
            filterCutoffHz: value * 1_000,
            delayMix: value * 0.1,
            delayFeedback: value * 0.05,
            reverbMix: value * 0.15
        )
    }

    private func midiFrequency(_ midi: UInt8) -> Double {
        440 * pow(2, (Double(midi) - 69) / 12)
    }

    private func spectralMagnitude(_ buffer: AVAudioPCMBuffer, frequency: Double) -> Double {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let sampleRate = buffer.format.sampleRate
        let start = min(Int(buffer.frameLength) / 10, Int(buffer.frameLength))
        let count = Int(buffer.frameLength) - start
        guard count > 0 else { return 0 }
        var real = 0.0
        var imaginary = 0.0
        for index in 0..<count {
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            let sample = Double(samples[start + index])
            real += sample * cos(phase)
            imaginary -= sample * sin(phase)
        }
        return hypot(real, imaginary)
    }

    private func rms(_ buffer: AVAudioPCMBuffer, startingAt requestedStart: Int = 0) -> Double {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let start = min(max(requestedStart, 0), Int(buffer.frameLength))
        let count = Int(buffer.frameLength) - start
        guard count > 0 else { return 0 }
        let sum = (start..<Int(buffer.frameLength)).reduce(0.0) {
            $0 + Double(samples[$1] * samples[$1])
        }
        return sqrt(sum / Double(count))
    }

    private func rms(
        _ buffer: AVAudioPCMBuffer,
        from startSeconds: Double,
        to endSeconds: Double
    ) -> Double {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let sampleRate = buffer.format.sampleRate
        let start = min(max(Int(startSeconds * sampleRate), 0), Int(buffer.frameLength))
        let end = min(max(Int(endSeconds * sampleRate), start), Int(buffer.frameLength))
        guard end > start else { return 0 }
        let sum = (start..<end).reduce(0.0) {
            $0 + Double(samples[$1] * samples[$1])
        }
        return sqrt(sum / Double(end - start))
    }

    private func differenceRMS(_ lhs: AVAudioPCMBuffer, _ rhs: AVAudioPCMBuffer) -> Double {
        guard let left = lhs.floatChannelData?[0],
              let right = rhs.floatChannelData?[0] else { return 0 }
        let count = min(Int(lhs.frameLength), Int(rhs.frameLength))
        guard count > 0 else { return 0 }
        let sum = (0..<count).reduce(0.0) {
            let difference = Double(left[$1] - right[$1])
            return $0 + difference * difference
        }
        return sqrt(sum / Double(count))
    }

    private func assertEffects(
        _ actual: HappeningEffectCommand,
        equalTo expected: HappeningEffectCommand,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.filterCutoffHz, expected.filterCutoffHz, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual.delayMix, expected.delayMix, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual.delayFeedback, expected.delayFeedback, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual.reverbMix, expected.reverbMix, accuracy: 1e-12, file: file, line: line)
    }

    private func renderProduction(
        recipeIDs: Set<HappeningSoundRecipeID>,
        sounds: [ResolvedHappeningSound],
        duration: TimeInterval,
        effects: HappeningEffectCommand = .init(
            filterCutoffHz: 18_000,
            delayMix: 0,
            delayFeedback: 0,
            reverbMix: 0
        )
    ) throws -> AVAudioPCMBuffer {
        let pool = DayObjectsHappeningSamplePool(bundle: Bundle(for: type(of: self)))
        try pool.prepare(recipeIDs: recipeIDs)
        pool.applyEffects(effects, rampSeconds: 0)
        let engine = AudioEngine()
        engine.output = pool.output
        _ = engine.startTest(totalDuration: duration)
        for sound in sounds {
            _ = try pool.play(
                sound,
                gain: 1,
                priority: .manualAudition,
                effects: effects
            )
        }
        return engine.render(duration: duration)
    }
}

@MainActor
private final class PoolHarness {
    private let recorder: PoolHarnessRecorder
    var decodeCounts: [String: Int] { recorder.decodeCounts }
    var loadedBuffers: [String: AVAudioPCMBuffer] { recorder.loadedBuffers }
    var voices: [FakeHappeningVoice] { recorder.voices }
    let pool: DayObjectsHappeningSamplePool

    init(
        recipes: [HappeningSoundRecipe],
        bytesPerResource: Int,
        failingResources: Set<String>,
        bufferAmplitudes: [String: Float],
        clock: @escaping () -> TimeInterval
    ) throws {
        let recorder = PoolHarnessRecorder()
        self.recorder = recorder
        pool = DayObjectsHappeningSamplePool(
            recipes: recipes,
            resourceResolver: { URL(fileURLWithPath: "/test/\($0)") },
            bufferLoader: { url in
                let resource = url.lastPathComponent
                recorder.decodeCounts[resource, default: 0] += 1
                if failingResources.contains(resource) { throw PoolTestFailure() }
                let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
                let frames = AVAudioFrameCount(max(bytesPerResource / MemoryLayout<Float>.size, 1))
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
                buffer.frameLength = frames
                if let amplitude = bufferAmplitudes[resource],
                   let samples = buffer.floatChannelData?[0] {
                    for frame in 0..<Int(frames) { samples[frame] = amplitude }
                }
                recorder.loadedBuffers[resource] = buffer
                return .init(buffer: buffer, decodedByteCount: bytesPerResource)
            },
            voiceFactory: { voiceID in
                let voice = FakeHappeningVoice(voiceID: voiceID)
                recorder.voices.append(voice)
                return voice
            },
            clock: clock
        )
    }
}

@MainActor
private final class PoolHarnessRecorder {
    var decodeCounts: [String: Int] = [:]
    var loadedBuffers: [String: AVAudioPCMBuffer] = [:]
    var voices: [FakeHappeningVoice] = []
}

private struct PoolTestFailure: Error {}

@MainActor
private final class FakeHappeningVoice: DayObjectsHappeningSampleVoiceBackend {
    let voiceID: Int
    private let mixer = Mixer()
    var output: Node { mixer }
    private(set) var playCount = 0
    private(set) var playCalls: [FakeHappeningVoiceCall] = []
    private(set) var releaseCount = 0
    private(set) var stopCount = 0
    private(set) var updateCalls: [(gain: Double, playbackRate: Double, rampSeconds: Double)] = []

    init(voiceID: Int) { self.voiceID = voiceID }

    func play(
        buffer: AVAudioPCMBuffer,
        playbackRate: Double,
        gain: Double,
        attackSeconds: Double,
        releaseSeconds: Double,
        resonantFilterHz: Double?
    ) {
        playCount += 1
        playCalls.append(.init(
            buffer: buffer,
            playbackRate: playbackRate,
            gain: gain,
            attackSeconds: attackSeconds,
            releaseSeconds: releaseSeconds,
            resonantFilterHz: resonantFilterHz
        ))
    }

    func release() { releaseCount += 1 }
    func stop() { stopCount += 1 }
    func update(gain: Double, playbackRate: Double, rampSeconds: Double) {
        updateCalls.append((gain, playbackRate, rampSeconds))
    }
}

private struct FakeHappeningVoiceCall {
    let buffer: AVAudioPCMBuffer
    let playbackRate: Double
    let gain: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let resonantFilterHz: Double?
}

private extension DayObjectsHappeningSamplePoolProtocol {
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority
    ) throws -> HappeningPlaybackHandle {
        try play(
            sound,
            gain: gain,
            priority: priority,
            effects: .init(filterCutoffHz: 8_000, delayMix: 0, delayFeedback: 0, reverbMix: 0)
        )
    }

    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double
    ) throws -> HappeningPlaybackHandle {
        try play(sound, gain: gain, priority: .recurrence)
    }
}
#endif
