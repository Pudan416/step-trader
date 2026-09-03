#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsMixState: Equatable, Sendable {
    let rhythmTargetDecibels: Double
    let harmonyTargetDecibels: Double
    let harmonyPerVoiceTargetDecibels: Double
    let happeningAggregateTargetDecibels: Double
    let happeningPerVoiceTargetDecibels: Double
    let leadTargetDecibels: Double
    let masterTargetDecibelsBeforeLimiter: Double
    let harmonyDuckingDecibels: Double
    let delayFeedback: Double
    let reverbFeedback: Double
    let rampDurationSeconds: TimeInterval
}

@MainActor
protocol DayObjectsMixBackend: AnyObject {
    func apply(_ state: DayObjectsMixState)
}

/// Sanitizes one Director-owned LayerMixPlan into a single typed backend
/// update. Continuous calls do not allocate nodes or create scheduling work.
@MainActor
final class DayObjectsMixController {
    private static let minimumDecibels = -60.0
    private static let maximumLayerDecibels = 0.0
    private static let maximumMasterDecibels = -2.0
    private static let maximumHarmonyDuckingDecibels = 2.5

    private let backend: DayObjectsMixBackend

    init(backend: DayObjectsMixBackend) {
        self.backend = backend
    }

    func apply(
        _ plan: LayerMixPlan,
        activeChordVoiceCount: Int,
        harmonyDuckingDecibels requestedDucking: Double,
        delayFeedback: Double,
        reverbFeedback: Double,
        rampDurationSeconds: TimeInterval
    ) {
        let rhythm = decibels(plan.rhythmTargetDecibels)
        let baseHarmony = decibels(plan.harmonyTargetDecibels)
        let duckingMaximum = min(
            nonnegative(plan.maximumHarmonyDuckingDecibels),
            Self.maximumHarmonyDuckingDecibels
        )
        let ducking = min(nonnegative(requestedDucking), duckingMaximum)
        let harmony = max(baseHarmony - ducking, Self.minimumDecibels)
        // HarmonyPlayer already divides a role's gain across its active voices.
        // Applying another power correction here made the complete chord much
        // quieter than the published harmony target.
        _ = activeChordVoiceCount
        let harmonyPerVoice = harmony

        let happeningAggregate = decibels(plan.happeningAggregateTargetDecibels)
        let publishedPerVoice = decibels(plan.happeningPerVoiceTargetDecibels)
        let happeningPerVoice = max(
            min(publishedPerVoice, happeningAggregate),
            Self.minimumDecibels
        )

        backend.apply(.init(
            rhythmTargetDecibels: rhythm,
            harmonyTargetDecibels: harmony,
            harmonyPerVoiceTargetDecibels: harmonyPerVoice,
            happeningAggregateTargetDecibels: happeningAggregate,
            happeningPerVoiceTargetDecibels: happeningPerVoice,
            leadTargetDecibels: decibels(plan.leadTargetDecibels),
            masterTargetDecibelsBeforeLimiter: min(
                decibels(plan.masterTargetDecibelsBeforeLimiter),
                Self.maximumMasterDecibels
            ),
            harmonyDuckingDecibels: ducking,
            delayFeedback: feedback(
                delayFeedback,
                maximum: DayObjectsAudioParameters.maximumDelayFeedback
            ),
            reverbFeedback: feedback(
                reverbFeedback,
                maximum: DayObjectsAudioParameters.maximumReverbFeedback
            ),
            rampDurationSeconds: duration(rampDurationSeconds)
        ))
    }

    private func decibels(_ value: Double) -> Double {
        guard value.isFinite else { return Self.minimumDecibels }
        return min(max(value, Self.minimumDecibels), Self.maximumLayerDecibels)
    }

    private func nonnegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(value, 0)
    }

    private func feedback(_ value: Double, maximum: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maximum)
    }

    private func duration(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0.25 }
        return min(max(value, 0), 2)
    }
}
#endif
