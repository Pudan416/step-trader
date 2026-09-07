#if DEBUG || INTERNAL_BUILD
struct DayObjectsLabMusicState: Equatable, Sendable {
    var steps: Double
    var stepGoal: Double
    var sleepHours: Double
    var sleepGoalHours: Double
    var happeningCount: Int
    var spentColors: Int
    var remixSeed: UInt64
    var soundWorld: DayObjectsSoundWorld
    var mood: DayObjectsSoundMood
    var guestWorld: DayObjectsSoundWorld?

    init(
        steps: Double = 10_000,
        stepGoal: Double = 10_000,
        sleepHours: Double = 8,
        sleepGoalHours: Double = 8,
        happeningCount: Int = 8,
        spentColors: Int = 0,
        remixSeed: UInt64 = 0xD4A0_B1EC_75ED_0001,
        soundWorld: DayObjectsSoundWorld = .feltAndWood,
        mood: DayObjectsSoundMood = .moving,
        guestWorld: DayObjectsSoundWorld? = nil
    ) {
        self.steps = steps
        self.stepGoal = stepGoal
        self.sleepHours = sleepHours
        self.sleepGoalHours = sleepGoalHours
        self.happeningCount = happeningCount
        self.spentColors = spentColors
        self.remixSeed = remixSeed
        self.soundWorld = soundWorld
        self.mood = mood
        self.guestWorld = guestWorld
    }
}
#endif
