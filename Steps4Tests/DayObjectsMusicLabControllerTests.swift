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
        XCTAssertEqual(playback.commands, ["add:lab-happening-09:true"])
        controller.setHappeningCount(8)
        XCTAssertEqual(playback.commands, ["add:lab-happening-09:true", "remove:lab-happening-09"])
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
    var suspendStop = false
    var stopContinuation: CheckedContinuation<Void, Never>?

    func start(plan: DayMusicPlan) async throws {
        startPlans.append(plan)
        state = .starting
        if let startError { state = .error(startError); throw startError }
        state = .on
    }
    func stop() async {
        stopCount += 1
        if suspendStop { await withCheckedContinuation { stopContinuation = $0 } }
        state = .off
    }
    func resumeStop() { suspendStop = false; stopContinuation?.resume(); stopContinuation = nil }
    func applyContinuous(_ plan: DayMusicPlan) { commands.append("continuous") }
    func scheduleStructuralPlan(_ plan: DayMusicPlan) { structuralPlans.append(plan); commands.append("structural") }
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) { commands.append("add:\(plan.happeningID):\(playBirth)") }
    func removeHappening(id: String) { commands.append("remove:\(id)") }
    func beginLead(_ gesture: LeadGestureSample) { beginLeadCount += 1 }
    func updateLead(_ gesture: LeadGestureSample) { updateLeadCount += 1 }
    func endLead() { endLeadCount += 1 }
}
#endif
