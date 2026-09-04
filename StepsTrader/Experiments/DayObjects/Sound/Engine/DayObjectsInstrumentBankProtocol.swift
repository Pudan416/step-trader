#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsRoleBus: CaseIterable, Equatable, Hashable, Sendable {
    case rhythm
    case bass
    case harmony
    case happenings
    case lead
}

struct DayObjectsRoleBusMetrics: Equatable, Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let activeVoiceCount: Int
}

struct DayObjectsMasterMetrics: Equatable, Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let limiterReductionDB: Double
}

struct DayObjectsFiveRoleBusMetrics: Equatable, Sendable {
    let rhythm: DayObjectsRoleBusMetrics
    let bass: DayObjectsRoleBusMetrics
    let harmony: DayObjectsRoleBusMetrics
    let happenings: DayObjectsRoleBusMetrics
    let lead: DayObjectsRoleBusMetrics

    func metrics(for role: DayObjectsRoleBus) -> DayObjectsRoleBusMetrics {
        return switch role {
        case .rhythm: rhythm
        case .bass: bass
        case .harmony: harmony
        case .happenings: happenings
        case .lead: lead
        }
    }
}

struct DayObjectsInstrumentBankConfiguration: Equatable, Sendable {
    let tonalPools: [DayObjectsTonalPoolSpecification]
    let pianoVoiceCount: Int
    let drumOverlapCounts: [DayObjectsDrumVoice: Int]
}

protocol DayObjectsTonalVoicePoolProtocol: AnyObject {
    var metrics: DayObjectsTonalPoolMetrics { get }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws
    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken?
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate)
    func noteOff(_ token: DayObjectsVoiceToken)
    func releaseAll()
}

extension DayObjectsTonalVoicePoolProtocol {
    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws {
        for id in ids { try prepareInstrument(id) }
    }
}

protocol DayObjectsDrumBankProtocol: AnyObject {
    var metrics: DayObjectsDrumBankMetrics { get }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double)
    func schedule(_ hit: DayObjectsScheduledDrumHit)
    func releaseAll()
}

extension DayObjectsDrumBankProtocol {
    func schedule(_ hit: DayObjectsScheduledDrumHit) {
        self.hit(hit.voice, velocity: hit.velocity)
    }
}

protocol DayObjectsPianoPoolProtocol: AnyObject {
    var metrics: DayObjectsFeltPianoMetrics { get }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken?
    func noteOn(_ request: DayObjectsPianoNoteRequest) -> DayObjectsFeltPianoToken?
    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double)
    func update(_ token: DayObjectsFeltPianoToken, with update: DayObjectsPianoVoiceUpdate)
    func noteOff(_ token: DayObjectsFeltPianoToken)
    func releaseAll()
}

extension DayObjectsPianoPoolProtocol {
    func noteOn(_ request: DayObjectsPianoNoteRequest) -> DayObjectsFeltPianoToken? {
        noteOn(request.midiNote, velocity: request.velocity)
    }

    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {}

    func update(_ token: DayObjectsFeltPianoToken, with update: DayObjectsPianoVoiceUpdate) {
        if let expression = update.expression {
            updateExpression(token, expression: expression)
        }
    }
}

enum DayObjectsInstrumentBankPreparationStage: String, CaseIterable, Equatable, Sendable {
    case tonalInstruments = "tonal-instruments"
    case tonalPools = "tonal-pools"
    case drums
    case piano
    case graph
    case engine
}

enum DayObjectsInstrumentBankState: Equatable, Sendable {
    case unprepared
    case prepared
    case started
}

enum DayObjectsInstrumentBankError: Error, Equatable, Sendable {
    case notPrepared
    case configurationChangedAfterPreparation
    case duplicateTonalPoolName(String)
    case invalidPianoVoiceCount
    case invalidDrumOverlap(DayObjectsDrumVoice)
    case unknownTonalPool(String)
    case unknownInstrument(DayObjectsInstrumentID)
    case invalidTonalInstrumentCategory(DayObjectsInstrumentCategory)
    case preparationFailed(DayObjectsInstrumentBankPreparationStage)
    case startFailed

    var diagnosticID: String {
        switch self {
        case .notPrepared: return "day-objects.instrument-bank.not-prepared"
        case .configurationChangedAfterPreparation: return "day-objects.instrument-bank.configuration-changed-after-preparation"
        case let .duplicateTonalPoolName(name): return "day-objects.instrument-bank.duplicate-tonal-pool.\(name)"
        case .invalidPianoVoiceCount: return "day-objects.instrument-bank.invalid-piano-voice-count"
        case let .invalidDrumOverlap(voice): return "day-objects.instrument-bank.invalid-drum-overlap.\(voice.rawValue)"
        case let .unknownTonalPool(name): return "day-objects.instrument-bank.unknown-tonal-pool.\(name)"
        case let .unknownInstrument(id): return "day-objects.instrument-bank.unknown-instrument.\(id.rawValue)"
        case let .invalidTonalInstrumentCategory(category): return "day-objects.instrument-bank.invalid-tonal-category.\(category.rawValue)"
        case let .preparationFailed(stage): return "day-objects.instrument-bank.prepare.\(stage.rawValue)"
        case .startFailed: return "day-objects.instrument-bank.start-failed"
        }
    }
}

struct DayObjectsInstrumentBankGraphLayout: Equatable, Sendable {
    let tonalBusCount: Int
    let drumBusCount: Int
    let sharedSpatialEffectCount: Int
    let tonalBusGainDB: Double
    let drumBusGainDB: Double
    let masterTrimDB: Double
    let finalPeakLimiterCount: Int
    let roleBuses: [DayObjectsRoleBus]
    let parallelSpatialReturnCount: Int

    init(
        tonalBusCount: Int,
        drumBusCount: Int,
        sharedSpatialEffectCount: Int,
        tonalBusGainDB: Double,
        drumBusGainDB: Double,
        masterTrimDB: Double,
        finalPeakLimiterCount: Int,
        roleBuses: [DayObjectsRoleBus] = [],
        parallelSpatialReturnCount: Int? = nil
    ) {
        self.tonalBusCount = tonalBusCount
        self.drumBusCount = drumBusCount
        self.sharedSpatialEffectCount = sharedSpatialEffectCount
        self.tonalBusGainDB = tonalBusGainDB
        self.drumBusGainDB = drumBusGainDB
        self.masterTrimDB = masterTrimDB
        self.finalPeakLimiterCount = finalPeakLimiterCount
        self.roleBuses = roleBuses
        self.parallelSpatialReturnCount = parallelSpatialReturnCount ?? sharedSpatialEffectCount
    }
}

struct DayObjectsInstrumentBankAllocationFingerprint: Equatable, Sendable {
    let tonalNodeIdentities: [ObjectIdentifier]
    let drumPreloadedSampleCount: Int
    let drumAllocatedNodeCount: Int
    let drumFixedPlayerCount: Int
    let pianoPreloadedSampleCount: Int
    let pianoLoadedPlayerCount: Int
    let pianoFixedBackendCount: Int
    let happeningFixedPlayerCount: Int
    let happeningDecodedByteCount: Int

    init(
        tonalNodeIdentities: [ObjectIdentifier],
        drumPreloadedSampleCount: Int,
        drumAllocatedNodeCount: Int,
        drumFixedPlayerCount: Int,
        pianoPreloadedSampleCount: Int,
        pianoLoadedPlayerCount: Int,
        pianoFixedBackendCount: Int,
        happeningFixedPlayerCount: Int = 0,
        happeningDecodedByteCount: Int = 0
    ) {
        self.tonalNodeIdentities = tonalNodeIdentities
        self.drumPreloadedSampleCount = drumPreloadedSampleCount
        self.drumAllocatedNodeCount = drumAllocatedNodeCount
        self.drumFixedPlayerCount = drumFixedPlayerCount
        self.pianoPreloadedSampleCount = pianoPreloadedSampleCount
        self.pianoLoadedPlayerCount = pianoLoadedPlayerCount
        self.pianoFixedBackendCount = pianoFixedBackendCount
        self.happeningFixedPlayerCount = happeningFixedPlayerCount
        self.happeningDecodedByteCount = happeningDecodedByteCount
    }
}

struct DayObjectsBankOutputGainAutomation: Equatable, Sendable {
    let targetLinearGain: Double
    let requestedStartHostTimeSeconds: TimeInterval
    let requestedEndHostTimeSeconds: TimeInterval
    let effectiveStartHostTimeSeconds: TimeInterval
    let effectiveEndHostTimeSeconds: TimeInterval
    let wasForcedImmediate: Bool
}

struct DayObjectsBankOutputGainMetrics: Equatable, Sendable {
    let isSupported: Bool
    let targetLinearGain: Double
    let lastRampDurationSeconds: TimeInterval
    let rampCount: Int
    let lastScheduledAutomation: DayObjectsBankOutputGainAutomation?
    let affectedRoles: Set<DayObjectsRoleBus>

    init(
        isSupported: Bool,
        targetLinearGain: Double,
        lastRampDurationSeconds: TimeInterval,
        rampCount: Int,
        lastScheduledAutomation: DayObjectsBankOutputGainAutomation? = nil,
        affectedRoles: Set<DayObjectsRoleBus> = []
    ) {
        self.isSupported = isSupported
        self.targetLinearGain = targetLinearGain
        self.lastRampDurationSeconds = lastRampDurationSeconds
        self.rampCount = rampCount
        self.lastScheduledAutomation = lastScheduledAutomation
        self.affectedRoles = affectedRoles
    }

    static let unsupported = DayObjectsBankOutputGainMetrics(
        isSupported: false,
        targetLinearGain: 1,
        lastRampDurationSeconds: 0,
        rampCount: 0,
        lastScheduledAutomation: nil
    )
}

struct DayObjectsProgramEffectMetrics: Equatable, Sendable {
    let isSupported: Bool
    let state: DayObjectsMixState?

    var masterLinearGain: Double {
        guard let state else { return 1 }
        return pow(10, state.masterTargetDecibelsBeforeLimiter / 20)
    }

    var rampDurationSeconds: TimeInterval { state?.rampDurationSeconds ?? 0 }

    static let unsupported = DayObjectsProgramEffectMetrics(
        isSupported: false,
        state: nil
    )
}

@MainActor
protocol DayObjectsInstrumentBankGraph: AnyObject {
    var layout: DayObjectsInstrumentBankGraphLayout { get }
    var allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint { get }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics { get }
    var bassDuckGainMetrics: BassDuckGainMetrics { get }
    var programEffectMetrics: DayObjectsProgramEffectMetrics { get }
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval)
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    )
    func scheduleBassDuck(_ command: BassDuckCommand)
    func resetBassDuckGain()
    func synchronizeForStart() throws
    func applyMix(_ state: DayObjectsMixState)
}

extension DayObjectsInstrumentBankGraph {
    var allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint {
        .init(tonalNodeIdentities: [], drumPreloadedSampleCount: 0, drumAllocatedNodeCount: 0, drumFixedPlayerCount: 0, pianoPreloadedSampleCount: 0, pianoLoadedPlayerCount: 0, pianoFixedBackendCount: 0)
    }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics { .unsupported }
    var bassDuckGainMetrics: BassDuckGainMetrics { .unsupported }
    var programEffectMetrics: DayObjectsProgramEffectMetrics { .unsupported }
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {}
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        setOutputGain(linearGain, rampDurationSeconds: max(endHostTime - startHostTime, 0))
    }
    func scheduleBassDuck(_ command: BassDuckCommand) {}
    func resetBassDuckGain() {}
    func synchronizeForStart() throws {}
    func applyMix(_ state: DayObjectsMixState) {}
}

@MainActor
protocol DayObjectsInstrumentBankEngine: AnyObject {
    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics { get }
    func attach(graph: any DayObjectsInstrumentBankGraph) throws
    func detach()
    func start() throws
    func stop()
}

struct DayObjectsInstrumentBankEngineTopologyMetrics: Equatable, Sendable {
    let persistentMasterNodeIdentities: [ObjectIdentifier]
    let finalPeakLimiterIdentities: [ObjectIdentifier]
    let roleBusIdentities: [DayObjectsRoleBus: ObjectIdentifier]
    let parallelSpatialReturnIdentities: [ObjectIdentifier]
    let commonMasterIdentity: ObjectIdentifier?
    let roleMasterDestinations: [DayObjectsRoleBus: ObjectIdentifier]
    let happeningsUsesWorldTrim: Bool
    let masterHighPassHz: Double
    let glueCompressorRatio: Double
    let nominalMaximumGlueReductionDB: Double
    let limiterCeilingDBFS: Double
    let roleHighPassHz: [DayObjectsRoleBus: Double]
    let bassUsesMonoCompatibleLowBand: Bool
    let bassUsesMildSaturation: Bool
    let physicalConnections: Set<DayObjectsGraphConnection>
    let namedNodeIdentities: [String: ObjectIdentifier]
    let meterTapNodeIdentities: [ObjectIdentifier]
    let meterTapInstallationCount: Int
    let masterSaturationIdentity: ObjectIdentifier?
    let finalOutputIdentity: ObjectIdentifier?
    let leadUpperMidDynamicsIdentity: ObjectIdentifier?
    let acceptedParameterValues: [String: Double]

    init(
        persistentMasterNodeIdentities: [ObjectIdentifier],
        finalPeakLimiterIdentities: [ObjectIdentifier],
        roleBusIdentities: [DayObjectsRoleBus: ObjectIdentifier] = [:],
        parallelSpatialReturnIdentities: [ObjectIdentifier] = [],
        commonMasterIdentity: ObjectIdentifier? = nil,
        roleMasterDestinations: [DayObjectsRoleBus: ObjectIdentifier] = [:],
        happeningsUsesWorldTrim: Bool = false,
        masterHighPassHz: Double = 0,
        glueCompressorRatio: Double = 1,
        nominalMaximumGlueReductionDB: Double = 0,
        limiterCeilingDBFS: Double = 0,
        roleHighPassHz: [DayObjectsRoleBus: Double] = [:],
        bassUsesMonoCompatibleLowBand: Bool = false,
        bassUsesMildSaturation: Bool = false,
        physicalConnections: Set<DayObjectsGraphConnection> = [],
        namedNodeIdentities: [String: ObjectIdentifier] = [:],
        meterTapNodeIdentities: [ObjectIdentifier] = [],
        meterTapInstallationCount: Int = 0,
        masterSaturationIdentity: ObjectIdentifier? = nil,
        finalOutputIdentity: ObjectIdentifier? = nil,
        leadUpperMidDynamicsIdentity: ObjectIdentifier? = nil,
        acceptedParameterValues: [String: Double] = [:]
    ) {
        self.persistentMasterNodeIdentities = persistentMasterNodeIdentities
        self.finalPeakLimiterIdentities = finalPeakLimiterIdentities
        self.roleBusIdentities = roleBusIdentities
        self.parallelSpatialReturnIdentities = parallelSpatialReturnIdentities
        self.commonMasterIdentity = commonMasterIdentity
        self.roleMasterDestinations = roleMasterDestinations
        self.happeningsUsesWorldTrim = happeningsUsesWorldTrim
        self.masterHighPassHz = masterHighPassHz
        self.glueCompressorRatio = glueCompressorRatio
        self.nominalMaximumGlueReductionDB = nominalMaximumGlueReductionDB
        self.limiterCeilingDBFS = limiterCeilingDBFS
        self.roleHighPassHz = roleHighPassHz
        self.bassUsesMonoCompatibleLowBand = bassUsesMonoCompatibleLowBand
        self.bassUsesMildSaturation = bassUsesMildSaturation
        self.physicalConnections = physicalConnections
        self.namedNodeIdentities = namedNodeIdentities
        self.meterTapNodeIdentities = meterTapNodeIdentities
        self.meterTapInstallationCount = meterTapInstallationCount
        self.masterSaturationIdentity = masterSaturationIdentity
        self.finalOutputIdentity = finalOutputIdentity
        self.leadUpperMidDynamicsIdentity = leadUpperMidDynamicsIdentity
        self.acceptedParameterValues = acceptedParameterValues
    }

    static let unsupported = Self(
        persistentMasterNodeIdentities: [],
        finalPeakLimiterIdentities: []
    )
}

struct DayObjectsGraphConnection: Equatable, Hashable, Sendable {
    let source: ObjectIdentifier
    let destination: ObjectIdentifier
}

extension DayObjectsInstrumentBankEngine {
    var topologyMetrics: DayObjectsInstrumentBankEngineTopologyMetrics { .unsupported }
}

struct DayObjectsInstrumentBankMetrics: Equatable, Sendable {
    let state: DayObjectsInstrumentBankState
    let tonalPoolCount: Int
    let graph: DayObjectsInstrumentBankGraphLayout?
    let allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint?
    let drumMetrics: DayObjectsDrumBankMetrics
    let pianoMetrics: DayObjectsFeltPianoMetrics
    let happeningMetrics: HappeningSamplePoolMetrics
    let engineTopology: DayObjectsInstrumentBankEngineTopologyMetrics
    let engineInstanceCount: Int
    let engineStartCount: Int

    init(
        state: DayObjectsInstrumentBankState,
        tonalPoolCount: Int,
        graph: DayObjectsInstrumentBankGraphLayout?,
        allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint?,
        drumMetrics: DayObjectsDrumBankMetrics,
        pianoMetrics: DayObjectsFeltPianoMetrics,
        happeningMetrics: HappeningSamplePoolMetrics = .inactive,
        engineTopology: DayObjectsInstrumentBankEngineTopologyMetrics = .unsupported,
        engineInstanceCount: Int = 1,
        engineStartCount: Int = 0
    ) {
        self.state = state
        self.tonalPoolCount = tonalPoolCount
        self.graph = graph
        self.allocationFingerprint = allocationFingerprint
        self.drumMetrics = drumMetrics
        self.pianoMetrics = pianoMetrics
        self.happeningMetrics = happeningMetrics
        self.engineTopology = engineTopology
        self.engineInstanceCount = engineInstanceCount
        self.engineStartCount = engineStartCount
    }
}

@MainActor
protocol DayObjectsInstrumentBankProtocol: AnyObject {
    var descriptors: [DayObjectsInstrumentDescriptor] { get }
    var metrics: DayObjectsInstrumentBankMetrics { get }
    var drums: DayObjectsDrumBankProtocol { get }
    var piano: DayObjectsPianoPoolProtocol { get }
    var happenings: DayObjectsHappeningSamplePoolProtocol { get }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics { get }
    var bassDuckGainMetrics: BassDuckGainMetrics { get }
    var programEffectMetrics: DayObjectsProgramEffectMetrics { get }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol
    func start() throws
    func stop() async
    func releaseWorldLocalVoices()
    func releaseAllIncludingSharedHappenings()
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval)
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    )
    func scheduleBassDuck(_ command: BassDuckCommand)
    func resetBassDuckGain()
    func applyMix(_ state: DayObjectsMixState)
}

extension DayObjectsInstrumentBankProtocol {
    var happenings: DayObjectsHappeningSamplePoolProtocol {
        DayObjectsInactiveHappeningSamplePool()
    }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics { .unsupported }
    var bassDuckGainMetrics: BassDuckGainMetrics { .unsupported }
    var programEffectMetrics: DayObjectsProgramEffectMetrics { .unsupported }
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {}
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        setOutputGain(linearGain, rampDurationSeconds: max(endHostTime - startHostTime, 0))
    }
    func scheduleBassDuck(_ command: BassDuckCommand) {}
    func resetBassDuckGain() {}
    func applyMix(_ state: DayObjectsMixState) {}
}
#endif
