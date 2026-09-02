#if DEBUG || INTERNAL_BUILD
struct HappeningScheduledOccurrence: Equatable, Sendable {
    let sequenceIndex: Int
    let position: MusicalPosition
    let intervalBars: Int
}

struct ActiveHappeningVoice {
    let pool: DayObjectsHappeningSamplePoolProtocol
    let voiceID: Int
    let resolvedSound: ResolvedHappeningSound
    let effectCommand: HappeningEffectCommand
    let baseGain: Double
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
}
#endif
