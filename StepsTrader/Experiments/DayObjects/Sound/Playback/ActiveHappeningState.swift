#if DEBUG || INTERNAL_BUILD
struct HappeningScheduledOccurrence: Equatable, Sendable {
    let sequenceIndex: Int
    let motifStepIndex: Int
    let position: MusicalPosition
    let intervalBars: Int
    var retryAttemptCount: Int
    var nextRetryPosition: MusicalPosition
    let retryDeadline: MusicalPosition
}

struct ActiveHappeningVoice {
    let pool: DayObjectsHappeningSamplePoolProtocol
    let handle: HappeningPlaybackHandle
    let resolvedSound: ResolvedHappeningSound
    let effectCommand: HappeningEffectCommand
    let baseGain: Double
    let basePlaybackRate: Double
    let releaseAt: MusicalPosition
}

struct ActiveHappeningState {
    var plan: HappeningMusicPlan
    var nextOccurrence: MusicalPosition
    var didPlaySinceStart: Bool
    var activeVoiceIDs: Set<Int>
    var scheduledOccurrences: [HappeningScheduledOccurrence]
    var nextOccurrenceIndex: Int
    var activeVoices: [Int: ActiveHappeningVoice]
    var lastAttackPosition: MusicalPosition?
    var isBirthPending: Bool
    var birthRetryAttemptCount: Int
    var birthNextRetryPosition: MusicalPosition
    var birthRetryDeadline: MusicalPosition
}
#endif
