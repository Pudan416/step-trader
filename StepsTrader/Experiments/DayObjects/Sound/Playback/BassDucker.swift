#if DEBUG || INTERNAL_BUILD
import Foundation

struct BassDuckCommand: Equatable, Sendable {
    let hostTimeSeconds: TimeInterval
    let maximumAttenuationDecibels: Double
    let attackSeconds: Double
    let holdSeconds: Double
    let releaseSeconds: Double
}

enum BassDuckGainStage: Equatable, Sendable {
    case attack
    case hold
    case release
}

/// A single scheduled segment of the fixed bass duck envelope. These values
/// are deliberately value-only so a graph can retain just the latest three
/// records without allocating a live event history on the playback path.
struct BassDuckGainAutomation: Equatable, Sendable {
    let stage: BassDuckGainStage
    let targetLinearGain: Double
    let requestedStartHostTimeSeconds: TimeInterval
    let requestedEndHostTimeSeconds: TimeInterval
    let effectiveStartHostTimeSeconds: TimeInterval
    let effectiveEndHostTimeSeconds: TimeInterval
    let wasForcedImmediate: Bool
}

struct BassDuckGainMetrics: Equatable, Sendable {
    let isSupported: Bool
    let scheduledSegmentCount: Int
    let resetCount: Int
    let isAtUnity: Bool
    let lastAttack: BassDuckGainAutomation?
    let lastHold: BassDuckGainAutomation?
    let lastRelease: BassDuckGainAutomation?

    static let unsupported = Self(
        isSupported: false,
        scheduledSegmentCount: 0,
        resetCount: 0,
        isAtUnity: true,
        lastAttack: nil,
        lastHold: nil,
        lastRelease: nil
    )
}

final class BassDucker {
    private var lastKickHostTime: TimeInterval?

    func command(
        kickVelocity: Double,
        hostTime: TimeInterval,
        plan: BassDuckingPlan
    ) -> BassDuckCommand? {
        guard hostTime.isFinite, lastKickHostTime != hostTime else { return nil }
        lastKickHostTime = hostTime

        let boundedVelocity = min(max(kickVelocity.isFinite ? kickVelocity : 0, 0), 1)
        let cap = min(max(plan.maximumAttenuationDecibels.isFinite ? plan.maximumAttenuationDecibels : 0, 0), 5)
        return .init(
            hostTimeSeconds: hostTime,
            maximumAttenuationDecibels: cap * boundedVelocity,
            attackSeconds: Self.clamp(plan.attackSeconds, to: 0.003...0.008),
            holdSeconds: Self.clamp(plan.holdSeconds, to: 0.030...0.060),
            releaseSeconds: Self.clamp(plan.releaseSeconds, to: 0.120...0.220)
        )
    }

    func reset() {
        lastKickHostTime = nil
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value.isFinite ? value : range.lowerBound, range.lowerBound), range.upperBound)
    }
}
#endif
