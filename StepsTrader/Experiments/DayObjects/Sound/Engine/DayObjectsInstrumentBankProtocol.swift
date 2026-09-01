#if DEBUG || INTERNAL_BUILD
import Foundation

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

    init(
        isSupported: Bool,
        targetLinearGain: Double,
        lastRampDurationSeconds: TimeInterval,
        rampCount: Int,
        lastScheduledAutomation: DayObjectsBankOutputGainAutomation? = nil
    ) {
        self.isSupported = isSupported
        self.targetLinearGain = targetLinearGain
        self.lastRampDurationSeconds = lastRampDurationSeconds
        self.rampCount = rampCount
        self.lastScheduledAutomation = lastScheduledAutomation
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
    let masterLinearGain: Double
    let delayFeedback: Double
    let reverbFeedback: Double
    let rampDurationSeconds: TimeInterval
    let delayFeedbackWasRamped: Bool
    let reverbFeedbackWasRamped: Bool
    let feedbackRampDurationSeconds: TimeInterval

    init(
        isSupported: Bool,
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval,
        delayFeedbackWasRamped: Bool = false,
        reverbFeedbackWasRamped: Bool = false,
        feedbackRampDurationSeconds: TimeInterval = 0
    ) {
        self.isSupported = isSupported
        self.masterLinearGain = masterLinearGain
        self.delayFeedback = delayFeedback
        self.reverbFeedback = reverbFeedback
        self.rampDurationSeconds = rampDurationSeconds
        self.delayFeedbackWasRamped = delayFeedbackWasRamped
        self.reverbFeedbackWasRamped = reverbFeedbackWasRamped
        self.feedbackRampDurationSeconds = feedbackRampDurationSeconds
    }

    static let unsupported = DayObjectsProgramEffectMetrics(
        isSupported: false,
        masterLinearGain: 1,
        delayFeedback: 0,
        reverbFeedback: 0,
        rampDurationSeconds: 0,
        delayFeedbackWasRamped: false,
        reverbFeedbackWasRamped: false,
        feedbackRampDurationSeconds: 0
    )
}

@MainActor
protocol DayObjectsInstrumentBankGraph: AnyObject {
    var layout: DayObjectsInstrumentBankGraphLayout { get }
    var allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint { get }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics { get }
    var programEffectMetrics: DayObjectsProgramEffectMetrics { get }
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval)
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    )
    func synchronizeForStart() throws
    func applyProgramEffects(
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    )
}

extension DayObjectsInstrumentBankGraph {
    var allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint {
        .init(tonalNodeIdentities: [], drumPreloadedSampleCount: 0, drumAllocatedNodeCount: 0, drumFixedPlayerCount: 0, pianoPreloadedSampleCount: 0, pianoLoadedPlayerCount: 0, pianoFixedBackendCount: 0)
    }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics { .unsupported }
    var programEffectMetrics: DayObjectsProgramEffectMetrics { .unsupported }
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {}
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        setOutputGain(linearGain, rampDurationSeconds: max(endHostTime - startHostTime, 0))
    }
    func synchronizeForStart() throws {}
    func applyProgramEffects(
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    ) {}
}

@MainActor
protocol DayObjectsInstrumentBankEngine: AnyObject {
    func attach(graph: any DayObjectsInstrumentBankGraph) throws
    func detach()
    func start() throws
    func stop()
}

struct DayObjectsInstrumentBankMetrics: Equatable, Sendable {
    let state: DayObjectsInstrumentBankState
    let tonalPoolCount: Int
    let graph: DayObjectsInstrumentBankGraphLayout?
    let allocationFingerprint: DayObjectsInstrumentBankAllocationFingerprint?
    let drumMetrics: DayObjectsDrumBankMetrics
    let pianoMetrics: DayObjectsFeltPianoMetrics
    let happeningMetrics: HappeningSamplePoolMetrics
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
    var programEffectMetrics: DayObjectsProgramEffectMetrics { get }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol
    func start() throws
    func stop() async
    func releaseAll()
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval)
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    )
    func applyProgramEffects(
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    )
}

extension DayObjectsInstrumentBankProtocol {
    var happenings: DayObjectsHappeningSamplePoolProtocol {
        DayObjectsInactiveHappeningSamplePool()
    }
    var outputGainMetrics: DayObjectsBankOutputGainMetrics { .unsupported }
    var programEffectMetrics: DayObjectsProgramEffectMetrics { .unsupported }
    func setOutputGain(_ linearGain: Double, rampDurationSeconds: TimeInterval) {}
    func scheduleOutputGain(
        _ linearGain: Double,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        setOutputGain(linearGain, rampDurationSeconds: max(endHostTime - startHostTime, 0))
    }
    func applyProgramEffects(
        masterLinearGain: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    ) {}
}
#endif
