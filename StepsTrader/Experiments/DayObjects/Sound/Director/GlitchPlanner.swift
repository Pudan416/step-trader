#if DEBUG || INTERNAL_BUILD
enum GlitchPlanner {
    static func makePlan(input: NormalizedDayMusicInput) -> GlitchPlan {
        let progress = unitValue(input.glitchProgress)
        guard progress > 0 else { return .neutral }

        return GlitchPlan(
            progress: progress,
            padPitchDriftCents: 14 * progress,
            happeningPitchDriftCents: 10 * progress,
            leadPitchDriftCents: 8 * progress,
            wowFlutterDepth: 0.18 * progress,
            delayTimeInstability: 0.08 * progress,
            stereoSeparationAddition: 0.22 * progress,
            softDropoutProbability: 0.06 * progress,
            percussionPitchDriftCents: 3 * progress,
            timingAnchorKick: .stableKick
        )
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
#endif
