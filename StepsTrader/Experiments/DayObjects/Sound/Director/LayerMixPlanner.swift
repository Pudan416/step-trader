#if DEBUG || INTERNAL_BUILD
import Foundation

enum LayerMixPlanner {
    static func makePlan(
        happeningCount: Int,
        soundWorld: DayObjectsSoundWorld? = nil,
        arrangement: DayObjectsArrangementProfile? = nil
    ) -> LayerMixPlan {
        let boundedCount = min(max(happeningCount, 0), 10)
        let happeningTarget = -3.3
        let audibleVoices = min(max(boundedCount, 1), 4)
        let countCompensationDecibels = -3 * log2(Double(audibleVoices))
        let masterTargetDecibelsBeforeLimiter: Double = switch soundWorld {
        case .feltAndWood, .livingField:
            -9
        case .metalAndCurrent, .electricDream:
            -10.5
        case nil:
            -6
        }

        return LayerMixPlan(
            rhythmTargetDecibels: arrangement?.world == .livingField ? -3 : 0,
            bassTargetDecibels: -4,
            harmonyTargetDecibels: 0,
            happeningAggregateTargetDecibels: happeningTarget,
            happeningPerVoiceTargetDecibels: happeningTarget + countCompensationDecibels,
            happeningCount: boundedCount,
            leadTargetDecibels: -3.1,
            masterTargetDecibelsBeforeLimiter: masterTargetDecibelsBeforeLimiter,
            maximumHarmonyDuckingDecibels: 2.5
        )
    }
}
#endif
