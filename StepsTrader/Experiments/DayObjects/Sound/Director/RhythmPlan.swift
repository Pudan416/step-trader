#if DEBUG || INTERNAL_BUILD
enum RhythmRole: CaseIterable, Equatable, Sendable {
    case lowPulse
    case halfTimeKick
    case closedHat
    case shaker
    case kickVariation
    case organicPercussion
    case syncopatedGhost
    case fills
}

struct RhythmActivationPlan: Equatable, Sendable {
    let startProgress: Double
    let fullProgress: Double
    let amount: Double
}

struct RhythmVoiceGlitchPlan: Equatable, Sendable {
    let pitchDriftCents: Double
    let dropoutProbability: Double
    let delayInstability: Double

    static let neutral = RhythmVoiceGlitchPlan(
        pitchDriftCents: 0,
        dropoutProbability: 0,
        delayInstability: 0
    )
}

struct RhythmVoicePlan: Equatable, Sendable {
    let role: RhythmRole
    let drumVoice: DayObjectsDrumVoice
    let stepProbabilities: [Double]
    let velocityRange: ClosedRange<Double>
    let microtimingMilliseconds: ClosedRange<Double>
    let roomSend: Double
    let activation: RhythmActivationPlan
    let isTimingAnchor: Bool
    let isGlitchEligible: Bool
    let glitch: RhythmVoiceGlitchPlan

    func effectiveProbability(at step: Int) -> Double {
        guard stepProbabilities.indices.contains(step) else { return 0 }
        return stepProbabilities[step] * activation.amount
    }
}

struct RhythmPlan: Equatable, Sendable {
    let baseTempoBPM: Double
    let tempoBPM: Double
    let stepsProgress: Double
    let voices: [RhythmVoicePlan]
    let maximumSimultaneousAttacks: Int
    let maximumFillsPerWindow: Int
    let fillWindowBars: Int
    let maximumMicrotimingMilliseconds: Double
    let velocityHumanizationRange: ClosedRange<Double>
    let maximumHarmonyDuckingDecibels: Double

    var rhythmicRichness: Double {
        voices.reduce(0) { richness, voice in
            richness + voice.stepProbabilities.reduce(0, +) * voice.activation.amount
        }
    }

    func voice(for role: RhythmRole) -> RhythmVoicePlan? {
        voices.first { $0.role == role }
    }
}
#endif
