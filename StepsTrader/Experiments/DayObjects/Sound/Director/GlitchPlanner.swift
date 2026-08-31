#if DEBUG || INTERNAL_BUILD
enum GlitchPlanner {
    static func makePlan(
        input: NormalizedDayMusicInput,
        remixSeed: UInt64
    ) -> GlitchPlan {
        let progress = unitValue(input.glitchProgress)
        var random = StableMusicRandom(seed: remixSeed, domain: .effects)

        return GlitchPlan(
            progress: progress,
            roles: [
                rolePlan(role: .pad, maximumPitchDriftCents: 14, progress: progress),
                rolePlan(role: .happening, maximumPitchDriftCents: 10, progress: progress),
                rolePlan(role: .lead, maximumPitchDriftCents: 8, progress: progress),
                rolePlan(role: .percussion, maximumPitchDriftCents: 3, progress: progress),
                .stableKick,
            ],
            wowFlutterDepth: 0.18 * progress,
            stereoSeparationAddition: 0.22 * progress,
            realization: GlitchRealizationState(
                dropoutSeed: random.nextUInt64(),
                variationSeed: random.nextUInt64(),
                cycleKey: random.nextUInt64(),
                counterMapping: .roleCycleStepParameterV1
            )
        )
    }

    private static func rolePlan(
        role: GlitchRole,
        maximumPitchDriftCents: Double,
        progress: Double
    ) -> GlitchRolePlan {
        GlitchRolePlan(
            role: role,
            isTimingAnchor: false,
            isGlitchEligible: true,
            pitchDriftCents: maximumPitchDriftCents * progress,
            dropoutProbability: 0.06 * progress,
            delayTimeInstability: 0.08 * progress
        )
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
#endif
