#if DEBUG || INTERNAL_BUILD
import Foundation

enum LayerMixPlanner {
    static func makePlan(happeningCount: Int) -> LayerMixPlan {
        let boundedCount = min(max(happeningCount, 0), 10)
        let compensatedCount = max(boundedCount, 1)
        let happeningTarget = -10.0
        let compensation = 10 * log10(Double(compensatedCount))

        return LayerMixPlan(
            rhythmTargetDecibels: -6,
            harmonyTargetDecibels: -9,
            happeningAggregateTargetDecibels: happeningTarget,
            happeningPerVoiceTargetDecibels: happeningTarget - compensation,
            happeningCount: boundedCount,
            leadTargetDecibels: -8,
            masterTargetDecibelsBeforeLimiter: -2,
            maximumHarmonyDuckingDecibels: 2.5
        )
    }
}
#endif
