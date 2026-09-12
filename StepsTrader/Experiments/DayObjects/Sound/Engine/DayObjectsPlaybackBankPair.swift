#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
import Foundation
import SoundpipeAudioKit

enum DayObjectsPlaybackBankPairLifecycleState: Equatable, Sendable {
    case unprepared
    case prepared
    case started
}

enum DayObjectsPlaybackBankPairStartFailure: Equatable, Sendable {
    case secondBankSynchronization
    case sharedEngineStart
}

struct DayObjectsPlaybackBankPairMetrics: Equatable, Sendable {
    let attachedBankCount: Int
    let sharedAudioEngineCount: Int
    let finalPeakLimiterCount: Int
    let sharedMasterTrimDecibels: Double
    let fixedSharedNodeCount: Int
    let fixedSharedNodeIdentities: [ObjectIdentifier]
    let happeningFixedPlayerIdentities: [ObjectIdentifier]
    let happeningDecodedBufferIdentities: [ObjectIdentifier]
    let happeningDecodedByteCount: Int
    let finalPeakLimiterIdentities: [ObjectIdentifier]
    let lifecycleState: DayObjectsPlaybackBankPairLifecycleState
    let sharedEngineIsRunning: Bool
    let sharedEngineStartCount: Int
    let sharedEngineStopCount: Int
    let individualStartedBankCount: Int
    let allocationFingerprint: [DayObjectsInstrumentBankAllocationFingerprint?]
    let roleBusMetrics: DayObjectsFiveRoleBusMetrics
    let masterMetrics: DayObjectsMasterMetrics
    let meterTapCapturedScalarSampleCounts: [String: UInt64]
}

@MainActor
final class DayObjectsPlaybackBankPair {
    let bankA: DayObjectsInstrumentBank
    let bankB: DayObjectsInstrumentBank
    private let sharedEngine: DayObjectsSharedInstrumentBankEngine
    private let startFailureProvider: () -> DayObjectsPlaybackBankPairStartFailure?
    private var lifecycleState: DayObjectsPlaybackBankPairLifecycleState = .unprepared
    private var holdsLivePlaybackLease = false

    var metrics: DayObjectsPlaybackBankPairMetrics {
        sharedEngine.metrics(
            lifecycleState: lifecycleState,
            allocationFingerprint: [
                bankA.metrics.allocationFingerprint,
                bankB.metrics.allocationFingerprint,
            ]
        )
    }

    init(
        bankA: DayObjectsInstrumentBank,
        bankB: DayObjectsInstrumentBank,
        sharedEngine: DayObjectsSharedInstrumentBankEngine,
        startFailureProvider: @escaping () -> DayObjectsPlaybackBankPairStartFailure?
    ) {
        self.bankA = bankA
        self.bankB = bankB
        self.sharedEngine = sharedEngine
        self.startFailureProvider = startFailureProvider
    }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws {
        try bankA.prepare(configuration: configuration)
        try bankB.prepare(configuration: configuration)
        if sharedEngine.hasPairOwnership {
            bankA.markPlaybackPairStarted()
            bankB.markPlaybackPairStarted()
            lifecycleState = .started
        } else {
            lifecycleState = .prepared
        }
    }

    func start() throws {
        guard lifecycleState != .unprepared else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        guard lifecycleState != .started else { return }
        let promotesBankAOwner = sharedEngine.canPromoteBankAOwnershipToPair
        guard sharedEngine.canAcquirePairOwnership || promotesBankAOwner else {
            throw DayObjectsInstrumentBankError.startFailed
        }
        try acquireLivePlaybackLease()

        let injectedFailure = startFailureProvider()
        do {
            try bankA.synchronizePreparedGraphForPlaybackPair()
            if injectedFailure == .secondBankSynchronization {
                throw DayObjectsInstrumentBankError.startFailed
            }
            try bankB.synchronizePreparedGraphForPlaybackPair()
            if injectedFailure == .sharedEngineStart {
                throw DayObjectsInstrumentBankError.startFailed
            }
            if promotesBankAOwner {
                try sharedEngine.promoteBankAOwnershipToPair()
            } else {
                try sharedEngine.startPair()
            }
            bankA.markPlaybackPairStarted()
            bankB.markPlaybackPairStarted()
            lifecycleState = .started
        } catch {
            releaseLivePlaybackLease()
            if promotesBankAOwner {
                bankA.releaseWorldLocalVoices()
                bankB.releaseWorldLocalVoices()
                sharedEngine.demotePairOwnershipToBankA()
                bankA.markPlaybackPairStarted()
                bankB.markPlaybackPairPrepared()
            } else {
                bankA.releaseAllIncludingSharedHappenings()
                bankB.releaseWorldLocalVoices()
                sharedEngine.rollbackFailedPairStart()
                bankA.markPlaybackPairPrepared()
                bankB.markPlaybackPairPrepared()
            }
            lifecycleState = .prepared
            throw DayObjectsInstrumentBankError.liveStartFailure(classifying: error)
        }
    }

    func demoteToBankASampleOnlyOwnership() {
        guard lifecycleState == .started else { return }
        guard (try? bankA.acquireLivePlaybackLease()) != nil else { return }
        sharedEngine.demotePairOwnershipToBankA()
        releaseLivePlaybackLease()
        bankA.markPlaybackPairStarted()
        bankB.markPlaybackPairPrepared()
        lifecycleState = .prepared
    }

    func stop() {
        guard lifecycleState == .started else { return }
        bankA.releaseAllIncludingSharedHappenings()
        bankB.releaseWorldLocalVoices()
        sharedEngine.stopPair()
        releaseLivePlaybackLease()
        bankA.releaseLivePlaybackLease()
        bankB.releaseLivePlaybackLease()
        bankA.markPlaybackPairPrepared()
        bankB.markPlaybackPairPrepared()
        lifecycleState = .prepared
    }

    func consumeMeterSamplesForTesting(role: DayObjectsRoleBus, amplitude: Float) {
        sharedEngine.consumeMeterSamplesForTesting(role: role, amplitude: amplitude)
    }

    private func acquireLivePlaybackLease() throws {
        guard !holdsLivePlaybackLease else { return }
        try DayObjectsAudioPlaybackLease.shared.acquireLive(owner: self)
        holdsLivePlaybackLease = true
    }

    private func releaseLivePlaybackLease() {
        guard holdsLivePlaybackLease else { return }
        DayObjectsAudioPlaybackLease.shared.releaseLive(owner: self)
        holdsLivePlaybackLease = false
    }
}

enum DayObjectsPlaybackBankSlot: Hashable { case a, b }

enum DayObjectsPairedInstrumentBankStopResult {
    case rejected
    case worldStopped
    case sharedRuntimeStopped
}

@MainActor
protocol DayObjectsPairedInstrumentBankLifecycleGate: AnyObject {
    func requestIndividualStop() -> DayObjectsPairedInstrumentBankStopResult
}

@MainActor
final class DayObjectsPairedInstrumentBankEngine: DayObjectsInstrumentBankEngine,
    DayObjectsPairedInstrumentBankLifecycleGate {
    private let slot: DayObjectsPlaybackBankSlot
    private let shared: DayObjectsSharedInstrumentBankEngine

    init(slot: DayObjectsPlaybackBankSlot, shared: DayObjectsSharedInstrumentBankEngine) {
        self.slot = slot
        self.shared = shared
    }

    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics {
        shared.topologyMetrics
    }

    func attach(graph: any DayObjectsInstrumentBankGraph) throws {
        try shared.attach(graph: graph, slot: slot)
    }
    func detach() { shared.releaseAttachmentRequest(slot: slot) }
    func start() throws { try shared.requestIndividualStart(slot: slot) }
    func stop() { _ = shared.requestIndividualStop(slot: slot) }
    func requestIndividualStop() -> DayObjectsPairedInstrumentBankStopResult {
        shared.requestIndividualStop(slot: slot)
    }
}

@MainActor
final class DayObjectsSharedInstrumentBankEngine {
    private let engine = AudioEngine()
    private var graphs: [DayObjectsPlaybackBankSlot: DayObjectsAudioKitInstrumentBankGraph] = [:]
    private var attachedSlots: Set<DayObjectsPlaybackBankSlot> = []
    private let masterGraph: DayObjectsPersistentMasterGraph
    private let happenings: DayObjectsHappeningSamplePool
    private let individualStartFailureProvider: () -> Error?
    private var individuallyStartedSlots: Set<DayObjectsPlaybackBankSlot> = []
    private var pairIsRunning = false
    private var startCount = 0
    private var stopCount = 0
    var canAcquirePairOwnership: Bool {
        individuallyStartedSlots.isEmpty && !pairIsRunning
    }
    var hasPairOwnership: Bool { pairIsRunning }
    var canPromoteBankAOwnershipToPair: Bool {
        individuallyStartedSlots == [.a]
            && !pairIsRunning
            && attachedSlots.count == 2
            && engine.avEngine.isRunning
    }

    init(
        happenings: DayObjectsHappeningSamplePool,
        individualStartFailureProvider: @escaping () -> Error?
    ) {
        self.happenings = happenings
        self.individualStartFailureProvider = individualStartFailureProvider
        masterGraph = DayObjectsPersistentMasterGraph(happenings: happenings)
        engine.output = masterGraph.finalOutput
        masterGraph.prepareMeters()
    }

    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics {
        masterGraph.topologyMetrics(
            graphs: Array(graphs.values),
            audioEngine: engine.avEngine
        )
    }

    func attach(
        graph: any DayObjectsInstrumentBankGraph,
        slot: DayObjectsPlaybackBankSlot
    ) throws {
        guard let graph = graph as? DayObjectsAudioKitInstrumentBankGraph else {
            throw DayObjectsInstrumentBankError.preparationFailed(.engine)
        }
        if let existing = graphs[slot], existing !== graph {
            masterGraph.remove(existing)
        }
        graphs[slot] = graph
        attachedSlots.insert(slot)
        masterGraph.add(graph)
        try graph.synchronizeForStart()
    }

    func releaseAttachmentRequest(slot: DayObjectsPlaybackBankSlot) {
        // Playback-pair graphs are retained for the pair's lifetime. An individual
        // bank cannot tear down the other slot's shared output topology.
        individuallyStartedSlots.remove(slot)
    }

    func requestIndividualStart(slot: DayObjectsPlaybackBankSlot) throws {
        guard !pairIsRunning else { throw DayObjectsInstrumentBankError.startFailed }
        guard !individuallyStartedSlots.contains(slot) else { return }
        guard attachedSlots.contains(slot) else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        if individuallyStartedSlots.isEmpty, !engine.avEngine.isRunning {
            masterGraph.startMeters()
            do {
                if let injectedFailure = individualStartFailureProvider() {
                    throw injectedFailure
                }
                try engine.start()
            }
            catch { masterGraph.stopMeters(); throw error }
            startCount += 1
        }
        individuallyStartedSlots.insert(slot)
    }

    func requestIndividualStop(slot: DayObjectsPlaybackBankSlot) -> DayObjectsPairedInstrumentBankStopResult {
        guard !pairIsRunning, individuallyStartedSlots.remove(slot) != nil else {
            return .rejected
        }
        if individuallyStartedSlots.isEmpty {
            stopEngineIfRunning()
            return .sharedRuntimeStopped
        }
        return .worldStopped
    }

    func startPair() throws {
        guard attachedSlots.count == 2 else {
            throw DayObjectsInstrumentBankError.notPrepared
        }
        guard !pairIsRunning else { return }
        if !engine.avEngine.isRunning {
            masterGraph.startMeters()
            do { try engine.start() }
            catch { masterGraph.stopMeters(); throw error }
            startCount += 1
        }
        pairIsRunning = true
    }

    func promoteBankAOwnershipToPair() throws {
        guard canPromoteBankAOwnershipToPair else {
            throw DayObjectsInstrumentBankError.startFailed
        }
        individuallyStartedSlots.remove(.a)
        pairIsRunning = true
    }

    func demotePairOwnershipToBankA() {
        guard pairIsRunning else { return }
        pairIsRunning = false
        individuallyStartedSlots = [.a]
    }

    func stopPair() {
        guard pairIsRunning else { return }
        pairIsRunning = false
        stopEngineIfRunning()
    }

    func rollbackFailedPairStart() {
        pairIsRunning = false
        stopEngineIfRunning()
    }

    func metrics(
        lifecycleState: DayObjectsPlaybackBankPairLifecycleState,
        allocationFingerprint: [DayObjectsInstrumentBankAllocationFingerprint?]
    ) -> DayObjectsPlaybackBankPairMetrics {
        let fixedNodeIdentities = masterGraph.fixedNodeIdentities
        let happeningMetrics = happenings.metrics
        let meterSnapshots = masterGraph.meterSnapshots(
            graphs: Array(graphs.values),
            happeningVoiceCount: happeningMetrics.activeVoiceCount
        )
        return .init(
            attachedBankCount: attachedSlots.count,
            sharedAudioEngineCount: 1,
            finalPeakLimiterCount: 1,
            sharedMasterTrimDecibels: masterGraph.actualMasterTrimDecibels,
            fixedSharedNodeCount: fixedNodeIdentities.count,
            fixedSharedNodeIdentities: fixedNodeIdentities,
            happeningFixedPlayerIdentities: happeningMetrics.fixedPlayerIdentities,
            happeningDecodedBufferIdentities: happeningMetrics.decodedBufferIdentities,
            happeningDecodedByteCount: happeningMetrics.decodedByteCount,
            finalPeakLimiterIdentities: [ObjectIdentifier(masterGraph.limiter)],
            lifecycleState: lifecycleState,
            sharedEngineIsRunning: engine.avEngine.isRunning,
            sharedEngineStartCount: startCount,
            sharedEngineStopCount: stopCount,
            individualStartedBankCount: individuallyStartedSlots.count,
            allocationFingerprint: allocationFingerprint,
            roleBusMetrics: meterSnapshots.0,
            masterMetrics: meterSnapshots.1,
            meterTapCapturedScalarSampleCounts: masterGraph.meterTapCapturedScalarSampleCounts
        )
    }

    func consumeMeterSamplesForTesting(role: DayObjectsRoleBus, amplitude: Float) {
        masterGraph.consumeMeterSamplesForTesting(role: role, amplitude: amplitude)
    }

    private func stopEngineIfRunning() {
        if engine.avEngine.isRunning {
            engine.stop()
            masterGraph.stopMeters()
            stopCount += 1
        }
    }
}
#endif
