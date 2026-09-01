#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsMusicLabControllerTests: XCTestCase {
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
    var suspendStop = false
    var stopContinuation: CheckedContinuation<Void, Never>?
    var suspendStart = false
    var startContinuation: CheckedContinuation<Void, Never>?

    func start(plan: DayMusicPlan) async throws {
        startPlans.append(plan)
        state = .starting
        if suspendStart { await withCheckedContinuation { startContinuation = $0 } }
        if let startError { state = .error(startError); throw startError }
        state = .on
    }
    func stop() async {
        stopCount += 1
        if suspendStop { await withCheckedContinuation { stopContinuation = $0 } }
        state = .off
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
}
#endif
