#if DEBUG || INTERNAL_BUILD

enum LayerMixPlanner {
    static func makePlan(happeningCount: Int) -> LayerMixPlan {
        let boundedCount = min(max(happeningCount, 0), 10)
        let happeningTarget = -2.0

        return LayerMixPlan(
            rhythmTargetDecibels: -6,
            harmonyTargetDecibels: -9,
            happeningAggregateTargetDecibels: happeningTarget,
            happeningPerVoiceTargetDecibels: happeningTarget,
            happeningCount: boundedCount,
            leadTargetDecibels: -12,
            masterTargetDecibelsBeforeLimiter: -2,
            maximumHarmonyDuckingDecibels: 2.5
        )
    }
}
#endif
