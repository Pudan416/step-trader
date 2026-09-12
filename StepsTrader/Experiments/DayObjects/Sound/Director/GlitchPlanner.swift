enum GlitchPlanner {
    static func makePlan(
        input: NormalizedDayMusicInput,
        remixSeed: UInt64
    ) -> GlitchPlan {
        let progress = unitValue(input.glitchProgress)
        var random = StableMusicRandom(seed: remixSeed, domain: .effects)

        return GlitchPlan(
            progress: progress,
            roles: GlitchRole.allCases.map { $0.safeLimits.scaled(by: progress) },
            wowFlutterDepth: GlitchPlan.maximumWowFlutterDepth * progress,
            stereoSeparationAddition: GlitchPlan.maximumStereoSeparationAddition * progress,
            realization: GlitchRealizationState(
                dropoutSeed: random.nextUInt64(),
                variationSeed: random.nextUInt64(),
                cycleKey: random.nextUInt64(),
                counterMapping: .roleCycleStepParameterV1
            )
        )
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
