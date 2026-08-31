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
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken?
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate)
    func noteOff(_ token: DayObjectsVoiceToken)
    func releaseAll()
}

protocol DayObjectsDrumBankProtocol: AnyObject {
    var metrics: DayObjectsDrumBankMetrics { get }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double)
    func releaseAll()
}

protocol DayObjectsPianoPoolProtocol: AnyObject {
    var metrics: DayObjectsFeltPianoMetrics { get }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken?
    func noteOff(_ token: DayObjectsFeltPianoToken)
    func releaseAll()
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
    let masterTrimDB: Double
    let finalPeakLimiterCount: Int
}

protocol DayObjectsInstrumentBankGraph: AnyObject {
    var layout: DayObjectsInstrumentBankGraphLayout { get }
    func synchronizeForStart()
}

extension DayObjectsInstrumentBankGraph {
    func synchronizeForStart() {}
}

protocol DayObjectsInstrumentBankEngine: AnyObject {
    func attach(graph: any DayObjectsInstrumentBankGraph) throws
    func start() throws
    func stop()
}

struct DayObjectsInstrumentBankMetrics: Equatable, Sendable {
    let state: DayObjectsInstrumentBankState
    let tonalPoolCount: Int
    let graph: DayObjectsInstrumentBankGraphLayout?
    let drumMetrics: DayObjectsDrumBankMetrics
    let pianoMetrics: DayObjectsFeltPianoMetrics
}

@MainActor
protocol DayObjectsInstrumentBankProtocol: AnyObject {
    var descriptors: [DayObjectsInstrumentDescriptor] { get }
    var metrics: DayObjectsInstrumentBankMetrics { get }
    var drums: DayObjectsDrumBankProtocol { get }
    var piano: DayObjectsPianoPoolProtocol { get }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol
    func start() throws
    func stop() async
    func releaseAll()
}
#endif
