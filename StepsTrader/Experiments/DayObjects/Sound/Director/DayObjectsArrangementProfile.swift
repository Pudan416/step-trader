struct DayObjectsArrangementProfile: Equatable, Sendable {
    let world: DayObjectsSoundWorld
    let mood: DayObjectsSoundMood
    let activeRoleRange: ClosedRange<Int>
    let rhythmicDensityMultiplier: Double
    let happeningDensityMultiplier: Double
    let maximumConcurrentHappenings: Int
    let harmonyReleaseMultiplier: Double
    let bassArticulationWeights: [BassArticulation: Double]
    let leadGestureSmoothingMultiplier: Double

    var usesBass: Bool { mood != .sparse && !(world == .livingField && mood == .moving) }

    var harmonyRoles: [HarmonyRole] {
        if mood == .sparse { return [.drone] }
        if mood == .moving || world == .livingField { return [.drone, .primaryPad] }
        let detail: HarmonyRole = switch world {
        case .feltAndWood: .pianoOrKeysAccents
        case .electricDream: .innerMotion
        default: .secondaryPadOrKeys
        }
        return [.drone, .primaryPad, detail]
    }

    var humanization: RhythmHumanizationProfile {
        switch world {
        case .feltAndWood: .loose
        case .livingField: .relaxed
        case .metalAndCurrent, .electricDream: .tight
        }
    }

    static func `for`(world: DayObjectsSoundWorld, mood: DayObjectsSoundMood) -> Self {
        let roleRange: ClosedRange<Int> = switch mood {
        case .sparse: 3...4
        case .moving: 5...6
        case .strange: 5...7
        }
        let moodDensity: Double = switch mood {
        case .sparse: 0.45
        case .moving: 0.8
        case .strange: 1
        }
        let density: Double
        let happeningDensity: Double
        let release: Double
        let smoothing: Double
        let weights: [BassArticulation: Double]
        switch world {
        case .feltAndWood:
            density = 0.75; happeningDensity = 0.8; release = 1; smoothing = 1.15
            weights = [.pulse: 0.2, .arpeggio: 0.15, .sustained: 0.65]
        case .livingField:
            density = 0.35; happeningDensity = 0.35; release = 1.8; smoothing = 1.5
            weights = [.pulse: 0, .arpeggio: 0, .sustained: 1]
        case .metalAndCurrent:
            density = 1; happeningDensity = 0.9; release = 1; smoothing = 0.85
            weights = [.pulse: 0.85, .arpeggio: 0.1, .sustained: 0.05]
        case .electricDream:
            density = 0.85; happeningDensity = 1; release = 1.1; smoothing = 1.1
            weights = [.pulse: 0.2, .arpeggio: 0.75, .sustained: 0.05]
        }
        return Self(
            world: world, mood: mood, activeRoleRange: roleRange,
            rhythmicDensityMultiplier: density * moodDensity,
            happeningDensityMultiplier: happeningDensity * moodDensity,
            maximumConcurrentHappenings: world == .livingField || mood == .sparse ? 1 : 2,
            harmonyReleaseMultiplier: release,
            bassArticulationWeights: weights, leadGestureSmoothingMultiplier: smoothing
        )
    }
}
