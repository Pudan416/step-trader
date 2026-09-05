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

enum RhythmFamily: CaseIterable, Equatable, Sendable {
    case grounded
    case crossPulse
    case orbiting
    case brokenBeat
}

enum RhythmHumanizationProfile: CaseIterable, Equatable, Sendable {
    case tight
    case relaxed
    case loose

    var depth: Double {
        switch self {
        case .tight: return 0.35
        case .relaxed: return 0.65
        case .loose: return 1
        }
    }
}

struct RhythmRealizationState: Equatable, Sendable {
    let patternSeed: UInt64
    let humanizationSeed: UInt64
    let cycleKey: UInt64
    let counterMapping: MusicEventCounterMapping
}

struct RhythmRealizedEvent: Equatable, Sendable {
    let role: RhythmRole
    let drumVoice: DayObjectsDrumVoice
    let cycleIndex: Int
    let stepIndex: Int
    let velocity: Double
    let microtimingMilliseconds: Double
}

struct RhythmActivationPlan: Equatable, Sendable {
    let startProgress: Double
    let fullProgress: Double
    let amount: Double
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

    func effectiveProbability(at step: Int) -> Double {
        guard stepProbabilities.indices.contains(step) else { return 0 }
        return stepProbabilities[step] * activation.amount
    }
}

struct RhythmPlan: Equatable, Sendable {
    let baseTempoBPM: Double
    let tempoBPM: Double
    let stepsProgress: Double
    let family: RhythmFamily
    let patternOffsetSteps: Int
    let humanizationProfile: RhythmHumanizationProfile
    let groove: GroovePlan
    let realization: RhythmRealizationState
    let voices: [RhythmVoicePlan]
    let maximumSimultaneousAttacks: Int
    let maximumFillsPerWindow: Int
    let fillWindowBars: Int
    let maximumMicrotimingMilliseconds: Double
    let velocityHumanizationRange: ClosedRange<Double>
    let maximumHarmonyDuckingDecibels: Double

    init(
        baseTempoBPM: Double,
        tempoBPM: Double,
        stepsProgress: Double,
        family: RhythmFamily,
        patternOffsetSteps: Int,
        humanizationProfile: RhythmHumanizationProfile,
        groove: GroovePlan = .percussion,
        realization: RhythmRealizationState,
        voices: [RhythmVoicePlan],
        maximumSimultaneousAttacks: Int,
        maximumFillsPerWindow: Int,
        fillWindowBars: Int,
        maximumMicrotimingMilliseconds: Double,
        velocityHumanizationRange: ClosedRange<Double>,
        maximumHarmonyDuckingDecibels: Double
    ) {
        self.baseTempoBPM = baseTempoBPM
        self.tempoBPM = tempoBPM
        self.stepsProgress = stepsProgress
        self.family = family
        self.patternOffsetSteps = patternOffsetSteps
        self.humanizationProfile = humanizationProfile
        self.groove = groove
        self.realization = realization
        self.voices = voices
        self.maximumSimultaneousAttacks = maximumSimultaneousAttacks
        self.maximumFillsPerWindow = maximumFillsPerWindow
        self.fillWindowBars = fillWindowBars
        self.maximumMicrotimingMilliseconds = maximumMicrotimingMilliseconds
        self.velocityHumanizationRange = velocityHumanizationRange
        self.maximumHarmonyDuckingDecibels = maximumHarmonyDuckingDecibels
    }

    var rhythmicRichness: Double {
        voices.reduce(0) { richness, voice in
            richness + voice.stepProbabilities.reduce(0, +) * voice.activation.amount
        }
    }

    func voice(for role: RhythmRole) -> RhythmVoicePlan? {
        voices.first { $0.role == role }
    }

    func realizedEvents(cycleIndex: Int, stepIndex: Int) -> [RhythmRealizedEvent] {
        guard cycleIndex >= 0, (0..<16).contains(stepIndex) else { return [] }

        var candidates: [(event: RhythmRealizedEvent, priority: Double, anchor: Bool, roleIndex: UInt64)] = []
        for voice in voices {
            let roleIndex = voice.role.realizationIndex
            if voice.role == .fills {
                guard fillWindowBars > 0 else { continue }
                let fillCycle = Int(realization.cycleKey % UInt64(fillWindowBars))
                guard cycleIndex % fillWindowBars == fillCycle else { continue }
            }
            if voice.role == .halfTimeKick,
               !isEligibleAnchorKick(at: stepIndex, voice: voice) {
                continue
            }

            let probability = voice.effectiveProbability(at: stepIndex)
            guard probability > 0 else { continue }
            let attackGate = sample(
                seed: realization.patternSeed,
                roleIndex: roleIndex,
                cycleIndex: cycleIndex,
                stepIndex: stepIndex,
                parameter: .attackGate
            )
            guard attackGate < probability else { continue }

            let velocityMidpoint = (voice.velocityRange.lowerBound + voice.velocityRange.upperBound) / 2
            let velocityHalfWidth = min(
                (voice.velocityRange.upperBound - voice.velocityRange.lowerBound) / 2,
                max(abs(velocityHumanizationRange.lowerBound), abs(velocityHumanizationRange.upperBound))
            )
            let velocitySample = sample(
                seed: realization.humanizationSeed,
                roleIndex: roleIndex,
                cycleIndex: cycleIndex,
                stepIndex: stepIndex,
                parameter: .velocity
            )
            let velocity = min(
                max(
                    velocityMidpoint
                        + ((velocitySample * 2 - 1) * velocityHalfWidth * humanizationProfile.depth),
                    voice.velocityRange.lowerBound
                ),
                voice.velocityRange.upperBound
            )

            let microtiming: Double
            if voice.isTimingAnchor {
                microtiming = 0
            } else {
                let lower = voice.microtimingMilliseconds.lowerBound * humanizationProfile.depth
                let upper = voice.microtimingMilliseconds.upperBound * humanizationProfile.depth
                let timingSample = sample(
                    seed: realization.humanizationSeed,
                    roleIndex: roleIndex,
                    cycleIndex: cycleIndex,
                    stepIndex: stepIndex,
                    parameter: .microtiming
                )
                microtiming = lower + ((upper - lower) * timingSample)
            }

            candidates.append((
                event: RhythmRealizedEvent(
                    role: voice.role,
                    drumVoice: voice.drumVoice,
                    cycleIndex: cycleIndex,
                    stepIndex: stepIndex,
                    velocity: velocity,
                    microtimingMilliseconds: microtiming
                ),
                priority: sample(
                    seed: realization.patternSeed,
                    roleIndex: roleIndex,
                    cycleIndex: cycleIndex,
                    stepIndex: stepIndex,
                    parameter: .attackPriority
                ),
                anchor: voice.isTimingAnchor,
                roleIndex: roleIndex
            ))
        }

        candidates = candidates.filter { candidate in
            if candidate.event.role == .halfTimeKick {
                return true
            }
            if groove.usesBass && candidate.event.role == .kickVariation {
                return false
            }
            let keep = StableMusicRandom.counterUnitDouble(
                seed: groove.thinningSeed,
                counter: UInt64(cycleIndex * 16 + stepIndex) &* 16
                    &+ candidate.roleIndex
            ) < groove.auxiliaryRetention
            return keep
        }

        candidates.sort { left, right in
            if left.anchor != right.anchor { return left.anchor }
            if left.priority != right.priority { return left.priority > right.priority }
            return left.roleIndex < right.roleIndex
        }
        return candidates.prefix(max(0, maximumSimultaneousAttacks))
            .sorted { $0.roleIndex < $1.roleIndex }
            .map(\.event)
    }

    private func sample(
        seed: UInt64,
        roleIndex: UInt64,
        cycleIndex: Int,
        stepIndex: Int,
        parameter: RhythmRealizationParameter
    ) -> Double {
        let counter = realization.counterMapping.counter(
            cycleKey: realization.cycleKey,
            roleIndex: roleIndex,
            cycleIndex: UInt64(cycleIndex),
            stepIndex: UInt64(stepIndex),
            parameterIndex: parameter.rawValue
        )
        return StableMusicRandom.counterUnitDouble(seed: seed, counter: counter)
    }

    private func isEligibleAnchorKick(
        at stepIndex: Int,
        voice: RhythmVoicePlan?
    ) -> Bool {
        guard let voice, voice.isTimingAnchor else { return false }

        let eligibleSteps = voice.stepProbabilities.enumerated()
            .filter { $0.element > 0 }
            .sorted { left, right in
                if left.element != right.element { return left.element > right.element }
                return left.offset < right.offset
            }
            .prefix(max(0, groove.maximumAnchorKicksPerBar))
            .map(\.offset)
        return eligibleSteps.contains(stepIndex)
    }
}

private enum RhythmRealizationParameter: UInt64 {
    case attackGate = 0
    case attackPriority = 1
    case velocity = 2
    case microtiming = 3
}

private extension RhythmRole {
    var realizationIndex: UInt64 {
        switch self {
        case .lowPulse: return 0
        case .halfTimeKick: return 1
        case .closedHat: return 2
        case .shaker: return 3
        case .kickVariation: return 4
        case .organicPercussion: return 5
        case .syncopatedGhost: return 6
        case .fills: return 7
        }
    }
}
#endif
