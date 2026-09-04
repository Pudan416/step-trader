#if DEBUG || INTERNAL_BUILD
import Foundation

struct BassDuckCommand: Equatable, Sendable {
    let hostTimeSeconds: TimeInterval
    let maximumAttenuationDecibels: Double
    let attackSeconds: Double
    let holdSeconds: Double
    let releaseSeconds: Double
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
