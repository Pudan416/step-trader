#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsMixRole: String, Codable, CaseIterable, Sendable {
    case rhythm
    case bass
    case harmony
    case happenings
    case lead
}

enum DayObjectsMixIssue: String, Codable, CaseIterable, Sendable {
    case silence
    case integratedLoudness
    case truePeak
    case clipping
    case dcOffset
    case excessiveBrightness
    case excessiveTransientDensity
    case inaudibleStem
    case kickBassMasking
    case harmonyLeadMasking
    case happeningsLeadMasking
    case excessiveReverbTail
}

struct DayObjectsMixSuggestion: Codable, Equatable, Sendable {
    let role: DayObjectsMixRole
    let gainAdjustmentDB: Double
    let additionalDuckingDB: Double
    let cutoffMultiplier: Double
    let reverbSendAdjustment: Double

    init(
        role: DayObjectsMixRole,
        gainAdjustmentDB: Double,
        additionalDuckingDB: Double,
        cutoffMultiplier: Double,
        reverbSendAdjustment: Double
    ) {
        self.role = role
        self.gainAdjustmentDB = gainAdjustmentDB.clamped(to: -3 ... 0)
        self.additionalDuckingDB = additionalDuckingDB.clamped(to: 0 ... 4)
        self.cutoffMultiplier = cutoffMultiplier.clamped(to: 0.75 ... 1)
        self.reverbSendAdjustment = reverbSendAdjustment.clamped(to: -0.15 ... 0)
    }
}

struct DayObjectsMixQualityReport: Codable, Equatable, Sendable {
    let integratedLUFS: Double
    let truePeakDBTP: Double
    let maximumAbsoluteDCOffset: Double
    let crestFactorDB: Double
    let lowBandEnergyRatio: Double
    let midBandEnergyRatio: Double
    let highBandEnergyRatio: Double
    let layerAudibilityDB: [String: Double]
    let kickBassLowBandCorrelation: Double
    let clippedSampleRatio: Double
    let transientDensityPerSecond: Double
    let harmonyLeadMaskingScore: Double
    let happeningsLeadMaskingScore: Double
    let reverbTailEnergyRatio: Double
    let reverbTailEnergyRatioByRole: [String: Double]
    let issues: [DayObjectsMixIssue]
    let suggestions: [DayObjectsMixSuggestion]

    var passes: Bool { issues.isEmpty }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(isFinite ? self : range.lowerBound, range.lowerBound), range.upperBound)
    }
}
#endif
