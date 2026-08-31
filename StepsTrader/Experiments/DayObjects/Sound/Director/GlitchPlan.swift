#if DEBUG || INTERNAL_BUILD
struct TimingAnchorGlitchPlan: Equatable, Sendable {
    let isTimingAnchor: Bool
    let pitchDriftCents: Double
    let dropoutProbability: Double
    let delayTimeInstability: Double

    static let stableKick = TimingAnchorGlitchPlan(
        isTimingAnchor: true,
        pitchDriftCents: 0,
        dropoutProbability: 0,
        delayTimeInstability: 0
    )
}

struct GlitchPlan: Equatable, Sendable {
    let progress: Double
    let padPitchDriftCents: Double
    let happeningPitchDriftCents: Double
    let leadPitchDriftCents: Double
    let wowFlutterDepth: Double
    let delayTimeInstability: Double
    let stereoSeparationAddition: Double
    let softDropoutProbability: Double
    let percussionPitchDriftCents: Double
    let timingAnchorKick: TimingAnchorGlitchPlan

    static let neutral = GlitchPlan(
        progress: 0,
        padPitchDriftCents: 0,
        happeningPitchDriftCents: 0,
        leadPitchDriftCents: 0,
        wowFlutterDepth: 0,
        delayTimeInstability: 0,
        stereoSeparationAddition: 0,
        softDropoutProbability: 0,
        percussionPitchDriftCents: 0,
        timingAnchorKick: .stableKick
    )

    var isNeutral: Bool { self == .neutral }
}
#endif
