#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsAudioError: Error, Equatable, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

enum DayObjectsSoundState: Equatable, Sendable {
    case off
    case starting
    case on
    case error(DayObjectsAudioError)
}

/// Debug-only mix comparison state. It is a command for an already prepared
/// playback graph; neither the view nor the lab controller creates audio nodes.
enum DayObjectsAuditionMode: Hashable, Sendable {
    case fullComposition
    case isolatedBus(DayObjectsRoleBus)
    case kickBassSidechain
}

struct DayObjectsSidechainAuditionResult: Equatable, Sendable {
    let instrumentID: DayObjectsInstrumentID
    let duckCommand: BassDuckCommand
    let scheduledKick: DayObjectsScheduledDrumHit

    var estimatedReductionDB: Double { duckCommand.maximumAttenuationDecibels }
}

struct DayObjectsDiagnosticMeterSnapshot: Equatable, Sendable {
    let roleBusMetrics: DayObjectsFiveRoleBusMetrics
    let masterMetrics: DayObjectsMasterMetrics

    static let silent = Self(
        roleBusMetrics: .init(
            rhythm: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
            bass: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
            harmony: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
            happenings: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0),
            lead: .init(peakDBFS: -120, rmsDBFS: -120, activeVoiceCount: 0)
        ),
        masterMetrics: .init(peakDBFS: -120, rmsDBFS: -120, estimatedLimiterReductionDB: 0)
    )
}

enum DayObjectsDiagnosticCommand: Equatable, Sendable {
    case mode(DayObjectsAuditionMode)
    case release
}

struct DayObjectsPlaybackMetrics: Equatable, Sendable {
    var engineStartCount: Int = 0
    var activeTransportCount: Int = 0
    var activeTaskCount: Int = 0
    var activeNodeCount: Int = 0
    var activeVoiceCount: Int = 0
    var activeHappeningCount: Int = 0
    var pendingRemixCount: Int = 0
    var leadVoiceCount: Int = 0
}

@MainActor
protocol DayObjectsMusicPlaybackProtocol: AnyObject {
    var state: DayObjectsSoundState { get }
    var metrics: DayObjectsPlaybackMetrics { get }
    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot { get }

    func start(plan: DayMusicPlan) async throws
    func auditionHappening(_ recipeID: HappeningSoundRecipeID) async throws
    func stop() async
    func applyContinuous(_ plan: DayMusicPlan)
    func scheduleStructuralPlan(_ plan: DayMusicPlan)
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool)
    func removeHappening(id: String)
    func beginLead(_ gesture: LeadGestureSample)
    func updateLead(_ gesture: LeadGestureSample)
    func endLead()
    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan)
    func releaseDiagnosticAudition()
    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult?
}

extension DayObjectsMusicPlaybackProtocol {
    var diagnosticMeterSnapshot: DayObjectsDiagnosticMeterSnapshot { .silent }
    func applyDiagnosticAudition(_ mode: DayObjectsAuditionMode, plan: DayMusicPlan) {}
    func releaseDiagnosticAudition() {}
    func auditionKickBassSidechain(preferredBassID: DayObjectsInstrumentID?) -> DayObjectsSidechainAuditionResult? { nil }
}
#endif
