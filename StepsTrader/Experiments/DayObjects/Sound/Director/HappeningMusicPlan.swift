#if DEBUG || INTERNAL_BUILD
enum HappeningSoundFamily: CaseIterable, Equatable, Hashable, Sendable {
    case pluck
    case mallet
    case bell
    case softOneShot
    case texture

}

enum HappeningRecurrenceAlignment: Equatable, Sendable {
    case gridAligned
    case floating
}

struct HappeningRecurrencePlan: Equatable, Sendable {
    /// Seed plus stable rank are sufficient for playback to regenerate and extend candidates.
    let scheduleSeed: UInt64
    let alignmentRank: UInt64
    let floatingOffsetBeats: Double
}

struct HappeningMusicPlan: Equatable, Sendable {
    static let minimumAudibleGain = 0.18

    let happeningID: String
    let family: HappeningSoundFamily
    let recipeID: HappeningSoundRecipeID
    let pan: Double
    let gain: Double
    let birthGain: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let delaySend: Double
    let reverbSend: Double
    let recurrence: HappeningRecurrencePlan
}

struct HappeningScheduleEvent: Equatable, Sendable {
    let happeningID: String
    let sequenceIndex: Int
    let startBeat: Double
    let intervalBars: Int
    let alignment: HappeningRecurrenceAlignment
    let gain: Double
}

struct HappeningScheduleCursor: Equatable, Sendable {
    let happeningID: String
    let nextSequenceIndex: Int
    let nextCandidateBeat: Double
}

struct HappeningScheduleAllocation: Equatable, Sendable {
    let cycleBars: Int
    let horizonBars: Int
    let beatsPerBar: Int
    let intervalBandBars: ClosedRange<Int>?
    let events: [HappeningScheduleEvent]
    let nextCursors: [HappeningScheduleCursor]
}
#endif
