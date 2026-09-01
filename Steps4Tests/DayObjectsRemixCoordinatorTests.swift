#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsRemixCoordinatorTests: XCTestCase {
    func testNewestPendingPlanWinsAndPreservesSubmittedDayInput() throws {
        let harness = try makeHarness(initialSeed: 1)
        let planA = makePlan(seed: 2, steps: 1_500, sleep: 2, ids: ["a"], spent: 10)
        let planB = makePlan(seed: 3, steps: 5_000, sleep: 5, ids: ["a", "b"], spent: 40)
        let planC = makePlan(seed: 4, steps: 8_750, sleep: 7.5, ids: ["a", "b", "c"], spent: 73)

        harness.coordinator.schedule(planA)
        harness.coordinator.schedule(planB)
        harness.coordinator.schedule(planC)

        XCTAssertEqual(harness.coordinator.metrics.allocatedBankCount, 2)
        XCTAssertEqual(harness.coordinator.metrics.preparedBankCount, 2)
        XCTAssertEqual(harness.coordinator.metrics.allocatedTonalVoiceCount, 46)
        XCTAssertEqual(harness.coordinator.metrics.allocatedPianoVoiceCount, 12)
        XCTAssertEqual(harness.coordinator.metrics.allocatedDrumPlayerCount, 62)
        XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 1)
        XCTAssertEqual(harness.coordinator.pendingPlan, planC)

        harness.coordinator.render(boundary(position: 16, hostTime: 42.25))

        XCTAssertEqual(harness.coordinator.currentPlan, planC)
        XCTAssertEqual(harness.coordinator.currentPlan?.input, planC.input)
        XCTAssertEqual(harness.runtime.configuredPlans.map(\.seed), [1, 4])
        XCTAssertFalse(harness.runtime.configuredPlans.contains { $0.seed == 2 || $0.seed == 3 })
        XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 0)
    }

    func testBoundaryOperationsHaveExactOrderAndSamePositionIsDeduplicated() throws {
        let harness = try makeHarness(initialSeed: 10)
        harness.runtime.resetLog()
        harness.runtime.compatibility = .safeCommonPitch(64)
        let target = makePlan(seed: 11, ids: ["a", "new"])
        harness.coordinator.schedule(target)

        harness.coordinator.render(event(.subdivision, position: 16, hostTime: 91.125))
        harness.coordinator.render(event(.barBoundary, position: 16, hostTime: 91.125))

        XCTAssertEqual(harness.runtime.log, [
            "stop-attacks@16",
            "release@16",
            "configure:11",
            "rhythm:11@91.125",
            "crossfade:2",
            "happenings:a,b->a,new@16",
            "lead-glide:64",
        ])
        XCTAssertEqual(harness.coordinator.metrics.transitionCount, 1)
        XCTAssertEqual(harness.runtime.startedRhythmHostTimes, [91.125])
    }

    func testOldBankRecyclesOnlyAfterTwoBarsAndRuntimeTailsDrain() throws {
        let harness = try makeHarness(initialSeed: 20)
        harness.runtime.resetLog()
        harness.runtime.drained = false
        harness.coordinator.schedule(makePlan(seed: 21))
        harness.coordinator.render(boundary(position: 16, hostTime: 10))

        harness.coordinator.render(event(.subdivision, position: 47, hostTime: 20))
        XCTAssertEqual(harness.runtime.recycleCount, 0)
        harness.coordinator.render(boundary(position: 48, hostTime: 21))
        XCTAssertEqual(harness.runtime.recycleCount, 0, "Two elapsed bars cannot cut audible tails")

        harness.runtime.drained = true
        harness.coordinator.render(event(.subdivision, position: 49, hostTime: 21.1))
        XCTAssertEqual(harness.runtime.recycleCount, 1)
        XCTAssertEqual(harness.coordinator.metrics.transitionCount, 0)
    }

    func testRemixDuringTransitionWaitsAndOnlyNewestStartsWhenBankBecomesAvailable() throws {
        let harness = try makeHarness(initialSeed: 30)
        harness.runtime.drained = false
        harness.coordinator.schedule(makePlan(seed: 31))
        harness.coordinator.render(boundary(position: 16, hostTime: 1))
        harness.coordinator.schedule(makePlan(seed: 32))
        harness.coordinator.schedule(makePlan(seed: 33))

        XCTAssertFalse(harness.coordinator.metrics.inactiveBankIsAvailable)

        harness.coordinator.render(boundary(position: 32, hostTime: 2))
        harness.coordinator.render(boundary(position: 48, hostTime: 3))
        XCTAssertEqual(harness.runtime.configuredPlans.map(\.seed), [30, 31])
        XCTAssertEqual(harness.coordinator.pendingPlan?.seed, 33)

        harness.runtime.drained = true
        harness.coordinator.render(event(.subdivision, position: 49, hostTime: 3.1))
        XCTAssertTrue(harness.coordinator.metrics.inactiveBankIsAvailable)
        harness.coordinator.render(boundary(position: 64, hostTime: 4))
        XCTAssertEqual(harness.runtime.configuredPlans.map(\.seed), [30, 31, 33])
        XCTAssertFalse(harness.runtime.configuredPlans.contains { $0.seed == 32 })
    }

    func testUnsafeHeldLeadUsesOneReleaseRestartPath() throws {
        let harness = try makeHarness(initialSeed: 40)
        harness.runtime.resetLog()
        harness.runtime.compatibility = .requiresRestart
        harness.runtime.leadTokenCount = 1
        harness.coordinator.schedule(makePlan(seed: 41))

        harness.coordinator.render(boundary(position: 16, hostTime: 5))

        XCTAssertEqual(harness.runtime.releaseRestartCount, 1)
        XCTAssertEqual(harness.runtime.glideCount, 0)
        XCTAssertLessThanOrEqual(harness.runtime.metrics.leadTokenCount, 1)
    }

    func testConfigureAndStartFailuresRollbackWithoutClaimingFailedPlanActive() throws {
        for stage in [RecordingRemixRuntime.FailureStage.configure, .startRhythm] {
            let harness = try makeHarness(initialSeed: 50)
            let baseline = harness.coordinator.metrics
            harness.runtime.failureStage = stage
            harness.coordinator.schedule(makePlan(seed: 51))

            harness.coordinator.render(boundary(position: 16, hostTime: 6))

            XCTAssertEqual(harness.coordinator.currentPlan?.seed, 50, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.activeBank, .a, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 0, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.transitionCount, 0, "failed \(stage)")
            XCTAssertEqual(harness.runtime.rollbackCount, 1, "failed \(stage)")
            XCTAssertEqual(harness.coordinator.metrics.allocatedBankCount, baseline.allocatedBankCount)
            guard case .failed = harness.coordinator.result else {
                return XCTFail("failure must be observable for \(stage)")
            }
        }
    }

    func testStopClearsPendingAndTransitionAndReleasesBothBanks() throws {
        let harness = try makeHarness(initialSeed: 60)
        harness.runtime.drained = false
        harness.coordinator.schedule(makePlan(seed: 61))
        harness.coordinator.render(boundary(position: 16, hostTime: 7))
        harness.coordinator.schedule(makePlan(seed: 62))

        harness.coordinator.stop()

        XCTAssertEqual(harness.coordinator.metrics.pendingRemixCount, 0)
        XCTAssertEqual(harness.coordinator.metrics.transitionCount, 0)
        XCTAssertNil(harness.coordinator.currentPlan)
        XCTAssertEqual(harness.runtime.stopCount, 2)
        XCTAssertEqual(harness.banks.map(\.releaseAllCount), [1, 1])
    }

    func testOneHundredRemixesKeepBanksPoolsNodesTasksAndTransportConstant() throws {
        let harness = try makeHarness(initialSeed: 100)
        let baseline = harness.coordinator.metrics
        for index in 1...100 {
            let start = Int64(index * 48 - 32)
            harness.runtime.drained = false
            harness.coordinator.schedule(makePlan(seed: UInt64(100 + index)))
            harness.coordinator.render(boundary(position: start, hostTime: Double(index)))
            harness.runtime.drained = true
            harness.coordinator.render(event(.subdivision, position: start + 32, hostTime: Double(index) + 0.5))
        }

        let final = harness.coordinator.metrics
        XCTAssertEqual(final.allocatedBankCount, 2)
        XCTAssertEqual(final.preparedBankCount, 2)
        XCTAssertEqual(final.allocatedTonalVoiceCount, baseline.allocatedTonalVoiceCount)
        XCTAssertEqual(final.allocatedPianoVoiceCount, baseline.allocatedPianoVoiceCount)
        XCTAssertEqual(final.allocatedDrumPlayerCount, baseline.allocatedDrumPlayerCount)
        XCTAssertEqual(final.runtime.nodeCount, baseline.runtime.nodeCount)
        XCTAssertEqual(final.runtime.poolCount, baseline.runtime.poolCount)
        XCTAssertEqual(final.runtime.taskCount, 0)
        XCTAssertEqual(final.runtime.transportCount, 1)
        XCTAssertEqual(final.runtime.leadTokenCount, 0)
        XCTAssertEqual(final.runtime.happeningTokenCount, 0)
        XCTAssertEqual(harness.banks.map(\.prepareCount), [1, 1])
        XCTAssertEqual(harness.runtime.recycleCount, 100)
        XCTAssertEqual(harness.runtime.oldAttackCountAfterCutoff, 0)
    }

    private func makeHarness(initialSeed: UInt64) throws -> (
        coordinator: DayObjectsRemixCoordinator,
        runtime: RecordingRemixRuntime,
        banks: [RecordingRemixInstrumentBank]
    ) {
        let runtime = RecordingRemixRuntime()
        let bankA = RecordingRemixInstrumentBank()
        let bankB = RecordingRemixInstrumentBank()
        let coordinator = DayObjectsRemixCoordinator(
            bankA: PlaybackWorldBank(instrumentBank: bankA),
            bankB: PlaybackWorldBank(instrumentBank: bankB),
            runtime: runtime
        )
        try coordinator.prepare(initialPlan: makePlan(seed: initialSeed))
        return (coordinator, runtime, [bankA, bankB])
    }

    private func makePlan(
        seed: UInt64,
        steps: Double = 6_000,
        sleep: Double = 6,
        ids: [String] = ["a", "b"],
        spent: Int = 25
    ) -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: .init(
                countedSteps: steps,
                stepGoal: 10_000,
                countedSleepHours: sleep,
                sleepGoalHours: 8,
                happeningIDs: ids,
                spentColors: spent
            ),
            remixSeed: seed
        )
    }

    private func boundary(position: Int64, hostTime: TimeInterval) -> DayObjectsTransportEvent {
        event(.barBoundary, position: position, hostTime: hostTime)
    }

    private func event(
        _ kind: DayObjectsTransportEventKind,
        position: Int64,
        hostTime: TimeInterval
    ) -> DayObjectsTransportEvent {
        .init(
            kind: kind,
            position: .init(absoluteSubdivision: position),
            hostTimeSeconds: hostTime,
            tempoBPM: 72
        )
    }
}

@MainActor
private final class RecordingRemixRuntime: DayObjectsRemixRuntime {
    enum FailureStage: CustomStringConvertible { case configure, startRhythm
        var description: String { self == .configure ? "configure" : "start-rhythm" }
    }

    private(set) var configuredPlans: [DayMusicPlan] = []
    private(set) var log: [String] = []
    private(set) var startedRhythmHostTimes: [TimeInterval] = []
    private(set) var recycleCount = 0
    private(set) var rollbackCount = 0
    private(set) var stopCount = 0
    private(set) var glideCount = 0
    private(set) var releaseRestartCount = 0
    private(set) var oldAttackCountAfterCutoff = 0
    var drained = true
    var compatibility: DayObjectsRemixLeadCompatibility = .notHeld
    var leadTokenCount = 0
    var happeningTokenCount = 0
    var failureStage: FailureStage?

    var metrics: DayObjectsRemixRuntimeMetrics {
        .init(nodeCount: 200, poolCount: 12, taskCount: 0, transportCount: 1, leadTokenCount: leadTokenCount, happeningTokenCount: happeningTokenCount)
    }

    func configure(bank: PlaybackWorldBank, plan: DayMusicPlan) throws {
        if failureStage == .configure { throw DayObjectsAudioError("configure") }
        configuredPlans.append(plan)
        log.append("configure:\(plan.seed)")
    }

    func stopAttackScheduling(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent) { log.append("stop-attacks@\(event.position.absoluteSubdivision)") }
    func beginRelease(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent) { log.append("release@\(event.position.absoluteSubdivision)") }
    func startRhythm(in bank: PlaybackWorldBank, plan: DayMusicPlan, at event: DayObjectsTransportEvent) throws {
        if failureStage == .startRhythm { throw DayObjectsAudioError("rhythm") }
        startedRhythmHostTimes.append(event.hostTimeSeconds)
        log.append("rhythm:\(plan.seed)@\(event.hostTimeSeconds)")
    }
    func beginEqualPowerCrossfade(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, plan: DayMusicPlan, startingAt event: DayObjectsTransportEvent, durationBars: Int) { log.append("crossfade:\(durationBars)") }
    func replaceHappeningsAndScheduleFirstCycle(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, oldPlan: DayMusicPlan, newPlan: DayMusicPlan, at event: DayObjectsTransportEvent) {
        log.append("happenings:\(oldPlan.happenings.map(\.happeningID).joined(separator: ","))->\(newPlan.happenings.map(\.happeningID).joined(separator: ","))@\(event.position.absoluteSubdivision)")
    }
    func leadCompatibility(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, oldPlan: DayMusicPlan, newPlan: DayMusicPlan) -> DayObjectsRemixLeadCompatibility { compatibility }
    func glideHeldLead(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, midiNote: UInt8, newPlan: DayMusicPlan) { glideCount += 1; log.append("lead-glide:\(midiNote)") }
    func releaseAndRestartHeldLead(from oldBank: PlaybackWorldBank, to newBank: PlaybackWorldBank, newPlan: DayMusicPlan) { releaseRestartCount += 1; leadTokenCount = min(leadTokenCount, 1); log.append("lead-restart") }
    func isDrained(_ bank: PlaybackWorldBank) -> Bool { drained }
    func recycle(_ bank: PlaybackWorldBank) { recycleCount += 1; leadTokenCount = 0; happeningTokenCount = 0; log.append("recycle") }
    func rollbackFailedTransition(newBank: PlaybackWorldBank, restoring oldBank: PlaybackWorldBank, currentPlan: DayMusicPlan, at event: DayObjectsTransportEvent) { rollbackCount += 1; log.append("rollback") }
    func stop(_ bank: PlaybackWorldBank) { stopCount += 1; leadTokenCount = 0; happeningTokenCount = 0 }

    func resetLog() { log.removeAll(); startedRhythmHostTimes.removeAll() }
}

@MainActor
private final class RecordingRemixInstrumentBank: DayObjectsInstrumentBankProtocol {
    let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
    private var configuration: DayObjectsInstrumentBankConfiguration?
    private var pools: [String: RecordingRemixPool] = [:]
    private let drumBank = RecordingRemixDrums()
    private let pianoBank = RecordingRemixPiano()
    private(set) var prepareCount = 0
    private(set) var releaseAllCount = 0

    var drums: DayObjectsDrumBankProtocol { drumBank }
    var piano: DayObjectsPianoPoolProtocol { pianoBank }
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: configuration == nil ? .unprepared : .prepared,
            tonalPoolCount: pools.count,
            graph: nil,
            allocationFingerprint: nil,
            drumMetrics: drums.metrics,
            pianoMetrics: piano.metrics
        )
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        guard self.configuration == nil else { return }
        prepareCount += 1
        self.configuration = configuration
        pools = Dictionary(uniqueKeysWithValues: configuration.tonalPools.map {
            ($0.name, RecordingRemixPool(name: $0.name, capacity: $0.capacity))
        })
    }

    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = pools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }

    func start() throws {}
    func stop() async { releaseAll() }
    func releaseAll() {
        releaseAllCount += 1
        pools.values.forEach { $0.releaseAll() }
        drums.releaseAll()
        piano.releaseAll()
    }
}

private final class RecordingRemixPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let capacity: Int
    var metrics: DayObjectsTonalPoolMetrics {
        .init(name: name, allocatedVoiceCount: capacity, allocatedNodeCount: capacity, activeVoiceCount: 0, activeLeadVoiceCount: 0, activeChordVoiceCount: 0)
    }
    init(name: String, capacity: Int) { self.name = name; self.capacity = capacity }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {}
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? { nil }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {}
    func noteOff(_ token: DayObjectsVoiceToken) {}
    func releaseAll() {}
}

private final class RecordingRemixDrums: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 31, enabledVoiceCount: 9) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class RecordingRemixPiano: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 6, activeNoteCount: 0, maximumPolyphony: 6) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {}
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}
#endif
