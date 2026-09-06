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

enum HappeningMotifRole: Equatable, Sendable {
    case legacyAccent
    case statement
    case response
    case texture
}

struct HappeningMotifPlan: Equatable, Sendable {
    let role: HappeningMotifRole
    let degreeOffsets: [Int]
    let offsetBeats: [Double]
    let velocityMultipliers: [Double]

    var noteCount: Int { offsetBeats.count }
    var isConversational: Bool { role != .legacyAccent }

    static let legacyAccent = HappeningMotifPlan(
        role: .legacyAccent,
        degreeOffsets: [0],
        offsetBeats: [0],
        velocityMultipliers: [1]
    )
}

struct HappeningMusicPlan: Equatable, Sendable {
    static let minimumAudibleGain = 0.62

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
    let motif: HappeningMotifPlan
    let recurrence: HappeningRecurrencePlan

    init(
        happeningID: String,
        family: HappeningSoundFamily,
        recipeID: HappeningSoundRecipeID,
        pan: Double,
        gain: Double,
        birthGain: Double,
        attackSeconds: Double,
        releaseSeconds: Double,
        delaySend: Double,
        reverbSend: Double,
        motif: HappeningMotifPlan = .legacyAccent,
        recurrence: HappeningRecurrencePlan
    ) {
        self.happeningID = happeningID
        self.family = family
        self.recipeID = recipeID
        self.pan = pan
        self.gain = gain
        self.birthGain = birthGain
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
        self.delaySend = delaySend
        self.reverbSend = reverbSend
        self.motif = motif
        self.recurrence = recurrence
    }
}

struct HappeningScheduleEvent: Equatable, Sendable {
    let happeningID: String
    let sequenceIndex: Int
    let motifStepIndex: Int
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
