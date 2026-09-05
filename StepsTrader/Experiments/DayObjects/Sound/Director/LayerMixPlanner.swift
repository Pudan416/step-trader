#if DEBUG || INTERNAL_BUILD
import Foundation

enum LayerMixPlanner {
    static func makePlan(happeningCount: Int) -> LayerMixPlan {
        let boundedCount = min(max(happeningCount, 0), 10)
        let happeningTarget = -3.3
        let audibleVoices = min(max(boundedCount, 1), 4)
        let countCompensationDecibels = -3 * log2(Double(audibleVoices))

        return LayerMixPlan(
            rhythmTargetDecibels: 0,
            bassTargetDecibels: -4,
            harmonyTargetDecibels: 0,
            happeningAggregateTargetDecibels: happeningTarget,
            happeningPerVoiceTargetDecibels: happeningTarget + countCompensationDecibels,
            happeningCount: boundedCount,
            leadTargetDecibels: -3.1,
            masterTargetDecibelsBeforeLimiter: -6,
            maximumHarmonyDuckingDecibels: 2.5
        )
    }
}
#endif
