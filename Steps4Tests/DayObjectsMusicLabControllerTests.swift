#if DEBUG || INTERNAL_BUILD
import XCTest
import SwiftUI
@testable import Steps4

@MainActor
final class DayObjectsMusicLabControllerTests: XCTestCase {
    func testCanvasMusicContinuesThroughBackgroundWithoutRestartAndReleasesLead() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback, allowsBackgroundPlayback: true)
        await controller.toggleSound()
        controller.beginLead(.init(normalizedX: 0.5, normalizedY: 0.5, speed: 0.2), isGridVisible: false, isVoiceOverRunning: false)
        await controller.sceneActivityChanged(isActive: false)
        await controller.sceneActivityChanged(isActive: false)
        XCTAssertEqual(controller.soundState, .on)
        XCTAssertEqual(playback.stopCount, 0)
        XCTAssertEqual(playback.endLeadCount, 1, "The finger's held note must not survive screen lock")
        await controller.sceneActivityChanged(isActive: true)
        XCTAssertEqual(playback.startPlans.count, 1, "Returning must keep the existing composition playing")
        await controller.turnSoundOff()
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertEqual(playback.stopCount, 1)
    }

    func testBackgroundMusicStillStopsForInterruptionAndViewRemoval() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback, allowsBackgroundPlayback: true)
        await controller.toggleSound()
        await controller.sceneActivityChanged(isActive: false)
        await controller.interruptionBegan()
        XCTAssertEqual(controller.soundState, .off)
        await controller.interruptionEnded()
        await controller.sceneActivityChanged(isActive: true)
        XCTAssertEqual(playback.startPlans.count, 1, "Interruption end must not start unsolicited playback")
        await controller.toggleSound()
        await controller.viewDidDisappear()
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertEqual(playback.stopCount, 2)
    }

    func testApplicationDeclaresBackgroundAudio() {
        XCTAssertTrue((Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []).contains("audio"))
    }

    func testSilentCanvasLifecycleDoesNotConstructPlaybackUntilSoundStarts() async {
        var constructions = 0
        func makePlayback() -> RecordingLabPlayback {
            constructions += 1
            return RecordingLabPlayback()
        }
        let controller = DayObjectsMusicLabController(playbackFactory: makePlayback)
        controller.viewDidAppear()
        controller.setSteps(4500)
        await controller.viewDidDisappear()
        XCTAssertEqual(constructions, 0, "A silent canvas must not allocate the audio graph")
        controller.viewDidAppear()
        await controller.toggleSound()
        XCTAssertEqual(constructions, 1)
        await controller.turnSoundOff()
        await controller.toggleSound()
        XCTAssertEqual(constructions, 1, "Subsequent starts must retain the prepared runtime")
        await controller.turnSoundOff()
    }

    func testControllerSeed38To39KeepsCurrentMasterAndWetUntilTheBarBoundary() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(state: .init(steps: 7_500, sleepHours: 6.5,
            happeningCount: 2, spentColors: 25, remixSeed: 38, soundWorld: .metalAndCurrent), playback: playback)
        let runtime = DayObjectsMobilePlaybackRuntime(bundle: Bundle(for: type(of: self)))
        try runtime.prepare(plan: controller.currentPlan)
        try runtime.startPreparedWorldForTesting()
        playback.continuousHandler = runtime.applyContinuous
        playback.structuralHandler = runtime.scheduleStructuralPlan
        await controller.toggleSound()
        let before = try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state)

        controller.applyRemix(seed: 39, selection: DayObjectsWorldSelector.makeSelection(remixSeed: 39))

        let pending = try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state)
        XCTAssertEqual(runtime.activePlanForTesting?.seed, 38)
        XCTAssertEqual(pending.masterTargetDecibelsBeforeLimiter, before.masterTargetDecibelsBeforeLimiter)
        XCTAssertEqual(pending.buses, before.buses)
        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 32),
            hostTimeSeconds: 4, tempoBPM: controller.currentPlan.rhythm.tempoBPM))
        XCTAssertEqual(runtime.activePlanForTesting, controller.currentPlan)
        XCTAssertEqual(try XCTUnwrap(runtime.activeProgramEffectMetricsForTesting.state).worldGroupCalibration,
            .init(masterMakeupDB: 9.52, reverbSendScale: 1))
    }

    func testCatalogFailureRemainsVisibleWhileControllerUsesLegacyPlan() {
        let resources = DayObjectsSoundWorldResources(bundle: Bundle(for: type(of: self)), catalogLoader: { _ in
            throw DayObjectsSoundWorldCatalogError.resourceMissing("synth-recipes-v1")
        })
        let controller = DayObjectsMusicLabController(playback: RecordingLabPlayback(), soundWorldResources: resources)
        controller.selectSoundWorld(.livingField)
        controller.selectSoundMood(.strange)
        controller.remix()
        XCTAssertNotNil(controller.soundWorldCatalogDiagnostic)
        XCTAssertEqual(controller.currentPlan.soundWorld, .feltAndWood)
        XCTAssertNil(controller.currentPlan.mix.worldGroupCalibration)
        XCTAssertTrue(DayObjectsInstrumentManifest.defaultDescriptors.contains { $0.id == controller.currentPlan.lead.instrumentID })
    }

    func testDiagnosticsSelectEveryMoodAndPreserveForcedWorldMoodOnRemixAndUndo() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        controller.selectSoundWorld(.livingField)
        await controller.toggleSound()
        let seed = controller.state.remixSeed
        let input = controller.currentPlan.input
        for mood in [DayObjectsSoundMood.sparse, .moving, .strange] {
            controller.selectSoundMood(mood)
            XCTAssertEqual(controller.state.mood, mood)
            XCTAssertEqual(controller.currentPlan.mood, mood)
            XCTAssertEqual(controller.currentPlan.soundWorld, .livingField)
            XCTAssertEqual(controller.currentPlan.seed, seed)
            XCTAssertEqual(controller.currentPlan.input, input)
            XCTAssertEqual(playback.structuralPlans.last, controller.currentPlan)
        }
        let forced = controller.currentPlan
        controller.remix()
        XCTAssertEqual(controller.currentPlan.seed, seed &+ 1)
        XCTAssertEqual(controller.currentPlan.soundWorld, .livingField)
        XCTAssertEqual(controller.currentPlan.mood, .strange)
        controller.undoMusicRemix()
        XCTAssertEqual(controller.currentPlan, forced)
        controller.undoMusicRemix()
        XCTAssertEqual(controller.currentPlan.mood, .moving)
    }

    func testExportSurvivesDiagnosticViewReplacementAndBlocksCompetingAudio() async throws {
        let playback = RecordingLabPlayback()
        let gate = CheckedContinuationGate()
        var invocationCount = 0
        let controller = DayObjectsMusicLabController(playback: playback, auditionExport: { _, _, _, progress in
            invocationCount += 1
            progress(3)
            await gate.suspend()
            progress(12)
        })
        let audition = DayObjectsInstrumentAuditionController()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fake-audition-export")
        let hosting = UIHostingController(rootView: AnyView(DayObjectsInstrumentAuditionView(controller: audition, musicController: controller)))
        hosting.loadViewIfNeeded()
        let task = try XCTUnwrap(controller.beginAuditionExport(stopping: audition, directory: directory))
        XCTAssertNil(controller.beginAuditionExport(stopping: audition, directory: directory))
        await gate.waitUntilSuspended()
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(controller.auditionExportProgress, 3)

        hosting.rootView = AnyView(EmptyView())
        controller.disableDiagnostics()
        hosting.rootView = AnyView(DayObjectsInstrumentAuditionView(controller: audition, musicController: controller))
        XCTAssertTrue(controller.isExportingAuditions)
        XCTAssertEqual(controller.auditionExportProgress, 3)
        XCTAssertNil(controller.beginAuditionExport(stopping: audition, directory: directory))
        XCTAssertNil(controller.acceptSoundButtonIntent())
        XCTAssertFalse(controller.canToggleSound)
        XCTAssertFalse(audition.allowsNote)
        XCTAssertFalse(audition.allowsChord)
        XCTAssertFalse(audition.allowsHit)
        XCTAssertFalse(audition.allowsLeadXY)
        let recipe = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
        XCTAssertEqual(controller.happeningPadStatus(for: recipe), .exporting)
        XCTAssertNil(controller.beginHappeningPadAudition(recipe, beforeAudition: {}))
        XCTAssertNil(controller.beginKickBassSidechainAudition(preferredBassID: nil))
        let commandsBefore = playback.commands
        await controller.toggleSound()
        do { try await controller.auditionHappening(recipe); XCTFail("Export must block direct sample audition") }
        catch { XCTAssertTrue(error is CancellationError) }
        await audition.turnSoundOn()
        await audition.auditionNote()
        audition.selectCategory(.drums)
        XCTAssertEqual(audition.selectedCategory, .pad)
        XCTAssertEqual(audition.soundState, .off)
        XCTAssertEqual(playback.commands, commandsBefore)
        XCTAssertTrue(audition.isAuditionExportInProgress)

        gate.resume()
        await task.value
        XCTAssertEqual(invocationCount, 1)
        XCTAssertFalse(controller.isExportingAuditions)
        XCTAssertFalse(audition.isAuditionExportInProgress)
        XCTAssertEqual(controller.auditionExportProgress, 12)
        XCTAssertEqual(controller.auditionExportDirectory, directory)
        XCTAssertNil(controller.auditionExportError)
    }

    func testLeavingWholeLabCancelsOwnedExportAndRestoresAudioActionsAfterCleanup() async throws {
        let started = expectation(description: "Export started")
        let playback = RecordingLabPlayback()
        var cleanupCount = 0
        let controller = DayObjectsMusicLabController(playback: playback, auditionExport: { _, _, _, progress in
            defer { cleanupCount += 1 }
            progress(1)
            started.fulfill()
            try await Task.sleep(for: .seconds(60))
        })
        let audition = DayObjectsInstrumentAuditionController()
        let task = try XCTUnwrap(controller.beginAuditionExport(stopping: audition,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("cancelled-fake-export")))
        await fulfillment(of: [started], timeout: 2)
        await controller.viewDidDisappear()
        await task.value
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertFalse(controller.isExportingAuditions)
        XCTAssertFalse(audition.isAuditionExportInProgress)
        XCTAssertEqual(controller.auditionExportError, "Export cancelled")
        await controller.toggleSound()
        XCTAssertEqual(controller.soundState, .on)
    }

    func testUnifiedRemixAppliesOneCompleteSelectionWhileSoundIsOff() {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let input = controller.currentPlan.input
        controller.applyRemix(seed: 77, selection: .init(world: .electricDream, mood: .strange, guestWorld: .livingField))
        XCTAssertEqual(controller.currentPlan.seed, 77)
        XCTAssertEqual(controller.currentPlan.soundWorld, .electricDream)
        XCTAssertEqual(controller.currentPlan.mood, .strange)
        XCTAssertEqual(controller.currentPlan.guestWorld, .livingField)
        XCTAssertEqual(controller.currentPlan.input, input)
        XCTAssertTrue(playback.commands.isEmpty)
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertFalse(controller.canUndoMusicRemix, "Unified history belongs to the canvas")
    }

    func testUnifiedRemixAndUndoRouteOneCompletePlanEachWithStableHappenings() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let originalSeed = controller.state.remixSeed
        let originalSelection = DayObjectsWorldSelection(world: controller.state.soundWorld, mood: controller.state.mood, guestWorld: controller.state.guestWorld)
        await controller.toggleSound()
        let input = controller.currentPlan.input
        controller.applyRemix(seed: 91, selection: .init(world: .livingField, mood: .sparse, guestWorld: nil))
        XCTAssertEqual(playback.structuralPlans.count, 1)
        XCTAssertEqual(playback.structuralPlans.last, controller.currentPlan)
        XCTAssertEqual(controller.currentPlan.guestWorld, nil)
        controller.applyRemix(seed: originalSeed, selection: originalSelection)
        XCTAssertEqual(playback.structuralPlans.count, 2)
        XCTAssertEqual(playback.structuralPlans.last, controller.currentPlan)
        XCTAssertEqual(controller.currentPlan.input, input)
        XCTAssertFalse(playback.commands.contains { $0.hasPrefix("add:") || $0.hasPrefix("remove:") })
    }

    func testCanvasRefreshAfterUnifiedRemixDoesNotScheduleTheSamePlanTwice() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        let selection = DayObjectsWorldSelection(world: .electricDream, mood: .strange, guestWorld: nil)
        controller.applyRemix(seed: 19, selection: selection)
        let state = controller.state
        controller.setDayInput(
            countedSteps: state.steps, stepGoal: state.stepGoal,
            countedSleepHours: state.sleepHours, sleepGoalHours: state.sleepGoalHours,
            happeningIDs: controller.happeningIDs, spentColors: state.spentColors
        )
        controller.applyRemix(seed: 19, selection: selection)
        XCTAssertEqual(playback.structuralPlans.count, 1)
    }
    func testSuccessfulPlaybackAttackFeedsTheVisualPulseBus() {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)

        playback.emitHappeningAttack(id: "lab-happening-02")

        XCTAssertEqual(
            controller.soundPulseBus.events(after: 0),
            [.init(sequence: 1, eventID: "lab-happening-02")]
        )
    }

    func testSceneInputCombinesMusicProgressWithCurrentCanvasAndPalette() {
        let controller = DayObjectsMusicLabController(playback: RecordingLabPlayback())
        controller.setSteps(5_000)
        controller.setSleepHours(4)
        controller.setHappeningCount(3)

        let input = controller.sceneInput(
            dayKey: "2026-09-05",
            canvasCoverage: .fullCanvas,
            paletteCategories: [.pastel, .cold]
        )

        XCTAssertEqual(input.canvasCoverage, .fullCanvas)
        XCTAssertEqual(input.uiExclusionRegion.area, 0)
        XCTAssertEqual(input.paletteCategories, [.pastel, .cold])
        XCTAssertEqual(input.eventIDs, controller.happeningIDs)
        XCTAssertEqual(input.motionEnergy, 0.625, accuracy: 0.000_001)
        XCTAssertEqual(input.visualClarity, 0.625, accuracy: 0.000_001)
    }

    func testHappeningPadAuditionForwardsWithoutMutatingLabOrSchedulingState() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
        let state = controller.state
        let plan = controller.currentPlan
        let happeningIDs = controller.happeningIDs
        let seed = controller.state.remixSeed
        let metrics = controller.metrics

        try await controller.auditionHappening(recipeID)

        XCTAssertEqual(playback.auditionedRecipeIDs, [recipeID])
        XCTAssertEqual(controller.state, state)
        XCTAssertEqual(controller.currentPlan, plan)
        XCTAssertEqual(controller.happeningIDs, happeningIDs)
        XCTAssertEqual(controller.state.remixSeed, seed)
        XCTAssertEqual(controller.metrics, metrics)
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertTrue(playback.commands.isEmpty)
    }

    func testViewDisappearanceStopsSampleOnlyAuditionWhilePublicSoundRemainsOff() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 28))
        try await controller.auditionHappening(recipeID)
        XCTAssertEqual(controller.soundState, .off)

        await controller.viewDidDisappear()

        XCTAssertEqual(playback.stopCount, 1)
        XCTAssertEqual(controller.soundState, .off)
    }

    func testPadTapSuspendedBeforeControllerCannotAuditionAfterViewDisappears() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let preflight = SuspendedHappeningPadPreflight()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 12))
        let staleTap = Task { @MainActor in
            await preflight.stopDiagnostics()
            try? await controller.auditionHappening(recipeID)
        }
        await preflight.waitUntilStopBegins()

        await controller.viewDidDisappear()
        preflight.resumeStop()
        await staleTap.value

        XCTAssertEqual(playback.stopCount, 1)
        XCTAssertTrue(
            playback.auditionedRecipeIDs.isEmpty,
            "A tap that predates disappearance must not restart sample-only playback"
        )
    }

    func testSynchronousViewDeactivationInvalidatesPadBeforeAsyncStopCanStart() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let preflight = SuspendedHappeningPadPreflight()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 13))
        let task = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {
            await preflight.stopDiagnostics()
        })
        await preflight.waitUntilStopBegins()

        controller.setHappeningPadLifecycleActive(false)
        preflight.resumeStop()
        await task.value
        await controller.viewDidDisappear()

        XCTAssertTrue(playback.auditionedRecipeIDs.isEmpty)
        XCTAssertEqual(playback.stopCount, 1)
    }

    func testControllerOwnedPadTaskCannotReenterAfterBackgroundForegroundEpoch() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let preflight = SuspendedHappeningPadPreflight()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 6))
        let task = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {
            await preflight.stopDiagnostics()
        })
        await preflight.waitUntilStopBegins()

        await controller.sceneActivityChanged(isActive: false)
        await controller.sceneActivityChanged(isActive: true)
        preflight.resumeStop()
        await task.value

        XCTAssertTrue(playback.auditionedRecipeIDs.isEmpty)
        XCTAssertEqual(controller.happeningPadStatus(for: recipeID), .ready)
    }

    func testSoundOffCancelsSuspendedPadTaskWithoutDisablingLaterAuditions() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let preflight = SuspendedHappeningPadPreflight()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 7))
        await controller.toggleSound()
        let staleTask = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {
            await preflight.stopDiagnostics()
        })
        await preflight.waitUntilStopBegins()

        await controller.toggleSound()
        preflight.resumeStop()
        await staleTask.value
        let freshTask = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {})
        await freshTask.value

        XCTAssertEqual(playback.auditionedRecipeIDs, [recipeID])
        XCTAssertEqual(controller.soundState, .off)
    }

    func testForegroundCannotBeginPadAuditionUntilSuspendedLifecycleStopCompletes() async throws {
        let playback = RecordingLabPlayback()
        playback.suspendStop = true
        let controller = DayObjectsMusicLabController(playback: playback)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 8))
        let inactive = Task { @MainActor in
            await controller.sceneActivityChanged(isActive: false)
        }
        await playback.waitUntilStopBegins()

        await controller.sceneActivityChanged(isActive: true)
        let duringStop = controller.beginHappeningPadAudition(recipeID) {}
        playback.resumeStop()
        await inactive.value
        let afterStop = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {})
        await afterStop.value

        XCTAssertNil(duringStop)
        XCTAssertEqual(playback.auditionedRecipeIDs, [recipeID])
    }

    func testPermanentHappeningDecodeFailureIsRememberedForControllerLifetime() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 19))
        playback.auditionError = HappeningSamplePoolError.recipeUnavailable(recipeID)

        _ = try? await controller.auditionHappening(recipeID)
        await controller.sceneActivityChanged(isActive: false)
        await controller.sceneActivityChanged(isActive: true)
        _ = try? await controller.auditionHappening(recipeID)

        XCTAssertEqual(
            playback.auditionedRecipeIDs,
            [recipeID],
            "Hide/show and lifecycle re-entry must not re-enable a permanently unavailable recipe"
        )
        XCTAssertEqual(controller.happeningPadStatus(for: recipeID), .unavailable)
    }

    func testAcceptedSoundOffIntentCancelsPendingPadBeforeDiagnosticsAwait() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let preflight = SuspendedHappeningPadPreflight()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 9))
        await controller.toggleSound()
        let padTask = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {
            await preflight.stopDiagnostics()
        })
        await preflight.waitUntilStopBegins()

        let soundOff = try XCTUnwrap(controller.acceptSoundButtonIntent())

        XCTAssertEqual(controller.happeningPadStatus(for: recipeID), .soundStopping)
        XCTAssertNil(controller.acceptSoundButtonIntent(), "Repeated UI taps must share one accepted intent")
        XCTAssertEqual(controller.soundState, .on, "The audio toggle must still wait for diagnostics teardown")
        preflight.resumeStop()
        await padTask.value
        await controller.completeSoundButtonIntent(soundOff)

        XCTAssertTrue(playback.auditionedRecipeIDs.isEmpty)
        XCTAssertEqual(controller.soundState, .off)
    }

    func testPendingSoundOffIntentRejectsNewPadBeforeAsyncCompletion() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let completionGate = CheckedContinuationGate()
        let padGate = CheckedContinuationGate()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 14))
        await controller.toggleSound()
        let soundOff = try XCTUnwrap(controller.acceptSoundButtonIntent())
        let delayedCompletion = Task { @MainActor in
            await completionGate.suspend()
            await controller.completeSoundButtonIntent(soundOff)
        }
        await completionGate.waitUntilSuspended()

        let padTask = controller.beginHappeningPadAudition(recipeID) {
            await padGate.suspend()
        }
        if padTask != nil { await padGate.waitUntilSuspended() }

        XCTAssertNil(padTask)
        XCTAssertEqual(controller.happeningPadStatus(for: recipeID), .soundStopping)
        XCTAssertTrue(controller.loadingHappeningRecipeIDs.isEmpty)
        XCTAssertTrue(playback.auditionedRecipeIDs.isEmpty)
        if let padTask {
            padGate.resume()
            await padTask.value
        }
        completionGate.resume()
        await delayedCompletion.value

        XCTAssertTrue(playback.auditionedRecipeIDs.isEmpty)
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertEqual(controller.happeningPadStatus(for: recipeID), .ready)
    }

    func testAcceptedSoundOnIntentDoesNotCancelPendingPadAndCoalescesRepeatedTap() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let preflight = SuspendedHappeningPadPreflight()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 10))
        let padTask = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {
            await preflight.stopDiagnostics()
        })
        await preflight.waitUntilStopBegins()

        let soundOn = try XCTUnwrap(controller.acceptSoundButtonIntent())

        XCTAssertEqual(controller.happeningPadStatus(for: recipeID), .loading)
        XCTAssertNil(controller.acceptSoundButtonIntent())
        preflight.resumeStop()
        await padTask.value
        await controller.completeSoundButtonIntent(soundOn)

        XCTAssertEqual(playback.auditionedRecipeIDs, [recipeID])
        XCTAssertEqual(controller.soundState, .on)
    }

    func testStaleSceneInactiveCompletionAfterActiveEventCannotDeactivatePads() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let gate = CheckedContinuationGate()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 11))
        let inactive = controller.acceptLifecycleEvent(.sceneInactive)
        let staleCompletion = Task { @MainActor in
            await gate.suspend()
            await controller.completeLifecycleEvent(inactive)
        }
        await gate.waitUntilSuspended()

        let active = controller.acceptLifecycleEvent(.sceneActive)
        await controller.completeLifecycleEvent(active)
        gate.resume()
        await staleCompletion.value
        let padTask = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {})
        await padTask.value

        XCTAssertEqual(playback.stopCount, 0, "A stale inactive completion must not tear down newer active state")
        XCTAssertEqual(playback.auditionedRecipeIDs, [recipeID])
    }

    func testStaleViewDisappearCompletionAfterAppearCannotDeactivatePads() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let gate = CheckedContinuationGate()
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 12))
        let disappear = controller.acceptLifecycleEvent(.viewDisappeared)
        let staleCompletion = Task { @MainActor in
            await gate.suspend()
            await controller.completeLifecycleEvent(disappear)
        }
        await gate.waitUntilSuspended()

        let appear = controller.acceptLifecycleEvent(.viewAppeared)
        await controller.completeLifecycleEvent(appear)
        gate.resume()
        await staleCompletion.value
        let padTask = try XCTUnwrap(controller.beginHappeningPadAudition(recipeID) {})
        await padTask.value

        XCTAssertEqual(playback.stopCount, 0, "A stale disappear completion must not overwrite a newer appearance")
        XCTAssertEqual(playback.auditionedRecipeIDs, [recipeID])
    }

    func testStartsOnlyAfterExplicitTapAndRoutesContinuousAndDedicatedHappeningChanges() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)

        controller.setSteps(2_000)
        XCTAssertTrue(playback.commands.isEmpty)
        await controller.toggleSound()
        XCTAssertEqual(playback.startPlans.count, 1)
        XCTAssertEqual(controller.soundState, .on)

        playback.commands.removeAll()
        controller.setSteps(7_000)
        XCTAssertEqual(playback.commands, ["continuous"])

        playback.commands.removeAll()
        controller.setHappeningCount(9)
        XCTAssertEqual(playback.commands, ["add:lab-happening-09:true", "continuous"])
        controller.setHappeningCount(8)
        XCTAssertEqual(playback.commands, [
            "add:lab-happening-09:true", "continuous",
            "remove:lab-happening-09", "continuous",
        ])
    }

    func testDiagnosticsRequireCanvasSoundAndExposeReadOnlyMeterRows() async {
        let playback = RecordingLabPlayback()
        playback.diagnosticMeterSnapshot = .init(
            roleBusMetrics: .init(
                rhythm: .init(peakDBFS: -8, rmsDBFS: -15, activeVoiceCount: 2),
                bass: .init(peakDBFS: -10, rmsDBFS: -18, activeVoiceCount: 1),
                harmony: .init(peakDBFS: -12, rmsDBFS: -20, activeVoiceCount: 3),
                happenings: .init(peakDBFS: -14, rmsDBFS: -24, activeVoiceCount: 1),
                lead: .init(peakDBFS: -16, rmsDBFS: -28, activeVoiceCount: 0)
            ),
            masterMetrics: .init(peakDBFS: -3, rmsDBFS: -11, estimatedLimiterReductionDB: 3.5)
        )
        let controller = DayObjectsMusicLabController(playback: playback)

        controller.selectAuditionMode(.isolatedBus(.bass))
        controller.refreshDiagnosticMeters(now: Date(timeIntervalSinceReferenceDate: 1))

        XCTAssertEqual(controller.auditionMode, .fullComposition)
        XCTAssertTrue(playback.diagnosticCommands.isEmpty)
        XCTAssertEqual(controller.busMeterRows.map(\.role), DayObjectsRoleBus.allCases)
        XCTAssertEqual(controller.masterMeterRow.estimatedLimiterReductionDB, 3.5, accuracy: 0.001)

        await controller.toggleSound()
        controller.selectAuditionMode(.isolatedBus(.bass))

        XCTAssertEqual(controller.auditionMode, .isolatedBus(.bass))
        XCTAssertEqual(playback.diagnosticCommands, [.mode(.isolatedBus(.bass))])
    }

    func testDisablingDiagnosticsReleasesAuditionWithoutRestartingCanvasSound() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        controller.selectAuditionMode(.isolatedBus(.lead))

        controller.disableDiagnostics()

        XCTAssertEqual(controller.auditionMode, .fullComposition)
        XCTAssertEqual(playback.diagnosticCommands, [.mode(.isolatedBus(.lead)), .release])
        XCTAssertEqual(playback.startPlans.count, 1)
        XCTAssertEqual(controller.soundState, .on)
    }

    func testCollapsingDiagnosticsInvalidatesSuspendedSidechainPreflightBeforeItCanScheduleAudio() async {
        let playback = RecordingLabPlayback()
        playback.sidechainResult = .init(
            instrumentID: .init(rawValue: "bass.analog-boom"),
            duckCommand: .init(
                hostTimeSeconds: 1,
                maximumAttenuationDecibels: 4,
                attackSeconds: 0.005,
                holdSeconds: 0.045,
                releaseSeconds: 0.18
            ),
            scheduledKick: .init(
                voice: .kickSoft,
                velocity: 1,
                scheduledHostTimeSeconds: 1,
                microtimingMilliseconds: 0,
                roomSend: 0,
                stereoOffset: 0,
                pitchDriftCents: 0
            )
        )
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        let gate = CheckedContinuationGate()

        let task = controller.beginKickBassSidechainAudition(
            preferredBassID: .init(rawValue: "bass.analog-boom"),
            beforeAudition: { await gate.suspend() }
        )
        XCTAssertNotNil(task)
        await gate.waitUntilSuspended()

        controller.disableDiagnostics()
        gate.resume()
        await task?.value

        XCTAssertEqual(playback.sidechainRequestCount, 0)
        XCTAssertEqual(controller.soundState, .on)
    }

    func testEachIsolatedBusLeavesOnlyItsSelectedSoloCommandActive() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()

        for role in DayObjectsRoleBus.allCases {
            controller.selectAuditionMode(.isolatedBus(role))
            XCTAssertEqual(controller.auditionMode, .isolatedBus(role))
            XCTAssertEqual(playback.diagnosticCommands.last, .mode(.isolatedBus(role)))
        }

        XCTAssertEqual(
            playback.diagnosticCommands,
            DayObjectsRoleBus.allCases.map { .mode(.isolatedBus($0)) }
        )
    }

    func testRemixPreservesDayInputsAndReplacesPendingStructuralPlan() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        let input = controller.currentPlan.input

        controller.remix()
        controller.remix()

        XCTAssertEqual(playback.structuralPlans.count, 2)
        XCTAssertEqual(playback.structuralPlans.last?.input, input)
        XCTAssertEqual(playback.structuralPlans.last?.seed, controller.currentPlan.seed)
    }

    func testSoundWorldSelectionAndMusicUndoScheduleTheActualPlaybackWorld() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let original = controller.state
        await controller.toggleSound()

        controller.selectSoundWorld(.metalAndCurrent)
        controller.remix()

        XCTAssertEqual(controller.currentPlan.soundWorld, .metalAndCurrent)
        XCTAssertEqual(playback.structuralPlans.last, controller.currentPlan)
        XCTAssertTrue(controller.canUndoMusicRemix)

        controller.undoMusicRemix()
        XCTAssertEqual(controller.state.soundWorld, .metalAndCurrent)
        XCTAssertEqual(controller.state.remixSeed, original.remixSeed)
        XCTAssertEqual(playback.structuralPlans.last, controller.currentPlan)

        controller.undoMusicRemix()
        XCTAssertEqual(controller.state.soundWorld, original.soundWorld)
        XCTAssertEqual(controller.state.remixSeed, original.remixSeed)
        XCTAssertFalse(controller.canUndoMusicRemix)
        XCTAssertEqual(controller.state.steps, original.steps)
        XCTAssertEqual(controller.state.sleepHours, original.sleepHours)
        XCTAssertEqual(controller.state.happeningCount, original.happeningCount)
        XCTAssertEqual(controller.state.spentColors, original.spentColors)
    }

    func testLifecycleAndLeadGatesConvergeOnPlaybackWithoutAutoResume() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        let gesture = LeadGestureSample(normalizedX: 0.4, normalizedY: 0.6, speed: 0)

        controller.beginLead(gesture, isGridVisible: true, isVoiceOverRunning: false)
        controller.beginLead(gesture, isGridVisible: false, isVoiceOverRunning: true)
        XCTAssertEqual(playback.beginLeadCount, 0)
        controller.beginLead(gesture, isGridVisible: false, isVoiceOverRunning: false)
        controller.updateLead(gesture)
        controller.endLead()
        XCTAssertEqual(playback.beginLeadCount, 1)
        XCTAssertEqual(playback.updateLeadCount, 1)
        XCTAssertEqual(playback.endLeadCount, 1)

        await controller.sceneActivityChanged(isActive: false)
        XCTAssertEqual(playback.stopCount, 1)
        XCTAssertEqual(controller.soundState, .off)
        await controller.sceneActivityChanged(isActive: true)
        await controller.interruptionEnded()
        XCTAssertEqual(playback.startPlans.count, 1, "Foreground and interruption end must never auto-resume")
    }

    func testGridPolicyEndsHeldGenerativeLeadExactlyOnceAndBlocksFurtherUpdates() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let gesture = LeadGestureSample(normalizedX: 0.4, normalizedY: 0.6, speed: 0)
        await controller.toggleSound()
        controller.beginLead(gesture, isGridVisible: false, isVoiceOverRunning: false)

        controller.leadAvailabilityChanged(isGridVisible: true, isVoiceOverRunning: false)
        controller.updateLead(gesture)
        controller.leadAvailabilityChanged(isGridVisible: true, isVoiceOverRunning: false)
        controller.endLead()

        XCTAssertEqual(playback.beginLeadCount, 1)
        XCTAssertEqual(playback.updateLeadCount, 0)
        XCTAssertEqual(playback.endLeadCount, 1)
    }

    func testVoiceOverPolicyEndsHeldGenerativeLeadExactlyOnceAndBlocksFurtherUpdates() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        let gesture = LeadGestureSample(normalizedX: 0.4, normalizedY: 0.6, speed: 0)
        await controller.toggleSound()
        controller.beginLead(gesture, isGridVisible: false, isVoiceOverRunning: false)

        controller.leadAvailabilityChanged(isGridVisible: false, isVoiceOverRunning: true)
        controller.updateLead(gesture)
        controller.leadAvailabilityChanged(isGridVisible: false, isVoiceOverRunning: true)
        controller.endLead()

        XCTAssertEqual(playback.beginLeadCount, 1)
        XCTAssertEqual(playback.updateLeadCount, 0)
        XCTAssertEqual(playback.endLeadCount, 1)
    }

    func testErrorIsRetryableAndStartingSuppressesDuplicateToggle() async {
        let playback = RecordingLabPlayback()
        playback.startError = DayObjectsAudioError("route")
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        guard case .error = controller.soundState else { return XCTFail("Expected retryable error") }

        playback.startError = nil
        await controller.toggleSound()
        XCTAssertEqual(controller.soundState, .on)
        XCTAssertEqual(playback.startPlans.count, 2)
    }

    func testUnavailableOutputClassificationSurvivesPlaybackToLabState() async {
        let playback = RecordingLabPlayback()
        playback.startError = .outputUnavailable
        let controller = DayObjectsMusicLabController(playback: playback)

        await controller.toggleSound()

        XCTAssertEqual(controller.soundState, .error(.outputUnavailable))
        guard case let .error(error) = controller.soundState else {
            return XCTFail("Expected classified output error")
        }
        XCTAssertEqual(error.classification, .outputUnavailable)
        XCTAssertEqual(error.diagnosticID, "day-objects.audio.output-unavailable")
    }

    func testConcurrentLifecycleStopsJoinOnePlaybackStop() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        playback.suspendStop = true

        let disappear = Task { await controller.viewDidDisappear() }
        await Task.yield()
        let inactive = Task { await controller.sceneActivityChanged(isActive: false) }
        let interruption = Task { await controller.interruptionBegan() }
        await Task.yield()
        XCTAssertEqual(playback.stopCount, 1)

        playback.resumeStop()
        await disappear.value
        await inactive.value
        await interruption.value
        XCTAssertEqual(playback.stopCount, 1)
    }

    func testPendingRemixIsReplacedWithEveryNewestDayInputUntilTransitionBegins() async throws {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()
        controller.remix()
        let pendingSeed = controller.currentPlan.seed

        controller.setSteps(3_000)
        controller.setSleepHours(4)
        controller.setSpentColors(40)
        controller.setHappeningCount(9)

        XCTAssertEqual(playback.metrics.pendingRemixCount, 1)
        XCTAssertEqual(playback.structuralPlans.last?.seed, pendingSeed)
        XCTAssertEqual(playback.structuralPlans.last?.input.stepsProgress, 0.3)
        XCTAssertEqual(playback.structuralPlans.last?.input.sleepProgress, 0.5)
        XCTAssertEqual(playback.structuralPlans.last?.mix.happeningCount, 9)
        XCTAssertEqual(
            try XCTUnwrap(playback.structuralPlans.last?.input.glitchProgress),
            0.16,
            accuracy: 0.000_001
        )

        playback.metrics.pendingRemixCount = 0
        playback.structuralPlans.removeAll()
        controller.setSteps(4_000)
        XCTAssertTrue(playback.structuralPlans.isEmpty, "Ordinary continuous edits must not create a Remix")
    }

    func testEditsDuringSuspendedStartReconcilePlaybackToLatestVisiblePlan() async {
        let playback = RecordingLabPlayback()
        playback.suspendStart = true
        let controller = DayObjectsMusicLabController(playback: playback)
        let start = Task { await controller.toggleSound() }
        await Task.yield()
        XCTAssertEqual(controller.soundState, .starting)

        controller.setSteps(2_500)
        controller.setHappeningCount(9)
        controller.remix()
        XCTAssertTrue(playback.commands.isEmpty)

        playback.resumeStart()
        await start.value
        XCTAssertEqual(controller.soundState, .on)
        XCTAssertTrue(playback.commands.contains("continuous"))
        XCTAssertTrue(playback.commands.contains("add:lab-happening-09:true"))
        XCTAssertEqual(playback.structuralPlans.last, controller.currentPlan)
    }

    func testLifecycleStopRacingSuspendedStartWinsAndRejectsTeardownMutations() async {
        let playback = RecordingLabPlayback()
        playback.suspendStart = true
        let controller = DayObjectsMusicLabController(playback: playback)
        let start = Task { await controller.toggleSound() }
        await Task.yield()
        XCTAssertEqual(controller.soundState, .starting)

        let stop = Task { await controller.viewDidDisappear() }
        await Task.yield()
        controller.setSteps(8_000)
        controller.beginLead(
            .init(normalizedX: 0.5, normalizedY: 0.8, speed: 0),
            isGridVisible: false,
            isVoiceOverRunning: false
        )
        playback.resumeStart()
        await start.value
        await stop.value

        XCTAssertEqual(controller.soundState, .off)
        XCTAssertEqual(playback.stopCount, 1)
        XCTAssertTrue(playback.commands.isEmpty)
        XCTAssertEqual(playback.beginLeadCount, 0)
    }

    func testTenBackgroundAndInterruptionCyclesConvergeOffWithoutAutomaticRestart() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)

        for cycle in 1...10 {
            await controller.toggleSound()
            XCTAssertEqual(controller.soundState, .on, "background cycle \(cycle)")
            await controller.sceneActivityChanged(isActive: false)
            XCTAssertEqual(controller.soundState, .off, "background cycle \(cycle)")
            await controller.sceneActivityChanged(isActive: true)
            XCTAssertEqual(playback.startPlans.count, cycle * 2 - 1, "foreground must not auto-resume")

            await controller.toggleSound()
            XCTAssertEqual(controller.soundState, .on, "interruption cycle \(cycle)")
            await controller.interruptionBegan()
            XCTAssertEqual(controller.soundState, .off, "interruption cycle \(cycle)")
            await controller.interruptionEnded()
            XCTAssertEqual(playback.startPlans.count, cycle * 2, "interruption end must not auto-resume")
        }

        XCTAssertEqual(playback.stopCount, 20)
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertEqual(playback.state, .off)
    }

    func testHappeningsZeroToTenLoopsKeepStableIDsAndLeaveNoActiveRecords() async {
        let playback = RecordingLabPlayback()
        let controller = DayObjectsMusicLabController(playback: playback)
        await controller.toggleSound()

        for cycle in 1...10 {
            controller.setHappeningCount(0)
            XCTAssertEqual(playback.metrics.activeHappeningCount, 0, "remove cycle \(cycle)")
            XCTAssertTrue(playback.activeHappeningIDs.isEmpty, "remove cycle \(cycle)")

            controller.setHappeningCount(10)
            XCTAssertEqual(playback.metrics.activeHappeningCount, 10, "add cycle \(cycle)")
            XCTAssertEqual(
                playback.activeHappeningIDs,
                Set((1...10).map { String(format: "lab-happening-%02d", $0) }),
                "add cycle \(cycle)"
            )
        }

        controller.setHappeningCount(0)
        XCTAssertEqual(playback.metrics.activeHappeningCount, 0)
        XCTAssertTrue(playback.activeHappeningIDs.isEmpty)
        await controller.toggleSound()
        XCTAssertEqual(controller.soundState, .off)
    }
}

@MainActor
private final class RecordingLabPlayback: DayObjectsMusicPlaybackProtocol {
    var continuousHandler: ((DayMusicPlan) -> Void)?
    var structuralHandler: ((DayMusicPlan) -> Void)?
    var state: DayObjectsSoundState = .off
    var metrics = DayObjectsPlaybackMetrics()
    var startError: DayObjectsAudioError?
    var startPlans: [DayMusicPlan] = []
    var structuralPlans: [DayMusicPlan] = []
    var commands: [String] = []
    var stopCount = 0
    var beginLeadCount = 0
    var updateLeadCount = 0
    var endLeadCount = 0
    var activeHappeningIDs: Set<String> = []
    var auditionedRecipeIDs: [HappeningSoundRecipeID] = []
    var auditionError: Error?
    var suspendStop = false
    var stopContinuation: CheckedContinuation<Void, Never>?
    var stopWaiters: [CheckedContinuation<Void, Never>] = []
    var suspendStart = false
    var startContinuation: CheckedContinuation<Void, Never>?
    var diagnosticMeterSnapshot = DayObjectsDiagnosticMeterSnapshot.silent
    var diagnosticCommands: [DayObjectsDiagnosticCommand] = []
    var sidechainResult: DayObjectsSidechainAuditionResult?
    var sidechainRequestCount = 0
    private var happeningAttackHandler: ((String) -> Void)?

    func setHappeningAttackHandler(_ handler: ((String) -> Void)?) {
        happeningAttackHandler = handler
    }

    func emitHappeningAttack(id: String) {
        happeningAttackHandler?(id)
    }

    func start(plan: DayMusicPlan) async throws {
        startPlans.append(plan)
        state = .starting
        if suspendStart { await withCheckedContinuation { startContinuation = $0 } }
        if let startError { state = .error(startError); throw startError }
        state = .on
    }
    func stop() async {
        stopCount += 1
        stopWaiters.forEach { $0.resume() }
        stopWaiters.removeAll()
        if suspendStop { await withCheckedContinuation { stopContinuation = $0 } }
        state = .off
    }
    func waitUntilStopBegins() async {
        if stopCount > 0 { return }
        await withCheckedContinuation { stopWaiters.append($0) }
    }
    func resumeStop() { suspendStop = false; stopContinuation?.resume(); stopContinuation = nil }
    func resumeStart() { suspendStart = false; startContinuation?.resume(); startContinuation = nil }
    func applyContinuous(_ plan: DayMusicPlan) {
        commands.append("continuous")
        continuousHandler?(plan)
    }
    func scheduleStructuralPlan(_ plan: DayMusicPlan) {
        structuralPlans.append(plan)
        metrics.pendingRemixCount = 1
        commands.append("structural")
        structuralHandler?(plan)
    }
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) {
        activeHappeningIDs.insert(plan.happeningID)
        metrics.activeHappeningCount = activeHappeningIDs.count
        commands.append("add:\(plan.happeningID):\(playBirth)")
    }
    func removeHappening(id: String) {
        activeHappeningIDs.remove(id)
        metrics.activeHappeningCount = activeHappeningIDs.count
        commands.append("remove:\(id)")
    }
    func beginLead(_ gesture: LeadGestureSample) { beginLeadCount += 1 }
    func updateLead(_ gesture: LeadGestureSample) { updateLeadCount += 1 }
    func endLead() { endLeadCount += 1 }
    func auditionHappening(_ recipeID: HappeningSoundRecipeID) async throws {
        auditionedRecipeIDs.append(recipeID)
        if let auditionError { throw auditionError }
    }
    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan) {
        diagnosticCommands.append(.mode(mode))
    }
    func releaseDiagnosticAudition() { diagnosticCommands.append(.release) }
    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult? {
        sidechainRequestCount += 1
        return sidechainResult
    }
}

@MainActor
private final class SuspendedHappeningPadPreflight {
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    func stopDiagnostics() async {
        stopWaiters.forEach { $0.resume() }
        stopWaiters.removeAll()
        await withCheckedContinuation { stopContinuation = $0 }
    }

    func waitUntilStopBegins() async {
        if stopContinuation != nil { return }
        await withCheckedContinuation { stopWaiters.append($0) }
    }

    func resumeStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

@MainActor
private final class CheckedContinuationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
#endif
