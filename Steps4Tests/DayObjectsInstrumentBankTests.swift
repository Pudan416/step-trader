import Foundation
import XCTest
@testable import Steps4

private let testHappeningEffects = HappeningEffectCommand(
    filterCutoffHz: 8_000,
    delayMix: 0,
    delayFeedback: 0,
    reverbMix: 0
)

@MainActor
final class DayObjectsInstrumentBankTests: XCTestCase {
    func testWorldRecyclePreservesNewerSchedulerAndManualSharedHappeningsAfterExactOldCleanup() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: .playbackWorld)
        let oldWorld = PlaybackWorldBank(instrumentBank: pair.bankA)
        let newWorld = PlaybackWorldBank(instrumentBank: pair.bankB)
        try oldWorld.prepare()
        try newWorld.prepare()
        let tonalWorld = lifecycleWorld()
        let chord = try XCTUnwrap(tonalWorld.progression.first)
        let oldScheduler = HappeningScheduler(worldBank: oldWorld)
        let newScheduler = HappeningScheduler(worldBank: newWorld)
        try oldScheduler.configure(plans: [], tonalWorld: tonalWorld, remixSeed: 1)
        try newScheduler.configure(plans: [], tonalWorld: tonalWorld, remixSeed: 2)
        try oldScheduler.start()
        try newScheduler.start()

        let oldPlan = lifecycleHappeningPlan(id: "old", recipeRawValue: 1)
        let newPlan = lifecycleHappeningPlan(id: "new", recipeRawValue: 2)
        try oldScheduler.add(oldPlan, currentChord: chord, playBirth: true)
        try newScheduler.add(newPlan, currentChord: chord, playBirth: true)

        let pool = oldWorld.happenings
        XCTAssertTrue(pool === newWorld.happenings)
        let manualRecipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: lifecycleRecipeID(3)))
        let manualSound = HappeningPitchResolver.resolve(
            recipe: manualRecipe,
            chord: chord,
            tonalWorld: tonalWorld
        )
        let manualHandle = try pool.play(
            manualSound,
            gain: 1,
            priority: .manualAudition,
            effects: lifecycleEffects(for: manualRecipe)
        )
        XCTAssertEqual(pool.metrics.activeVoiceCount, 3)

        oldScheduler.remove(id: oldPlan.happeningID)
        let survivingEffects = pool.metrics.effects
        XCTAssertEqual(oldScheduler.metrics.activeVoiceCount, 0)
        XCTAssertEqual(newScheduler.metrics.activeVoiceCount, 1)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)

        oldWorld.recycleAfterTailsDrain()

        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)
        XCTAssertEqual(pool.metrics.effects, survivingEffects)
        XCTAssertEqual(newScheduler.metrics.activeVoiceCount, 1)
        pool.update(manualHandle, gain: 0.5, playbackRate: manualSound.playbackRate)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)
    }

    func testRepeatedWorldRecycleKeepsSharedPlayersBuffersAndLiveEffectAggregateStable() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: .playbackWorld)
        let worlds = [
            PlaybackWorldBank(instrumentBank: pair.bankA),
            PlaybackWorldBank(instrumentBank: pair.bankB),
        ]
        try worlds.forEach { try $0.prepare() }
        let pool = worlds[0].happenings
        let playerIdentities = pool.metrics.fixedPlayerIdentities
        let bufferIdentities = pool.metrics.decodedBufferIdentities
        XCTAssertEqual(bufferIdentities.count, 102)

        for cycle in 0..<8 {
            let firstRecipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: lifecycleRecipeID((cycle % 10) + 1)))
            let secondRecipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: lifecycleRecipeID(((cycle + 1) % 10) + 1)))
            let firstSound = lifecycleResolvedSound(recipe: firstRecipe)
            let secondSound = lifecycleResolvedSound(recipe: secondRecipe)
            let first = try pool.play(firstSound, gain: 1, priority: .birth, effects: lifecycleEffects(for: firstRecipe))
            let secondEffects = lifecycleEffects(for: secondRecipe)
            let second = try pool.play(secondSound, gain: 1, priority: .manualAudition, effects: secondEffects)
            pool.stop(first)

            worlds[cycle % 2].recycleAfterTailsDrain()

            XCTAssertEqual(pool.metrics.activeVoiceCount, 1, "cycle \(cycle)")
            XCTAssertEqual(pool.metrics.effects, secondEffects, "cycle \(cycle)")
            pool.stop(second)
            XCTAssertEqual(pool.metrics.activeVoiceCount, 0, "cycle \(cycle)")
            XCTAssertEqual(pool.metrics.fixedPlayerIdentities, playerIdentities, "cycle \(cycle)")
            XCTAssertEqual(pool.metrics.decodedBufferIdentities, bufferIdentities, "cycle \(cycle)")
        }
    }

    func testPlaybackPairStopClearsAllSharedHappeningHandlesAndEffectContributions() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(bundle: Bundle(for: type(of: self)))
        try pair.prepare(configuration: .playbackWorld)
        try pair.start()
        let pool = pair.bankA.happenings
        let baselineEffects = pool.metrics.effects
        let recipes = Array(HappeningSoundCatalog.recipes.prefix(4))

        for recipe in recipes {
            _ = try pool.play(
                lifecycleResolvedSound(recipe: recipe),
                gain: 1,
                priority: .manualAudition,
                effects: lifecycleEffects(for: recipe)
            )
        }
        XCTAssertEqual(pool.metrics.activeVoiceCount, 4)
        XCTAssertNotEqual(pool.metrics.effects, baselineEffects)

        pair.stop()

        XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(pool.metrics.releasingVoiceCount, 0)
        XCTAssertEqual(pool.metrics.effects, baselineEffects)
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
    }

    func testPlaybackWorldReplacesTheTonalHappeningPoolWithFourSamplePlayers() throws {
        let configuration = PlaybackWorldBankConfiguration.playbackWorld

        XCTAssertEqual(configuration.tonalPools.map(\.capacity).reduce(0, +), 8)
        XCTAssertEqual(configuration.pianoVoiceCount, 2)
        XCTAssertEqual(configuration.drumOverlapCounts.values.reduce(0, +), 10)
        XCTAssertEqual(PlaybackWorldBankConfiguration.PoolName.allCases.count, 4)
        XCTAssertFalse(configuration.tonalPools.map(\.name).contains("happenings"))

        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        try bank.prepare(configuration: configuration)

        XCTAssertEqual(bank.happenings.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(bank.metrics.happeningMetrics.allocatedPlayerCount, 4)
        XCTAssertLessThanOrEqual(bank.metrics.happeningMetrics.decodedByteCount, 48 * 1_024 * 1_024)
    }

    func testSampleOnlyPreparationUpgradesToFullMusicWithoutStartingASecondEngine() throws {
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))

        try bank.prepare(level: .sampleOnly([recipeID]))
        XCTAssertEqual(bank.preparationLevel, .sampleOnly([recipeID]))
        XCTAssertEqual(bank.happenings.metrics.availableRecipeIDs, [recipeID])
        XCTAssertEqual(bank.metrics.tonalPoolCount, 0)

        try bank.prepare(level: .fullMusic(.playbackWorld))
        try bank.start()

        XCTAssertEqual(bank.preparationLevel, .fullMusic(.playbackWorld))
        XCTAssertEqual(bank.metrics.engineInstanceCount, 1)
        XCTAssertEqual(bank.metrics.engineStartCount, 1)
        XCTAssertEqual(bank.metrics.happeningMetrics.allocatedPlayerCount, 4)
    }

    func testSuccessfulSampleOnlyUpgradeHardReleasesManualAuditionsWithoutRebuildingSampleGraph() throws {
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        let allRecipeIDs = Set(HappeningSoundCatalog.recipes.map(\.id))
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let source = try XCTUnwrap(recipe.sources.first)
        let sound = ResolvedHappeningSound(
            recipeID: recipe.id,
            resourceName: source.resourceName,
            sourceRootMIDI: source.rootMIDI,
            targetMIDI: source.rootMIDI,
            playbackRate: 1,
            resonantFilterHz: nil
        )

        try bank.prepare(level: .sampleOnly(allRecipeIDs))
        try bank.start()
        let pool = bank.happenings
        let players = pool.metrics.fixedPlayerIdentities
        let buffers = pool.metrics.decodedBufferIdentities
        let bytes = pool.metrics.decodedByteCount
        let topology = bank.metrics.engineTopology
        let manualVoices = try Set((0..<4).map { _ in
            try pool.play(sound, gain: 1, priority: .manualAudition, effects: testHappeningEffects)
        })
        XCTAssertEqual(manualVoices.count, 4)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 4)

        try bank.prepare(level: .fullMusic(.playbackWorld))

        XCTAssertTrue(bank.happenings === pool)
        XCTAssertEqual(pool.metrics.fixedPlayerIdentities, players)
        XCTAssertEqual(pool.metrics.decodedBufferIdentities, buffers)
        XCTAssertEqual(pool.metrics.decodedByteCount, bytes)
        XCTAssertEqual(bank.metrics.engineTopology, topology)
        XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
        XCTAssertEqual(pool.metrics.releasingVoiceCount, 0)
        XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .birth, effects: testHappeningEffects))
        XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .recurrence, effects: testHappeningEffects))
        XCTAssertEqual(pool.metrics.activeVoiceCount, 2)
        bank.releaseAllIncludingSharedHappenings()
    }

    func testStartedSampleOnlyUpgradeFailuresKeepRunningGraphAndRetryTransactionally() throws {
        for stage in DayObjectsInstrumentBankPreparationStage.allCases {
            let harness = makeHarness()
            let allRecipeIDs = Set(HappeningSoundCatalog.recipes.map(\.id))
            let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
            let sound = ResolvedHappeningSound(
                recipeID: recipeID,
                resourceName: "one.wav",
                sourceRootMIDI: 60,
                targetMIDI: 60,
                playbackRate: 1,
                resonantFilterHz: nil
            )
            try harness.bank.prepare(level: .sampleOnly(allRecipeIDs))
            try harness.bank.start()
            let pool = try XCTUnwrap(harness.bank.happenings as? FakeHappeningSamplePool)
            for _ in 0..<4 {
                _ = try pool.play(sound, gain: 1, priority: .manualAudition, effects: testHappeningEffects)
            }
            let originalGraph = try XCTUnwrap(harness.engine.attachedGraph)
            let originalPlayerIdentities = harness.bank.happenings.metrics.fixedPlayerIdentities
            let originalBufferIdentities = harness.bank.happenings.metrics.decodedBufferIdentities
            let originalDecodedBytes = harness.bank.happenings.metrics.decodedByteCount
            let originalTopology = harness.bank.metrics.engineTopology
            XCTAssertEqual(pool.metrics.activeVoiceCount, 4)

            harness.failingAt = stage
            harness.engine.attachError = stage == .engine ? InjectedFailure() : nil
            XCTAssertThrowsError(try harness.bank.prepare(level: .fullMusic(configuration()))) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .preparationFailed(stage))
            }

            XCTAssertEqual(harness.bank.metrics.state, .started, "stage: \(stage)")
            XCTAssertTrue(harness.engine.isRunning, "stage: \(stage)")
            XCTAssertTrue(harness.engine.attachedGraph === originalGraph, "stage: \(stage)")
            XCTAssertEqual(harness.bank.happenings.metrics.fixedPlayerIdentities, originalPlayerIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedBufferIdentities, originalBufferIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedByteCount, originalDecodedBytes)
            XCTAssertEqual(harness.bank.metrics.engineTopology, originalTopology, "stage: \(stage)")
            XCTAssertEqual(harness.bank.metrics.engineTopology.finalPeakLimiterIdentities.count, 1)
            XCTAssertEqual(pool.metrics.activeVoiceCount, 4, "stage: \(stage)")
            XCTAssertEqual(pool.releaseAllCount, 0, "stage: \(stage)")

            harness.failingAt = nil
            harness.engine.attachError = nil
            try harness.bank.prepare(level: .fullMusic(configuration()))
            XCTAssertEqual(harness.bank.metrics.state, .started)
            XCTAssertTrue(harness.engine.isRunning)
            XCTAssertEqual(harness.bank.happenings.metrics.fixedPlayerIdentities, originalPlayerIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedBufferIdentities, originalBufferIdentities)
            XCTAssertEqual(harness.bank.happenings.metrics.decodedByteCount, originalDecodedBytes)
            XCTAssertEqual(harness.bank.metrics.engineTopology, originalTopology)
            XCTAssertEqual(pool.releaseAllCount, 1)
            XCTAssertEqual(pool.metrics.activeVoiceCount, 0)
            XCTAssertEqual(pool.metrics.releasingVoiceCount, 0)
            XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .birth, effects: testHappeningEffects))
            XCTAssertNoThrow(try pool.play(sound, gain: 1, priority: .recurrence, effects: testHappeningEffects))
        }
    }

    func testPairStopIsNoOpWhileAnIndividualBankOwnsTheSharedEngine() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics
        try pair.bankA.start()

        pair.stop()

        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)

        await pair.bankA.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.bankA.metrics.state, .prepared)
    }

    func testIndividualPlaybackBankOwnersStartOnFirstAndStopOnLastWithoutDetachingGraphs() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics

        try pair.bankA.start()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)

        try pair.bankB.start()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 2)

        await pair.bankA.stop()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .prepared)
        XCTAssertEqual(pair.bankB.metrics.state, .started)

        await pair.bankB.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
    }

    func testPairOwnershipRejectsIndividualStopsWithoutCorruptingBankStates() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        try pair.start()

        try pair.bankA.start()
        await pair.bankA.stop()
        await pair.bankB.stop()

        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .started)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)

        pair.stop()
        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
    }

    func testIndividualOwnershipRejectsPairStartAndRecoversAfterLastOwnerStops() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics
        try pair.bankA.start()

        XCTAssertThrowsError(try pair.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)

        await pair.bankA.stop()
        try pair.start()
        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
        pair.stop()
    }

    func testPlaybackPairLifecycleStartsAndStopsSharedEngineOnceWithoutChangingTopology() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics

        for cycle in 1...3 {
            try pair.start()
            XCTAssertEqual(pair.metrics.lifecycleState, .started)
            XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.sharedEngineStartCount, cycle)

            pair.stop()
            XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
            XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.sharedEngineStopCount, cycle)
            XCTAssertEqual(pair.metrics.attachedBankCount, 2)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
            XCTAssertEqual(pair.bankA.metrics.state, .prepared)
            XCTAssertEqual(pair.bankB.metrics.state, .prepared)
        }
    }

    func testPlaybackPairStartFailuresRollbackWithoutLosingPreparedGraphsAndRetryWithoutAllocation() throws {
        for failure in [
            DayObjectsPlaybackBankPairStartFailure.secondBankSynchronization,
            .sharedEngineStart,
        ] {
            var pendingFailure: DayObjectsPlaybackBankPairStartFailure? = failure
            let pair = DayObjectsInstrumentBank.makePlaybackPair(
                bundle: Bundle(for: type(of: self)),
                startFailureProvider: {
                    defer { pendingFailure = nil }
                    return pendingFailure
                }
            )
            try pair.prepare(configuration: smallPlaybackPairConfiguration())
            let baseline = pair.metrics

            XCTAssertThrowsError(try pair.start()) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
            }
            XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
            XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.attachedBankCount, 2)
            XCTAssertEqual(pair.bankA.metrics.state, .prepared)
            XCTAssertEqual(pair.bankB.metrics.state, .prepared)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)

            try pair.start()
            XCTAssertEqual(pair.metrics.lifecycleState, .started)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
            pair.stop()
        }
    }

    func testPlaybackPairUsesOneSharedEngineLimiterAndFixedRampableBankOutputs() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        let smallFixedWorld = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "world", capacity: 1, reservesLeadVoice: true)],
            pianoVoiceCount: 1,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )

        try pair.prepare(configuration: smallFixedWorld)
        let baseline = pair.metrics

        XCTAssertEqual(baseline.attachedBankCount, 2)
        XCTAssertEqual(baseline.sharedAudioEngineCount, 1)
        XCTAssertEqual(baseline.finalPeakLimiterCount, 1)
        XCTAssertTrue(pair.bankA.happenings === pair.bankB.happenings)
        XCTAssertEqual(pair.bankA.happenings.metrics.allocatedPlayerCount, 4)
        XCTAssertEqual(pair.bankA.happenings.metrics.decodedBufferCount, 102)
        XCTAssertEqual(Set(baseline.happeningFixedPlayerIdentities).count, 4)
        XCTAssertEqual(baseline.happeningFixedPlayerIdentities.count, 4)
        XCTAssertEqual(Set(baseline.happeningDecodedBufferIdentities).count, 102)
        XCTAssertEqual(baseline.happeningDecodedBufferIdentities.count, 102)
        XCTAssertLessThanOrEqual(baseline.happeningDecodedByteCount, 48 * 1_024 * 1_024)
        XCTAssertEqual(Set(baseline.finalPeakLimiterIdentities).count, 1)
        XCTAssertEqual(baseline.sharedMasterTrimDecibels, -3, accuracy: 1e-12)
        XCTAssertEqual(pair.bankA.metrics.graph?.finalPeakLimiterCount, 0)
        XCTAssertEqual(pair.bankB.metrics.graph?.finalPeakLimiterCount, 0)
        XCTAssertEqual(pair.bankA.outputGainMetrics.targetLinearGain, 1)
        XCTAssertEqual(pair.bankB.outputGainMetrics.targetLinearGain, 1)

        pair.bankA.setOutputGain(0.25, rampDurationSeconds: 0.5)
        pair.bankB.setOutputGain(0.75, rampDurationSeconds: 0.5)

        XCTAssertEqual(pair.bankA.outputGainMetrics.targetLinearGain, 0.25)
        XCTAssertEqual(pair.bankB.outputGainMetrics.targetLinearGain, 0.75)
        XCTAssertEqual(pair.bankA.outputGainMetrics.lastRampDurationSeconds, 0.5)
        XCTAssertEqual(pair.bankB.outputGainMetrics.lastRampDurationSeconds, 0.5)
        XCTAssertEqual(pair.bankA.outputGainMetrics.rampCount, 1)
        XCTAssertEqual(pair.bankB.outputGainMetrics.rampCount, 1)
        XCTAssertEqual(pair.metrics.fixedSharedNodeCount, baseline.fixedSharedNodeCount)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
    }

    func testPlaybackPairFitsTheMobileRealtimeAllocationBudget() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )

        try pair.prepare(configuration: .playbackWorld)

        let allocations = pair.metrics.allocationFingerprint.compactMap { $0 }
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.tonalNodeIdentities.count },
            500
        )
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.pianoLoadedPlayerCount },
            48
        )
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.drumFixedPlayerCount },
            20
        )
    }

    func testPlaybackPairDoesNotStackMoreThanThreeDecibelsOfFixedTrimPerStage() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )

        try pair.prepare(configuration: .playbackWorld)

        for bank in [pair.bankA, pair.bankB] {
            let graph = try XCTUnwrap(bank.metrics.graph)
            XCTAssertGreaterThanOrEqual(graph.tonalBusGainDB, -3.01)
            XCTAssertGreaterThanOrEqual(graph.drumBusGainDB, -3.01)
            XCTAssertGreaterThanOrEqual(graph.masterTrimDB, -3.01)
        }
        XCTAssertGreaterThanOrEqual(pair.metrics.sharedMasterTrimDecibels, -3.01)
    }

    func testPlaybackPairSchedulesBankOutputGainAtAuthoritativeHostTimes() throws {
        var currentHostTime: TimeInterval = 100
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self)),
            outputGainHostTimeProvider: { currentHostTime }
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())

        pair.bankA.scheduleOutputGain(
            0.5,
            startingAtHostTime: 101,
            endingAtHostTime: 102
        )

        XCTAssertEqual(pair.bankA.outputGainMetrics.lastScheduledAutomation, .init(
            targetLinearGain: 0.5,
            requestedStartHostTimeSeconds: 101,
            requestedEndHostTimeSeconds: 102,
            effectiveStartHostTimeSeconds: 101,
            effectiveEndHostTimeSeconds: 102,
            wasForcedImmediate: false
        ))

        currentHostTime = 103
        pair.bankA.scheduleOutputGain(
            0.25,
            startingAtHostTime: 101,
            endingAtHostTime: 102
        )
        XCTAssertEqual(pair.bankA.outputGainMetrics.lastScheduledAutomation, .init(
            targetLinearGain: 0.25,
            requestedStartHostTimeSeconds: 101,
            requestedEndHostTimeSeconds: 102,
            effectiveStartHostTimeSeconds: 103,
            effectiveEndHostTimeSeconds: 103,
            wasForcedImmediate: true
        ))
        XCTAssertEqual(pair.bankA.outputGainMetrics.rampCount, 2)
    }

    private func smallPlaybackPairConfiguration() -> DayObjectsInstrumentBankConfiguration {
        .init(
            tonalPools: [.init(name: "world", capacity: 1, reservesLeadVoice: true)],
            pianoVoiceCount: 1,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )
    }

    private func lifecycleWorld() -> TonalWorldPlan {
        .init(
            centerPitchClass: 0,
            mode: .dorian,
            scalePitchClasses: [0, 2, 3, 5, 7, 9, 10],
            progression: [lifecycleChord()],
            cycleBars: 8
        )
    }

    private func lifecycleChord() -> ChordPlan {
        .init(
            modalDegree: 0,
            rootPitchClass: 0,
            chordPitchClasses: [0, 3, 7],
            safePassingPitchClasses: [2, 5],
            voicedMIDINotes: [60, 63, 67],
            durationBars: 8
        )
    }

    private func lifecycleHappeningPlan(id: String, recipeRawValue: Int) -> HappeningMusicPlan {
        let recipe = HappeningSoundCatalog.recipe(for: lifecycleRecipeID(recipeRawValue))!
        return .init(
            happeningID: id,
            family: lifecycleFamily(for: recipe.family),
            recipeID: recipe.id,
            pan: 0,
            gain: 0.24,
            birthGain: 0.32,
            attackSeconds: recipe.attackSeconds,
            releaseSeconds: recipe.releaseSeconds,
            delaySend: recipe.delayMix,
            reverbSend: recipe.reverbMix,
            recurrence: .init(scheduleSeed: UInt64(recipeRawValue), alignmentRank: UInt64(recipeRawValue), floatingOffsetBeats: 0.25)
        )
    }

    private func lifecycleResolvedSound(recipe: HappeningSoundRecipe) -> ResolvedHappeningSound {
        HappeningPitchResolver.resolve(
            recipe: recipe,
            chord: lifecycleChord(),
            tonalWorld: lifecycleWorld()
        )
    }

    private func lifecycleEffects(for recipe: HappeningSoundRecipe) -> HappeningEffectCommand {
        .init(
            filterCutoffHz: recipe.filterEndHz,
            delayMix: recipe.delayMix,
            delayFeedback: recipe.delayFeedback,
            reverbMix: recipe.reverbMix
        )
    }

    private func lifecycleRecipeID(_ rawValue: Int) -> HappeningSoundRecipeID {
        HappeningSoundRecipeID(rawValue: rawValue)!
    }

    private func lifecycleFamily(for family: HappeningRecipeFamily) -> HappeningSoundFamily {
        switch family {
        case .synthPluck: return .pluck
        case .acousticMallet: return .mallet
        case .acousticBell: return .bell
        case .softOneShot: return .softOneShot
        case .texture: return .texture
        }
    }

    func testEqualPreparationBuildsTheFixedGraphOnlyOnceAndChangedConfigurationIsRejected() throws {
        let harness = makeHarness()
        let configuration = configuration()

        try harness.bank.prepare(configuration: configuration)
        try harness.bank.prepare(configuration: configuration)

        XCTAssertEqual(harness.tonalFactoryCallCount, 2)
        XCTAssertEqual(harness.drumFactoryCallCount, 1)
        XCTAssertEqual(harness.pianoFactoryCallCount, 1)
        XCTAssertEqual(harness.graphFactoryCallCount, 1)
        XCTAssertEqual(harness.bank.metrics.graph, .init(
            tonalBusCount: 1,
            drumBusCount: 1,
            sharedSpatialEffectCount: 2,
            tonalBusGainDB: -3,
            drumBusGainDB: -3,
            masterTrimDB: -3,
            finalPeakLimiterCount: 0
        ))

        XCTAssertThrowsError(try harness.bank.prepare(configuration: .init(
            tonalPools: [.init(name: "world", capacity: 3, reservesLeadVoice: false)],
            pianoVoiceCount: 4,
            drumOverlapCounts: [:]
        ))) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .configurationChangedAfterPreparation)
        }
    }

    func testTonalPoolRejectsNonTonalInstrumentCommandsAtFacadeBoundary() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())

        let pool = try harness.bank.tonalPool(named: "role")
        XCTAssertThrowsError(try pool.prepareInstrument(.init(rawValue: "drums.kick"))) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .invalidTonalInstrumentCategory(.drums))
        }
        XCTAssertThrowsError(try pool.prepareInstrument(.init(rawValue: "piano.felt"))) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .invalidTonalInstrumentCategory(.piano))
        }
        XCTAssertNil(pool.noteOn(request(instrumentID: .init(rawValue: "drums.kick"))))
        XCTAssertNil(pool.noteOn(request(instrumentID: .init(rawValue: "piano.felt"))))
        XCTAssertEqual(harness.tonalNoteOnCount, 0)
    }

    func testEachPreparationFailureReleasesPartialStateAndIsRetryableWithStableDiagnostic() throws {
        for stage in DayObjectsInstrumentBankPreparationStage.allCases {
            let harness = makeHarness(failingAt: stage)

            XCTAssertThrowsError(try harness.bank.prepare(configuration: configuration())) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .preparationFailed(stage))
            }
            XCTAssertEqual(harness.bank.metrics.state, .unprepared)
            XCTAssertEqual(harness.releaseCount, expectedReleaseCount(for: stage))
            XCTAssertEqual(harness.engine.detachCount, 1)
            XCTAssertNil(harness.engine.attachedGraph)

            harness.failingAt = nil
            harness.engine.attachError = nil
            try harness.bank.prepare(configuration: configuration())
            XCTAssertEqual(harness.bank.metrics.state, .prepared)
        }
    }

    func testStartFailureStopsEngineReleasesVoicesAndLeavesTheBankRetryable() throws {
        let harness = makeHarness()
        harness.engine.startError = InjectedFailure()
        try harness.bank.prepare(configuration: configuration())

        XCTAssertThrowsError(try harness.bank.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(harness.engine.stopCount, 1)
        XCTAssertEqual(harness.engine.detachCount, 1)
        XCTAssertEqual(harness.releaseCount, 5)
        XCTAssertEqual(harness.bank.metrics.state, .unprepared)
        XCTAssertNil(harness.engine.attachedGraph)

        harness.engine.startError = nil
        try harness.bank.prepare(configuration: configuration())
        try harness.bank.start()
        XCTAssertEqual(harness.bank.metrics.state, .started)
    }

    func testDetachedRealGraphExposesSeparateBusesBoundedSpatialEffectsAndOneLimiter() throws {
        let bank = DayObjectsInstrumentBank(bundle: Bundle(for: type(of: self)))
        let configuration = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "role", capacity: 2, reservesLeadVoice: true)],
            pianoVoiceCount: 3,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )

        try bank.prepare(configuration: configuration)

        XCTAssertEqual(bank.metrics.state, .prepared)
        let graph = try XCTUnwrap(bank.metrics.graph)
        XCTAssertEqual(graph.tonalBusCount, 1)
        XCTAssertEqual(graph.drumBusCount, 1)
        XCTAssertEqual(graph.sharedSpatialEffectCount, 2)
        XCTAssertEqual(graph.tonalBusGainDB, -3, accuracy: 0.001)
        XCTAssertEqual(graph.drumBusGainDB, -3, accuracy: 0.001)
        XCTAssertEqual(graph.masterTrimDB, -3, accuracy: 0.001)
        XCTAssertEqual(graph.finalPeakLimiterCount, 0)
        XCTAssertEqual(bank.metrics.drumMetrics.allocatedPlayerCount, DayObjectsDrumVoice.allCases.count)
        XCTAssertEqual(bank.metrics.pianoMetrics.allocatedPlayerCount, 3)

        let pool = try bank.tonalPool(named: "role")
        try pool.prepareInstrument(.init(rawValue: "pad.interstellar"))
        let fingerprint = try XCTUnwrap(bank.metrics.allocationFingerprint)
        for _ in 0..<20 {
            let token = try XCTUnwrap(pool.noteOn(request(instrumentID: .init(rawValue: "pad.interstellar"))))
            pool.update(token, with: .init(cutoffHz: 4_000, expression: 0.7, pan: 0.15))
            pool.noteOff(token)
            bank.drums.hit(.kickSoft, velocity: 0.7)
            let pianoToken = try XCTUnwrap(bank.piano.noteOn(60, velocity: 0.7))
            bank.piano.noteOff(pianoToken)
        }
        XCTAssertEqual(bank.metrics.allocationFingerprint, fingerprint)
    }

    func testFactoriesReceiveRequestedFixedCountsAndStopCanRestartWithoutReconfiguration() async throws {
        let harness = makeHarness()
        let requested = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "role", capacity: 2, reservesLeadVoice: true)],
            pianoVoiceCount: 3,
            drumOverlapCounts: [.kickSoft: 1, .hatClosed: 2]
        )
        try harness.bank.prepare(configuration: requested)
        let graphIdentity = ObjectIdentifier(try XCTUnwrap(harness.engine.attachedGraph))
        harness.engine.events.removeAll()
        let pool = try harness.bank.tonalPool(named: "role")
        try pool.prepareInstrument(.init(rawValue: "pad.safe"))
        let identity = ObjectIdentifier(pool)
        for _ in 0..<100 {
            _ = pool.noteOn(request(instrumentID: .init(rawValue: "pad.safe")))
            harness.bank.drums.hit(.kickSoft, velocity: 0.7)
            _ = harness.bank.piano.noteOn(60, velocity: 0.7)
        }
        XCTAssertEqual(harness.requestedDrumOverlaps, [.kickSoft: 1, .hatClosed: 2])
        XCTAssertEqual(harness.requestedPianoVoiceCount, 3)
        XCTAssertEqual(harness.tonalFactoryCallCount, 1)
        XCTAssertEqual(harness.drumFactoryCallCount, 1)
        XCTAssertEqual(harness.pianoFactoryCallCount, 1)
        XCTAssertEqual(harness.tonalNoteOnCount, 100)
        XCTAssertEqual(harness.drumHitCount, 100)
        XCTAssertEqual(harness.pianoNoteOnCount, 100)
        XCTAssertEqual(ObjectIdentifier(try harness.bank.tonalPool(named: "role")), identity)

        try harness.bank.start()
        XCTAssertEqual(harness.engine.events, ["synchronize", "start"])
        await harness.bank.stop()
        XCTAssertEqual(harness.releaseCount, 4)
        XCTAssertEqual(harness.engine.detachCount, 1)
        XCTAssertNil(harness.engine.attachedGraph)
        harness.engine.events.removeAll()
        try harness.bank.start()
        XCTAssertEqual(harness.engine.attachCount, 2)
        XCTAssertEqual(harness.engine.events, ["attach", "synchronize", "start"])
        XCTAssertNotNil(harness.engine.attachedGraph)
        XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(harness.engine.attachedGraph)), graphIdentity)
    }

    func testPublicReleaseAllReachesEveryPreparedSubBank() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())

        harness.bank.releaseAllIncludingSharedHappenings()

        XCTAssertEqual(harness.releaseCount, 5)
        XCTAssertNotNil(harness.engine.attachedGraph)
    }

    func testSynchronizationAndStartFailuresDetachTheRetainedGraphAndAreRetryable() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())
        harness.graphSynchronizeError = InjectedFailure()
        harness.engine.events.removeAll()

        XCTAssertThrowsError(try harness.bank.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(harness.engine.events, ["synchronize", "stop", "detach"])
        XCTAssertNil(harness.engine.attachedGraph)
        XCTAssertEqual(harness.bank.metrics.state, .unprepared)

        harness.graphSynchronizeError = nil
        try harness.bank.prepare(configuration: configuration())
        XCTAssertNotNil(harness.engine.attachedGraph)
        harness.engine.startError = InjectedFailure()
        harness.engine.events.removeAll()
        XCTAssertThrowsError(try harness.bank.start())
        XCTAssertEqual(harness.engine.events, ["synchronize", "start", "stop", "detach"])
        XCTAssertNil(harness.engine.attachedGraph)
    }

    private func configuration() -> DayObjectsInstrumentBankConfiguration {
        .init(
            tonalPools: [
                .init(name: "role", capacity: 2, reservesLeadVoice: true),
                .init(name: "world", capacity: 3, reservesLeadVoice: false),
            ],
            pianoVoiceCount: 4,
            drumOverlapCounts: [.kickSoft: 2, .hatClosed: 3]
        )
    }

    private func makeHarness(
        failingAt stage: DayObjectsInstrumentBankPreparationStage? = nil
    ) -> InstrumentBankHarness {
        InstrumentBankHarness(failingAt: stage)
    }

    private func request(instrumentID: DayObjectsInstrumentID) -> DayObjectsTonalNoteRequest {
        .init(instrumentID: instrumentID, midiNote: 60, velocity: 0.7, role: .note, envelopeVariant: nil, pan: 0, delaySend: 0, reverbSend: 0)
    }

    private func expectedReleaseCount(for stage: DayObjectsInstrumentBankPreparationStage) -> Int {
        switch stage {
        case .tonalInstruments: return 1
        case .tonalPools: return 2
        case .drums: return 3
        case .piano: return 4
        case .graph, .engine: return 5
        }
    }
}

@MainActor
private final class InstrumentBankHarness {
    var failingAt: DayObjectsInstrumentBankPreparationStage?
    var tonalFactoryCallCount = 0
    var drumFactoryCallCount = 0
    var pianoFactoryCallCount = 0
    var graphFactoryCallCount = 0
    var releaseCount = 0
    var tonalNoteOnCount = 0
    var drumHitCount = 0
    var pianoNoteOnCount = 0
    var graphSynchronizeError: Error?
    var requestedDrumOverlaps: [DayObjectsDrumVoice: Int] = [:]
    var requestedPianoVoiceCount: Int?
    let engine = FakeInstrumentBankEngine()
    private(set) var bank: DayObjectsInstrumentBank!

    init(failingAt: DayObjectsInstrumentBankPreparationStage?) {
        self.failingAt = failingAt
        engine.attachError = failingAt == .engine ? InjectedFailure() : nil
        bank = DayObjectsInstrumentBank(
            descriptors: [
                .init(id: .init(rawValue: "pad.safe"), category: .pad, displayName: "Safe", bankName: "Test", sourceUID: nil, referenceMIDI: 60, auditionChord: [60], outputTrimDB: -12),
                .init(id: .init(rawValue: "drums.kick"), category: .drums, displayName: "Kick", bankName: "Test", sourceUID: nil, referenceMIDI: 36, auditionChord: [], outputTrimDB: -12),
                .init(id: .init(rawValue: "piano.felt"), category: .piano, displayName: "Piano", bankName: "Test", sourceUID: nil, referenceMIDI: 60, auditionChord: [], outputTrimDB: -12),
            ],
            tonalInstrumentLoader: { [weak self] in
                guard self?.failingAt != .tonalInstruments else { throw InjectedFailure() }
                return [.init(rawValue: "pad.safe"): Self.safeVoice]
            },
            tonalPoolFactory: { [weak self] specification, _ in
                guard !(self?.failingAt == .tonalPools && self?.tonalFactoryCallCount == 1) else { throw InjectedFailure() }
                self?.tonalFactoryCallCount += 1
                return FakeTonalPool(name: specification.name, onNoteOn: { self?.tonalNoteOnCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            drumBankFactory: { [weak self] counts in
                guard self?.failingAt != .drums else { throw InjectedFailure() }
                self?.drumFactoryCallCount += 1
                self?.requestedDrumOverlaps = counts
                return FakeDrumBank(onHit: { self?.drumHitCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            pianoPoolFactory: { [weak self] count in
                guard self?.failingAt != .piano else { throw InjectedFailure() }
                self?.pianoFactoryCallCount += 1
                self?.requestedPianoVoiceCount = count
                return FakePianoPool(onNoteOn: { self?.pianoNoteOnCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            happeningPoolFactory: { [weak self] in
                FakeHappeningSamplePool(onRelease: { self?.releaseCount += 1 })
            },
            graphFactory: { [weak self] _, _, _, _ in
                guard self?.failingAt != .graph else { throw InjectedFailure() }
                self?.graphFactoryCallCount += 1
                return FakeInstrumentBankGraph(
                    isAttached: { [weak self] in self?.engine.attachedGraph != nil },
                    synchronizeError: { [weak self] in self?.graphSynchronizeError },
                    onSynchronize: { [weak self] in self?.engine.events.append("synchronize") }
                )
            },
            engine: engine
        )
    }

    private static let safeVoice = NormalizedSynthVoice(
        oscillator1: .init(wavePosition: 0, level: 0.8, semitoneOffset: 0, detuneHz: 0),
        oscillator2: .init(wavePosition: 0, level: 0, semitoneOffset: 0, detuneHz: 0),
        oscillatorBalance: 0.5,
        subOscillator: .init(level: 0, waveform: .sine, octaveOffset: -1),
        noiseLevel: 0,
        amplitudeEnvelope: .init(attackSeconds: 0.01, decaySeconds: 0.1, sustainLevel: 0.8, releaseSeconds: 0.2),
        filter: .init(kind: .lowPass, cutoffHz: 12_000, resonance: 0.1, envelope: .init(attackSeconds: 0.01, decaySeconds: 0.1, sustainLevel: 0.8, releaseSeconds: 0.2), envelopeAmount: 0),
        glideSeconds: 0,
        isMonophonic: false,
        lfo: .init(target: .none, rateHz: 1, depth: 0),
        delay: .init(isEnabled: false, timeSeconds: 0.2, feedback: 0, mix: 0),
        reverb: .init(isEnabled: false, feedback: 0.8, highPassHz: 80, mix: 0),
        phaser: .init(rateHz: 0.5, feedback: 0, mix: 0),
        autoPan: .init(rateHz: 0.25, depth: 0, stereoWidth: 0),
        outputTrimDB: -12,
        referenceMIDI: 60,
        auditionChord: [60]
    )
}

private struct InjectedFailure: Error {}

@MainActor
private final class FakeTonalPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let onNoteOn: () -> Void
    let onRelease: () -> Void
    init(name: String, onNoteOn: @escaping () -> Void, onRelease: @escaping () -> Void) { self.name = name; self.onNoteOn = onNoteOn; self.onRelease = onRelease }
    var metrics: DayObjectsTonalPoolMetrics { .init(name: name, allocatedVoiceCount: 2, allocatedNodeCount: 0, activeVoiceCount: 0, activeLeadVoiceCount: 0, activeChordVoiceCount: 0) }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {}
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? { onNoteOn(); return nil }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {}
    func noteOff(_ token: DayObjectsVoiceToken) {}
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakeDrumBank: DayObjectsDrumBankProtocol {
    let onHit: () -> Void
    let onRelease: () -> Void
    init(onHit: @escaping () -> Void, onRelease: @escaping () -> Void) { self.onHit = onHit; self.onRelease = onRelease }
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) { onHit() }
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakePianoPool: DayObjectsPianoPoolProtocol {
    let onNoteOn: () -> Void
    let onRelease: () -> Void
    init(onNoteOn: @escaping () -> Void, onRelease: @escaping () -> Void) { self.onNoteOn = onNoteOn; self.onRelease = onRelease }
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 4) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { onNoteOn(); return nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakeHappeningSamplePool: DayObjectsHappeningSamplePoolProtocol {
    let onRelease: () -> Void
    private let playerTokens = (0..<4).map { _ in NSObject() }
    private var preparedIDs: Set<HappeningSoundRecipeID> = []
    private var bufferTokens: [HappeningSoundRecipeID: NSObject] = [:]
    private var active: [Int: (priority: HappeningPlaybackPriority, handle: HappeningPlaybackHandle)] = [:]
    private var generation: UInt64 = 0
    private(set) var releaseAllCount = 0
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    var metrics: HappeningSamplePoolMetrics {
        .init(
            allocatedPlayerCount: 4,
            fixedPlayerIdentities: playerTokens.map(ObjectIdentifier.init),
            activeVoiceCount: active.count,
            releasingVoiceCount: 0,
            stealCount: 0,
            decodedBufferCount: preparedIDs.count,
            decodedBufferIdentities: preparedIDs.sorted(by: { $0.rawValue < $1.rawValue }).compactMap {
                bufferTokens[$0].map(ObjectIdentifier.init)
            },
            decodedByteCount: preparedIDs.count * 1_024,
            availableRecipeIDs: preparedIDs,
            unavailableRecipeIDs: [],
            effects: .init(filterCutoffHz: 8_000, delayMix: 0, delayFeedback: 0, reverbMix: 0),
            lastEffectRampSeconds: 0
        )
    }
    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws {
        for id in recipeIDs where bufferTokens[id] == nil { bufferTokens[id] = NSObject() }
        preparedIDs.formUnion(recipeIDs)
    }
    func play(
        _ sound: ResolvedHappeningSound,
        gain: Double,
        priority: HappeningPlaybackPriority,
        effects: HappeningEffectCommand
    ) throws -> HappeningPlaybackHandle {
        let voiceID: Int
        if let idle = (0..<4).first(where: { active[$0] == nil }) {
            voiceID = idle
        } else {
            guard let eligible = active
                .filter({ $0.value.priority < priority })
                .map(\.key)
                .min() else { throw HappeningSamplePoolError.noEligibleVoice }
            voiceID = eligible
        }
        generation &+= 1
        let handle = HappeningPlaybackHandle(voiceID: voiceID, generation: generation)
        active[voiceID] = (priority, handle)
        return handle
    }
    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double) {}
    func update(_ handle: HappeningPlaybackHandle, gain: Double, playbackRate: Double) {}
    func stop(_ handle: HappeningPlaybackHandle) {
        guard active[handle.voiceID]?.handle == handle else { return }
        active[handle.voiceID] = nil
    }
    func releaseAll() {
        releaseAllCount += 1
        active.removeAll()
        onRelease()
    }
}

@MainActor
private final class FakeInstrumentBankGraph: DayObjectsInstrumentBankGraph {
    let layout = DayObjectsInstrumentBankGraphLayout(tonalBusCount: 1, drumBusCount: 1, sharedSpatialEffectCount: 2, tonalBusGainDB: -3, drumBusGainDB: -3, masterTrimDB: -3, finalPeakLimiterCount: 0)
    let isAttached: () -> Bool
    let synchronizeError: () -> Error?
    let onSynchronize: () -> Void
    init(isAttached: @escaping () -> Bool, synchronizeError: @escaping () -> Error?, onSynchronize: @escaping () -> Void) {
        self.isAttached = isAttached
        self.synchronizeError = synchronizeError
        self.onSynchronize = onSynchronize
    }
    func synchronizeForStart() throws {
        onSynchronize()
        guard isAttached() else { throw InjectedFailure() }
        if let error = synchronizeError() { throw error }
    }
}

@MainActor
private final class FakeInstrumentBankEngine: DayObjectsInstrumentBankEngine {
    private let masterToken = NSObject()
    private let limiterToken = NSObject()
    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics {
        .init(
            persistentMasterNodeIdentities: [ObjectIdentifier(masterToken)],
            finalPeakLimiterIdentities: [ObjectIdentifier(limiterToken)]
        )
    }
    var startError: Error?
    var attachError: Error?
    private(set) var stopCount = 0
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    private(set) var attachedGraph: (any DayObjectsInstrumentBankGraph)?
    private(set) var isRunning = false
    var events: [String] = []
    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        events.append("attach")
        attachCount += 1
        if let attachError { throw attachError }
        attachedGraph = graph
    }
    func detach() { events.append("detach"); detachCount += 1; attachedGraph = nil }
    func start() throws {
        events.append("start")
        guard attachedGraph != nil else { throw InjectedFailure() }
        if let startError { throw startError }
        isRunning = true
    }
    func stop() { events.append("stop"); stopCount += 1; isRunning = false }
}
