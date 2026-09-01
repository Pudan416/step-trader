#if DEBUG || INTERNAL_BUILD
import AVFAudio
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsMusicPlaybackEngineTests: XCTestCase {
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
        XCTAssertGreaterThan(runtime.inactiveWorldVoiceCountForTesting, 0, "p0 must not cut the old harmony tail")

        runtime.renderForTesting(.init(kind: .subdivision, position: .init(absoluteSubdivision: 160), hostTimeSeconds: 10, tempoBPM: 100))
        XCTAssertEqual(runtime.inactiveWorldVoiceCountForTesting, 0, "the recycled world must retain no old tokens")
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
    private var tailDrainContinuation: CheckedContinuation<Void, Never>?
    private var tailDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var prepareAttempts = 0
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
    }

    func startTransport(plan: DayMusicPlan) async throws {
        log.values.append("runtime.transport.start:\(plan.seed)")
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
    func stopAudio() { log.values.append("runtime.audio.stop") }
    func applyContinuous(_ plan: DayMusicPlan) {}
    func scheduleStructuralPlan(_ plan: DayMusicPlan) {}
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool) {}
    func removeHappening(id: String) {}
    func beginLead(_ gesture: LeadGestureSample) {}
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
}

private func makePlaybackEnginePlan(seed: UInt64) -> DayMusicPlan {
    DeterministicMusicDirector.makePlan(
        input: DayMusicInput(
            countedSteps: 7_500,
            stepGoal: 10_000,
            countedSleepHours: 6,
            sleepGoalHours: 8,
            happeningIDs: ["a", "b"],
            spentColors: 20
        ),
        remixSeed: seed
    )
}
#endif
