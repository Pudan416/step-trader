#if DEBUG || INTERNAL_BUILD
import AVFAudio
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsMusicPlaybackEngineTests: XCTestCase {
    func testMobileRuntimeReferenceC4AuditionResolvesTonalResonantAndUnpitchedRecipes() async throws {
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let recipeIDs = try Set([7, 25, 28].map {
            try XCTUnwrap(HappeningSoundRecipeID(rawValue: $0))
        })

        try await runtime.prepareSamples(recipeIDs: recipeIDs)
        try runtime.startAudio()
        for recipeID in recipeIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            try runtime.auditionHappening(recipeID, harmony: .referenceC4)
        }

        let records = runtime.auditionRecordsForTesting
        XCTAssertEqual(records.map(\.resolvedSound.targetMIDI), [60, 60, nil])
        XCTAssertEqual(records.map(\.resolvedSound.playbackRate), [1, 1, 1])
        XCTAssertNil(records[0].resolvedSound.resonantFilterHz)
        XCTAssertEqual(records[1].resolvedSound.resonantFilterHz ?? 0, 261.625_565, accuracy: 0.001)
        XCTAssertNil(records[2].resolvedSound.resonantFilterHz)
        XCTAssertTrue(records.allSatisfy { $0.priority == .manualAudition })
        for record in records {
            let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: record.resolvedSound.recipeID))
            XCTAssertEqual(record.effects, .init(
                filterCutoffHz: recipe.filterEndHz,
                delayMix: recipe.delayMix,
                delayFeedback: recipe.delayFeedback,
                reverbMix: recipe.reverbMix
            ))
        }

        runtime.releaseAuditions()
        await runtime.stopAudio()
    }

    func testMobileRuntimeRunningAuditionResolvesAgainstChordSoundingAtAttackTime() throws {
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let plan = makePlaybackEnginePlan(seed: 0xC4, happeningIDs: [])
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 7))
        try runtime.prepare(plan: plan)
        try runtime.startPreparedWorldForTesting()
        let targetChordIndex = min(1, plan.world.progression.count - 1)
        let targetBar = plan.world.progression.prefix(targetChordIndex)
            .reduce(0) { $0 + max($1.durationBars, 1) }
        runtime.renderForTesting(.init(
            kind: .barBoundary,
            position: .init(absoluteSubdivision: Int64(targetBar) * MusicalPosition.subdivisionsPerBar),
            hostTimeSeconds: 1,
            tempoBPM: plan.rhythm.tempoBPM
        ))

        let schedulerHistory = runtime.activeHappeningAttackHistoryForTesting
        try runtime.auditionHappening(recipeID, harmony: .currentHarmony)

        let record = try XCTUnwrap(runtime.auditionRecordsForTesting.last)
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        XCTAssertEqual(
            record.resolvedSound,
            HappeningPitchResolver.resolve(
                recipe: recipe,
                chord: plan.world.progression[targetChordIndex],
                tonalWorld: plan.world
            )
        )
        XCTAssertEqual(record.priority, .manualAudition)
        XCTAssertEqual(runtime.activeHappeningAttackHistoryForTesting, schedulerHistory)
    }

    func testRunningAuditionUsesCurrentHarmonyWithoutRestartingMusic() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 7))
        try await engine.start(plan: makePlaybackEnginePlan(seed: 6))
        log.values.removeAll()

        try await engine.auditionHappening(recipeID)

        XCTAssertEqual(runtime.auditionRequests, ["7:currentHarmony"])
        XCTAssertEqual(log.values, ["runtime.audition:7:currentHarmony"])
        XCTAssertEqual(engine.state, .on)
        XCTAssertEqual(engine.metrics.engineStartCount, 1)
        XCTAssertEqual(session.activationCount, 1)
    }

    func testColdAuditionsCoalescePreparationKeepPublicStateOffAndPreserveDistinctTaps() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let tonal = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 7))
        let resonant = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
        let unpitched = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 28))

        let first = Task { @MainActor in try await engine.auditionHappening(tonal) }
        await runtime.waitUntilSamplePreparationBegins()
        let second = Task { @MainActor in try await engine.auditionHappening(resonant) }
        let third = Task { @MainActor in try await engine.auditionHappening(unpitched) }
        await Task.yield()

        XCTAssertEqual(runtime.samplePreparationAttempts, 1)
        XCTAssertEqual(engine.state, .off)
        runtime.resumeSamplePreparation()
        try await first.value
        try await second.value
        try await third.value

        XCTAssertEqual(Set(runtime.auditionRequests), Set([
            "7:referenceC4", "25:referenceC4", "28:referenceC4",
        ]))
        XCTAssertEqual(runtime.audioStartCount, 1)
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(engine.state, .off)
        XCTAssertEqual(engine.metrics.engineStartCount, 0)
    }

    func testCancellingOneColdWaiterDoesNotCancelSharedPreparationOrLoseOtherTap() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let firstID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let secondID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 2))

        let cancelled = Task { @MainActor in try await engine.auditionHappening(firstID) }
        await runtime.waitUntilSamplePreparationBegins()
        let retained = Task { @MainActor in try await engine.auditionHappening(secondID) }
        await Task.yield()
        cancelled.cancel()
        await Task.yield()
        runtime.resumeSamplePreparation()
        _ = try? await cancelled.value
        try await retained.value

        XCTAssertEqual(runtime.samplePreparationAttempts, 1)
        XCTAssertEqual(runtime.auditionRequests, ["2:referenceC4"])
        XCTAssertFalse(runtime.samplePreparationWasCancelled)
        XCTAssertTrue(session.isActive)
    }

    func testCancellingLastColdWaiterCancelsPreparationAndDeactivatesSession() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 3))

        let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
        await runtime.waitUntilSamplePreparationBegins()
        XCTAssertEqual(engine.runtimeState, .preparingSamples)
        audition.cancel()
        await Task.yield()
        runtime.resumeSamplePreparation()
        _ = try? await audition.value
        for _ in 0..<5 { await Task.yield() }

        XCTAssertTrue(runtime.samplePreparationWasCancelled)
        XCTAssertTrue(runtime.auditionRequests.isEmpty)
        XCTAssertEqual(engine.runtimeState, .stopped)
        XCTAssertFalse(session.isActive)
    }

    func testFullStartUpgradesSampleOnlyRuntimeWithoutReactivatingSession() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 9))

        try await engine.auditionHappening(recipeID)
        XCTAssertEqual(engine.state, .off)
        try await engine.start(plan: makePlaybackEnginePlan(seed: 77))

        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(runtime.audioStartCount, 1, "The already-running sample engine must be upgraded in place")
        XCTAssertEqual(runtime.prepareAttempts, 1)
        XCTAssertEqual(engine.state, .on)
        XCTAssertEqual(engine.metrics.engineStartCount, 1)
    }

    func testFailedFullUpgradePreservesSampleOnlyRuntimeAndAllowsAnotherAudition() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let firstID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 9))
        let secondID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 10))
        try await engine.auditionHappening(firstID)
        runtime.failureStage = .prepare

        do {
            try await engine.start(plan: makePlaybackEnginePlan(seed: 88))
            XCTFail("Expected full upgrade to fail")
        } catch {}

        XCTAssertEqual(engine.runtimeState, .sampleOnly)
        XCTAssertTrue(session.isActive)
        runtime.failureStage = nil
        try await engine.auditionHappening(secondID)
        XCTAssertEqual(runtime.samplePreparationAttempts, 1)
        XCTAssertEqual(runtime.audioStartCount, 1)
        XCTAssertEqual(runtime.auditionRequests.last, "10:referenceC4")
    }

    func testStoppingSampleOnlyReleasesAuditionsAndDeactivatesSession() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 28))
        try await engine.auditionHappening(recipeID)

        await engine.stop()

        XCTAssertEqual(runtime.releaseAuditionCount, 1)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(engine.state, .off)
    }

    func testMobileRuntimePreparesOnlyOnePlaybackWorld() throws {
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))

        try runtime.prepare(plan: makePlaybackEnginePlan(seed: 32))

        XCTAssertEqual(runtime.preparedRhythmBackendCount, 1)
        XCTAssertEqual(runtime.playbackMetrics.activeTransportCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.activeTaskCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.activeVoiceCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.pendingRemixCount, 0)
        XCTAssertEqual(runtime.instrumentAllocationCountForTesting, 1)
    }

    func testMobileRuntimeAppliesRemixInPlaceAtTheNextBarBoundary() throws {
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: 40)
        let remixed = makePlaybackEnginePlan(seed: 41)
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()

        runtime.scheduleStructuralPlan(remixed)
        XCTAssertEqual(runtime.playbackMetrics.pendingRemixCount, 1)
        runtime.renderForTesting(.init(
            kind: .barBoundary,
            position: .init(absoluteSubdivision: 128),
            hostTimeSeconds: 8,
            tempoBPM: 100
        ))

        XCTAssertEqual(runtime.activePlanForTesting?.seed, remixed.seed)
        XCTAssertEqual(runtime.playbackMetrics.pendingRemixCount, 0)
    }

    func testLiveRuntimePreparesTwoFixedWorldsWithoutStartingTransportOrVoices() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let plan = makePlaybackEnginePlan(seed: 33)

        try runtime.prepare(plan: plan)

        XCTAssertEqual(runtime.playbackMetrics.activeTransportCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.activeTaskCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.activeVoiceCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.leadVoiceCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.pendingRemixCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.activeHappeningCount, plan.happenings.count)
        XCTAssertGreaterThan(runtime.playbackMetrics.activeNodeCount, 0)
        XCTAssertEqual(runtime.preparedRhythmBackendCount, 2)
        let effects = runtime.activeProgramEffectMetricsForTesting
        XCTAssertTrue(effects.isSupported)
        XCTAssertEqual(
            effects.masterLinearGain,
            pow(10, plan.mix.masterTargetDecibelsBeforeLimiter / 20),
            accuracy: 0.000_001
        )
        let expectedDelay = max(
            plan.harmony.roles.map(\.delaySend).max() ?? 0,
            plan.happenings.map(\.delaySend).max() ?? 0
        )
        let expectedReverb = max(
            plan.harmony.roles.map(\.reverbSend).max() ?? 0,
            plan.happenings.map(\.reverbSend).max() ?? 0
        )
        XCTAssertEqual(effects.delayFeedback, expectedDelay, accuracy: 0.000_001)
        XCTAssertEqual(effects.reverbFeedback, expectedReverb, accuracy: 0.000_001)
        XCTAssertTrue(effects.delayFeedbackWasRamped)
        XCTAssertTrue(effects.reverbFeedbackWasRamped)
        XCTAssertEqual(effects.feedbackRampDurationSeconds, 0.25, accuracy: 0.000_001)
    }

    func testLiveRuntimeRemixKeepsOldHarmonyThroughP0ThenReleasesBeforeRecycle() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: 501)
        let remixed = makePlaybackEnginePlan(seed: 502)
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()
        runtime.renderForTesting(.init(kind: .barBoundary, position: .init(absoluteSubdivision: 0), hostTimeSeconds: 0, tempoBPM: 100))
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 16), hostTimeSeconds: 1, tempoBPM: 100))
        XCTAssertGreaterThan(runtime.activeWorldVoiceCountForTesting, 0)

        runtime.scheduleStructuralPlan(remixed)
        runtime.renderForTesting(.init(kind: .barBoundary, position: .init(absoluteSubdivision: 128), hostTimeSeconds: 8, tempoBPM: 100))
        XCTAssertEqual(runtime.remixResultForTesting, .transitioned(seed: remixed.seed))
        XCTAssertTrue(runtime.activeHappeningNextPositionsForTesting.values.allSatisfy {
            $0.absoluteSubdivision >= 128
        }, "The new world's first cycle must be aligned to the Remix boundary")
        XCTAssertTrue(runtime.activeHappeningScheduledPositionsForTesting.values
            .flatMap { $0 }
            .allSatisfy { $0.absoluteSubdivision >= 128 })
        XCTAssertTrue(runtime.activeHappeningAttackHistoryForTesting.allSatisfy {
            $0.position.absoluteSubdivision >= 128
        })
        XCTAssertGreaterThan(runtime.inactiveWorldVoiceCountForTesting, 0, "p0 must not cut the old harmony tail")

        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 160), hostTimeSeconds: 10, tempoBPM: 100))
        XCTAssertEqual(runtime.inactiveWorldVoiceCountForTesting, 0, "the recycled world must retain no old tokens")
    }

    func testLiveContinuousUpdateDoesNotExposeStructuralWorldBeforeBoundary() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: 601)
        let mixed = DeterministicMusicDirector.makePlan(
            input: .init(
                countedSteps: 10_000,
                stepGoal: 10_000,
                countedSleepHours: 8,
                sleepGoalHours: 8,
                happeningIDs: ["a", "b"],
                spentColors: 100
            ),
            remixSeed: 602
        )
        try runtime.prepare(plan: initial)

        runtime.applyContinuous(mixed)

        let audible = try XCTUnwrap(runtime.activePlanForTesting)
        XCTAssertEqual(audible.seed, initial.seed)
        XCTAssertEqual(audible.world, initial.world)
        XCTAssertEqual(audible.rhythm.family, initial.rhythm.family)
        XCTAssertEqual(audible.rhythm.realization, initial.rhythm.realization)
        XCTAssertEqual(audible.lead.instrumentID, initial.lead.instrumentID)
        XCTAssertEqual(audible.rhythm.tempoBPM, mixed.rhythm.tempoBPM)
        XCTAssertEqual(audible.rhythm.stepsProgress, mixed.rhythm.stepsProgress)
        XCTAssertEqual(audible.harmony.sleepProgress, mixed.harmony.sleepProgress)
        XCTAssertEqual(audible.glitch.progress, mixed.glitch.progress)
        XCTAssertEqual(audible.mix, mixed.mix)
    }

    func testLiveSafeHeldLeadKeepsSourceTokenAndDelaysOldBankRecycleUntilRelease() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: 701)
        let remixed = DayMusicPlan(
            seed: 702,
            input: initial.input,
            world: initial.world,
            rhythm: initial.rhythm,
            harmony: initial.harmony,
            happenings: initial.happenings,
            lead: initial.lead,
            glitch: initial.glitch,
            mix: initial.mix
        )
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()
        runtime.renderForTesting(.init(kind: .barBoundary, position: .init(absoluteSubdivision: 0), hostTimeSeconds: 0, tempoBPM: 100))
        runtime.beginLead(.init(normalizedX: 0.45, normalizedY: 0.7, speed: 0))
        XCTAssertEqual(runtime.totalLeadAttackCountForTesting, 1)

        runtime.scheduleStructuralPlan(remixed)
        runtime.renderForTesting(.init(kind: .barBoundary, position: .init(absoluteSubdivision: 128), hostTimeSeconds: 8, tempoBPM: 100))
        XCTAssertEqual(runtime.totalLeadAttackCountForTesting, 1)
        XCTAssertEqual(runtime.totalLeadReleaseCountForTesting, 0)
        XCTAssertEqual(runtime.inactiveLeadVoiceCountForTesting, 1)

        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 160), hostTimeSeconds: 10, tempoBPM: 100))
        XCTAssertEqual(runtime.inactiveWorldRecycleCountForTesting, 0)
        XCTAssertEqual(runtime.inactiveBankActiveTonalVoiceCountForTesting, 1)
        XCTAssertEqual(runtime.totalLeadAttackCountForTesting, 1)
        XCTAssertEqual(runtime.totalLeadReleaseCountForTesting, 0)

        runtime.endLead()
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 161), hostTimeSeconds: 10.1, tempoBPM: 100))
        XCTAssertEqual(runtime.inactiveWorldRecycleCountForTesting, 1)
        XCTAssertEqual(runtime.inactiveBankActiveTonalVoiceCountForTesting, 0)
        XCTAssertEqual(runtime.totalLeadAttackCountForTesting, 1)
        XCTAssertEqual(runtime.totalLeadReleaseCountForTesting, 1)
    }

    func testStartUsesTheApprovedSessionBankTransportAndFadeOrder() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let plan = makePlaybackEnginePlan(seed: 41)

        try await engine.start(plan: plan)

        XCTAssertEqual(log.values, [
            "session.configure.playback",
            "session.activate",
            "runtime.prepare:41",
            "runtime.audio.start",
            "runtime.transport.start:41",
            "runtime.master.fade:41",
        ])
        XCTAssertEqual(engine.state, .on)
        XCTAssertEqual(engine.metrics.engineStartCount, 1)
        XCTAssertEqual(engine.metrics.activeTransportCount, 1)
    }

    func testEveryStartStageFailureRunsAtomicTeardownAndLeavesRetryableError() async {
        for stage in PlaybackEngineFailureStage.allCases {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
            session.failureStage = stage
            runtime.failureStage = stage
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
            let plan = makePlaybackEnginePlan(seed: 0xCAFE)

            do {
                try await engine.start(plan: plan)
                XCTFail("Expected start failure at \(stage)")
            } catch {}

            guard case .error = engine.state else {
                XCTFail("Expected retryable error at \(stage), got \(engine.state)")
                continue
            }
            XCTAssertEqual(engine.currentPlan, plan, "A failed start must retain the requested lab plan")
            XCTAssertEqual(engine.metrics.activeTransportCount, 0)
            XCTAssertEqual(engine.metrics.activeTaskCount, 0)
            XCTAssertEqual(engine.metrics.activeVoiceCount, 0)
            XCTAssertEqual(engine.metrics.leadVoiceCount, 0)
            XCTAssertEqual(engine.metrics.pendingRemixCount, 0)
            XCTAssertFalse(session.isActive)
            XCTAssertTrue(log.values.contains("runtime.scheduling.stop"))
            XCTAssertTrue(log.values.contains("runtime.lead.end"))
            XCTAssertTrue(log.values.contains("runtime.remix.cancel"))
            XCTAssertTrue(log.values.contains("runtime.layers.release"))
            XCTAssertTrue(log.values.contains("runtime.transport-effects.stop"))
            XCTAssertTrue(log.values.contains("runtime.tail.drain"))
            XCTAssertTrue(log.values.contains("runtime.audio.stop"))
            if stage != .configureSession {
                XCTAssertEqual(session.deactivationOptions.last, .notifyOthersOnDeactivation)
            }
        }
    }

    func testFailureIsRetryableWithoutReplacingTheEngineOrPlan() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.failureStage = .prepare
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let plan = makePlaybackEnginePlan(seed: 88)

        do { try await engine.start(plan: plan) } catch {}
        runtime.failureStage = nil
        log.values.removeAll()

        try await engine.start(plan: plan)

        XCTAssertEqual(engine.state, .on)
        XCTAssertEqual(engine.currentPlan, plan)
        XCTAssertEqual(runtime.prepareAttempts, 2)
        XCTAssertEqual(log.values.prefix(6), [
            "session.configure.playback",
            "session.activate",
            "runtime.prepare:88",
            "runtime.audio.start",
            "runtime.transport.start:88",
            "runtime.master.fade:88",
        ])
    }

    func testConcurrentAndRepeatedStopsJoinOneOrderedTeardown() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        try await engine.start(plan: makePlaybackEnginePlan(seed: 9))
        log.values.removeAll()
        runtime.suspendTailDrain = true

        let first = Task { @MainActor in await engine.stop() }
        await runtime.waitUntilTailDrainBegins()
        let second = Task { @MainActor in await engine.stop() }
        await Task.yield()
        runtime.resumeTailDrain()
        await first.value
        await second.value
        await engine.stop()

        XCTAssertEqual(log.values, [
            "runtime.scheduling.stop",
            "runtime.lead.end",
            "runtime.remix.cancel",
            "runtime.layers.release",
            "runtime.transport-effects.stop",
            "runtime.tail.drain",
            "runtime.audio.stop",
            "session.deactivate.notifyOthers",
        ])
        XCTAssertEqual(engine.state, .off)
        XCTAssertEqual(engine.metrics.activeTransportCount, 0)
        XCTAssertFalse(session.isActive)
    }

    func testStopRacingSuspendedStartWinsAndCannotFadeOrReturnOn() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendTransportStart = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let plan = makePlaybackEnginePlan(seed: 123)

        let start = Task { @MainActor in try await engine.start(plan: plan) }
        await runtime.waitUntilTransportStartBegins()
        let stop = Task { @MainActor in await engine.stop() }
        await Task.yield()

        engine.applyContinuous(makePlaybackEnginePlan(seed: 124))
        engine.beginLead(.init(normalizedX: 0.4, normalizedY: 0.6, speed: 0))
        runtime.resumeTransportStart()
        try await start.value
        await stop.value

        XCTAssertEqual(engine.state, .off)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(log.values.contains("runtime.master.fade:123"))
        XCTAssertEqual(runtime.continuousCount, 0)
        XCTAssertEqual(runtime.beginLeadCount, 0)
    }

    func testTwentyFiveSoundCyclesKeepRuntimeMetricsFixedAndLeaveNoActiveTokens() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let plan = makePlaybackEnginePlan(seed: 0x25)

        for cycle in 1...25 {
            try await engine.start(plan: plan)

            XCTAssertEqual(engine.state, .on, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.engineStartCount, cycle, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTransportCount, 1, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTaskCount, 1, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeNodeCount, 64, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeVoiceCount, 4, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeHappeningCount, 2, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.pendingRemixCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.leadVoiceCount, 0, "cycle \(cycle)")

            await engine.stop()

            XCTAssertEqual(engine.state, .off, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.engineStartCount, cycle, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTransportCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTaskCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeNodeCount, 64, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeVoiceCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeHappeningCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.pendingRemixCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.leadVoiceCount, 0, "cycle \(cycle)")
            XCTAssertFalse(session.isActive, "cycle \(cycle)")
        }
    }

    func testLiveRuntimeTwentyFiveSoundCyclesPreserveRealFixedAllocationsAndDrain() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let plan = makePlaybackEnginePlan(seed: 0x2500, happeningIDs: [])
        try runtime.prepare(plan: plan)
        let baseline = runtime.allocationSnapshotForTesting

        XCTAssertGreaterThan(baseline.activeNodeCount, 0)
        XCTAssertGreaterThan(baseline.poolCount, 0)
        XCTAssertFalse(baseline.fixedSharedNodeIdentities.isEmpty)
        XCTAssertEqual(baseline.instrumentAllocationFingerprint.count, 2)
        XCTAssertTrue(baseline.instrumentAllocationFingerprint.allSatisfy { $0 != nil })
        XCTAssertTrue(baseline.allocatedTonalVoiceCounts.allSatisfy { $0 > 0 })
        XCTAssertTrue(baseline.allocatedPianoVoiceCounts.allSatisfy { $0 > 0 })
        XCTAssertTrue(baseline.allocatedDrumPlayerCounts.allSatisfy { $0 > 0 })

        for cycle in 1...25 {
            try await engine.start(plan: plan)

            XCTAssertEqual(runtime.allocationSnapshotForTesting, baseline, "started cycle \(cycle)")
            XCTAssertEqual(runtime.playbackPairMetricsForTesting.lifecycleState, .started, "cycle \(cycle)")
            XCTAssertTrue(runtime.playbackPairMetricsForTesting.sharedEngineIsRunning, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTransportCount, 1, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTaskCount, 1, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeNodeCount, baseline.activeNodeCount, "cycle \(cycle)")

            await engine.stop()

            XCTAssertEqual(runtime.allocationSnapshotForTesting, baseline, "stopped cycle \(cycle)")
            XCTAssertEqual(runtime.playbackPairMetricsForTesting.lifecycleState, .prepared, "cycle \(cycle)")
            XCTAssertFalse(runtime.playbackPairMetricsForTesting.sharedEngineIsRunning, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTransportCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeTaskCount, 0, "cycle \(cycle)")
            XCTAssertEqual(engine.metrics.activeVoiceCount, 0, "cycle \(cycle)")
            XCTAssertEqual(runtime.metrics.leadTokenCount, 0, "cycle \(cycle)")
            XCTAssertEqual(runtime.metrics.happeningTokenCount, 0, "cycle \(cycle)")
            XCTAssertTrue(runtime.happeningRecordIDsForTesting.isEmpty, "cycle \(cycle)")
            XCTAssertFalse(session.isActive, "cycle \(cycle)")
        }
    }

    func testLiveRuntimeHappeningsZeroToTenLoopsPreserveRealAllocationsAndRemoveRecords() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let emptyPlan = makePlaybackEnginePlan(seed: 0x10, happeningIDs: [])
        let fullPlan = makePlaybackEnginePlan(
            seed: 0x10,
            happeningIDs: (1...10).map { "live-happening-\($0)" }
        )
        try await engine.start(plan: emptyPlan)
        let baseline = runtime.allocationSnapshotForTesting
        var ambientVoiceCountAfterRemoval: Int?

        for cycle in 1...10 {
            fullPlan.happenings.forEach { engine.addHappening($0, playBirth: true) }
            XCTAssertEqual(runtime.happeningRecordIDsForTesting, Set(fullPlan.happenings.map(\.happeningID)), "add cycle \(cycle)")
            XCTAssertEqual(runtime.playbackMetrics.activeHappeningCount, 10, "add cycle \(cycle)")
            XCTAssertEqual(runtime.allocationSnapshotForTesting, baseline, "add cycle \(cycle)")
            XCTAssertEqual(runtime.playbackMetrics.activeTransportCount, 1, "add cycle \(cycle)")
            XCTAssertEqual(runtime.playbackMetrics.activeTaskCount, 1, "add cycle \(cycle)")

            fullPlan.happenings.forEach { engine.removeHappening(id: $0.happeningID) }
            XCTAssertTrue(runtime.happeningRecordIDsForTesting.isEmpty, "remove cycle \(cycle)")
            XCTAssertEqual(runtime.playbackMetrics.activeHappeningCount, 0, "remove cycle \(cycle)")
            XCTAssertEqual(runtime.metrics.happeningTokenCount, 0, "remove cycle \(cycle)")
            if let ambientVoiceCountAfterRemoval {
                XCTAssertEqual(
                    runtime.playbackMetrics.activeVoiceCount,
                    ambientVoiceCountAfterRemoval,
                    "remove cycle \(cycle)"
                )
            } else {
                ambientVoiceCountAfterRemoval = runtime.playbackMetrics.activeVoiceCount
            }
            XCTAssertEqual(runtime.allocationSnapshotForTesting, baseline, "remove cycle \(cycle)")
            XCTAssertEqual(runtime.playbackMetrics.activeTransportCount, 1, "remove cycle \(cycle)")
            XCTAssertEqual(runtime.playbackMetrics.activeTaskCount, 1, "remove cycle \(cycle)")
        }

        await engine.stop()
        XCTAssertEqual(runtime.allocationSnapshotForTesting, baseline)
        XCTAssertEqual(runtime.playbackMetrics.activeTaskCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.activeTransportCount, 0)
        XCTAssertEqual(runtime.playbackMetrics.activeVoiceCount, 0)
        XCTAssertEqual(runtime.metrics.leadTokenCount, 0)
        XCTAssertEqual(runtime.metrics.happeningTokenCount, 0)
        XCTAssertTrue(runtime.happeningRecordIDsForTesting.isEmpty)
    }

    func testLiveRuntimeUsesFourSamplePlayersPerPreparedWorldAndOneSharedEngineStart() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)

        try await engine.start(plan: makePlaybackEnginePlan(seed: 0x404, happeningIDs: []))

        let metrics = runtime.playbackPairMetricsForTesting
        XCTAssertEqual(Set(metrics.happeningFixedPlayerIdentities).count, 4)
        XCTAssertEqual(metrics.happeningFixedPlayerIdentities.count, 4)
        XCTAssertEqual(Set(metrics.happeningDecodedBufferIdentities).count, 102)
        XCTAssertEqual(metrics.happeningDecodedBufferIdentities.count, 102)
        XCTAssertLessThanOrEqual(metrics.happeningDecodedByteCount, 48 * 1_024 * 1_024)
        XCTAssertEqual(Set(metrics.finalPeakLimiterIdentities).count, 1)
        XCTAssertEqual(metrics.sharedAudioEngineCount, 1)
        XCTAssertEqual(metrics.sharedEngineStartCount, 1)

        await engine.stop()
    }
}

@MainActor
private final class PlaybackEngineCallLog {
    var values: [String] = []
}

private enum PlaybackEngineFailureStage: CaseIterable {
    case configureSession
    case activateSession
    case prepare
    case audioStart
    case transportStart
    case masterFade
}

@MainActor
private final class RecordingDayObjectsAudioSession: DayObjectsAudioSessionProtocol {
    let log: PlaybackEngineCallLog
    var failureStage: PlaybackEngineFailureStage?
    private(set) var isActive = false
    private(set) var activationCount = 0
    private(set) var deactivationOptions: [AVAudioSession.SetActiveOptions] = []

    init(log: PlaybackEngineCallLog) { self.log = log }

    func configurePlayback() throws {
        log.values.append("session.configure.playback")
        if failureStage == .configureSession { throw DayObjectsAudioError("configure") }
    }

    func activate() throws {
        log.values.append("session.activate")
        if failureStage == .activateSession { throw DayObjectsAudioError("activate") }
        isActive = true
        activationCount += 1
    }

    func deactivate(options: AVAudioSession.SetActiveOptions) throws {
        deactivationOptions.append(options)
        isActive = false
        log.values.append("session.deactivate.notifyOthers")
    }
}

@MainActor
private final class RecordingDayObjectsPlaybackRuntime: DayObjectsPlaybackRuntimeProtocol {
    let log: PlaybackEngineCallLog
    var failureStage: PlaybackEngineFailureStage?
    var suspendTailDrain = false
    var suspendTransportStart = false
    var suspendSamplePreparation = false
    private var tailDrainContinuation: CheckedContinuation<Void, Never>?
    private var tailDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var transportStartContinuation: CheckedContinuation<Void, Never>?
    private var transportStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var samplePreparationContinuation: CheckedContinuation<Void, Never>?
    private var samplePreparationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var prepareAttempts = 0
    private(set) var samplePreparationAttempts = 0
    private(set) var samplePreparationWasCancelled = false
    private(set) var auditionRequests: [String] = []
    private(set) var releaseAuditionCount = 0
    private(set) var audioStartCount = 0
    private(set) var continuousCount = 0
    private(set) var beginLeadCount = 0
    private var running = false

    var playbackMetrics: DayObjectsPlaybackMetrics {
        .init(
            activeTransportCount: running ? 1 : 0,
            activeTaskCount: running ? 1 : 0,
            activeNodeCount: 64,
            activeVoiceCount: running ? 4 : 0,
            activeHappeningCount: running ? 2 : 0,
            pendingRemixCount: 0,
            leadVoiceCount: 0
        )
    }

    init(log: PlaybackEngineCallLog) { self.log = log }

    func prepare(plan: DayMusicPlan) throws {
        prepareAttempts += 1
        log.values.append("runtime.prepare:\(plan.seed)")
        if failureStage == .prepare { throw DayObjectsAudioError("prepare") }
    }

    func startAudio() throws {
        log.values.append("runtime.audio.start")
        if failureStage == .audioStart { throw DayObjectsAudioError("audio") }
        audioStartCount += 1
    }

    func startTransport(plan: DayMusicPlan) async throws {
        log.values.append("runtime.transport.start:\(plan.seed)")
        transportStartWaiters.forEach { $0.resume() }
        transportStartWaiters.removeAll()
        if suspendTransportStart {
            await withCheckedContinuation { transportStartContinuation = $0 }
        }
        if failureStage == .transportStart { throw DayObjectsAudioError("transport") }
        running = true
    }

    func fadeMaster(to plan: DayMusicPlan) throws {
        log.values.append("runtime.master.fade:\(plan.seed)")
        if failureStage == .masterFade { throw DayObjectsAudioError("fade") }
    }

    func stopScheduling() { log.values.append("runtime.scheduling.stop") }
    func endLead() { log.values.append("runtime.lead.end") }
    func cancelRemix() { log.values.append("runtime.remix.cancel") }
    func releaseLayers() {
        running = false
        log.values.append("runtime.layers.release")
    }
    func stopTransportAndEffects() async {
        log.values.append("runtime.transport-effects.stop")
    }
    func drainTail() async {
        log.values.append("runtime.tail.drain")
        tailDrainWaiters.forEach { $0.resume() }
        tailDrainWaiters.removeAll()
        guard suspendTailDrain else { return }
        await withCheckedContinuation { continuation in
            tailDrainContinuation = continuation
        }
    }
    func stopAudio() async { log.values.append("runtime.audio.stop") }
    func prepareSamples(recipeIDs: Set<HappeningSoundRecipeID>) async throws {
        samplePreparationAttempts += 1
        log.values.append("runtime.samples.prepare")
        samplePreparationWaiters.forEach { $0.resume() }
        samplePreparationWaiters.removeAll()
        if suspendSamplePreparation {
            await withTaskCancellationHandler {
                await withCheckedContinuation { samplePreparationContinuation = $0 }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.samplePreparationWasCancelled = true
                }
            }
        }
    }
    func auditionHappening(
        _ recipeID: HappeningSoundRecipeID,
        harmony: DayObjectsHappeningAuditionHarmony
    ) throws {
        let value = "\(recipeID.rawValue):\(harmony)"
        auditionRequests.append(value)
        log.values.append("runtime.audition:\(value)")
    }
    func releaseAuditions() {
        releaseAuditionCount += 1
        log.values.append("runtime.auditions.release")
    }
    func applyContinuous(_ plan: DayMusicPlan) { continuousCount += 1 }
    func scheduleStructuralPlan(_ plan: DayMusicPlan) {}
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) {}
    func removeHappening(id: String) {}
    func beginLead(_ gesture: LeadGestureSample) { beginLeadCount += 1 }
    func updateLead(_ gesture: LeadGestureSample) {}

    func waitUntilTailDrainBegins() async {
        if tailDrainContinuation != nil { return }
        await withCheckedContinuation { continuation in
            tailDrainWaiters.append(continuation)
        }
    }

    func resumeTailDrain() {
        suspendTailDrain = false
        tailDrainContinuation?.resume()
        tailDrainContinuation = nil
    }

    func waitUntilTransportStartBegins() async {
        if transportStartContinuation != nil { return }
        await withCheckedContinuation { transportStartWaiters.append($0) }
    }

    func resumeTransportStart() {
        suspendTransportStart = false
        transportStartContinuation?.resume()
        transportStartContinuation = nil
    }

    func waitUntilSamplePreparationBegins() async {
        if samplePreparationContinuation != nil { return }
        await withCheckedContinuation { samplePreparationWaiters.append($0) }
    }

    func resumeSamplePreparation() {
        suspendSamplePreparation = false
        samplePreparationContinuation?.resume()
        samplePreparationContinuation = nil
    }
}

private func makePlaybackEnginePlan(
    seed: UInt64,
    happeningIDs: [String] = ["a", "b"]
) -> DayMusicPlan {
    DeterministicMusicDirector.makePlan(
        input: DayMusicInput(
            countedSteps: 7_500,
            stepGoal: 10_000,
            countedSleepHours: 6,
            sleepGoalHours: 8,
            happeningIDs: happeningIDs,
            spentColors: 20
        ),
        remixSeed: seed
    )
}
#endif
