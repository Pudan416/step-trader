#if DEBUG || INTERNAL_BUILD
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

    func start(plan: DayMusicPlan) async throws
    func stop() async
    func applyContinuous(_ plan: DayMusicPlan)
    func scheduleStructuralPlan(_ plan: DayMusicPlan)
    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool)
    func removeHappening(id: String)
    func beginLead(_ gesture: LeadGestureSample)
    func updateLead(_ gesture: LeadGestureSample)
    func endLead()
}
#endif
