enum GlitchRole: CaseIterable, Equatable, Sendable {
    case pad
    case happening
    case lead
    case percussion
    case timingAnchorKick
}

struct GlitchRolePlan: Equatable, Sendable {
    let role: GlitchRole
    let isTimingAnchor: Bool
    let isGlitchEligible: Bool
    let pitchDriftCents: Double
    let dropoutProbability: Double
    let delayTimeInstability: Double
    let saturationAmount: Double
    let timingDriftMilliseconds: Double

    init(
        role: GlitchRole,
        isTimingAnchor: Bool,
        isGlitchEligible: Bool,
        pitchDriftCents: Double,
        dropoutProbability: Double,
        delayTimeInstability: Double,
        saturationAmount: Double = 0,
        timingDriftMilliseconds: Double = 0
    ) {
        self.role = role
        self.isTimingAnchor = isTimingAnchor
        self.isGlitchEligible = isGlitchEligible
        self.pitchDriftCents = pitchDriftCents
        self.dropoutProbability = dropoutProbability
        self.delayTimeInstability = delayTimeInstability
        self.saturationAmount = saturationAmount
        self.timingDriftMilliseconds = timingDriftMilliseconds
    }

    static let stableKick = GlitchRolePlan(
        role: .timingAnchorKick,
        isTimingAnchor: true,
        isGlitchEligible: false,
        pitchDriftCents: 0,
        dropoutProbability: 0,
        delayTimeInstability: 0,
        saturationAmount: 0,
        timingDriftMilliseconds: 0
    )

    func scaled(by rawProgress: Double) -> Self {
        let progress = rawProgress.isFinite ? min(max(rawProgress, 0), 1) : 0
        return .init(
            role: role,
            isTimingAnchor: isTimingAnchor,
            isGlitchEligible: isGlitchEligible,
            pitchDriftCents: pitchDriftCents * progress,
            dropoutProbability: dropoutProbability * progress,
            delayTimeInstability: delayTimeInstability * progress,
            saturationAmount: saturationAmount * progress,
            timingDriftMilliseconds: timingDriftMilliseconds * progress
        )
    }

    fileprivate func clamped(to limits: Self) -> Self {
        .init(
            role: role,
            isTimingAnchor: isTimingAnchor,
            isGlitchEligible: isGlitchEligible,
            pitchDriftCents: Self.bounded(pitchDriftCents, maximum: limits.pitchDriftCents),
            dropoutProbability: Self.bounded(dropoutProbability, maximum: limits.dropoutProbability),
            delayTimeInstability: Self.bounded(delayTimeInstability, maximum: limits.delayTimeInstability),
            saturationAmount: Self.bounded(saturationAmount, maximum: limits.saturationAmount),
            timingDriftMilliseconds: Self.bounded(
                timingDriftMilliseconds,
                maximum: limits.timingDriftMilliseconds
            )
        )
    }

    private static func bounded(_ value: Double, maximum: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maximum)
    }
}

extension GlitchRole {
    var safeLimits: GlitchRolePlan {
        switch self {
        case .pad:
            return .init(
                role: self,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 14,
                dropoutProbability: 0,
                delayTimeInstability: 0.08
            )
        case .happening:
            return .init(
                role: self,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 10,
                dropoutProbability: 0.06,
                delayTimeInstability: 0.04
            )
        case .lead:
            return .init(
                role: self,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 8,
                dropoutProbability: 0,
                delayTimeInstability: 0,
                saturationAmount: 0.18
            )
        case .percussion:
            return .init(
                role: self,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 3,
                dropoutProbability: 0,
                delayTimeInstability: 0,
                timingDriftMilliseconds: 0.32
            )
        case .timingAnchorKick:
            return .stableKick
        }
    }
}

struct GlitchRealizationState: Equatable, Sendable {
    let dropoutSeed: UInt64
    let variationSeed: UInt64
    let cycleKey: UInt64
    let counterMapping: MusicEventCounterMapping

    static let neutral = GlitchRealizationState(
        dropoutSeed: 0,
        variationSeed: 0,
        cycleKey: 0,
        counterMapping: .roleCycleStepParameterV1
    )
}

struct GlitchRealizedEvent: Equatable, Sendable {
    let role: GlitchRole
    let cycleIndex: Int
    let stepIndex: Int
    let shouldDropOut: Bool
    let pitchDriftCents: Double
    let delayTimeVariation: Double
    let timingDriftMilliseconds: Double
}

struct GlitchPlan: Equatable, Sendable {
    static let maximumWowFlutterDepth = 0.18
    static let maximumStereoSeparationAddition = 0.22

    let progress: Double
    let roles: [GlitchRolePlan]
    let wowFlutterDepth: Double
    let stereoSeparationAddition: Double
    let realization: GlitchRealizationState

    static let neutral = GlitchPlan(
        progress: 0,
        roles: [
            GlitchRolePlan(
                role: .pad,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 0,
                dropoutProbability: 0,
                delayTimeInstability: 0,
                saturationAmount: 0,
                timingDriftMilliseconds: 0
            ),
            GlitchRolePlan(
                role: .happening,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 0,
                dropoutProbability: 0,
                delayTimeInstability: 0,
                saturationAmount: 0,
                timingDriftMilliseconds: 0
            ),
            GlitchRolePlan(
                role: .lead,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 0,
                dropoutProbability: 0,
                delayTimeInstability: 0,
                saturationAmount: 0,
                timingDriftMilliseconds: 0
            ),
            GlitchRolePlan(
                role: .percussion,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 0,
                dropoutProbability: 0,
                delayTimeInstability: 0,
                saturationAmount: 0,
                timingDriftMilliseconds: 0
            ),
            .stableKick,
        ],
        wowFlutterDepth: 0,
        stereoSeparationAddition: 0,
        realization: .neutral
    )

    var isNeutral: Bool {
        progress == 0
            && wowFlutterDepth == 0
            && stereoSeparationAddition == 0
            && roles.allSatisfy {
                $0.pitchDriftCents == 0
                    && $0.dropoutProbability == 0
                    && $0.delayTimeInstability == 0
                    && $0.saturationAmount == 0
                    && $0.timingDriftMilliseconds == 0
            }
    }

    func role(for role: GlitchRole) -> GlitchRolePlan? {
        roles.first { $0.role == role }
    }

    var sanitizedProgress: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    var sanitizedWowFlutterDepth: Double {
        Self.bounded(wowFlutterDepth, maximum: Self.maximumWowFlutterDepth)
    }

    var sanitizedStereoSeparationAddition: Double {
        Self.bounded(
            stereoSeparationAddition,
            maximum: Self.maximumStereoSeparationAddition
        )
    }

    func validatedRolePlan(for role: GlitchRole) -> GlitchRolePlan? {
        let matches = roles.filter { $0.role == role }
        guard matches.count == 1, let candidate = matches.first else { return nil }
        if role == .timingAnchorKick {
            guard candidate.isTimingAnchor, !candidate.isGlitchEligible else { return nil }
        } else {
            guard !candidate.isTimingAnchor, candidate.isGlitchEligible else { return nil }
        }
        return candidate.clamped(to: role.safeLimits)
    }

    func realizedEvent(
        for role: GlitchRole,
        cycleIndex: Int,
        stepIndex: Int
    ) -> GlitchRealizedEvent? {
        guard cycleIndex >= 0,
              (0..<16).contains(stepIndex),
              let rolePlan = validatedRolePlan(for: role)
        else {
            return nil
        }
        guard sanitizedProgress > 0, rolePlan.isGlitchEligible else {
            return GlitchRealizedEvent(
                role: role,
                cycleIndex: cycleIndex,
                stepIndex: stepIndex,
                shouldDropOut: false,
                pitchDriftCents: 0,
                delayTimeVariation: 0,
                timingDriftMilliseconds: 0
            )
        }

        let roleIndex = role.realizationIndex
        let dropout = sample(
            seed: realization.dropoutSeed,
            roleIndex: roleIndex,
            cycleIndex: cycleIndex,
            stepIndex: stepIndex,
            parameter: .dropout
        ) < rolePlan.dropoutProbability
        let pitchSample = sample(
            seed: realization.variationSeed,
            roleIndex: roleIndex,
            cycleIndex: cycleIndex,
            stepIndex: stepIndex,
            parameter: .pitchDrift
        )
        let delaySample = sample(
            seed: realization.variationSeed,
            roleIndex: roleIndex,
            cycleIndex: cycleIndex,
            stepIndex: stepIndex,
            parameter: .delayTime
        )

        return GlitchRealizedEvent(
            role: role,
            cycleIndex: cycleIndex,
            stepIndex: stepIndex,
            shouldDropOut: dropout,
            pitchDriftCents: ((pitchSample * 2) - 1) * rolePlan.pitchDriftCents,
            delayTimeVariation: ((delaySample * 2) - 1) * rolePlan.delayTimeInstability,
            timingDriftMilliseconds: ((delaySample * 2) - 1) * rolePlan.timingDriftMilliseconds
        )
    }

    private static func bounded(_ value: Double, maximum: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maximum)
    }

    private func sample(
        seed: UInt64,
        roleIndex: UInt64,
        cycleIndex: Int,
        stepIndex: Int,
        parameter: GlitchRealizationParameter
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
}

private enum GlitchRealizationParameter: UInt64 {
    case dropout = 0
    case pitchDrift = 1
    case delayTime = 2
}

private extension GlitchRole {
    var realizationIndex: UInt64 {
        switch self {
        case .pad: return 0
        case .happening: return 1
        case .lead: return 2
        case .percussion: return 3
        case .timingAnchorKick: return 4
        }
    }
}
