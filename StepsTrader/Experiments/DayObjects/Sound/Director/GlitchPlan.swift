#if DEBUG || INTERNAL_BUILD
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

    static let stableKick = GlitchRolePlan(
        role: .timingAnchorKick,
        isTimingAnchor: true,
        isGlitchEligible: false,
        pitchDriftCents: 0,
        dropoutProbability: 0,
        delayTimeInstability: 0
    )
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
}

struct GlitchPlan: Equatable, Sendable {
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
                delayTimeInstability: 0
            ),
            GlitchRolePlan(
                role: .happening,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 0,
                dropoutProbability: 0,
                delayTimeInstability: 0
            ),
            GlitchRolePlan(
                role: .lead,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 0,
                dropoutProbability: 0,
                delayTimeInstability: 0
            ),
            GlitchRolePlan(
                role: .percussion,
                isTimingAnchor: false,
                isGlitchEligible: true,
                pitchDriftCents: 0,
                dropoutProbability: 0,
                delayTimeInstability: 0
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
            }
    }

    func role(for role: GlitchRole) -> GlitchRolePlan? {
        roles.first { $0.role == role }
    }

    func realizedEvent(
        for role: GlitchRole,
        cycleIndex: Int,
        stepIndex: Int
    ) -> GlitchRealizedEvent? {
        guard cycleIndex >= 0, (0..<16).contains(stepIndex), let rolePlan = self.role(for: role) else {
            return nil
        }
        guard rolePlan.isGlitchEligible else {
            return GlitchRealizedEvent(
                role: role,
                cycleIndex: cycleIndex,
                stepIndex: stepIndex,
                shouldDropOut: false,
                pitchDriftCents: 0,
                delayTimeVariation: 0
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
            delayTimeVariation: ((delaySample * 2) - 1) * rolePlan.delayTimeInstability
        )
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
#endif
