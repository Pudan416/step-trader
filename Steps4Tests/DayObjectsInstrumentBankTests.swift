import Foundation
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsInstrumentBankTests: XCTestCase {
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
            tonalBusGainDB: -10,
            drumBusGainDB: -12,
            masterTrimDB: -8,
            finalPeakLimiterCount: 1
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
        XCTAssertEqual(harness.releaseCount, 4)
        XCTAssertEqual(harness.bank.metrics.state, .unprepared)

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
        XCTAssertEqual(graph.tonalBusGainDB, -10, accuracy: 0.001)
        XCTAssertEqual(graph.drumBusGainDB, -12, accuracy: 0.001)
        XCTAssertEqual(graph.masterTrimDB, -8, accuracy: 0.001)
        XCTAssertEqual(graph.finalPeakLimiterCount, 1)
        XCTAssertEqual(bank.metrics.drumMetrics.allocatedPlayerCount, DayObjectsDrumVoice.allCases.count)
        XCTAssertEqual(bank.metrics.pianoMetrics.allocatedPlayerCount, 3)
    }

    func testFactoriesReceiveRequestedFixedCountsAndStopCanRestartWithoutReconfiguration() async throws {
        let harness = makeHarness()
        let requested = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "role", capacity: 2, reservesLeadVoice: true)],
            pianoVoiceCount: 3,
            drumOverlapCounts: [.kickSoft: 1, .hatClosed: 2]
        )
        try harness.bank.prepare(configuration: requested)
        let pool = try harness.bank.tonalPool(named: "role")
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
        XCTAssertEqual(ObjectIdentifier(try harness.bank.tonalPool(named: "role")), identity)

        try harness.bank.start()
        await harness.bank.stop()
        XCTAssertEqual(harness.releaseCount, 3)
        XCTAssertEqual(harness.engine.detachCount, 1)
        try harness.bank.start()
        XCTAssertEqual(harness.engine.attachCount, 2)
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
        case .tonalInstruments: return 0
        case .tonalPools: return 1
        case .drums: return 2
        case .piano: return 3
        case .graph, .engine: return 4
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
                return [:]
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
                return FakeDrumBank(onRelease: { self?.releaseCount += 1 })
            },
            pianoPoolFactory: { [weak self] count in
                guard self?.failingAt != .piano else { throw InjectedFailure() }
                self?.pianoFactoryCallCount += 1
                self?.requestedPianoVoiceCount = count
                return FakePianoPool(onRelease: { self?.releaseCount += 1 })
            },
            graphFactory: { [weak self] _, _, _ in
                guard self?.failingAt != .graph else { throw InjectedFailure() }
                self?.graphFactoryCallCount += 1
                return FakeInstrumentBankGraph()
            },
            engine: engine
        )
    }
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
    let onRelease: () -> Void
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakePianoPool: DayObjectsPianoPoolProtocol {
    let onRelease: () -> Void
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 4) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakeInstrumentBankGraph: DayObjectsInstrumentBankGraph {
    let layout = DayObjectsInstrumentBankGraphLayout(tonalBusCount: 1, drumBusCount: 1, sharedSpatialEffectCount: 2, tonalBusGainDB: -10, drumBusGainDB: -12, masterTrimDB: -8, finalPeakLimiterCount: 1)
}

@MainActor
private final class FakeInstrumentBankEngine: DayObjectsInstrumentBankEngine {
    var startError: Error?
    var attachError: Error?
    private(set) var stopCount = 0
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    func attach(graph: any DayObjectsInstrumentBankGraph) throws { attachCount += 1; if let attachError { throw attachError } }
    func detach() { detachCount += 1 }
    func start() throws { if let startError { throw startError } }
    func stop() { stopCount += 1 }
}
