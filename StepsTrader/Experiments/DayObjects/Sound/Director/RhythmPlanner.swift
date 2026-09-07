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
        makePlan(
            input: input,
            remixSeed: remixSeed,
            groove: GroovePlanner.makePlan(remixSeed: remixSeed)
        )
    }

    static func makePlan(
        input: NormalizedDayMusicInput,
        remixSeed: UInt64,
        groove: GroovePlan,
        kitID: String = "legacy",
        arrangement: DayObjectsArrangementProfile? = nil
    ) -> RhythmPlan {
        let stepsProgress = unitValue(input.stepsProgress)
        var familyRandom = StableMusicRandom(seed: remixSeed, domain: .rhythmFamily)
        let baseTempoBPM = 58 + Double(familyRandom.nextInt(upperBound: 25) ?? 0)
        let sampledFamily = familyRandom.choice(from: RhythmFamily.allCases) ?? .grounded
        let family = arrangement?.world == .metalAndCurrent ? .grounded : sampledFamily
        var patternRandom = StableMusicRandom(seed: remixSeed, domain: .rhythmPattern)
        let patternSeed = patternRandom.nextUInt64()
        let cycleKey = patternRandom.nextUInt64()
        let patternOffsetSteps = (patternRandom.nextInt(upperBound: 2) ?? 0) * 8
        var humanizationRandom = StableMusicRandom(seed: remixSeed, domain: .rhythmHumanization)
        let humanizationSeed = humanizationRandom.nextUInt64()
        let sampledHumanization = humanizationRandom.choice(
            from: RhythmHumanizationProfile.allCases
        ) ?? .tight
        let humanizationProfile = arrangement?.humanization ?? sampledHumanization

        let voices = voiceTemplates.map { template in
            RhythmVoicePlan(
                role: template.role,
                drumVoice: kitID == "legacy" ? template.drumVoice : DayObjectsDrumBank.voice(for: template.role, kitID: kitID),
                stepProbabilities: transformedPattern(
                    template.probabilities.map { $0 * (arrangement?.rhythmicDensityMultiplier ?? 1) },
                    family: family,
                    offsetSteps: patternOffsetSteps
                ),
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
                isGlitchEligible: template.isGlitchEligible
            )
        }

        return RhythmPlan(
            kitID: kitID,
            baseTempoBPM: baseTempoBPM,
            tempoBPM: min(102, baseTempoBPM + (20 * stepsProgress)),
            stepsProgress: stepsProgress,
            family: family,
            patternOffsetSteps: patternOffsetSteps,
            humanizationProfile: humanizationProfile,
            groove: groove,
            realization: RhythmRealizationState(
                patternSeed: patternSeed,
                humanizationSeed: humanizationSeed,
                cycleKey: cycleKey,
                counterMapping: .roleCycleStepParameterV1
            ),
            voices: voices,
            maximumSimultaneousAttacks: arrangement?.world == .livingField ? 1 : 3,
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

    private static func transformedPattern(
        _ probabilities: [Double],
        family: RhythmFamily,
        offsetSteps: Int
    ) -> [Double] {
        guard probabilities.count == 16 else { return probabilities }
        var result = Array(repeating: 0.0, count: probabilities.count)
        for (sourceStep, probability) in probabilities.enumerated() {
            let targetStep = (sourceStep * family.stepMultiplier + offsetSteps) % probabilities.count
            result[targetStep] = probability
        }
        return result
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

private extension RhythmFamily {
    var stepMultiplier: Int {
        switch self {
        case .grounded: return 1
        case .crossPulse: return 3
        case .orbiting: return 5
        case .brokenBeat: return 7
        }
    }
}
#endif
