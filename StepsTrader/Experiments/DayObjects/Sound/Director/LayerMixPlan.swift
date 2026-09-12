struct DayObjectsWorldGroupCalibration: Equatable, Sendable {
    static let makeupBounds = 0.0 ... 10.5
    static let reverbScaleBounds = 0.20 ... 1.0
    static let neutral = Self()
    let masterMakeupDB: Double
    let reverbSendScale: Double

    init(masterMakeupDB: Double = 0, reverbSendScale: Double = 1) {
        self.masterMakeupDB = masterMakeupDB.isFinite ? min(max(masterMakeupDB, 0), 10.5) : 0
        self.reverbSendScale = reverbSendScale.isFinite ? min(max(reverbSendScale, 0.20), 1) : 1
    }
}

struct LayerMixPlan: Equatable, Sendable {
    let rhythmTargetDecibels: Double
    let bassTargetDecibels: Double
    let harmonyTargetDecibels: Double
    let happeningAggregateTargetDecibels: Double
    let happeningPerVoiceTargetDecibels: Double
    let happeningCount: Int
    let leadTargetDecibels: Double
    let masterTargetDecibelsBeforeLimiter: Double
    let maximumHarmonyDuckingDecibels: Double
    var worldGroupCalibration: DayObjectsWorldGroupCalibration? = nil

    func harmonyTargetDecibels(applyingDucking duckingDecibels: Double) -> Double {
        guard duckingDecibels.isFinite else { return harmonyTargetDecibels }
        let boundedDucking = min(max(duckingDecibels, 0), maximumHarmonyDuckingDecibels)
        return harmonyTargetDecibels - boundedDucking
    }
}
