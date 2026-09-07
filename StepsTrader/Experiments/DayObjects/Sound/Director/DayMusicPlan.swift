#if DEBUG || INTERNAL_BUILD
struct DayMusicPlan: Equatable, Sendable {
    let seed: UInt64
    let soundWorld: DayObjectsSoundWorld
    let mood: DayObjectsSoundMood
    let guestWorld: DayObjectsSoundWorld?
    let guestInstrumentIDs: Set<DayObjectsInstrumentID>
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
        guestInstrumentIDs: Set<DayObjectsInstrumentID> = [],
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
        self.guestInstrumentIDs = guestInstrumentIDs
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

    /// Lead is gesture-ready; health-gated bass counts only when it has audible events.
    var activeLayerRoleCount: Int {
        (rhythm.rhythmicRichness > 0 ? 1 : 0)
            + (bass?.activeEvents.isEmpty == false ? 1 : 0)
            + harmony.activeRoleCount + (happenings.isEmpty ? 0 : 1) + 1
    }

    var bassIsGuest: Bool { bass.map { guestInstrumentIDs.contains($0.instrumentID) } ?? false }
    var primaryHarmonyIsGuest: Bool {
        guard let role = harmony.role(for: .primaryPad),
              case let .tonal(id) = role.instrumentTarget else { return false }
        return guestInstrumentIDs.contains(id)
    }
}
#endif
