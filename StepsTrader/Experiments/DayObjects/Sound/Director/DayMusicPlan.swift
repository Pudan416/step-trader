#if DEBUG || INTERNAL_BUILD
struct DayMusicPlan: Equatable, Sendable {
    let seed: UInt64
    let soundWorld: DayObjectsSoundWorld
    let mood: DayObjectsSoundMood
    let guestWorld: DayObjectsSoundWorld?
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
        mood: DayObjectsSoundMood = .moving,
        guestWorld: DayObjectsSoundWorld? = nil,
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
        self.mood = mood
        self.guestWorld = guestWorld
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
