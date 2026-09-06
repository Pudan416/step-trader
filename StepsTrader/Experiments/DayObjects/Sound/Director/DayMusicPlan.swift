#if DEBUG || INTERNAL_BUILD
enum DayObjectsSoundWorld: String, Codable, CaseIterable, Equatable, Sendable {
    case feltAndWood
    case metalAndCurrent

    var displayName: String {
        switch self {
        case .feltAndWood: "Felt & Wood"
        case .metalAndCurrent: "Metal & Current"
        }
    }

    var harmonyInstrumentIDs: Set<String> {
        switch self {
        case .feltAndWood:
            ["pad.forgotten-stories", "keys.bb-slow-poly", "keys.jec-polaroids-2"]
        case .metalAndCurrent:
            ["pad.interstellar", "pad.whispering-sands", "keys.maschinenmensch"]
        }
    }

    var bassInstrumentIDs: Set<String> {
        switch self {
        case .feltAndWood: ["bass.hey-jakob", "bass.jec-hollores-2"]
        case .metalAndCurrent: ["bass.analog-boom", "bass.bassliner"]
        }
    }

    var leadInstrumentIDs: Set<String> {
        switch self {
        case .feltAndWood: ["lead.jec-softwah-2"]
        case .metalAndCurrent: ["lead.verbacious", "lead.bb-silver-screen"]
        }
    }

    var happeningRecipeRawIDs: Set<Int> {
        switch self {
        case .feltAndWood:
            [4, 7, 9, 10, 11, 12, 15, 16, 17, 18, 24, 29, 30]
        case .metalAndCurrent:
            [1, 2, 3, 5, 6, 8, 13, 14, 19, 20, 21, 22, 23, 25, 26, 27, 28]
        }
    }
}

struct DayMusicPlan: Equatable, Sendable {
    let seed: UInt64
    let soundWorld: DayObjectsSoundWorld
    let input: NormalizedDayMusicInput
    let world: TonalWorldPlan
    let rhythm: RhythmPlan
    let groove: GroovePlan
    let bass: BassPlan?
    let harmony: HarmonyPlan
    let happenings: [HappeningMusicPlan]
    let lead: LeadPlan
    let glitch: GlitchPlan
    let mix: LayerMixPlan

    init(
        seed: UInt64,
        soundWorld: DayObjectsSoundWorld = .feltAndWood,
        input: NormalizedDayMusicInput,
        world: TonalWorldPlan,
        rhythm: RhythmPlan,
        groove: GroovePlan,
        bass: BassPlan?,
        harmony: HarmonyPlan,
        happenings: [HappeningMusicPlan],
        lead: LeadPlan,
        glitch: GlitchPlan,
        mix: LayerMixPlan
    ) {
        self.seed = seed
        self.soundWorld = soundWorld
        self.input = input
        self.world = world
        self.rhythm = rhythm
        self.groove = groove
        self.bass = bass
        self.harmony = harmony
        self.happenings = happenings
        self.lead = lead
        self.glitch = glitch
        self.mix = mix
    }
}
#endif
