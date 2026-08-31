#if DEBUG || INTERNAL_BUILD
enum RhythmPlanner {
    private struct VoiceTemplate {
        let role: RhythmRole
        let drumVoice: DayObjectsDrumVoice
        let probabilities: [Double]
        let velocityRange: ClosedRange<Double>
        let microtimingMilliseconds: ClosedRange<Double>
        let roomSend: Double
        let activationStart: Double
        let activationFull: Double
        let isTimingAnchor: Bool

        var isGlitchEligible: Bool { !isTimingAnchor }
    }

    static func makePlan(
        input: NormalizedDayMusicInput,
        remixSeed: UInt64
    ) -> RhythmPlan {
        let stepsProgress = unitValue(input.stepsProgress)
        let glitchProgress = unitValue(input.glitchProgress)
        var tempoRandom = StableMusicRandom(seed: remixSeed, domain: .rhythmFamily)
        let baseTempoBPM = 58 + Double(tempoRandom.nextInt(upperBound: 25) ?? 0)

        let voices = voiceTemplates.map { template in
            RhythmVoicePlan(
                role: template.role,
                drumVoice: template.drumVoice,
                stepProbabilities: template.probabilities,
                velocityRange: template.velocityRange,
                microtimingMilliseconds: template.microtimingMilliseconds,
                roomSend: template.roomSend,
                activation: RhythmActivationPlan(
                    startProgress: template.activationStart,
                    fullProgress: template.activationFull,
                    amount: smoothActivation(
                        stepsProgress,
                        start: template.activationStart,
                        end: template.activationFull
                    )
                ),
                isTimingAnchor: template.isTimingAnchor,
                isGlitchEligible: template.isGlitchEligible,
                glitch: template.isGlitchEligible
                    ? RhythmVoiceGlitchPlan(
                        pitchDriftCents: 3 * glitchProgress,
                        dropoutProbability: 0.06 * glitchProgress,
                        delayInstability: 0.08 * glitchProgress
                    )
                    : .neutral
            )
        }

        return RhythmPlan(
            baseTempoBPM: baseTempoBPM,
            tempoBPM: min(102, baseTempoBPM + (20 * stepsProgress)),
            stepsProgress: stepsProgress,
            voices: voices,
            maximumSimultaneousAttacks: 3,
            maximumFillsPerWindow: 1,
            fillWindowBars: 8,
            maximumMicrotimingMilliseconds: 18,
            velocityHumanizationRange: -0.08...0.08,
            maximumHarmonyDuckingDecibels: 2.5
        )
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static let voiceTemplates: [VoiceTemplate] = [
        VoiceTemplate(
            role: .lowPulse,
            drumVoice: .organicLow,
            probabilities: [0.72, 0, 0, 0, 0, 0, 0, 0, 0.62, 0, 0, 0, 0, 0, 0, 0],
            velocityRange: 0.54...0.66,
            microtimingMilliseconds: -8...8,
            roomSend: 0.20,
            activationStart: 0,
            activationFull: 0.20,
            isTimingAnchor: false
        ),
        VoiceTemplate(
            role: .halfTimeKick,
            drumVoice: .kickSoft,
            probabilities: [1, 0, 0, 0, 0, 0, 0, 0, 0.86, 0, 0, 0, 0, 0, 0, 0],
            velocityRange: 0.80...0.92,
            microtimingMilliseconds: 0...0,
            roomSend: 0.08,
            activationStart: 0.10,
            activationFull: 0.35,
            isTimingAnchor: true
        ),
        VoiceTemplate(
            role: .closedHat,
            drumVoice: .hatClosed,
            probabilities: [0.38, 0, 0.34, 0, 0.40, 0, 0.32, 0, 0.40, 0, 0.34, 0, 0.42, 0, 0.32, 0],
            velocityRange: 0.42...0.56,
            microtimingMilliseconds: -12...12,
            roomSend: 0.24,
            activationStart: 0.30,
            activationFull: 0.60,
            isTimingAnchor: false
        ),
        VoiceTemplate(
            role: .shaker,
            drumVoice: .shaker,
            probabilities: [0, 0.30, 0, 0.34, 0, 0.28, 0, 0.36, 0, 0.30, 0, 0.34, 0, 0.28, 0, 0.38],
            velocityRange: 0.34...0.48,
            microtimingMilliseconds: -18...18,
            roomSend: 0.34,
            activationStart: 0.38,
            activationFull: 0.68,
            isTimingAnchor: false
        ),
        VoiceTemplate(
            role: .kickVariation,
            drumVoice: .kickFull,
            probabilities: [0, 0, 0, 0, 0, 0, 0.42, 0, 0, 0, 0, 0, 0, 0, 0.35, 0],
            velocityRange: 0.68...0.82,
            microtimingMilliseconds: -6...6,
            roomSend: 0.10,
            activationStart: 0.45,
            activationFull: 0.72,
            isTimingAnchor: false
        ),
        VoiceTemplate(
            role: .organicPercussion,
            drumVoice: .organicHigh,
            probabilities: [0, 0, 0, 0, 0, 0.38, 0, 0, 0, 0, 0, 0, 0, 0.45, 0, 0],
            velocityRange: 0.45...0.59,
            microtimingMilliseconds: -16...16,
            roomSend: 0.38,
            activationStart: 0.55,
            activationFull: 0.85,
            isTimingAnchor: false
        ),
        VoiceTemplate(
            role: .syncopatedGhost,
            drumVoice: .stick,
            probabilities: [0, 0, 0, 0.22, 0, 0, 0, 0.26, 0, 0, 0, 0.22, 0, 0, 0, 0.28],
            velocityRange: 0.28...0.40,
            microtimingMilliseconds: -18...18,
            roomSend: 0.42,
            activationStart: 0.65,
            activationFull: 0.92,
            isTimingAnchor: false
        ),
        VoiceTemplate(
            role: .fills,
            drumVoice: .clapSoft,
            probabilities: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.65],
            velocityRange: 0.52...0.68,
            microtimingMilliseconds: -10...10,
            roomSend: 0.46,
            activationStart: 0.82,
            activationFull: 1,
            isTimingAnchor: false
        )
    ]
}
#endif
