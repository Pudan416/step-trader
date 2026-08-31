#if DEBUG || INTERNAL_BUILD
struct DayMusicPlan: Equatable, Sendable {
    let seed: UInt64
    let input: NormalizedDayMusicInput
    let world: TonalWorldPlan
    let rhythm: RhythmPlan
    let harmony: HarmonyPlan
    let happenings: [HappeningMusicPlan]
    let lead: LeadPlan
    let glitch: GlitchPlan
    let mix: LayerMixPlan
}
#endif
