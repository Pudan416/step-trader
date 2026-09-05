#if DEBUG || INTERNAL_BUILD
enum DayMusicMode: CaseIterable, Equatable, Sendable {
    case dorian
    case aeolian
    case mixolydian
    case majorPentatonic

    var scaleIntervals: [Int] {
        switch self {
        case .dorian:
            return [0, 2, 3, 5, 7, 9, 10]
        case .aeolian:
            return [0, 2, 3, 5, 7, 8, 10]
        case .mixolydian:
            return [0, 2, 4, 5, 7, 9, 10]
        case .majorPentatonic:
            return [0, 2, 4, 7, 9]
        }
    }

    var progressionDegreeTemplates: [[Int]] {
        switch self {
        case .dorian:
            return [[0], [0, 5], [0, 10, 5], [0, 3, 10, 5]]
        case .aeolian:
            return [[0], [0, 8], [0, 10, 8], [0, 8, 3, 10]]
        case .mixolydian:
            return [[0], [0, 10], [0, 7, 10], [0, 10, 5, 0]]
        case .majorPentatonic:
            return [[0], [0, 5], [0, 9, 5], [0, 9, 5, 7]]
        }
    }
}

struct TonalWorldPlan: Equatable, Sendable {
    let centerPitchClass: Int
    let mode: DayMusicMode
    let scalePitchClasses: [Int]
    let progression: [ChordPlan]
    let cycleBars: Int
}

struct ChordPlan: Equatable, Sendable {
    let modalDegree: Int
    let rootPitchClass: Int
    let chordPitchClasses: [Int]
    let safePassingPitchClasses: [Int]
    let voicedMIDINotes: [UInt8]
    let durationBars: Int
}
#endif
