#if DEBUG || INTERNAL_BUILD
struct LayerMixPlan: Equatable, Sendable {
    let rhythmTargetDecibels: Double
    let harmonyTargetDecibels: Double
    let happeningAggregateTargetDecibels: Double
    let happeningPerVoiceTargetDecibels: Double
    let happeningCount: Int
    let leadTargetDecibels: Double
    let masterTargetDecibelsBeforeLimiter: Double
    let maximumHarmonyDuckingDecibels: Double

    func harmonyTargetDecibels(applyingDucking duckingDecibels: Double) -> Double {
        guard duckingDecibels.isFinite else { return harmonyTargetDecibels }
        let boundedDucking = min(max(duckingDecibels, 0), maximumHarmonyDuckingDecibels)
        return harmonyTargetDecibels - boundedDucking
    }
}
#endif
