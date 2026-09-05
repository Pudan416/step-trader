#if DEBUG || INTERNAL_BUILD
import AVFAudio
import class AudioKit.AudioEngine
import class AudioKit.Mixer
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsMusicPlaybackEngineTests: XCTestCase {
    func testMobileRuntimeReferenceC4AuditionLegallyResolvesEveryCatalogRecipe() async throws {
        try requireLiveAudioOutput()
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let recipes = HappeningSoundCatalog.recipes
        let recipeIDs = Set(recipes.map(\.id))

        try await runtime.prepareSamples(recipeIDs: recipeIDs)
        try runtime.startAudio()
        for recipeID in recipeIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            try runtime.auditionHappening(recipeID, harmony: .referenceC4)
            runtime.releaseAuditions()
        }

        let records = runtime.auditionRecordsForTesting
        XCTAssertEqual(records.count, 30)
        XCTAssertTrue(records.allSatisfy { $0.priority == .manualAudition })
        for record in records {
            let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: record.resolvedSound.recipeID))
            switch recipe.pitch {
            case .tonal(let range):
                let target = try XCTUnwrap(record.resolvedSound.targetMIDI)
                XCTAssertTrue(range.contains(target), "recipe \(recipe.id.rawValue)")
                XCTAssertTrue([0, 2, 4, 7, 9].contains(target % 12))
                XCTAssertNotNil(record.resolvedSound.sourceRootMIDI)
                XCTAssertGreaterThan(record.resolvedSound.playbackRate, 0)
                XCTAssertNil(record.resolvedSound.resonantFilterHz)
            case .resonantNoise(_, let range, let targetPitchClasses):
                let target = try XCTUnwrap(record.resolvedSound.targetMIDI)
                XCTAssertTrue(range.contains(target), "recipe \(recipe.id.rawValue)")
                XCTAssertTrue(targetPitchClasses.contains(target % 12))
                XCTAssertGreaterThan(record.resolvedSound.playbackRate, 0)
                XCTAssertGreaterThan(try XCTUnwrap(record.resolvedSound.resonantFilterHz), 0)
            case .unpitched:
                XCTAssertNil(record.resolvedSound.targetMIDI)
                XCTAssertEqual(record.resolvedSound.playbackRate, 1)
                XCTAssertNil(record.resolvedSound.resonantFilterHz)
            }
            XCTAssertEqual(record.effects, .init(
                filterCutoffHz: recipe.filterEndHz,
                delayMix: recipe.delayMix,
                delayFeedback: recipe.delayFeedback,
                reverbMix: recipe.reverbMix
            ))
        }

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
            kind: .subdivision,
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

        XCTAssertEqual(runtime.auditionRequests.count, 3)
        XCTAssertEqual(Dictionary(grouping: runtime.auditionRequests, by: { $0 }).mapValues(\.count), [
            "7:referenceC4": 1,
            "25:referenceC4": 1,
            "28:referenceC4": 1,
        ])
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
        XCTAssertEqual(runtime.auditionRequests, ["9:referenceC4"])
        XCTAssertTrue(runtime.activeAuditionRequests.isEmpty, "A successful full commit must clear reference tails")
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

    func testFreshMobileRuntimeColdAuditionThenRepeatedStopIsSafeAndTruthful() async throws {
        try requireLiveAudioOutput()
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 28))

        try await engine.auditionHappening(recipeID)
        await engine.stop()
        await engine.stop()

        XCTAssertEqual(engine.runtimeState, .stopped)
        XCTAssertEqual(engine.metrics.activeTaskCount, 0)
        XCTAssertEqual(engine.metrics.activeVoiceCount, 0)
        XCTAssertEqual(runtime.auditionHandleCountForTesting, 0)
        XCTAssertEqual(runtime.auditionReleaseTaskCountForTesting, 0)
        XCTAssertFalse(runtime.audioEngineIsRunningForTesting)
        XCTAssertFalse(session.isActive)
    }

    func testFreshLiveRuntimeColdAuditionThenRepeatedStopIsSafeAndTruthful() async throws {
        try requireLiveAudioOutput()
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))

        try await engine.auditionHappening(recipeID)
        await engine.stop()
        await engine.stop()

        XCTAssertEqual(engine.runtimeState, .stopped)
        XCTAssertEqual(engine.metrics.activeTaskCount, 0)
        XCTAssertEqual(engine.metrics.activeVoiceCount, 0)
        XCTAssertEqual(runtime.auditionHandleCountForTesting, 0)
        XCTAssertEqual(runtime.auditionReleaseTaskCountForTesting, 0)
        XCTAssertFalse(runtime.audioEngineIsRunningForTesting)
        XCTAssertFalse(session.isActive)
    }

    func testRealRuntimeLifecycleDisappearanceAndInterruptionAreSafeAndIdempotent() async throws {
        try requireLiveAudioOutput()
        let mobileLog = PlaybackEngineCallLog()
        let mobileSession = RecordingDayObjectsAudioSession(log: mobileLog)
        let mobileRuntime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let mobileEngine = DayObjectsMusicPlaybackEngine(audioSession: mobileSession, runtime: mobileRuntime)
        let mobileController = DayObjectsMusicLabController(playback: mobileEngine)
        let unpitched = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 28))
        try await mobileController.auditionHappening(unpitched)

        await mobileController.viewDidDisappear()
        await mobileController.viewDidDisappear()

        XCTAssertEqual(mobileEngine.runtimeState, .stopped)
        XCTAssertEqual(mobileRuntime.auditionHandleCountForTesting, 0)
        XCTAssertEqual(mobileRuntime.auditionReleaseTaskCountForTesting, 0)
        XCTAssertFalse(mobileRuntime.audioEngineIsRunningForTesting)
        XCTAssertFalse(mobileSession.isActive)

        let liveLog = PlaybackEngineCallLog()
        let liveSession = RecordingDayObjectsAudioSession(log: liveLog)
        let liveRuntime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let liveEngine = DayObjectsMusicPlaybackEngine(audioSession: liveSession, runtime: liveRuntime)
        let liveController = DayObjectsMusicLabController(playback: liveEngine)
        let resonant = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
        try await liveController.auditionHappening(resonant)

        await liveController.interruptionBegan()
        await liveController.interruptionBegan()

        XCTAssertEqual(liveEngine.runtimeState, .stopped)
        XCTAssertEqual(liveRuntime.auditionHandleCountForTesting, 0)
        XCTAssertEqual(liveRuntime.auditionReleaseTaskCountForTesting, 0)
        XCTAssertFalse(liveRuntime.audioEngineIsRunningForTesting)
        XCTAssertFalse(liveSession.isActive)
    }

    func testRealRuntimeInjectedColdAndUpgradeFailuresLeaveTruthfulCleanup() async throws {
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))

        for stage in [RealRuntimeFailureStage.sessionActivation, .samplePreparation] {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let mobile = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
            let runtime = FaultInjectingRealPlaybackRuntime(base: mobile, failureStage: stage)
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)

            if stage == .sessionActivation {
                session.failureStage = .activateSession
                _ = try? await engine.auditionHappening(recipeID)
                XCTAssertEqual(engine.runtimeState, .stopped, "\(stage)")
                XCTAssertFalse(session.isActive, "\(stage)")
            } else if stage == .samplePreparation {
                _ = try? await engine.auditionHappening(recipeID)
                XCTAssertEqual(engine.runtimeState, .stopped, "\(stage)")
                XCTAssertFalse(session.isActive, "\(stage)")
            }

            XCTAssertEqual(mobile.auditionHandleCountForTesting, 0, "\(stage)")
            XCTAssertEqual(mobile.auditionReleaseTaskCountForTesting, 0, "\(stage)")
            XCTAssertFalse(mobile.audioEngineIsRunningForTesting, "\(stage)")
        }

        try requireLiveAudioOutput()
        for stage in [RealRuntimeFailureStage.fullPreparation, .transportStart] {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let mobile = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
            let runtime = FaultInjectingRealPlaybackRuntime(base: mobile, failureStage: stage)
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)

            try await engine.auditionHappening(recipeID)
            _ = try? await engine.start(plan: makePlaybackEnginePlan(seed: 0xFA11))
            XCTAssertEqual(engine.runtimeState, .sampleOnly, "\(stage)")
            XCTAssertTrue(session.isActive, "\(stage)")
            await engine.stop()
            XCTAssertEqual(engine.runtimeState, .stopped, "\(stage)")
            XCTAssertFalse(session.isActive, "\(stage)")
            XCTAssertEqual(mobile.auditionHandleCountForTesting, 0, "\(stage)")
            XCTAssertEqual(mobile.auditionReleaseTaskCountForTesting, 0, "\(stage)")
            XCTAssertFalse(mobile.audioEngineIsRunningForTesting, "\(stage)")
        }
    }

    func testInjectedSampleAudioStartFailureCleansUnboundWorldsAndRepeatedStopIsSafe() async throws {
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))

        do {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let mobile = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
            let runtime = FaultInjectingRealPlaybackRuntime(base: mobile, failureStage: nil)
            runtime.injectAudioStartFailure = true
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)

            await assertInjectedSampleStartFailure(
                engine: engine,
                session: session,
                recipeID: recipeID,
                audioIsRunning: { mobile.audioEngineIsRunningForTesting }
            )
        }

        do {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let live = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
            let runtime = FaultInjectingRealPlaybackRuntime(base: live, failureStage: nil)
            runtime.injectAudioStartFailure = true
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)

            await assertInjectedSampleStartFailure(
                engine: engine,
                session: session,
                recipeID: recipeID,
                audioIsRunning: { live.audioEngineIsRunningForTesting }
            )
        }

        final class OfflineProbe {}
        let probe = OfflineProbe()
        XCTAssertNoThrow(try DayObjectsAudioPlaybackLease.shared.acquireOffline(owner: probe))
        DayObjectsAudioPlaybackLease.shared.releaseOffline(owner: probe)
    }

    func testColdWaiterAwaitsSuccessfulFullStartAndAttacksCurrentHarmonyExactlyOnce() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 7))

        let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
        await runtime.waitUntilSamplePreparationBegins()
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xA771))
        }
        await Task.yield()
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()

        XCTAssertTrue(runtime.auditionRequests.isEmpty)
        runtime.resumeTransportStart()
        try await start.value
        try await audition.value

        XCTAssertEqual(runtime.auditionRequests, ["7:currentHarmony"])
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(runtime.audioStartCount, 1)
        XCTAssertEqual(engine.runtimeState, .fullMusic)
    }

    func testAuditionArrivingDuringSuspendedFullStartAwaitsCurrentHarmony() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendTransportStart = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 19))

        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xA772))
        }
        await runtime.waitUntilTransportStartBegins()
        let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
        await Task.yield()

        XCTAssertTrue(runtime.auditionRequests.isEmpty)
        runtime.resumeTransportStart()
        try await start.value
        try await audition.value

        XCTAssertEqual(runtime.auditionRequests, ["19:currentHarmony"])
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(engine.runtimeState, .fullMusic)
    }

    func testColdWaiterAttacksReferenceExactlyOnceAfterFailedFullStart() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        runtime.failureStage = .transportStart
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))

        let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
        await runtime.waitUntilSamplePreparationBegins()
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xFA17))
        }
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        XCTAssertTrue(runtime.auditionRequests.isEmpty)
        runtime.resumeTransportStart()
        _ = try? await start.value
        try await audition.value

        XCTAssertEqual(runtime.auditionRequests, ["25:referenceC4"])
        XCTAssertEqual(engine.runtimeState, .sampleOnly)
        XCTAssertTrue(session.isActive)
    }

    func testCancellingOneWaiterDuringFullStartDoesNotCancelStartOrOtherWaiter() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let cancelledID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let retainedID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 2))

        let cancelled = Task { @MainActor in try await engine.auditionHappening(cancelledID) }
        await runtime.waitUntilSamplePreparationBegins()
        let retained = Task { @MainActor in try await engine.auditionHappening(retainedID) }
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xA773))
        }
        cancelled.cancel()
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        runtime.resumeTransportStart()
        _ = try? await cancelled.value
        try await retained.value
        try await start.value

        XCTAssertEqual(runtime.auditionRequests, ["2:currentHarmony"])
        XCTAssertFalse(runtime.samplePreparationWasCancelled)
        XCTAssertEqual(engine.runtimeState, .fullMusic)
        XCTAssertEqual(session.activationCount, 1)
    }

    func testStopWhileFullStartAwaitsCancelledColdPreparationCannotFormTeardownCycle() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 7))
        let stalePlan = makePlaybackEnginePlan(seed: 0xC01D)
        let freshPlan = makePlaybackEnginePlan(seed: 0xC01E)

        let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
        await runtime.waitUntilSamplePreparationBegins()
        let staleStart = Task { @MainActor in try await engine.start(plan: stalePlan) }
        try await waitUntil(timeout: .seconds(1)) { engine.hasFullStartTaskForTesting }

        let stopCompleted = expectation(description: "stop completes after cancelled cold preparation fails")
        let stop = Task { @MainActor in
            await engine.stop()
            stopCompleted.fulfill()
        }
        try await waitUntil(timeout: .seconds(1)) {
            engine.hasTeardownTaskForTesting && runtime.samplePreparationWasCancelled
        }
        runtime.resumeSamplePreparation()

        await fulfillment(of: [stopCompleted], timeout: 1)
        guard !engine.hasTeardownTaskForTesting else {
            audition.cancel()
            staleStart.cancel()
            stop.cancel()
            return
        }
        _ = try? await audition.value
        _ = try? await staleStart.value
        await stop.value

        XCTAssertEqual(engine.state, .off)
        XCTAssertEqual(engine.runtimeState, .stopped)
        XCTAssertFalse(engine.hasFullStartTaskForTesting)
        XCTAssertFalse(engine.hasSamplePreparationTaskForTesting)
        XCTAssertFalse(engine.hasTeardownTaskForTesting)
        XCTAssertFalse(session.isActive)

        try await engine.start(plan: freshPlan)

        XCTAssertFalse(log.values.contains("runtime.master.fade:\(stalePlan.seed)"))
        XCTAssertEqual(
            log.values.filter { $0 == "runtime.master.fade:\(freshPlan.seed)" }.count,
            1
        )
        XCTAssertEqual(engine.currentPlan, freshPlan)
        XCTAssertEqual(engine.state, .on)
        await engine.stop()
    }

    func testPreStopStartWaitingOnOlderBarrierIsInvalidatedWhilePostStopStartOwnsPlan() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let initialPlan = makePlaybackEnginePlan(seed: 0xB001)
        let preStopPlan = makePlaybackEnginePlan(seed: 0xB002)
        let postStopPlan = makePlaybackEnginePlan(seed: 0xB003)
        try await engine.start(plan: initialPlan)
        runtime.suspendTailDrain = true

        let firstStop = Task { @MainActor in await engine.stop() }
        await runtime.waitUntilTailDrainBegins()

        let preStopEntered = expectation(description: "pre-stop start entered old barrier")
        let preStopStart = Task { @MainActor in
            preStopEntered.fulfill()
            try await engine.start(plan: preStopPlan)
        }
        await fulfillment(of: [preStopEntered], timeout: 1)

        let secondStopEntered = expectation(description: "second stop advanced the lifecycle epoch")
        let secondStop = Task { @MainActor in
            secondStopEntered.fulfill()
            await engine.stop()
        }
        await fulfillment(of: [secondStopEntered], timeout: 1)

        let postStopEntered = expectation(description: "post-stop start entered the new epoch")
        let postStopStart = Task { @MainActor in
            postStopEntered.fulfill()
            try await engine.start(plan: postStopPlan)
        }
        await fulfillment(of: [postStopEntered], timeout: 1)

        runtime.resumeTailDrain()
        await firstStop.value
        await secondStop.value
        do {
            try await preStopStart.value
            XCTFail("A start intent that predates the second stop must be cancelled")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation for the invalidated start intent, got \(error)")
        }
        try await postStopStart.value

        XCTAssertFalse(log.values.contains("runtime.prepare:\(preStopPlan.seed)"))
        XCTAssertFalse(log.values.contains("runtime.master.fade:\(preStopPlan.seed)"))
        XCTAssertEqual(
            log.values.filter { $0 == "runtime.prepare:\(postStopPlan.seed)" }.count,
            1
        )
        XCTAssertEqual(
            log.values.filter { $0 == "runtime.master.fade:\(postStopPlan.seed)" }.count,
            1
        )
        XCTAssertEqual(runtime.prepareAttempts, 2, "Only the initial and post-stop plans may prepare")
        XCTAssertEqual(engine.currentPlan, postStopPlan)
        XCTAssertEqual(engine.state, .on)
        await engine.stop()
    }

    func testAuditionArrivingDuringFailedUpgradeRegistersBeforeAwaitAndAttacksReferenceOnce() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        runtime.failureStage = .transportStart
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let cancelledID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let retainedID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 2))

        let cancelled = Task { @MainActor in try await engine.auditionHappening(cancelledID) }
        await runtime.waitUntilSamplePreparationBegins()
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xF411))
        }
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        cancelled.cancel()
        try await waitUntil(timeout: .seconds(1)) { engine.auditionWaiterCountForTesting == 0 }

        let retainedEntered = expectation(description: "new audition entered during failed upgrade")
        let retained = Task { @MainActor in
            retainedEntered.fulfill()
            try await engine.auditionHappening(retainedID)
        }
        await fulfillment(of: [retainedEntered], timeout: 1)
        XCTAssertEqual(
            engine.auditionWaiterCountForTesting,
            1,
            "An arrived tap must be visible to full-start reconciliation before it awaits"
        )

        runtime.resumeTransportStart()
        _ = try? await cancelled.value
        _ = try? await start.value
        try await retained.value

        XCTAssertEqual(runtime.auditionRequests, ["2:referenceC4"])
        XCTAssertEqual(engine.auditionWaiterCountForTesting, 0)
        XCTAssertEqual(engine.runtimeState, .sampleOnly)
        XCTAssertTrue(session.isActive)
        await engine.stop()
    }

    func testAuditionArrivingDuringSuccessfulUpgradeRegistersBeforeAwaitAndAttacksCurrentHarmonyOnce() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let cancelledID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let retainedID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 19))

        let cancelled = Task { @MainActor in try await engine.auditionHappening(cancelledID) }
        await runtime.waitUntilSamplePreparationBegins()
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xF412))
        }
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        cancelled.cancel()
        try await waitUntil(timeout: .seconds(1)) { engine.auditionWaiterCountForTesting == 0 }

        let retainedEntered = expectation(description: "new audition entered during successful upgrade")
        let retained = Task { @MainActor in
            retainedEntered.fulfill()
            try await engine.auditionHappening(retainedID)
        }
        await fulfillment(of: [retainedEntered], timeout: 1)
        XCTAssertEqual(engine.auditionWaiterCountForTesting, 1)

        runtime.resumeTransportStart()
        _ = try? await cancelled.value
        try await start.value
        try await retained.value

        XCTAssertEqual(runtime.auditionRequests, ["19:currentHarmony"])
        XCTAssertEqual(engine.auditionWaiterCountForTesting, 0)
        XCTAssertEqual(engine.runtimeState, .fullMusic)
        XCTAssertEqual(engine.state, .on)
        await engine.stop()
    }

    func testCancellingAuditionArrivingDuringUpgradeRemovesWaiterWithoutAttackOrLeak() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let firstID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let cancelledID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 2))

        let first = Task { @MainActor in try await engine.auditionHappening(firstID) }
        await runtime.waitUntilSamplePreparationBegins()
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xF413))
        }
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        first.cancel()
        try await waitUntil(timeout: .seconds(1)) { engine.auditionWaiterCountForTesting == 0 }

        let cancelledEntered = expectation(description: "cancelled audition entered during upgrade")
        let cancelled = Task { @MainActor in
            cancelledEntered.fulfill()
            try await engine.auditionHappening(cancelledID)
        }
        await fulfillment(of: [cancelledEntered], timeout: 1)
        XCTAssertEqual(engine.auditionWaiterCountForTesting, 1)
        cancelled.cancel()
        try await waitUntil(timeout: .seconds(1)) { engine.auditionWaiterCountForTesting == 0 }

        runtime.resumeTransportStart()
        _ = try? await first.value
        _ = try? await cancelled.value
        try await start.value

        XCTAssertTrue(runtime.auditionRequests.isEmpty)
        XCTAssertEqual(engine.auditionWaiterCountForTesting, 0)
        XCTAssertFalse(engine.hasFullStartTaskForTesting)
        XCTAssertFalse(engine.hasSamplePreparationTaskForTesting)
        await engine.stop()
        XCTAssertEqual(engine.runtimeState, .stopped)
        XCTAssertFalse(engine.hasTeardownTaskForTesting)
        XCTAssertFalse(session.isActive)
    }

    func testStopQuiescesDetachedOldStartBeforeImmediateNewPlanCommits() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendTransportStart = true
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let oldPlan = makePlaybackEnginePlan(seed: 0x0D1)
        let newPlan = makePlaybackEnginePlan(seed: 0x0D2)

        let oldStart = Task { @MainActor in try await engine.start(plan: oldPlan) }
        await runtime.waitUntilTransportStartBegins()
        let stop = Task { @MainActor in await engine.stop() }
        await Task.yield()
        let newStart = Task { @MainActor in try await engine.start(plan: newPlan) }
        await Task.yield()

        runtime.resumeTransportStart()
        _ = try? await oldStart.value
        await stop.value
        try await newStart.value

        XCTAssertFalse(log.values.contains("runtime.master.fade:\(oldPlan.seed)"))
        XCTAssertTrue(log.values.contains("runtime.master.fade:\(newPlan.seed)"))
        XCTAssertLessThan(
            try XCTUnwrap(log.values.lastIndex(of: "session.deactivate.notifyOthers")),
            try XCTUnwrap(log.values.lastIndex(of: "runtime.master.fade:\(newPlan.seed)"))
        )
        XCTAssertEqual(runtime.prepareAttempts, 2)
        XCTAssertEqual(engine.currentPlan, newPlan)
        XCTAssertEqual(engine.state, .on)
        XCTAssertEqual(engine.metrics.engineStartCount, 1)
    }

    func testStopPendingFullStartReleasesEngineAndOwnedTasksAfterOldTransportResumes() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendTransportStart = true
        var engine: DayObjectsMusicPlaybackEngine? = DayObjectsMusicPlaybackEngine(
            audioSession: session,
            runtime: runtime
        )
        weak var weakEngine = engine
        let plan = makePlaybackEnginePlan(seed: 0xDEA1)
        var start: Task<Void, Error>? = Task { @MainActor [engine] in
            try await engine?.start(plan: plan)
        }
        await runtime.waitUntilTransportStartBegins()
        var stop: Task<Void, Never>? = Task { @MainActor [engine] in
            await engine?.stop()
        }
        await Task.yield()

        runtime.resumeTransportStart()
        _ = try? await start?.value
        await stop?.value

        XCTAssertFalse(try XCTUnwrap(engine).hasFullStartTaskForTesting)
        XCTAssertFalse(try XCTUnwrap(engine).hasSamplePreparationTaskForTesting)
        XCTAssertFalse(try XCTUnwrap(engine).hasTeardownTaskForTesting)
        start = nil
        stop = nil
        engine = nil
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(weakEngine)
    }

    func testStopBeforeFullStartInnerDispatchCompletesAndImmediateRestartUsesNewPlan() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let oldPlan = makePlaybackEnginePlan(seed: 0xD15A)
        let newPlan = makePlaybackEnginePlan(seed: 0xD15B)
        let completed = expectation(description: "stop and restart complete without a task cycle")

        let oldStart = Task { @MainActor in try await engine.start(plan: oldPlan) }
        let stop = Task { @MainActor in await engine.stop() }
        let newStart = Task { @MainActor in
            defer { completed.fulfill() }
            try await engine.start(plan: newPlan)
        }

        await fulfillment(of: [completed], timeout: 1)
        guard !engine.hasTeardownTaskForTesting else {
            oldStart.cancel()
            stop.cancel()
            newStart.cancel()
            return
        }
        _ = try? await oldStart.value
        await stop.value
        try await newStart.value

        XCTAssertFalse(log.values.contains("runtime.master.fade:\(oldPlan.seed)"))
        XCTAssertTrue(log.values.contains("runtime.master.fade:\(newPlan.seed)"))
        XCTAssertEqual(engine.currentPlan, newPlan)
        XCTAssertEqual(engine.state, .on)
        XCTAssertFalse(engine.hasFullStartTaskForTesting)
        XCTAssertFalse(engine.hasTeardownTaskForTesting)
    }

    func testStartFailureAfterAwaitedStopBarrierOwnsFreshTeardownAndLeavesNoTasks() async throws {
        for failure in [PlaybackEngineFailureStage.prepare, .audioStart] {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
            runtime.suspendTransportStart = true
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
            let oldStart = Task { @MainActor in
                try await engine.start(plan: makePlaybackEnginePlan(seed: 0xBAA0))
            }
            await runtime.waitUntilTransportStartBegins()
            let stop = Task { @MainActor in await engine.stop() }
            try await waitUntil(timeout: .seconds(1)) { engine.hasTeardownTaskForTesting }
            runtime.failureStage = failure
            let failedStart = Task { @MainActor in
                try await engine.start(plan: makePlaybackEnginePlan(seed: 0xBAA1))
            }

            runtime.resumeTransportStart()
            _ = try? await oldStart.value
            await stop.value
            do {
                try await failedStart.value
                XCTFail("Expected \(failure) after the prior stop barrier")
            } catch {}

            XCTAssertEqual(engine.runtimeState, .stopped, "\(failure)")
            XCTAssertFalse(session.isActive, "\(failure)")
            XCTAssertFalse(engine.hasFullStartTaskForTesting, "\(failure)")
            XCTAssertFalse(engine.hasSamplePreparationTaskForTesting, "\(failure)")
            XCTAssertFalse(engine.hasTeardownTaskForTesting, "\(failure)")
        }
    }

    func testCancelledSoleColdWaiterFailedUpgradeReconcilesOrphanedSampleOnly() async throws {
        for failure in [PlaybackEngineFailureStage.prepare, .transportStart] {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
            runtime.suspendSamplePreparation = true
            runtime.suspendTransportStart = failure == .transportStart
            runtime.failureStage = failure
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
            let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))

            let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
            await runtime.waitUntilSamplePreparationBegins()
            let start = Task { @MainActor in
                try await engine.start(plan: makePlaybackEnginePlan(seed: 0xCA11))
            }
            runtime.resumeSamplePreparation()
            if failure == .transportStart { await runtime.waitUntilTransportStartBegins() }
            audition.cancel()
            await Task.yield()
            if failure == .transportStart { runtime.resumeTransportStart() }
            _ = try? await audition.value
            _ = try? await start.value
            for _ in 0..<5 { await Task.yield() }

            XCTAssertTrue(runtime.auditionRequests.isEmpty, "\(failure)")
            XCTAssertEqual(engine.runtimeState, .stopped, "\(failure)")
            XCTAssertEqual(engine.metrics.activeTaskCount, 0, "\(failure)")
            XCTAssertFalse(session.isActive, "\(failure)")
        }
    }

    func testCancelledSoleWaiterReconcilesWhenUpgradeFailureFinishesBeforeCancellationHandler() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        runtime.failureStage = .transportStart
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))

        let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
        await runtime.waitUntilSamplePreparationBegins()
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0x0A11))
        }
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        runtime.resumeTransportStart()
        audition.cancel()
        _ = try? await start.value
        _ = try? await audition.value
        try await waitUntil(timeout: .seconds(1)) { engine.runtimeState == .stopped }

        XCTAssertTrue(runtime.auditionRequests.isEmpty)
        XCTAssertEqual(engine.auditionWaiterCountForTesting, 0)
        XCTAssertEqual(engine.runtimeState, .stopped)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(engine.hasFullStartTaskForTesting)
        XCTAssertFalse(engine.hasSamplePreparationTaskForTesting)
        XCTAssertFalse(engine.hasTeardownTaskForTesting)
    }

    func testCancelledSoleWaiterReconcilesWhenCancellationHandlerRunsBeforeUpgradeFailure() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        runtime.failureStage = .transportStart
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))

        let audition = Task { @MainActor in try await engine.auditionHappening(recipeID) }
        await runtime.waitUntilSamplePreparationBegins()
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0x0A12))
        }
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        audition.cancel()
        try await waitUntil(timeout: .seconds(1)) { engine.auditionWaiterCountForTesting == 0 }
        runtime.resumeTransportStart()
        _ = try? await start.value
        _ = try? await audition.value
        try await waitUntil(timeout: .seconds(1)) { engine.runtimeState == .stopped }

        XCTAssertTrue(runtime.auditionRequests.isEmpty)
        XCTAssertEqual(engine.runtimeState, .stopped)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(engine.hasFullStartTaskForTesting)
        XCTAssertFalse(engine.hasSamplePreparationTaskForTesting)
        XCTAssertFalse(engine.hasTeardownTaskForTesting)
    }

    func testCancelledOneOfMultipleWaitersFailedUpgradePreservesOtherReferenceTapExactlyOnce() async throws {
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = RecordingDayObjectsPlaybackRuntime(log: log)
        runtime.suspendSamplePreparation = true
        runtime.suspendTransportStart = true
        runtime.failureStage = .transportStart
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let cancelledID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 1))
        let retainedID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 2))

        let cancelled = Task { @MainActor in try await engine.auditionHappening(cancelledID) }
        await runtime.waitUntilSamplePreparationBegins()
        let retained = Task { @MainActor in try await engine.auditionHappening(retainedID) }
        let start = Task { @MainActor in
            try await engine.start(plan: makePlaybackEnginePlan(seed: 0xFA18))
        }
        runtime.resumeSamplePreparation()
        await runtime.waitUntilTransportStartBegins()
        cancelled.cancel()
        await Task.yield()
        runtime.resumeTransportStart()
        _ = try? await cancelled.value
        _ = try? await start.value
        try await retained.value

        XCTAssertEqual(runtime.auditionRequests, ["2:referenceC4"])
        XCTAssertEqual(engine.runtimeState, .sampleOnly)
        XCTAssertTrue(session.isActive)
    }

    func testLiveRuntimePromotesSampleOwnerOnFullSuccessAndStopsEngineOnLifecycle() async throws {
        try requireLiveAudioOutput()
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let controller = DayObjectsMusicLabController(playback: engine)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
        try await engine.auditionHappening(recipeID)
        let sampleMetrics = runtime.playbackPairMetricsForTesting
        let nodeIdentities = sampleMetrics.fixedSharedNodeIdentities

        try await engine.start(plan: makePlaybackEnginePlan(seed: 0xF011, happeningIDs: []))

        XCTAssertEqual(runtime.playbackPairMetricsForTesting.lifecycleState, .started)
        XCTAssertEqual(runtime.playbackPairMetricsForTesting.individualStartedBankCount, 0)
        XCTAssertTrue(runtime.playbackPairMetricsForTesting.sharedEngineIsRunning)
        XCTAssertEqual(runtime.playbackPairMetricsForTesting.sharedEngineStartCount, sampleMetrics.sharedEngineStartCount)
        XCTAssertEqual(runtime.playbackPairMetricsForTesting.fixedSharedNodeIdentities, nodeIdentities)

        await controller.interruptionBegan()

        XCTAssertEqual(runtime.playbackPairMetricsForTesting.lifecycleState, .prepared)
        XCTAssertFalse(runtime.playbackPairMetricsForTesting.sharedEngineIsRunning)
        XCTAssertEqual(runtime.playbackPairMetricsForTesting.sharedEngineStopCount, 1)
        XCTAssertFalse(session.isActive)
    }

    func testLiveRuntimeFailedUpgradeDemotesToSampleOwnerThenRetriesAuditionAndStops() async throws {
        try requireLiveAudioOutput()
        for failure in [RealRuntimeFailureStage.fullPreparation, .transportStart] {
            let log = PlaybackEngineCallLog()
            let session = RecordingDayObjectsAudioSession(log: log)
            let live = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
            let runtime = FaultInjectingRealPlaybackRuntime(base: live, failureStage: failure)
            let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
            let firstID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
            let retryID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 28))
            try await engine.auditionHappening(firstID)
            let nodeIdentities = live.playbackPairMetricsForTesting.fixedSharedNodeIdentities

            _ = try? await engine.start(plan: makePlaybackEnginePlan(seed: 0xFA12, happeningIDs: []))

            XCTAssertEqual(engine.runtimeState, .sampleOnly, "\(failure)")
            XCTAssertEqual(
                live.playbackPairMetricsForTesting.lifecycleState,
                failure == .fullPreparation ? .unprepared : .prepared,
                "\(failure)"
            )
            XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 1, "\(failure)")
            XCTAssertTrue(live.playbackPairMetricsForTesting.sharedEngineIsRunning, "\(failure)")
            XCTAssertEqual(live.playbackPairMetricsForTesting.fixedSharedNodeIdentities, nodeIdentities, "\(failure)")
            try await engine.auditionHappening(retryID)
            await engine.stop()

            XCTAssertFalse(live.playbackPairMetricsForTesting.sharedEngineIsRunning, "\(failure)")
            XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 0, "\(failure)")
            XCTAssertFalse(session.isActive, "\(failure)")
        }
    }

    func testLiveRuntimeRepeatedColdFullEpochsKeepExplicitOwnershipAndStableCache() async throws {
        try requireLiveAudioOutput()
        let log = PlaybackEngineCallLog()
        let session = RecordingDayObjectsAudioSession(log: log)
        let live = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let runtime = FaultInjectingRealPlaybackRuntime(base: live, failureStage: nil)
        let engine = DayObjectsMusicPlaybackEngine(audioSession: session, runtime: runtime)
        let controller = DayObjectsMusicLabController(playback: engine)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
        let retryID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 28))

        try await engine.auditionHappening(recipeID)
        XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 1)
        try await engine.start(plan: makePlaybackEnginePlan(seed: 0xE001, happeningIDs: []))
        let baseline = live.allocationSnapshotForTesting
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .started)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStartCount, 1)
        await engine.stop()
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .prepared)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStopCount, 1)
        XCTAssertFalse(session.isActive)

        try await engine.auditionHappening(recipeID)
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .prepared)
        XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 1)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStartCount, 2)
        XCTAssertEqual(live.allocationSnapshotForTesting, baseline)
        runtime.failureStage = .transportStart
        _ = try? await engine.start(plan: makePlaybackEnginePlan(seed: 0xE002, happeningIDs: []))
        XCTAssertEqual(engine.runtimeState, .sampleOnly)
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .prepared)
        XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 1)
        XCTAssertTrue(live.playbackPairMetricsForTesting.sharedEngineIsRunning)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStartCount, 2)
        XCTAssertEqual(live.allocationSnapshotForTesting, baseline)

        runtime.failureStage = nil
        try await engine.auditionHappening(retryID)
        try await engine.start(plan: makePlaybackEnginePlan(seed: 0xE003, happeningIDs: []))
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .started)
        XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 0)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStartCount, 2)
        XCTAssertEqual(live.allocationSnapshotForTesting, baseline)
        await controller.interruptionBegan()
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .prepared)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStopCount, 2)
        XCTAssertFalse(session.isActive)

        try await engine.auditionHappening(recipeID)
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .prepared)
        XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 1)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStartCount, 3)
        XCTAssertEqual(live.allocationSnapshotForTesting, baseline)
        try await engine.start(plan: makePlaybackEnginePlan(seed: 0xE004, happeningIDs: []))
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .started)
        XCTAssertEqual(live.playbackPairMetricsForTesting.individualStartedBankCount, 0)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStartCount, 3)
        await engine.stop()
        XCTAssertEqual(live.playbackPairMetricsForTesting.lifecycleState, .prepared)
        XCTAssertEqual(live.playbackPairMetricsForTesting.sharedEngineStopCount, 3)
        XCTAssertFalse(live.playbackPairMetricsForTesting.sharedEngineIsRunning)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(live.allocationSnapshotForTesting, baseline)
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
            kind: .subdivision,
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
        let state = try XCTUnwrap(effects.state)
        let calibration = DayObjectsPlanAwareGainCalibration.make(
            grooveMode: plan.groove.mode,
            stepsActivityDensity: plan.rhythm.stepsProgress
        )
        XCTAssertEqual(
            state.buses.harmony.sendLevel,
            (plan.harmony.roles.map(\.reverbSend).max() ?? 0)
                * pow(10, calibration.harmonyAdjustmentDecibels / 20),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            state.buses.happenings.sendLevel,
            plan.happenings.map(\.reverbSend).max() ?? 0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(state.buses.rhythm.decay, 0.42, accuracy: 0.000_001)
        XCTAssertEqual(state.buses.harmony.decay, 0.72, accuracy: 0.000_001)
        XCTAssertEqual(state.buses.happenings.decay, 0.84, accuracy: 0.000_001)
        XCTAssertEqual(effects.rampDurationSeconds, 0.25, accuracy: 0.000_001)
    }

    func testLiveRuntimeIntroducesExistingHappeningsWhenSoundStarts() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let plan = makePlaybackEnginePlan(
            seed: 34,
            happeningIDs: (1...10).map { "existing-happening-\($0)" }
        )
        try runtime.prepare(plan: plan)

        try runtime.startPreparedWorldForTesting()
        runtime.renderForTesting(.init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: 0),
            hostTimeSeconds: 0,
            tempoBPM: plan.rhythm.tempoBPM
        ))

        let firstAttack = try XCTUnwrap(runtime.activeHappeningAttackHistoryForTesting.first)
        XCTAssertTrue(firstAttack.isBirth)
        XCTAssertEqual(firstAttack.position, MusicalPosition(absoluteSubdivision: 0))
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
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 128), hostTimeSeconds: 8, tempoBPM: 100))
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

    func testLiveRuntimeRemixAtNonzeroBoundaryHandsOffMonophonicBassWithoutOverlap() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = bassLifecyclePlan(seed: 511)
        let remixed = bassLifecyclePlan(seed: 512)
        try runtime.prepare(plan: initial)
        let allocation = runtime.allocationSnapshotForTesting
        try runtime.startPreparedWorldForTesting()
        runtime.renderForTesting(.init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: 0),
            hostTimeSeconds: 0,
            tempoBPM: initial.rhythm.tempoBPM
        ))
        XCTAssertEqual(runtime.activeBassVoiceCountForTesting, 1)

        runtime.scheduleStructuralPlan(remixed)
        renderTransportBoundary(
            at: 128,
            tempoBPM: remixed.rhythm.tempoBPM,
            into: runtime
        )

        XCTAssertEqual(runtime.remixResultForTesting, .transitioned(seed: remixed.seed))
        XCTAssertEqual(runtime.totalBassAttackCountForTesting, 2)
        XCTAssertEqual(runtime.totalBassReleaseCountForTesting, 1, "old bass gate is released before handoff")
        XCTAssertEqual(runtime.activeBassVoiceCountForTesting, 1)
        XCTAssertEqual(runtime.inactiveBassVoiceCountForTesting, 0)
        XCTAssertEqual(runtime.activeBassSchedulingOriginForTesting, 128)
        XCTAssertEqual(runtime.allocationSnapshotForTesting, allocation)
    }

    func testLiveRuntimeSameSeedStructuralHarmonyRemixSwitchesOnCycleBoundarySubdivision() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = bassLifecyclePlan(seed: 521)
        let remixed = replacingPlaybackHarmony(in: initial, crossfadeAddition: 1)
        let boundary = Int64(initial.world.cycleBars) * MusicalPosition.subdivisionsPerBar
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 0), hostTimeSeconds: 0, tempoBPM: initial.rhythm.tempoBPM))
        runtime.scheduleStructuralPlan(remixed)

        renderTransportBoundary(at: boundary, tempoBPM: remixed.rhythm.tempoBPM, into: runtime)

        XCTAssertEqual(runtime.remixResultForTesting, .transitioned(seed: remixed.seed))
        XCTAssertEqual(runtime.totalBassReleaseCountForTesting, 1)
        XCTAssertEqual(runtime.totalBassAttackCountForTesting, 2)
        XCTAssertEqual(runtime.activeBassVoiceCountForTesting, 1)
        XCTAssertEqual(runtime.inactiveBassVoiceCountForTesting, 0)
        XCTAssertEqual(runtime.activeBassSchedulingOriginForTesting, boundary)
    }

    func testMobileRuntimeInPlaceRemixSwitchesOnBoundarySubdivisionAndAttacksBassImmediately() throws {
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = bassLifecyclePlan(seed: 531)
        let remixed = bassLifecyclePlan(seed: 532)
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 0), hostTimeSeconds: 0, tempoBPM: initial.rhythm.tempoBPM))
        runtime.scheduleStructuralPlan(remixed)

        renderTransportBoundary(at: 128, tempoBPM: remixed.rhythm.tempoBPM, into: runtime)

        XCTAssertEqual(runtime.activePlanForTesting?.seed, remixed.seed)
        XCTAssertEqual(runtime.totalBassReleaseCountForTesting, 1)
        XCTAssertEqual(runtime.totalBassAttackCountForTesting, 2)
        XCTAssertEqual(runtime.activeBassVoiceCountForTesting, 1)
        XCTAssertEqual(runtime.activeBassSchedulingOriginForTesting, 128)
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

    func testLiveContinuousUpdatePreservesBassStructureAndRefreshesBassActivation() throws {
        let seed = seedProducingBass()
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: seed, steps: 1_500)
        let update = makePlaybackEnginePlan(seed: seed, steps: 10_000)
        let initialBass = try XCTUnwrap(initial.bass)
        let updateBass = try XCTUnwrap(update.bass)
        XCTAssertEqual(initialBass.events.map(\.stableID), updateBass.events.map(\.stableID))
        XCTAssertNotEqual(
            initialBass.activeEvents.map(\.stableID),
            updateBass.activeEvents.map(\.stableID)
        )
        try runtime.prepare(plan: initial)

        runtime.applyContinuous(update)

        let audibleBass = try XCTUnwrap(runtime.activePlanForTesting?.bass)
        XCTAssertEqual(audibleBass.mode, initialBass.mode)
        XCTAssertEqual(audibleBass.instrumentID, initialBass.instrumentID)
        XCTAssertEqual(audibleBass.articulation, initialBass.articulation)
        XCTAssertEqual(audibleBass.register, initialBass.register)
        XCTAssertEqual(audibleBass.events.map(\.stableID), initialBass.events.map(\.stableID))
        XCTAssertEqual(audibleBass.stepsProgress, updateBass.stepsProgress)
        XCTAssertEqual(audibleBass.activeEvents.map(\.stableID), updateBass.activeEvents.map(\.stableID))
        XCTAssertEqual(audibleBass.cutoffMultiplier, updateBass.cutoffMultiplier)
        XCTAssertEqual(audibleBass.glideMilliseconds, updateBass.glideMilliseconds)
        XCTAssertEqual(audibleBass.reverbSend, updateBass.reverbSend)
        XCTAssertEqual(
            audibleBass.ducking.maximumAttenuationDecibels,
            updateBass.ducking.maximumAttenuationDecibels
        )
    }

    func testLivePlanAwareGainUpdateUsesContinuousRampWithoutWorldRestart() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: 1, steps: 0)
        let update = makePlaybackEnginePlan(seed: 1, steps: 10_000)
        XCTAssertEqual(initial.groove.mode, .bassArp)
        XCTAssertEqual(update.groove.mode, .bassArp)
        try runtime.prepare(plan: initial)
        let allocation = runtime.allocationSnapshotForTesting
        let recycleCounts = runtime.worldRecycleCountsForTesting

        runtime.applyContinuous(update)

        let mix = try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state)
        let calibration = DayObjectsPlanAwareGainCalibration.make(
            grooveMode: .bassArp,
            stepsActivityDensity: 1
        )
        XCTAssertEqual(
            mix.rhythmTargetDecibels,
            update.mix.rhythmTargetDecibels + calibration.rhythmAdjustmentDecibels,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            mix.bassTargetDecibels,
            update.mix.bassTargetDecibels + calibration.bassAdjustmentDecibels,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            mix.harmonyTargetDecibels,
            update.mix.harmonyTargetDecibels + calibration.harmonyAdjustmentDecibels,
            accuracy: 1e-12
        )
        XCTAssertEqual(mix.happeningAggregateTargetDecibels, update.mix.happeningAggregateTargetDecibels)
        XCTAssertEqual(mix.leadVoiceTargetDecibels, update.mix.leadTargetDecibels)
        XCTAssertEqual(mix.rampDurationSeconds, 0.25, accuracy: 1e-12)
        XCTAssertEqual(runtime.allocationSnapshotForTesting, allocation)
        XCTAssertEqual(runtime.worldRecycleCountsForTesting, recycleCounts)
        XCTAssertEqual(runtime.activePlanForTesting?.seed, initial.seed)
        XCTAssertEqual(runtime.activePlanForTesting?.world, initial.world)
        XCTAssertEqual(runtime.activePlanForTesting?.rhythm.stepsProgress, 1)
    }

    func testLiveContinuousUpdateKeepsEntireBassWhenBassStructureAlsoChanges() throws {
        let seed = seedProducingBass()
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: seed, steps: 1_500)
        let initialBass = try XCTUnwrap(initial.bass)
        let alternateInstrument = try XCTUnwrap(
            DayObjectsInstrumentManifest.defaultDescriptors.first {
                $0.category == .bass && $0.id != initialBass.instrumentID
            }
        )
        let changedBass = BassPlan(
            mode: initialBass.mode,
            instrumentID: alternateInstrument.id,
            register: initialBass.register,
            articulation: initialBass.articulation,
            stepsProgress: 1,
            cutoffMultiplier: initialBass.cutoffMultiplier + 0.1,
            glideMilliseconds: initialBass.glideMilliseconds + 1,
            reverbSend: initialBass.reverbSend + 0.01,
            ducking: BassDuckingPlan(
                maximumAttenuationDecibels: initialBass.ducking.maximumAttenuationDecibels + 0.1,
                attackSeconds: initialBass.ducking.attackSeconds,
                holdSeconds: initialBass.ducking.holdSeconds,
                releaseSeconds: initialBass.ducking.releaseSeconds
            ),
            events: initialBass.events.map { event in
                BassEventPlan(
                    stableID: event.stableID,
                    chordIndex: event.chordIndex,
                    startSubdivision: event.startSubdivision,
                    durationSubdivisions: event.durationSubdivisions,
                    midiNote: event.midiNote,
                    velocity: event.velocity + 0.1,
                    activationThreshold: 0,
                    allowedPitchClasses: event.allowedPitchClasses
                )
            }
        )
        let update = replacingPlaybackBass(in: initial, with: changedBass)
        try runtime.prepare(plan: initial)

        runtime.applyContinuous(update)

        XCTAssertEqual(try XCTUnwrap(runtime.activePlanForTesting?.bass), initialBass)
    }

    func testLiveRuntimeRoutesAnchorKicksToBassDuckBusWhenHarmonyDuckingIsZero() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let seed = seedProducingBass()
        let baseline = makePlaybackEnginePlan(seed: seed, steps: 10_000)
        let plan = DayMusicPlan(
            seed: baseline.seed,
            input: baseline.input,
            world: baseline.world,
            rhythm: RhythmPlan(
                baseTempoBPM: baseline.rhythm.baseTempoBPM,
                tempoBPM: baseline.rhythm.tempoBPM,
                stepsProgress: baseline.rhythm.stepsProgress,
                family: baseline.rhythm.family,
                patternOffsetSteps: baseline.rhythm.patternOffsetSteps,
                humanizationProfile: baseline.rhythm.humanizationProfile,
                groove: baseline.rhythm.groove,
                realization: baseline.rhythm.realization,
                voices: baseline.rhythm.voices,
                maximumSimultaneousAttacks: baseline.rhythm.maximumSimultaneousAttacks,
                maximumFillsPerWindow: baseline.rhythm.maximumFillsPerWindow,
                fillWindowBars: baseline.rhythm.fillWindowBars,
                maximumMicrotimingMilliseconds: baseline.rhythm.maximumMicrotimingMilliseconds,
                velocityHumanizationRange: baseline.rhythm.velocityHumanizationRange,
                maximumHarmonyDuckingDecibels: 0
            ),
            groove: baseline.groove,
            bass: baseline.bass,
            harmony: baseline.harmony,
            happenings: baseline.happenings,
            lead: baseline.lead,
            glitch: baseline.glitch,
            mix: baseline.mix
        )
        try runtime.prepare(plan: plan)
        try runtime.startPreparedWorldForTesting()

        for subdivision in 0..<Int(MusicalPosition.subdivisionsPerBar) {
            runtime.renderForTesting(.init(
                kind: .subdivision,
                position: .init(absoluteSubdivision: Int64(subdivision)),
                hostTimeSeconds: Double(subdivision) * 0.125,
                tempoBPM: plan.rhythm.tempoBPM
            ))
        }

        XCTAssertEqual(runtime.activeHarmonyDuckingForTesting, 0)
        let duck = runtime.activeBassDuckGainMetricsForTesting
        XCTAssertTrue(duck.isSupported)
        XCTAssertGreaterThan(duck.scheduledSegmentCount, 0)
        XCTAssertLessThan(try XCTUnwrap(duck.lastAttack).targetLinearGain, 1)
        XCTAssertEqual(try XCTUnwrap(duck.lastRelease).targetLinearGain, 1, accuracy: 0.000_001)
    }

    func testLiveDiagnosticSoloPersistsAcrossRenderContinuousAndRemixUntilReleased() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: 7_101)
        let continuous = makePlaybackEnginePlan(seed: initial.seed, steps: 9_000)
        let remixed = makePlaybackEnginePlan(seed: 7_102)
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()

        runtime.applyDiagnosticAudition(.isolatedBus(.bass), plan: initial)
        assertSolo(.bass, in: try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state))

        runtime.renderForTesting(.init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: 0),
            hostTimeSeconds: 0,
            tempoBPM: initial.rhythm.tempoBPM
        ))
        assertSolo(.bass, in: try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state))

        runtime.applyContinuous(continuous)
        assertSolo(.bass, in: try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state))

        runtime.scheduleStructuralPlan(remixed)
        runtime.renderForTesting(.init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: 128),
            hostTimeSeconds: 8,
            tempoBPM: remixed.rhythm.tempoBPM
        ))
        XCTAssertEqual(runtime.remixResultForTesting, .transitioned(seed: remixed.seed))
        assertSolo(.bass, in: try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state))

        runtime.releaseDiagnosticAudition(plan: remixed)
        let restored = try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state)
        XCTAssertEqual(restored.rampDurationSeconds, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(restored.bassTargetDecibels, remixed.mix.bassTargetDecibels, accuracy: 0.000_001)
        XCTAssertNotEqual(restored.rhythmTargetDecibels, -60)
    }

    func testLiveDiagnosticSidechainUsesProductionBassAndActualDuckCommandWithFallback() throws {
        var diagnosticTime = 42.0
        let runtime = try DayObjectsLivePlaybackRuntime(
            bundle: Bundle(for: type(of: self)),
            diagnosticHostTimeProvider: {
                defer { diagnosticTime += 0.001 }
                return diagnosticTime
            }
        )
        let plan = bassLifecyclePlan(seed: 7_201)
        try runtime.prepare(plan: plan)
        try runtime.startPreparedWorldForTesting()
        let attacksBefore = runtime.totalBassAttackCountForTesting
        diagnosticTime = 42

        let result = runtime.auditionKickBassSidechain(
            preferredBassID: DayObjectsInstrumentID(rawValue: "lead.hazy-sine")
        )

        let sidechain = try XCTUnwrap(result)
        let expectedDeadline = 42.08
        XCTAssertEqual(sidechain.instrumentID, DayObjectsInstrumentID(rawValue: "bass.analog-boom"))
        XCTAssertEqual(sidechain.duckCommand.hostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        XCTAssertEqual(sidechain.scheduledKick.voice, .kickSoft)
        XCTAssertEqual(sidechain.scheduledKick.velocity, 1, accuracy: 0.000_001)
        XCTAssertEqual(sidechain.scheduledKick.scheduledHostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        XCTAssertTrue((2.5...5).contains(sidechain.estimatedReductionDB))
        XCTAssertEqual(runtime.totalBassAttackCountForTesting, attacksBefore + 1)
        let duck = runtime.activeBassDuckGainMetricsForTesting
        let duckAttack = try XCTUnwrap(duck.lastAttack)
        XCTAssertEqual(duckAttack.requestedStartHostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        XCTAssertEqual(duckAttack.effectiveStartHostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        XCTAssertFalse(duckAttack.wasForcedImmediate)
        XCTAssertGreaterThan(duck.scheduledSegmentCount, 0)
        runtime.releaseDiagnosticAudition(plan: plan)
        diagnosticTime = 43
        let selected = try XCTUnwrap(runtime.auditionKickBassSidechain(
            preferredBassID: DayObjectsInstrumentID(rawValue: "bass.hey-jakob")
        ))
        XCTAssertEqual(selected.instrumentID, DayObjectsInstrumentID(rawValue: "bass.hey-jakob"))
        runtime.releaseDiagnosticAudition(plan: plan)
        runtime.renderForTesting(.init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: 8),
            hostTimeSeconds: 44,
            tempoBPM: plan.rhythm.tempoBPM
        ))
        XCTAssertGreaterThan(runtime.totalBassAttackCountForTesting, attacksBefore + 1)
    }

    func testMobileDiagnosticSidechainUsesOneFutureDeadlineForBassKickAndDuck() throws {
        var diagnosticTime = 84.0
        let runtime = DayObjectsMobilePlaybackRuntime(
            bundle: Bundle(for: type(of: self)),
            diagnosticHostTimeProvider: {
                defer { diagnosticTime += 0.001 }
                return diagnosticTime
            }
        )
        let plan = bassLifecyclePlan(seed: 7_202)
        try runtime.prepare(plan: plan)
        try runtime.startPreparedWorldForTesting()
        diagnosticTime = 84

        let sidechain = try XCTUnwrap(runtime.auditionKickBassSidechain(
            preferredBassID: DayObjectsInstrumentID(rawValue: "bass.hey-jakob")
        ))

        let expectedDeadline = 84.08
        XCTAssertEqual(sidechain.instrumentID, DayObjectsInstrumentID(rawValue: "bass.hey-jakob"))
        XCTAssertEqual(sidechain.duckCommand.hostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        XCTAssertEqual(sidechain.scheduledKick.scheduledHostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        let duckAttack = try XCTUnwrap(runtime.activeBassDuckGainMetricsForTesting.lastAttack)
        XCTAssertEqual(duckAttack.requestedStartHostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        XCTAssertEqual(duckAttack.effectiveStartHostTimeSeconds, expectedDeadline, accuracy: 0.000_001)
        XCTAssertFalse(duckAttack.wasForcedImmediate)

        runtime.releaseDiagnosticAudition(plan: plan)
        diagnosticTime = 85
    }

    func testMobileDiagnosticSoloPersistsAcrossRenderContinuousRemixAndRelease() throws {
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = bassLifecyclePlan(seed: 7_301)
        let update = bassLifecyclePlan(seed: 7_301)
        let remixed = bassLifecyclePlan(seed: 7_302)
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()
        runtime.applyDiagnosticAudition(.isolatedBus(.harmony), plan: initial)
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 0), hostTimeSeconds: 0, tempoBPM: initial.rhythm.tempoBPM))
        runtime.applyContinuous(update)
        runtime.scheduleStructuralPlan(remixed)
        renderTransportBoundary(at: 128, tempoBPM: remixed.rhythm.tempoBPM, into: runtime)
        assertSolo(.harmony, in: try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state))
        runtime.releaseDiagnosticAudition(plan: remixed)
        XCTAssertEqual(try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state).rampDurationSeconds, 0.25, accuracy: 0.000_001)
    }

    func testMobileDirectReleaseLayersResetsBothDiagnosticModesAcrossStopReprepareStart() async throws {
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = bassLifecyclePlan(seed: 7_311)
        let restarted = bassLifecyclePlan(seed: 7_312)
        try runtime.prepare(plan: initial)
        try runtime.startPreparedWorldForTesting()
        runtime.applyDiagnosticAudition(.isolatedBus(.lead), plan: initial)
        XCTAssertEqual(runtime.retainedDiagnosticAuditionModeForTesting, .isolatedBus(.lead))
        XCTAssertEqual(runtime.worldDiagnosticAuditionModeForTesting, .isolatedBus(.lead))

        runtime.releaseLayers()

        XCTAssertEqual(runtime.retainedDiagnosticAuditionModeForTesting, .fullComposition)
        XCTAssertEqual(runtime.worldDiagnosticAuditionModeForTesting, .fullComposition)
        await runtime.stopTransportAndEffects()
        await runtime.stopAudio()

        try runtime.prepare(plan: restarted)
        try runtime.startPreparedWorldForTesting()
        runtime.renderForTesting(.init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: 0),
            hostTimeSeconds: 0,
            tempoBPM: restarted.rhythm.tempoBPM
        ))

        XCTAssertEqual(runtime.retainedDiagnosticAuditionModeForTesting, .fullComposition)
        XCTAssertEqual(runtime.worldDiagnosticAuditionModeForTesting, .fullComposition)
        let mix = try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state)
        let calibration = DayObjectsPlanAwareGainCalibration.make(
            grooveMode: restarted.groove.mode,
            stepsActivityDensity: restarted.rhythm.stepsProgress
        )
        XCTAssertEqual(
            mix.rhythmTargetDecibels,
            restarted.mix.rhythmTargetDecibels + calibration.rhythmAdjustmentDecibels,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            mix.bassTargetDecibels,
            restarted.mix.bassTargetDecibels + calibration.bassAdjustmentDecibels,
            accuracy: 0.000_001
        )
        runtime.releaseLayers()
        await runtime.stopTransportAndEffects()
        await runtime.stopAudio()
    }

    func testLiveSafeHeldLeadKeepsSourceTokenAndDelaysOldBankRecycleUntilRelease() throws {
        let runtime = try DayObjectsLivePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        let initial = makePlaybackEnginePlan(seed: 701)
        let remixed = DayMusicPlan(
            seed: 702,
            input: initial.input,
            world: initial.world,
            rhythm: initial.rhythm,
            groove: initial.groove,
            bass: initial.bass,
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
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 128), hostTimeSeconds: 8, tempoBPM: 100))
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
        do {
            try await start.value
            XCTFail("A start invalidated by stop must throw cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation for the invalidated start, got \(error)")
        }
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
        try requireLiveAudioOutput()
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
        try requireLiveAudioOutput()
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
        try requireLiveAudioOutput()
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

    private func assertInjectedSampleStartFailure(
        engine: DayObjectsMusicPlaybackEngine,
        session: RecordingDayObjectsAudioSession,
        recipeID: HappeningSoundRecipeID,
        audioIsRunning: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await engine.auditionHappening(recipeID)
            XCTFail("Injected sample audio start must fail", file: file, line: line)
        } catch {}

        guard case .error = engine.state else {
            return XCTFail("Failed sample start must publish an error", file: file, line: line)
        }
        XCTAssertEqual(engine.runtimeState, .stopped, file: file, line: line)
        XCTAssertEqual(engine.metrics.activeTaskCount, 0, file: file, line: line)
        XCTAssertEqual(engine.metrics.activeVoiceCount, 0, file: file, line: line)
        XCTAssertFalse(audioIsRunning(), file: file, line: line)
        XCTAssertFalse(session.isActive, file: file, line: line)

        await engine.stop()
        await engine.stop()

        XCTAssertEqual(engine.state, .off, file: file, line: line)
        XCTAssertEqual(engine.runtimeState, .stopped, file: file, line: line)
        XCTAssertFalse(audioIsRunning(), file: file, line: line)
        XCTAssertFalse(session.isActive, file: file, line: line)
    }

    private func requireLiveAudioOutput(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
#if targetEnvironment(simulator)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw XCTSkip(
                "Simulator has no activatable Core Audio output device: \(error)",
                file: file,
                line: line
            )
        }
        let hasSessionRoute = session.sampleRate > 0 && !session.currentRoute.outputs.isEmpty
        let probe = AudioEngine()
        probe.output = Mixer()
        do {
            try probe.start()
            probe.stop()
        } catch {
            probe.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw XCTSkip(
                "Simulator has no valid Core Audio output device: \(error)",
                file: file,
                line: line
            )
        }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if !hasSessionRoute {
            throw XCTSkip(
                "Simulator has no valid Core Audio output route",
                file: file,
                line: line
            )
        }
#endif
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

private enum RealRuntimeFailureStage: CaseIterable {
    case sessionActivation
    case samplePreparation
    case fullPreparation
    case transportStart
}

@MainActor
private final class FaultInjectingRealPlaybackRuntime: DayObjectsPlaybackRuntimeProtocol {
    let base: any DayObjectsPlaybackRuntimeProtocol
    var failureStage: RealRuntimeFailureStage?
    var injectAudioStartFailure = false

    init(base: any DayObjectsPlaybackRuntimeProtocol, failureStage: RealRuntimeFailureStage?) {
        self.base = base
        self.failureStage = failureStage
    }

    var playbackMetrics: DayObjectsPlaybackMetrics { base.playbackMetrics }

    func prepare(plan: DayMusicPlan) throws {
        if failureStage == .fullPreparation { throw DayObjectsAudioError("injected full prepare") }
        try base.prepare(plan: plan)
    }

    func startAudio() throws {
        if injectAudioStartFailure { throw DayObjectsAudioError("injected audio start") }
        try base.startAudio()
    }

    func startTransport(plan: DayMusicPlan) async throws {
        if failureStage == .transportStart { throw DayObjectsAudioError("injected transport") }
        try await base.startTransport(plan: plan)
    }

    func fadeMaster(to plan: DayMusicPlan) throws { try base.fadeMaster(to: plan) }

    func prepareSamples(recipeIDs: Set<HappeningSoundRecipeID>) async throws {
        if failureStage == .samplePreparation { throw DayObjectsAudioError("injected sample prepare") }
        try await base.prepareSamples(recipeIDs: recipeIDs)
    }

    func auditionHappening(
        _ recipeID: HappeningSoundRecipeID,
        harmony: DayObjectsHappeningAuditionHarmony
    ) throws {
        try base.auditionHappening(recipeID, harmony: harmony)
    }

    func releaseAuditions() { base.releaseAuditions() }
    func rollbackFullStartToSampleOnly() { base.rollbackFullStartToSampleOnly() }
    func stopScheduling() { base.stopScheduling() }
    func endLead() { base.endLead() }
    func cancelRemix() { base.cancelRemix() }
    func releaseLayers() { base.releaseLayers() }
    func stopTransportAndEffects() async { await base.stopTransportAndEffects() }
    func drainTail() async { await base.drainTail() }
    func stopAudio() async { await base.stopAudio() }
    func applyContinuous(_ plan: DayMusicPlan) { base.applyContinuous(plan) }
    func scheduleStructuralPlan(_ plan: DayMusicPlan) { base.scheduleStructuralPlan(plan) }
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) {
        base.addHappening(plan, playBirth: playBirth)
    }
    func removeHappening(id: String) { base.removeHappening(id: id) }
    func beginLead(_ gesture: LeadGestureSample) { base.beginLead(gesture) }
    func updateLead(_ gesture: LeadGestureSample) { base.updateLead(gesture) }
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
    private(set) var activeAuditionRequests: [String] = []
    private(set) var releaseAuditionCount = 0
    private(set) var audioStartCount = 0
    private(set) var continuousCount = 0
    private(set) var beginLeadCount = 0
    private var running = false
    private var audioIsRunning = false

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
        activeAuditionRequests.removeAll()
    }

    func startAudio() throws {
        log.values.append("runtime.audio.start")
        if failureStage == .audioStart { throw DayObjectsAudioError("audio") }
        if !audioIsRunning {
            audioStartCount += 1
            audioIsRunning = true
        }
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
    func stopAudio() async {
        audioIsRunning = false
        log.values.append("runtime.audio.stop")
    }
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
        activeAuditionRequests.append(value)
        log.values.append("runtime.audition:\(value)")
    }
    func releaseAuditions() {
        releaseAuditionCount += 1
        activeAuditionRequests.removeAll()
        log.values.append("runtime.auditions.release")
    }
    func rollbackFullStartToSampleOnly() {
        log.values.append("runtime.full-start.rollback-to-samples")
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

@MainActor
private func waitUntil(
    timeout: Duration,
    condition: @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            throw DayObjectsAudioError("Timed out waiting for test condition")
        }
        try await clock.sleep(for: .milliseconds(1))
    }
}

private func makePlaybackEnginePlan(
    seed: UInt64,
    happeningIDs: [String] = ["a", "b"],
    steps: Double = 7_500
) -> DayMusicPlan {
    DeterministicMusicDirector.makePlan(
        input: DayMusicInput(
            countedSteps: steps,
            stepGoal: 10_000,
            countedSleepHours: 6,
            sleepGoalHours: 8,
            happeningIDs: happeningIDs,
            spentColors: 20
        ),
        remixSeed: seed
    )
}

private func replacingPlaybackBass(in plan: DayMusicPlan, with bass: BassPlan?) -> DayMusicPlan {
    DayMusicPlan(
        seed: plan.seed,
        input: plan.input,
        world: plan.world,
        rhythm: plan.rhythm,
        groove: plan.groove,
        bass: bass,
        harmony: plan.harmony,
        happenings: plan.happenings,
        lead: plan.lead,
        glitch: plan.glitch,
        mix: plan.mix
    )
}

private func bassLifecyclePlan(seed: UInt64) -> DayMusicPlan {
    let base = makePlaybackEnginePlan(seed: seed)
    let bass = BassPlan(
        mode: .bassPulse,
        instrumentID: .init(rawValue: "bass.analog-boom"),
        register: 29...52,
        articulation: .pulse,
        stepsProgress: 1,
        cutoffMultiplier: 0.88,
        glideMilliseconds: 40,
        reverbSend: 0.05,
        ducking: .init(
            maximumAttenuationDecibels: 5,
            attackSeconds: 0.005,
            holdSeconds: 0.045,
            releaseSeconds: 0.180
        ),
        events: [.init(
            stableID: 1,
            chordIndex: 0,
            startSubdivision: 0,
            durationSubdivisions: 8,
            midiNote: 36,
            velocity: 0.7,
            activationThreshold: 0,
            allowedPitchClasses: [0, 4, 7]
        )]
    )
    return replacingPlaybackBass(in: base, with: bass)
}

private func replacingPlaybackHarmony(
    in plan: DayMusicPlan,
    crossfadeAddition: Int
) -> DayMusicPlan {
    let roles = plan.harmony.roles.enumerated().map { index, role in
        HarmonyRolePlan(
            role: role.role,
            instrumentTarget: role.instrumentTarget,
            register: role.register,
            gain: role.gain,
            attackSeconds: role.attackSeconds,
            releaseSeconds: role.releaseSeconds,
            delaySend: role.delaySend,
            reverbSend: role.reverbSend,
            activation: role.activation,
            chordSchedule: role.chordSchedule,
            crossfadeBars: role.crossfadeBars + (index == 0 ? Double(crossfadeAddition) : 0)
        )
    }
    return DayMusicPlan(
        seed: plan.seed,
        input: plan.input,
        world: plan.world,
        rhythm: plan.rhythm,
        groove: plan.groove,
        bass: plan.bass,
        harmony: .init(
            sleepProgress: plan.harmony.sleepProgress,
            cycleBars: plan.harmony.cycleBars,
            chordCount: plan.harmony.chordCount,
            roles: roles
        ),
        happenings: plan.happenings,
        lead: plan.lead,
        glitch: plan.glitch,
        mix: plan.mix
    )
}

@MainActor
private func renderTransportBoundary(
    at subdivision: Int64,
    tempoBPM: Double,
    into runtime: DayObjectsLivePlaybackRuntime
) {
    for kind in [
        DayObjectsTransportEventKind.subdivision,
        .beat,
        .barBoundary,
        .harmonicCycleBoundary,
    ] {
        runtime.renderForTesting(.init(
            kind: kind,
            position: .init(absoluteSubdivision: subdivision),
            hostTimeSeconds: Double(subdivision) * 0.125,
            tempoBPM: tempoBPM
        ))
    }
}

@MainActor
private func renderTransportBoundary(
    at subdivision: Int64,
    tempoBPM: Double,
    into runtime: DayObjectsMobilePlaybackRuntime
) {
    for kind in [
        DayObjectsTransportEventKind.subdivision,
        .beat,
        .barBoundary,
        .harmonicCycleBoundary,
    ] {
        runtime.renderForTesting(.init(
            kind: kind,
            position: .init(absoluteSubdivision: subdivision),
            hostTimeSeconds: Double(subdivision) * 0.125,
            tempoBPM: tempoBPM
        ))
    }
}

private func seedProducingBass() -> UInt64 {
    for seed in UInt64(0)..<10_000 where GroovePlanner.makePlan(remixSeed: seed).usesBass {
        return seed
    }
    fatalError("No Bass Groove seed found")
}

private func assertSolo(
    _ role: DayObjectsRoleBus,
    in state: DayObjectsMixState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for candidate in DayObjectsRoleBus.allCases {
        let value = state.buses.parameters(for: candidate).directTargetDecibels
        if candidate == role {
            XCTAssertGreaterThan(value, -60, file: file, line: line)
        } else {
            XCTAssertLessThanOrEqual(value, -55, file: file, line: line)
        }
    }
}
#endif
