#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class BassPlayerTests: XCTestCase {
    func testActiveBassEventsUseOneReservedVoiceWithoutOverlap() throws {
        let harness = try makeHarness()
        let plan = bassPlan(events: [
            bassEvent(id: 1, start: 0, duration: 4),
            bassEvent(id: 2, start: 2, duration: 4),
        ])
        try harness.player.configure(plan)

        _ = harness.player.render(event(at: 0), plan: plan, duckCommand: nil)
        _ = harness.player.render(event(at: 2), plan: plan, duckCommand: nil)
        _ = harness.player.render(event(at: 6), plan: plan, duckCommand: nil)

        XCTAssertEqual(harness.pool.capacity, 1)
        XCTAssertEqual(harness.pool.noteOnRequests.map(\.midiNote), [36, 38])
        XCTAssertEqual(harness.pool.maximumActiveVoiceCount, 1)
        XCTAssertEqual(harness.pool.noteOffCount, 2)
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 0)
    }

    func testInactiveAndNonSubdivisionEventsDoNotAttackAndDuckTheBusOnly() throws {
        let harness = try makeHarness()
        let plan = bassPlan(events: [
            bassEvent(id: 1, start: 0, duration: 4, threshold: 0.8),
        ])
        try harness.player.configure(plan)
        let duck = BassDuckCommand(
            hostTimeSeconds: 2,
            maximumAttenuationDecibels: 4,
            attackSeconds: 0.005,
            holdSeconds: 0.04,
            releaseSeconds: 0.16
        )

        _ = harness.player.render(nonSubdivisionEvent(at: 0), plan: plan, duckCommand: duck)
        _ = harness.player.render(event(at: 0), plan: plan, duckCommand: duck)

        XCTAssertTrue(harness.pool.noteOnRequests.isEmpty)
        XCTAssertEqual(harness.duckBackend.commands, [duck, duck])
    }

    func testReleaseAllReleasesTheHeldNoteExactlyOnce() throws {
        let harness = try makeHarness()
        let plan = bassPlan(events: [bassEvent(id: 1, start: 0, duration: 16)])
        try harness.player.configure(plan)
        _ = harness.player.render(event(at: 0), plan: plan, duckCommand: nil)

        harness.player.releaseAll()
        harness.player.releaseAll()

        XCTAssertEqual(harness.pool.noteOffCount, 1)
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 0)
    }

    func testCycleRelativeEventsRepeatAfterTheFirstTransportCycle() throws {
        let harness = try makeHarness()
        let plan = bassPlan(events: [bassEvent(id: 1, start: 0, duration: 2)])
        try harness.player.configure(plan, cycleLengthSubdivisions: 16)
        harness.player.startScheduling(at: .init(absoluteSubdivision: 0))

        _ = harness.player.render(event(at: 0), plan: plan, duckCommand: nil)
        _ = harness.player.render(event(at: 2), plan: plan, duckCommand: nil)
        _ = harness.player.render(event(at: 16), plan: plan, duckCommand: nil)

        XCTAssertEqual(harness.pool.noteOnRequests.map(\.midiNote), [36, 36])
        XCTAssertEqual(harness.pool.noteOffCount, 1)
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 1)
    }

    func testNonzeroSchedulingOriginStartsPlanAtPhraseBoundary() throws {
        let harness = try makeHarness()
        let plan = bassPlan(events: [bassEvent(id: 1, start: 0, duration: 4)])
        try harness.player.configure(plan, cycleLengthSubdivisions: 16)
        harness.player.startScheduling(at: .init(absoluteSubdivision: 32))

        let frame = harness.player.render(event(at: 32), plan: plan, duckCommand: nil)

        XCTAssertEqual(frame.attackedEventStableID, 1)
        XCTAssertEqual(harness.pool.noteOnRequests.count, 1)
    }

    func testContinuousUpdateRampsHeldEventVelocityAndReleasesWhenItBecomesInactive() throws {
        let harness = try makeHarness()
        let structural = bassPlan(events: [bassEvent(id: 1, start: 0, duration: 12, velocity: 0.7)])
        try harness.player.configure(structural, cycleLengthSubdivisions: 16)
        harness.player.startScheduling(at: .init(absoluteSubdivision: 0))
        _ = harness.player.render(event(at: 0), plan: structural, duckCommand: nil)

        let quieter = bassPlan(events: [bassEvent(id: 1, start: 0, duration: 12, velocity: 0.31)])
        harness.player.applyContinuous(quieter)

        let update = try XCTUnwrap(harness.pool.updateRequests.last)
        XCTAssertEqual(try XCTUnwrap(update.expression), 0.31, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(update.expressionRampSeconds), 0.025, accuracy: 0.000_001)
        XCTAssertEqual(harness.pool.noteOffCount, 0)

        let inactive = bassPlan(events: [bassEvent(id: 1, start: 0, duration: 12, threshold: 0.8, velocity: 0.31)])
        harness.player.applyContinuous(inactive)

        XCTAssertEqual(harness.pool.noteOffCount, 1)
        XCTAssertEqual(harness.player.metrics.activeVoiceCount, 0)
    }

    func testNonzeroRemixBoundaryStopsSourceBeforeDestinationAttacks() throws {
        let source = try makeHarness()
        let destination = try makeHarness()
        let plan = bassPlan(events: [bassEvent(id: 1, start: 0, duration: 8)])
        try source.player.configure(plan, cycleLengthSubdivisions: 16)
        try destination.player.configure(plan, cycleLengthSubdivisions: 16)
        source.player.startScheduling(at: .init(absoluteSubdivision: 0))
        _ = source.player.render(event(at: 0), plan: plan, duckCommand: nil)

        source.player.stopAttacks()
        _ = source.player.render(event(at: 16), plan: plan, duckCommand: nil)
        destination.player.startScheduling(at: .init(absoluteSubdivision: 16))
        _ = destination.player.render(event(at: 16), plan: plan, duckCommand: nil)

        XCTAssertEqual(source.pool.capacity, 1)
        XCTAssertEqual(destination.pool.capacity, 1)
        XCTAssertEqual(source.pool.noteOnRequests.count, 1)
        XCTAssertEqual(source.pool.noteOffCount, 1)
        XCTAssertEqual(destination.pool.noteOnRequests.count, 1)
        XCTAssertEqual(source.player.metrics.activeVoiceCount + destination.player.metrics.activeVoiceCount, 1)
        XCTAssertEqual(source.pool.maximumActiveVoiceCount, 1)
        XCTAssertEqual(destination.pool.maximumActiveVoiceCount, 1)
    }

    private func makeHarness() throws -> (
        player: BassPlayer,
        pool: RecordingBassPool,
        duckBackend: RecordingBassDuckBackend
    ) {
        let bank = RecordingBassInstrumentBank()
        let world = PlaybackWorldBank(instrumentBank: bank)
        let duckBackend = RecordingBassDuckBackend()
        try world.prepare()
        return (BassPlayer(worldBank: world, duckBackend: duckBackend), try XCTUnwrap(bank.bassPool), duckBackend)
    }

    private func bassPlan(events: [BassEventPlan]) -> BassPlan {
        .init(
            mode: .bassPulse,
            instrumentID: .init(rawValue: "bass.analog-boom"),
            register: 29...52,
            articulation: .pulse,
            stepsProgress: 0.5,
            cutoffMultiplier: 0.88,
            glideMilliseconds: 40,
            reverbSend: 0.05,
            ducking: .init(
                maximumAttenuationDecibels: 5,
                attackSeconds: 0.005,
                holdSeconds: 0.045,
                releaseSeconds: 0.180
            ),
            events: events
        )
    }

    private func bassEvent(
        id: UInt64,
        start: Int64,
        duration: Int64,
        threshold: Double = 0,
        velocity: Double = 0.7
    ) -> BassEventPlan {
        .init(
            stableID: id,
            chordIndex: 0,
            startSubdivision: start,
            durationSubdivisions: duration,
            midiNote: UInt8(34 + id * 2),
            velocity: velocity,
            activationThreshold: threshold,
            allowedPitchClasses: [0, 4, 7]
        )
    }

    private func event(at subdivision: Int64) -> DayObjectsTransportEvent {
        .init(
            kind: .subdivision,
            position: .init(absoluteSubdivision: subdivision),
            hostTimeSeconds: Double(subdivision) * 0.125,
            tempoBPM: 120
        )
    }

    private func nonSubdivisionEvent(at subdivision: Int64) -> DayObjectsTransportEvent {
        .init(
            kind: .beat,
            position: .init(absoluteSubdivision: subdivision),
            hostTimeSeconds: Double(subdivision) * 0.125,
            tempoBPM: 120
        )
    }
}

@MainActor
private final class RecordingBassInstrumentBank: DayObjectsInstrumentBankProtocol {
    let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
    private(set) var pools: [String: RecordingBassPool] = [:]
    var bassPool: RecordingBassPool? { pools[PlaybackWorldBankConfiguration.PoolName.bass.rawValue] }
    private let drumBank = RecordingBassDrums()
    private let pianoBank = RecordingBassPiano()
    var drums: DayObjectsDrumBankProtocol { drumBank }
    var piano: DayObjectsPianoPoolProtocol { pianoBank }
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: .prepared,
            tonalPoolCount: pools.count,
            graph: nil,
            allocationFingerprint: nil,
            drumMetrics: drumBank.metrics,
            pianoMetrics: pianoBank.metrics
        )
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        pools = Dictionary(uniqueKeysWithValues: configuration.tonalPools.map {
            ($0.name, RecordingBassPool(name: $0.name, capacity: $0.capacity))
        })
    }
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol {
        guard let pool = pools[id] else { throw DayObjectsInstrumentBankError.unknownTonalPool(id) }
        return pool
    }
    func start() throws {}
    func stop() async {}
    func releaseWorldLocalVoices() { pools.values.forEach { $0.releaseAll() } }
    func releaseAllIncludingSharedHappenings() { releaseWorldLocalVoices() }
}

private final class RecordingBassPool: DayObjectsTonalVoicePoolProtocol {
    let name: String
    let capacity: Int
    private(set) var noteOnRequests: [DayObjectsTonalNoteRequest] = []
    private(set) var noteOffCount = 0
    private(set) var updateRequests: [DayObjectsVoiceUpdate] = []
    private(set) var maximumActiveVoiceCount = 0
    private var preparedInstrument: DayObjectsInstrumentID?
    private var token: DayObjectsVoiceToken?
    var metrics: DayObjectsTonalPoolMetrics {
        .init(
            name: name,
            allocatedVoiceCount: capacity,
            allocatedNodeCount: capacity,
            activeVoiceCount: token == nil ? 0 : 1,
            activeLeadVoiceCount: 0,
            activeChordVoiceCount: 0
        )
    }

    init(name: String, capacity: Int) { self.name = name; self.capacity = capacity }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws { preparedInstrument = id }
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard request.instrumentID == preparedInstrument, token == nil else { return nil }
        let token = DayObjectsVoiceToken(slotID: 0, generation: UInt64(noteOnRequests.count + 1))
        self.token = token
        noteOnRequests.append(request)
        maximumActiveVoiceCount = max(maximumActiveVoiceCount, 1)
        return token
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {
        guard self.token == token else { return }
        updateRequests.append(update)
    }
    func noteOff(_ token: DayObjectsVoiceToken) {
        guard self.token == token else { return }
        self.token = nil
        noteOffCount += 1
    }
    func releaseAll() { token = nil }
}

@MainActor
private final class RecordingBassDuckBackend: BassDuckBackend {
    private(set) var commands: [BassDuckCommand] = []
    func apply(_ command: BassDuckCommand) { commands.append(command) }
}

private final class RecordingBassDrums: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

private final class RecordingBassPiano: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 0) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {}
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}
#endif
