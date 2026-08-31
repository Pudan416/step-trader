#if DEBUG || INTERNAL_BUILD
struct HappeningScheduledOccurrence: Equatable, Sendable {
    let sequenceIndex: Int
    let position: MusicalPosition
    let intervalBars: Int
}

struct ActiveHappeningVoice {
    let pool: DayObjectsTonalVoicePoolProtocol
    let token: DayObjectsVoiceToken
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
    var pendingBirthChord: ChordPlan?
}
#endif
