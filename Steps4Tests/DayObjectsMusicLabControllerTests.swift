#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsMusicLabControllerTests: XCTestCase {
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
    func applyContinuous(_ plan: DayMusicPlan) { commands.append("continuous") }
    func scheduleStructuralPlan(_ plan: DayMusicPlan) {
        structuralPlans.append(plan)
        metrics.pendingRemixCount = 1
        commands.append("structural")
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
