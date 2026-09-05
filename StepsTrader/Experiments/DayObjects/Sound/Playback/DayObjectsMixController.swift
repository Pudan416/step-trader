#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsRoleBusSpatialParameters: Equatable, Sendable {
    let sendLevel: Double
    let decay: Double
    let secondarySendLevel: Double?
    let secondaryDecay: Double?

    init(
        sendLevel: Double,
        decay: Double,
        secondarySendLevel: Double? = nil,
        secondaryDecay: Double? = nil
    ) {
        self.sendLevel = sendLevel
        self.decay = decay
        self.secondarySendLevel = secondarySendLevel
        self.secondaryDecay = secondaryDecay
    }
}

struct DayObjectsFiveRoleBusSpatialParameters: Equatable, Sendable {
    let rhythm: DayObjectsRoleBusSpatialParameters
    let bass: DayObjectsRoleBusSpatialParameters
    let harmony: DayObjectsRoleBusSpatialParameters
    let happenings: DayObjectsRoleBusSpatialParameters
    let lead: DayObjectsRoleBusSpatialParameters

    init(
        rhythm: DayObjectsRoleBusSpatialParameters,
        bass: DayObjectsRoleBusSpatialParameters,
        harmony: DayObjectsRoleBusSpatialParameters,
        happenings: DayObjectsRoleBusSpatialParameters,
        lead: DayObjectsRoleBusSpatialParameters
    ) {
        self.rhythm = rhythm
        self.bass = bass
        self.harmony = harmony
        self.happenings = happenings
        self.lead = lead
    }

    init(repeating value: DayObjectsRoleBusSpatialParameters) {
        rhythm = value
        bass = value
        harmony = value
        happenings = value
        lead = value
    }

    static let dry = Self(repeating: .init(sendLevel: 0, decay: 0))
}

struct DayObjectsRoleBusMixParameters: Equatable, Sendable {
    let directTargetDecibels: Double
    let sendLevel: Double
    let decay: Double
    let secondarySendLevel: Double?
    let secondaryDecay: Double?

    init(
        directTargetDecibels: Double,
        sendLevel: Double,
        decay: Double,
        secondarySendLevel: Double? = nil,
        secondaryDecay: Double? = nil
    ) {
        self.directTargetDecibels = directTargetDecibels
        self.sendLevel = sendLevel
        self.decay = decay
        self.secondarySendLevel = secondarySendLevel
        self.secondaryDecay = secondaryDecay
    }
}

struct DayObjectsFiveRoleBusMixParameters: Equatable, Sendable {
    let rhythm: DayObjectsRoleBusMixParameters
    let bass: DayObjectsRoleBusMixParameters
    let harmony: DayObjectsRoleBusMixParameters
    let happenings: DayObjectsRoleBusMixParameters
    let lead: DayObjectsRoleBusMixParameters

    var all: [DayObjectsRoleBusMixParameters] {
        [rhythm, bass, harmony, happenings, lead]
    }

    func parameters(for role: DayObjectsRoleBus) -> DayObjectsRoleBusMixParameters {
        return switch role {
        case .rhythm: rhythm
        case .bass: bass
        case .harmony: harmony
        case .happenings: happenings
        case .lead: lead
        }
    }
}

struct DayObjectsMixState: Equatable, Sendable {
    let buses: DayObjectsFiveRoleBusMixParameters
    let harmonyPerVoiceTargetDecibels: Double
    let happeningPerVoiceTargetDecibels: Double
    let masterTargetDecibelsBeforeLimiter: Double
    let harmonyDuckingDecibels: Double
    let rampDurationSeconds: TimeInterval
    let leadVoiceTargetDecibels: Double

    init(
        buses: DayObjectsFiveRoleBusMixParameters,
        harmonyPerVoiceTargetDecibels: Double,
        happeningPerVoiceTargetDecibels: Double,
        masterTargetDecibelsBeforeLimiter: Double,
        harmonyDuckingDecibels: Double,
        rampDurationSeconds: TimeInterval,
        leadVoiceTargetDecibels: Double? = nil
    ) {
        self.buses = buses
        self.harmonyPerVoiceTargetDecibels = harmonyPerVoiceTargetDecibels
        self.happeningPerVoiceTargetDecibels = happeningPerVoiceTargetDecibels
        self.masterTargetDecibelsBeforeLimiter = masterTargetDecibelsBeforeLimiter
        self.harmonyDuckingDecibels = harmonyDuckingDecibels
        self.rampDurationSeconds = rampDurationSeconds
        self.leadVoiceTargetDecibels = leadVoiceTargetDecibels ?? buses.lead.directTargetDecibels
    }

    var rhythmTargetDecibels: Double { buses.rhythm.directTargetDecibels }
    var bassTargetDecibels: Double { buses.bass.directTargetDecibels }
    var harmonyTargetDecibels: Double { buses.harmony.directTargetDecibels }
    var happeningAggregateTargetDecibels: Double { buses.happenings.directTargetDecibels }
    var leadTargetDecibels: Double { leadVoiceTargetDecibels }
}

struct DayObjectsPlanAwareGainCalibration: Equatable, Sendable {
    let rhythmAdjustmentDecibels: Double
    let bassAdjustmentDecibels: Double
    let harmonyAdjustmentDecibels: Double

    static let neutral = Self(
        rhythmAdjustmentDecibels: 0,
        bassAdjustmentDecibels: 0,
        harmonyAdjustmentDecibels: 0
    )

    static func make(
        grooveMode: GrooveMode,
        stepsActivityDensity rawDensity: Double
    ) -> Self {
        let density = rawDensity.isFinite ? min(max(rawDensity, 0), 1) : 0
        let smoothDensity = density * density * (3 - (2 * density))
        let rhythm: Double = switch grooveMode {
        case .percussion:
            0
        case .bassPulse:
            -0.35 - (0.20 * smoothDensity)
        case .bassArp:
            -1
        case .bassBed:
            -0.30 - (0.20 * smoothDensity)
        }
        let bass = grooveMode == .bassArp ? -0.5 : 0
        let harmony = grooveMode == .bassArp ? -0.5 : 0
        return Self(
            rhythmAdjustmentDecibels: min(max(rhythm, -1), 0),
            bassAdjustmentDecibels: bass,
            harmonyAdjustmentDecibels: harmony
        )
    }
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
    private static let maximumMasterDecibels = -6.0
    private static let maximumHarmonyDuckingDecibels = 2.5

    private let backend: DayObjectsMixBackend

    init(backend: DayObjectsMixBackend) {
        self.backend = backend
    }

    func apply(
        _ plan: LayerMixPlan,
        activeChordVoiceCount: Int,
        harmonyDuckingDecibels requestedDucking: Double,
        spatial: DayObjectsFiveRoleBusSpatialParameters,
        calibration: DayObjectsPlanAwareGainCalibration = .neutral,
        rampDurationSeconds: TimeInterval
    ) {
        let rhythmAdjustment = adjustment(
            calibration.rhythmAdjustmentDecibels,
            range: -1 ... 0
        )
        let bassAdjustment = adjustment(
            calibration.bassAdjustmentDecibels,
            range: -1 ... 0
        )
        let harmonyAdjustment = adjustment(
            calibration.harmonyAdjustmentDecibels,
            range: -1 ... 0
        )
        let rhythm = adjustedDecibels(
            plan.rhythmTargetDecibels,
            by: rhythmAdjustment
        )
        let bass = adjustedDecibels(
            plan.bassTargetDecibels,
            by: bassAdjustment
        )
        let baseHarmony = adjustedDecibels(
            plan.harmonyTargetDecibels,
            by: harmonyAdjustment
        )
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
            buses: .init(
                rhythm: bus(
                    directTargetDecibels: rhythm,
                    spatial: spatial.rhythm,
                    sendGainDecibels: rhythmAdjustment
                ),
                bass: bus(
                    directTargetDecibels: bass,
                    spatial: spatial.bass,
                    sendGainDecibels: bassAdjustment
                ),
                harmony: bus(
                    directTargetDecibels: harmony,
                    spatial: spatial.harmony,
                    sendGainDecibels: harmonyAdjustment
                ),
                happenings: bus(directTargetDecibels: happeningAggregate, spatial: spatial.happenings),
                lead: bus(
                    directTargetDecibels: LeadPlayer.busTargetDecibels(for: plan.leadTargetDecibels),
                    spatial: spatial.lead
                )
            ),
            harmonyPerVoiceTargetDecibels: harmonyPerVoice,
            happeningPerVoiceTargetDecibels: happeningPerVoice,
            masterTargetDecibelsBeforeLimiter: min(
                decibels(plan.masterTargetDecibelsBeforeLimiter),
                Self.maximumMasterDecibels
            ),
            harmonyDuckingDecibels: ducking,
            rampDurationSeconds: duration(rampDurationSeconds),
            leadVoiceTargetDecibels: decibels(plan.leadTargetDecibels)
        ))
    }

    private func bus(
        directTargetDecibels: Double,
        spatial: DayObjectsRoleBusSpatialParameters,
        sendGainDecibels: Double = 0
    ) -> DayObjectsRoleBusMixParameters {
        let sendGain = pow(10, sendGainDecibels / 20)
        return .init(
            directTargetDecibels: directTargetDecibels,
            sendLevel: feedback(
                spatial.sendLevel * sendGain,
                maximum: DayObjectsAudioParameters.maximumReverbFeedback
            ),
            decay: feedback(
                spatial.decay,
                maximum: DayObjectsAudioParameters.maximumReverbFeedback
            ),
            secondarySendLevel: spatial.secondarySendLevel.map {
                feedback($0 * sendGain, maximum: DayObjectsAudioParameters.maximumDelayFeedback)
            },
            secondaryDecay: spatial.secondaryDecay.map {
                feedback($0, maximum: DayObjectsAudioParameters.maximumDelayFeedback)
            }
        )
    }

    private func decibels(_ value: Double) -> Double {
        guard value.isFinite else { return Self.minimumDecibels }
        return min(max(value, Self.minimumDecibels), Self.maximumLayerDecibels)
    }

    private func adjustedDecibels(_ value: Double, by adjustment: Double) -> Double {
        let base = decibels(value)
        guard base > Self.minimumDecibels else { return Self.minimumDecibels }
        return decibels(base + adjustment)
    }

    private func adjustment(
        _ value: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
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
