struct NormalizedDayMusicInput: Equatable, Sendable {
    let stepsProgress: Double
    let sleepProgress: Double
    let happeningIDs: [String]
    let glitchProgress: Double
    let motionEnergy: Double
    let visualClarity: Double
    let diagnostics: [DayMusicDiagnostic]
}
