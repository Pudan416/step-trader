import Foundation
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsInstrumentBankTests: XCTestCase {
    func testPairStopIsNoOpWhileAnIndividualBankOwnsTheSharedEngine() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics
        try pair.bankA.start()

        pair.stop()

        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)

        await pair.bankA.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.bankA.metrics.state, .prepared)
    }

    func testIndividualPlaybackBankOwnersStartOnFirstAndStopOnLastWithoutDetachingGraphs() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics

        try pair.bankA.start()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)

        try pair.bankB.start()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 2)

        await pair.bankA.stop()
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .prepared)
        XCTAssertEqual(pair.bankB.metrics.state, .started)

        await pair.bankB.stop()
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
    }

    func testPairOwnershipRejectsIndividualStopsWithoutCorruptingBankStates() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        try pair.start()

        try pair.bankA.start()
        await pair.bankA.stop()
        await pair.bankB.stop()

        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 0)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .started)
        XCTAssertEqual(pair.metrics.attachedBankCount, 2)

        pair.stop()
        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
    }

    func testIndividualOwnershipRejectsPairStartAndRecoversAfterLastOwnerStops() async throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics
        try pair.bankA.start()

        XCTAssertThrowsError(try pair.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
        XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
        XCTAssertEqual(pair.metrics.individualStartedBankCount, 1)
        XCTAssertEqual(pair.bankA.metrics.state, .started)
        XCTAssertEqual(pair.bankB.metrics.state, .prepared)

        await pair.bankA.stop()
        try pair.start()
        XCTAssertEqual(pair.metrics.lifecycleState, .started)
        XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
        pair.stop()
    }

    func testPlaybackPairLifecycleStartsAndStopsSharedEngineOnceWithoutChangingTopology() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())
        let baseline = pair.metrics

        for cycle in 1...3 {
            try pair.start()
            XCTAssertEqual(pair.metrics.lifecycleState, .started)
            XCTAssertTrue(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.sharedEngineStartCount, cycle)

            pair.stop()
            XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
            XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.sharedEngineStopCount, cycle)
            XCTAssertEqual(pair.metrics.attachedBankCount, 2)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
            XCTAssertEqual(pair.bankA.metrics.state, .prepared)
            XCTAssertEqual(pair.bankB.metrics.state, .prepared)
        }
    }

    func testPlaybackPairStartFailuresRollbackWithoutLosingPreparedGraphsAndRetryWithoutAllocation() throws {
        for failure in [
            DayObjectsPlaybackBankPairStartFailure.secondBankSynchronization,
            .sharedEngineStart,
        ] {
            var pendingFailure: DayObjectsPlaybackBankPairStartFailure? = failure
            let pair = DayObjectsInstrumentBank.makePlaybackPair(
                bundle: Bundle(for: type(of: self)),
                startFailureProvider: {
                    defer { pendingFailure = nil }
                    return pendingFailure
                }
            )
            try pair.prepare(configuration: smallPlaybackPairConfiguration())
            let baseline = pair.metrics

            XCTAssertThrowsError(try pair.start()) {
                XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
            }
            XCTAssertEqual(pair.metrics.lifecycleState, .prepared)
            XCTAssertFalse(pair.metrics.sharedEngineIsRunning)
            XCTAssertEqual(pair.metrics.attachedBankCount, 2)
            XCTAssertEqual(pair.bankA.metrics.state, .prepared)
            XCTAssertEqual(pair.bankB.metrics.state, .prepared)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)

            try pair.start()
            XCTAssertEqual(pair.metrics.lifecycleState, .started)
            XCTAssertEqual(pair.metrics.fixedSharedNodeIdentities, baseline.fixedSharedNodeIdentities)
            XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
            pair.stop()
        }
    }

    func testPlaybackPairUsesOneSharedEngineLimiterAndFixedRampableBankOutputs() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )
        let smallFixedWorld = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "world", capacity: 1, reservesLeadVoice: true)],
            pianoVoiceCount: 1,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )

        try pair.prepare(configuration: smallFixedWorld)
        let baseline = pair.metrics

        XCTAssertEqual(baseline.attachedBankCount, 2)
        XCTAssertEqual(baseline.sharedAudioEngineCount, 1)
        XCTAssertEqual(baseline.finalPeakLimiterCount, 1)
        XCTAssertEqual(baseline.sharedMasterTrimDecibels, -3, accuracy: 1e-12)
        XCTAssertEqual(pair.bankA.outputGainMetrics.targetLinearGain, 1)
        XCTAssertEqual(pair.bankB.outputGainMetrics.targetLinearGain, 1)

        pair.bankA.setOutputGain(0.25, rampDurationSeconds: 0.5)
        pair.bankB.setOutputGain(0.75, rampDurationSeconds: 0.5)

        XCTAssertEqual(pair.bankA.outputGainMetrics.targetLinearGain, 0.25)
        XCTAssertEqual(pair.bankB.outputGainMetrics.targetLinearGain, 0.75)
        XCTAssertEqual(pair.bankA.outputGainMetrics.lastRampDurationSeconds, 0.5)
        XCTAssertEqual(pair.bankB.outputGainMetrics.lastRampDurationSeconds, 0.5)
        XCTAssertEqual(pair.bankA.outputGainMetrics.rampCount, 1)
        XCTAssertEqual(pair.bankB.outputGainMetrics.rampCount, 1)
        XCTAssertEqual(pair.metrics.fixedSharedNodeCount, baseline.fixedSharedNodeCount)
        XCTAssertEqual(pair.metrics.allocationFingerprint, baseline.allocationFingerprint)
    }

    func testPlaybackPairFitsTheMobileRealtimeAllocationBudget() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )

        try pair.prepare(configuration: .playbackWorld)

        let allocations = pair.metrics.allocationFingerprint.compactMap { $0 }
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.tonalNodeIdentities.count },
            500
        )
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.pianoLoadedPlayerCount },
            48
        )
        XCTAssertLessThanOrEqual(
            allocations.reduce(0) { $0 + $1.drumFixedPlayerCount },
            20
        )
    }

    func testPlaybackPairDoesNotStackMoreThanThreeDecibelsOfFixedTrimPerStage() throws {
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self))
        )

        try pair.prepare(configuration: .playbackWorld)

        for bank in [pair.bankA, pair.bankB] {
            let graph = try XCTUnwrap(bank.metrics.graph)
            XCTAssertGreaterThanOrEqual(graph.tonalBusGainDB, -3.01)
            XCTAssertGreaterThanOrEqual(graph.drumBusGainDB, -3.01)
            XCTAssertGreaterThanOrEqual(graph.masterTrimDB, -3.01)
        }
        XCTAssertGreaterThanOrEqual(pair.metrics.sharedMasterTrimDecibels, -3.01)
    }

    func testPlaybackPairSchedulesBankOutputGainAtAuthoritativeHostTimes() throws {
        var currentHostTime: TimeInterval = 100
        let pair = DayObjectsInstrumentBank.makePlaybackPair(
            bundle: Bundle(for: type(of: self)),
            outputGainHostTimeProvider: { currentHostTime }
        )
        try pair.prepare(configuration: smallPlaybackPairConfiguration())

        pair.bankA.scheduleOutputGain(
            0.5,
            startingAtHostTime: 101,
            endingAtHostTime: 102
        )

        XCTAssertEqual(pair.bankA.outputGainMetrics.lastScheduledAutomation, .init(
            targetLinearGain: 0.5,
            requestedStartHostTimeSeconds: 101,
            requestedEndHostTimeSeconds: 102,
            effectiveStartHostTimeSeconds: 101,
            effectiveEndHostTimeSeconds: 102,
            wasForcedImmediate: false
        ))

        currentHostTime = 103
        pair.bankA.scheduleOutputGain(
            0.25,
            startingAtHostTime: 101,
            endingAtHostTime: 102
        )
        XCTAssertEqual(pair.bankA.outputGainMetrics.lastScheduledAutomation, .init(
            targetLinearGain: 0.25,
            requestedStartHostTimeSeconds: 101,
            requestedEndHostTimeSeconds: 102,
            effectiveStartHostTimeSeconds: 103,
            effectiveEndHostTimeSeconds: 103,
            wasForcedImmediate: true
        ))
        XCTAssertEqual(pair.bankA.outputGainMetrics.rampCount, 2)
    }

    private func smallPlaybackPairConfiguration() -> DayObjectsInstrumentBankConfiguration {
        .init(
            tonalPools: [.init(name: "world", capacity: 1, reservesLeadVoice: true)],
            pianoVoiceCount: 1,
            drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map {
                ($0, 1)
            })
        )
    }

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
            tonalBusGainDB: -3,
            drumBusGainDB: -3,
            masterTrimDB: -3,
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
            XCTAssertNil(harness.engine.attachedGraph)

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
        XCTAssertNil(harness.engine.attachedGraph)

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
        XCTAssertEqual(graph.tonalBusGainDB, -3, accuracy: 0.001)
        XCTAssertEqual(graph.drumBusGainDB, -3, accuracy: 0.001)
        XCTAssertEqual(graph.masterTrimDB, -3, accuracy: 0.001)
        XCTAssertEqual(graph.finalPeakLimiterCount, 1)
        XCTAssertEqual(bank.metrics.drumMetrics.allocatedPlayerCount, DayObjectsDrumVoice.allCases.count)
        XCTAssertEqual(bank.metrics.pianoMetrics.allocatedPlayerCount, 3)

        let pool = try bank.tonalPool(named: "role")
        try pool.prepareInstrument(.init(rawValue: "pad.interstellar"))
        let fingerprint = try XCTUnwrap(bank.metrics.allocationFingerprint)
        for _ in 0..<20 {
            let token = try XCTUnwrap(pool.noteOn(request(instrumentID: .init(rawValue: "pad.interstellar"))))
            pool.update(token, with: .init(cutoffHz: 4_000, expression: 0.7, pan: 0.15))
            pool.noteOff(token)
            bank.drums.hit(.kickSoft, velocity: 0.7)
            let pianoToken = try XCTUnwrap(bank.piano.noteOn(60, velocity: 0.7))
            bank.piano.noteOff(pianoToken)
        }
        XCTAssertEqual(bank.metrics.allocationFingerprint, fingerprint)
    }

    func testFactoriesReceiveRequestedFixedCountsAndStopCanRestartWithoutReconfiguration() async throws {
        let harness = makeHarness()
        let requested = DayObjectsInstrumentBankConfiguration(
            tonalPools: [.init(name: "role", capacity: 2, reservesLeadVoice: true)],
            pianoVoiceCount: 3,
            drumOverlapCounts: [.kickSoft: 1, .hatClosed: 2]
        )
        try harness.bank.prepare(configuration: requested)
        let graphIdentity = ObjectIdentifier(try XCTUnwrap(harness.engine.attachedGraph))
        harness.engine.events.removeAll()
        let pool = try harness.bank.tonalPool(named: "role")
        try pool.prepareInstrument(.init(rawValue: "pad.safe"))
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
        XCTAssertEqual(harness.tonalNoteOnCount, 100)
        XCTAssertEqual(harness.drumHitCount, 100)
        XCTAssertEqual(harness.pianoNoteOnCount, 100)
        XCTAssertEqual(ObjectIdentifier(try harness.bank.tonalPool(named: "role")), identity)

        try harness.bank.start()
        XCTAssertEqual(harness.engine.events, ["synchronize", "start"])
        await harness.bank.stop()
        XCTAssertEqual(harness.releaseCount, 3)
        XCTAssertEqual(harness.engine.detachCount, 1)
        XCTAssertNil(harness.engine.attachedGraph)
        harness.engine.events.removeAll()
        try harness.bank.start()
        XCTAssertEqual(harness.engine.attachCount, 2)
        XCTAssertEqual(harness.engine.events, ["attach", "synchronize", "start"])
        XCTAssertNotNil(harness.engine.attachedGraph)
        XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(harness.engine.attachedGraph)), graphIdentity)
    }

    func testPublicReleaseAllReachesEveryPreparedSubBank() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())

        harness.bank.releaseAll()

        XCTAssertEqual(harness.releaseCount, 4)
        XCTAssertNotNil(harness.engine.attachedGraph)
    }

    func testSynchronizationAndStartFailuresDetachTheRetainedGraphAndAreRetryable() throws {
        let harness = makeHarness()
        try harness.bank.prepare(configuration: configuration())
        harness.graphSynchronizeError = InjectedFailure()
        harness.engine.events.removeAll()

        XCTAssertThrowsError(try harness.bank.start()) {
            XCTAssertEqual($0 as? DayObjectsInstrumentBankError, .startFailed)
        }
        XCTAssertEqual(harness.engine.events, ["synchronize", "stop", "detach"])
        XCTAssertNil(harness.engine.attachedGraph)
        XCTAssertEqual(harness.bank.metrics.state, .unprepared)

        harness.graphSynchronizeError = nil
        try harness.bank.prepare(configuration: configuration())
        XCTAssertNotNil(harness.engine.attachedGraph)
        harness.engine.startError = InjectedFailure()
        harness.engine.events.removeAll()
        XCTAssertThrowsError(try harness.bank.start())
        XCTAssertEqual(harness.engine.events, ["synchronize", "start", "stop", "detach"])
        XCTAssertNil(harness.engine.attachedGraph)
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
    var drumHitCount = 0
    var pianoNoteOnCount = 0
    var graphSynchronizeError: Error?
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
                return [.init(rawValue: "pad.safe"): Self.safeVoice]
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
                return FakeDrumBank(onHit: { self?.drumHitCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            pianoPoolFactory: { [weak self] count in
                guard self?.failingAt != .piano else { throw InjectedFailure() }
                self?.pianoFactoryCallCount += 1
                self?.requestedPianoVoiceCount = count
                return FakePianoPool(onNoteOn: { self?.pianoNoteOnCount += 1 }, onRelease: { self?.releaseCount += 1 })
            },
            graphFactory: { [weak self] _, _, _ in
                guard self?.failingAt != .graph else { throw InjectedFailure() }
                self?.graphFactoryCallCount += 1
                return FakeInstrumentBankGraph(
                    isAttached: { [weak self] in self?.engine.attachedGraph != nil },
                    synchronizeError: { [weak self] in self?.graphSynchronizeError },
                    onSynchronize: { [weak self] in self?.engine.events.append("synchronize") }
                )
            },
            engine: engine
        )
    }

    private static let safeVoice = NormalizedSynthVoice(
        oscillator1: .init(wavePosition: 0, level: 0.8, semitoneOffset: 0, detuneHz: 0),
        oscillator2: .init(wavePosition: 0, level: 0, semitoneOffset: 0, detuneHz: 0),
        oscillatorBalance: 0.5,
        subOscillator: .init(level: 0, waveform: .sine, octaveOffset: -1),
        noiseLevel: 0,
        amplitudeEnvelope: .init(attackSeconds: 0.01, decaySeconds: 0.1, sustainLevel: 0.8, releaseSeconds: 0.2),
        filter: .init(kind: .lowPass, cutoffHz: 12_000, resonance: 0.1, envelope: .init(attackSeconds: 0.01, decaySeconds: 0.1, sustainLevel: 0.8, releaseSeconds: 0.2), envelopeAmount: 0),
        glideSeconds: 0,
        isMonophonic: false,
        lfo: .init(target: .none, rateHz: 1, depth: 0),
        delay: .init(isEnabled: false, timeSeconds: 0.2, feedback: 0, mix: 0),
        reverb: .init(isEnabled: false, feedback: 0.8, highPassHz: 80, mix: 0),
        phaser: .init(rateHz: 0.5, feedback: 0, mix: 0),
        autoPan: .init(rateHz: 0.25, depth: 0, stereoWidth: 0),
        outputTrimDB: -12,
        referenceMIDI: 60,
        auditionChord: [60]
    )
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
    let onHit: () -> Void
    let onRelease: () -> Void
    init(onHit: @escaping () -> Void, onRelease: @escaping () -> Void) { self.onHit = onHit; self.onRelease = onRelease }
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) { onHit() }
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakePianoPool: DayObjectsPianoPoolProtocol {
    let onNoteOn: () -> Void
    let onRelease: () -> Void
    init(onNoteOn: @escaping () -> Void, onRelease: @escaping () -> Void) { self.onNoteOn = onNoteOn; self.onRelease = onRelease }
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 4) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { onNoteOn(); return nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() { onRelease() }
}

@MainActor
private final class FakeInstrumentBankGraph: DayObjectsInstrumentBankGraph {
    let layout = DayObjectsInstrumentBankGraphLayout(tonalBusCount: 1, drumBusCount: 1, sharedSpatialEffectCount: 2, tonalBusGainDB: -3, drumBusGainDB: -3, masterTrimDB: -3, finalPeakLimiterCount: 1)
    let isAttached: () -> Bool
    let synchronizeError: () -> Error?
    let onSynchronize: () -> Void
    init(isAttached: @escaping () -> Bool, synchronizeError: @escaping () -> Error?, onSynchronize: @escaping () -> Void) {
        self.isAttached = isAttached
        self.synchronizeError = synchronizeError
        self.onSynchronize = onSynchronize
    }
    func synchronizeForStart() throws {
        onSynchronize()
        guard isAttached() else { throw InjectedFailure() }
        if let error = synchronizeError() { throw error }
    }
}

@MainActor
private final class FakeInstrumentBankEngine: DayObjectsInstrumentBankEngine {
    var startError: Error?
    var attachError: Error?
    private(set) var stopCount = 0
    private(set) var attachCount = 0
    private(set) var detachCount = 0
    private(set) var attachedGraph: (any DayObjectsInstrumentBankGraph)?
    var events: [String] = []
    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        events.append("attach")
        attachCount += 1
        if let attachError { throw attachError }
        attachedGraph = graph
    }
    func detach() { events.append("detach"); detachCount += 1; attachedGraph = nil }
    func start() throws {
        events.append("start")
        guard attachedGraph != nil else { throw InjectedFailure() }
        if let startError { throw startError }
    }
    func stop() { events.append("stop"); stopCount += 1 }
}
