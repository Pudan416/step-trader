#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsGlitchCommand: Equatable, Sendable {
    let role: GlitchRole
    let isBypassed: Bool
    let dryGain: Double
    let pitchDriftCents: Double
    let wowFlutterDepth: Double
    let stereoSeparationAddition: Double
    let delayTimeVariation: Double
    let saturationAmount: Double
    let timingDriftMilliseconds: Double
    let dropoutAttenuationDecibels: Double
    let dropoutReleaseSeconds: TimeInterval
    let rampDurationSeconds: TimeInterval
}

@MainActor
protocol DayObjectsGlitchBackend: AnyObject {
    func apply(_ command: DayObjectsGlitchCommand)
}

/// Converts the Director-owned Glitch plan into bounded, role-specific
/// playback commands. It owns no clock, random generator, task, or audio node.
@MainActor
final class GlitchProcessor {
    nonisolated static let rampDurationSeconds: TimeInterval = 0.25

    private let backend: DayObjectsGlitchBackend

    init(backend: DayObjectsGlitchBackend) {
        self.backend = backend
    }

    func apply(_ plan: GlitchPlan) {
        for role in GlitchRole.allCases {
            backend.apply(continuousCommand(for: role, plan: plan))
        }
    }

    /// Applies only the Director's counter-based event realization. The
    /// processor never samples an additional source of randomness.
    @discardableResult
    func applyRealizedEvent(
        plan: GlitchPlan,
        role: GlitchRole,
        cycleIndex: Int,
        stepIndex: Int
    ) -> GlitchRealizedEvent? {
        guard let event = plan.realizedEvent(
            for: role,
            cycleIndex: cycleIndex,
            stepIndex: stepIndex
        ) else { return nil }

        if role == .timingAnchorKick || unit(plan.progress) == 0 {
            backend.apply(.neutral(role: role))
            return event
        }

        let base = continuousCommand(for: role, plan: plan)
        let pitchDrift = finite(event.pitchDriftCents)
        let delayVariation = finite(event.delayTimeVariation)
        let dropoutDecibels = role == .happening && event.shouldDropOut ? -6.0 : 0
        let dropoutRelease = role == .happening && event.shouldDropOut ? 0.12 : 0

        let command: DayObjectsGlitchCommand
        switch role {
        case .pad:
            command = base.replacing(
                pitchDriftCents: pitchDrift,
                delayTimeVariation: delayVariation
            )
        case .happening:
            command = base.replacing(
                dryGain: Self.linearGain(decibels: dropoutDecibels),
                pitchDriftCents: pitchDrift,
                delayTimeVariation: delayVariation,
                dropoutAttenuationDecibels: dropoutDecibels,
                dropoutReleaseSeconds: dropoutRelease
            )
        case .lead:
            command = base.replacing(pitchDriftCents: pitchDrift)
        case .percussion:
            command = base.replacing(
                pitchDriftCents: min(max(pitchDrift, -3), 3),
                timingDriftMilliseconds: delayVariation * 4
            )
        case .timingAnchorKick:
            command = .neutral(role: role)
        }
        backend.apply(command.withBypassDerivedFromValues())
        return event
    }

    private func continuousCommand(for role: GlitchRole, plan: GlitchPlan) -> DayObjectsGlitchCommand {
        guard role != .timingAnchorKick,
              unit(plan.progress) > 0,
              let rolePlan = plan.role(for: role),
              rolePlan.isGlitchEligible
        else { return .neutral(role: role) }

        let progress = unit(plan.progress)
        let plannedPitch = nonnegative(rolePlan.pitchDriftCents)
        let plannedDelay = nonnegative(rolePlan.delayTimeInstability)
        let stereo = nonnegative(plan.stereoSeparationAddition)
        let wowFlutter = nonnegative(plan.wowFlutterDepth)

        let command: DayObjectsGlitchCommand
        switch role {
        case .pad:
            command = .init(
                role: role,
                isBypassed: false,
                dryGain: 1,
                pitchDriftCents: plannedPitch,
                wowFlutterDepth: wowFlutter,
                stereoSeparationAddition: stereo,
                delayTimeVariation: plannedDelay,
                saturationAmount: 0,
                timingDriftMilliseconds: 0,
                dropoutAttenuationDecibels: 0,
                dropoutReleaseSeconds: 0,
                rampDurationSeconds: Self.rampDurationSeconds
            )
        case .happening:
            command = .init(
                role: role,
                isBypassed: false,
                dryGain: 1,
                pitchDriftCents: plannedPitch,
                wowFlutterDepth: 0,
                stereoSeparationAddition: 0,
                delayTimeVariation: plannedDelay,
                saturationAmount: 0,
                timingDriftMilliseconds: 0,
                dropoutAttenuationDecibels: 0,
                dropoutReleaseSeconds: 0,
                rampDurationSeconds: Self.rampDurationSeconds
            )
        case .lead:
            command = .init(
                role: role,
                isBypassed: false,
                dryGain: 1,
                pitchDriftCents: plannedPitch,
                wowFlutterDepth: 0,
                stereoSeparationAddition: 0,
                delayTimeVariation: 0,
                saturationAmount: progress,
                timingDriftMilliseconds: 0,
                dropoutAttenuationDecibels: 0,
                dropoutReleaseSeconds: 0,
                rampDurationSeconds: Self.rampDurationSeconds
            )
        case .percussion:
            command = .init(
                role: role,
                isBypassed: false,
                dryGain: 1,
                pitchDriftCents: min(plannedPitch, 3),
                wowFlutterDepth: 0,
                stereoSeparationAddition: stereo,
                delayTimeVariation: 0,
                saturationAmount: 0,
                timingDriftMilliseconds: plannedDelay * 4,
                dropoutAttenuationDecibels: 0,
                dropoutReleaseSeconds: 0,
                rampDurationSeconds: Self.rampDurationSeconds
            )
        case .timingAnchorKick:
            command = .neutral(role: role)
        }
        return command.withBypassDerivedFromValues()
    }

    private func unit(_ value: Double) -> Double {
        min(max(finite(value), 0), 1)
    }

    private func nonnegative(_ value: Double) -> Double {
        max(finite(value), 0)
    }

    private func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func linearGain(decibels: Double) -> Double {
        pow(10, decibels / 20)
    }
}

private extension DayObjectsGlitchCommand {
    static func neutral(role: GlitchRole) -> Self {
        .init(
            role: role,
            isBypassed: true,
            dryGain: 1,
            pitchDriftCents: 0,
            wowFlutterDepth: 0,
            stereoSeparationAddition: 0,
            delayTimeVariation: 0,
            saturationAmount: 0,
            timingDriftMilliseconds: 0,
            dropoutAttenuationDecibels: 0,
            dropoutReleaseSeconds: 0,
            rampDurationSeconds: GlitchProcessor.rampDurationSeconds
        )
    }

    func replacing(
        dryGain: Double? = nil,
        pitchDriftCents: Double? = nil,
        delayTimeVariation: Double? = nil,
        timingDriftMilliseconds: Double? = nil,
        dropoutAttenuationDecibels: Double? = nil,
        dropoutReleaseSeconds: TimeInterval? = nil
    ) -> Self {
        .init(
            role: role,
            isBypassed: isBypassed,
            dryGain: dryGain ?? self.dryGain,
            pitchDriftCents: pitchDriftCents ?? self.pitchDriftCents,
            wowFlutterDepth: wowFlutterDepth,
            stereoSeparationAddition: stereoSeparationAddition,
            delayTimeVariation: delayTimeVariation ?? self.delayTimeVariation,
            saturationAmount: saturationAmount,
            timingDriftMilliseconds: timingDriftMilliseconds ?? self.timingDriftMilliseconds,
            dropoutAttenuationDecibels: dropoutAttenuationDecibels ?? self.dropoutAttenuationDecibels,
            dropoutReleaseSeconds: dropoutReleaseSeconds ?? self.dropoutReleaseSeconds,
            rampDurationSeconds: rampDurationSeconds
        )
    }

    func withBypassDerivedFromValues() -> Self {
        let hasEffect = pitchDriftCents != 0
            || wowFlutterDepth != 0
            || stereoSeparationAddition != 0
            || delayTimeVariation != 0
            || saturationAmount != 0
            || timingDriftMilliseconds != 0
            || dropoutAttenuationDecibels != 0
        return .init(
            role: role,
            isBypassed: !hasEffect,
            dryGain: dryGain,
            pitchDriftCents: pitchDriftCents,
            wowFlutterDepth: wowFlutterDepth,
            stereoSeparationAddition: stereoSeparationAddition,
            delayTimeVariation: delayTimeVariation,
            saturationAmount: saturationAmount,
            timingDriftMilliseconds: timingDriftMilliseconds,
            dropoutAttenuationDecibels: dropoutAttenuationDecibels,
            dropoutReleaseSeconds: dropoutReleaseSeconds,
            rampDurationSeconds: rampDurationSeconds
        )
    }
}
#endif
