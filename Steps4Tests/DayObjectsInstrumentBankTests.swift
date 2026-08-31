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
    }

    func testEachPreparationFailureReleasesPartialStateAndIsRetryableWithStableDiagnostic() throws {
        for stage in DayObjectsInstrumentBankPreparationStage.allCases {
            let harness = makeHarness(failingAt: stage)

            XCTAssertThrowsError(try harness.bank.prepare(configuration: configuration())) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .preparationFailed(stage))
            }
            XCTAssertEqual(harness.bank.metrics.state, .unprepared)
            XCTAssertGreaterThanOrEqual(harness.releaseCount, 0)

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
            pianoVoiceCount: 4,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, DayObjectsDrumRecipe.recipe(for: $0).overlapCount)
            })
        )

        try bank.prepare(configuration: configuration)

        XCTAssertEqual(bank.metrics.state, .prepared)
        XCTAssertEqual(bank.metrics.graph, .init(
            tonalBusCount: 1,
            drumBusCount: 1,
            sharedSpatialEffectCount: 2,
            masterTrimDB: -8,
            finalPeakLimiterCount: 1
        ))
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
}

@MainActor
private final class InstrumentBankHarness {
    var failingAt: DayObjectsInstrumentBankPreparationStage?
    var tonalFactoryCallCount = 0
    var drumFactoryCallCount = 0
    var pianoFactoryCallCount = 0
    var graphFactoryCallCount = 0
    var releaseCount = 0
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
            tonalPoolFactory: { [weak self] _, _ in
                guard self?.failingAt != .tonalPools else { throw InjectedFailure() }
                self?.tonalFactoryCallCount += 1
                return FakeTonalPool(onRelease: { self?.releaseCount += 1 })
            },
            drumBankFactory: { [weak self] _ in
                guard self?.failingAt != .drums else { throw InjectedFailure() }
                self?.drumFactoryCallCount += 1
                return FakeDrumBank(onRelease: { self?.releaseCount += 1 })
            },
            pianoPoolFactory: { [weak self] _ in
                guard self?.failingAt != .piano else { throw InjectedFailure() }
                self?.pianoFactoryCallCount += 1
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
    let onRelease: () -> Void
    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }
    var metrics: DayObjectsTonalPoolMetrics { .init(name: "fake", allocatedVoiceCount: 2, allocatedNodeCount: 0, activeVoiceCount: 0, activeLeadVoiceCount: 0, activeChordVoiceCount: 0) }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {}
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? { nil }
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
    let layout = DayObjectsInstrumentBankGraphLayout(tonalBusCount: 1, drumBusCount: 1, sharedSpatialEffectCount: 2, masterTrimDB: -8, finalPeakLimiterCount: 1)
}

@MainActor
private final class FakeInstrumentBankEngine: DayObjectsInstrumentBankEngine {
    var startError: Error?
    var attachError: Error?
    private(set) var stopCount = 0
    func attach(graph: any DayObjectsInstrumentBankGraph) throws { if let attachError { throw attachError } }
    func start() throws { if let startError { throw startError } }
    func stop() { stopCount += 1 }
}
