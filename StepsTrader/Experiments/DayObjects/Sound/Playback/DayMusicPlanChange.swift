#if DEBUG || INTERNAL_BUILD
struct DayMusicPlanChange: Equatable, Sendable {
    let continuousPlan: DayMusicPlan?
    let structuralPlan: DayMusicPlan?
    let addedHappenings: [HappeningMusicPlan]
    let removedHappeningIDs: [String]
}
#endif
