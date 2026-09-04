#if DEBUG || INTERNAL_BUILD
import Foundation

enum LayerMixPlanner {
    static func makePlan(happeningCount: Int) -> LayerMixPlan {
        let boundedCount = min(max(happeningCount, 0), 10)
        let happeningTarget = -8.0
        let audibleVoices = min(max(boundedCount, 1), 4)
        let countCompensationDecibels = -3 * log2(Double(audibleVoices))

        return LayerMixPlan(
            rhythmTargetDecibels: -10,
            bassTargetDecibels: -12,
            harmonyTargetDecibels: -10,
            happeningAggregateTargetDecibels: happeningTarget,
            happeningPerVoiceTargetDecibels: happeningTarget + countCompensationDecibels,
            happeningCount: boundedCount,
            leadTargetDecibels: -9,
            masterTargetDecibelsBeforeLimiter: -6,
            maximumHarmonyDuckingDecibels: 2.5
        )
    }
}
#endif
