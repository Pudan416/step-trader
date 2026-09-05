#if DEBUG || INTERNAL_BUILD
enum DayMusicDiagnostic: Equatable, Sendable {
    case invalidCountedSteps
    case invalidStepGoal
    case invalidCountedSleepHours
    case invalidSleepGoal
    case emptyHappeningID
    case happeningIDLimitReached
}
#endif
