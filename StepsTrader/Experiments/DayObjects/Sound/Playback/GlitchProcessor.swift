#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsGlitchCommand: Equatable, Sendable {
    let role: GlitchRole
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

    var isBypassed: Bool {
        dryGain == 1
            && pitchDriftCents == 0
            && wowFlutterDepth == 0
            && stereoSeparationAddition == 0
            && delayTimeVariation == 0
            && saturationAmount == 0
            && timingDriftMilliseconds == 0
            && dropoutAttenuationDecibels == 0
            && dropoutReleaseSeconds == 0
    }
}

@MainActor
protocol DayObjectsGlitchBackend: AnyObject {
    func apply(_ command: DayObjectsGlitchCommand)
}

/// Converts the Director-owned Glitch plan into bounded, role-specific
/// playback commands. RhythmPlayer remains the sole percussion owner because
/// it alone has the hit and host-time identity needed to apply that texture.
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

    /// Invalid requests fail closed by emitting neutral state for the exact
    /// requested route. Only a sanitized command can leave this boundary.
    @discardableResult
    func applyRealizedEvent(
        plan: GlitchPlan,
        role: GlitchRole,
        cycleIndex: Int,
        stepIndex: Int
    ) -> DayObjectsGlitchCommand? {
        let preview = realizedEventPreview(
            plan: plan,
            role: role,
            cycleIndex: cycleIndex,
            stepIndex: stepIndex
        )
        commitRealizedEvent(preview.command)
        return preview.isRealized ? preview.command : nil
    }

    func previewRealizedEvent(
        plan: GlitchPlan,
        role: GlitchRole,
        cycleIndex: Int,
        stepIndex: Int
    ) -> DayObjectsGlitchCommand {
        realizedEventPreview(
            plan: plan,
            role: role,
            cycleIndex: cycleIndex,
            stepIndex: stepIndex
        ).command
    }

    private func realizedEventPreview(
        plan: GlitchPlan,
        role: GlitchRole,
        cycleIndex: Int,
        stepIndex: Int
    ) -> (command: DayObjectsGlitchCommand, isRealized: Bool) {
        guard role != .percussion, role != .timingAnchorKick else {
            return (.neutral(role: role), false)
        }
        guard plan.sanitizedProgress > 0,
              let rolePlan = plan.validatedRolePlan(for: role),
              !rolePlan.isTimingAnchor,
              rolePlan.isGlitchEligible,
              let event = plan.realizedEvent(
                for: role,
                cycleIndex: cycleIndex,
                stepIndex: stepIndex
              )
        else {
            return (.neutral(role: role), false)
        }

        let base = continuousCommand(for: role, plan: plan)
        let pitchDrift = signed(event.pitchDriftCents, maximum: rolePlan.pitchDriftCents)
        let delayVariation = signed(
            event.delayTimeVariation,
            maximum: rolePlan.delayTimeInstability
        )
        let shouldDropOut = role == .happening && event.shouldDropOut
        let dropoutDecibels = shouldDropOut ? -6.0 : 0
        let dropoutRelease = shouldDropOut ? 0.12 : 0

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
        case .percussion, .timingAnchorKick:
            return (.neutral(role: role), false)
        }
        return (command, true)
    }

    func commitRealizedEvent(_ command: DayObjectsGlitchCommand) {
        backend.apply(command)
    }

    private func continuousCommand(for role: GlitchRole, plan: GlitchPlan) -> DayObjectsGlitchCommand {
        guard role != .percussion,
              role != .timingAnchorKick,
              plan.sanitizedProgress > 0,
              let rolePlan = plan.validatedRolePlan(for: role),
              !rolePlan.isTimingAnchor,
              rolePlan.isGlitchEligible
        else { return .neutral(role: role) }

        switch role {
        case .pad:
            return .init(
                role: role,
                dryGain: 1,
                pitchDriftCents: rolePlan.pitchDriftCents,
                wowFlutterDepth: plan.sanitizedWowFlutterDepth,
                stereoSeparationAddition: plan.sanitizedStereoSeparationAddition,
                delayTimeVariation: rolePlan.delayTimeInstability,
                saturationAmount: 0,
                timingDriftMilliseconds: 0,
                dropoutAttenuationDecibels: 0,
                dropoutReleaseSeconds: 0,
                rampDurationSeconds: Self.rampDurationSeconds
            )
        case .happening:
            return .init(
                role: role,
                dryGain: 1,
                pitchDriftCents: rolePlan.pitchDriftCents,
                wowFlutterDepth: 0,
                stereoSeparationAddition: 0,
                delayTimeVariation: rolePlan.delayTimeInstability,
                saturationAmount: 0,
                timingDriftMilliseconds: 0,
                dropoutAttenuationDecibels: 0,
                dropoutReleaseSeconds: 0,
                rampDurationSeconds: Self.rampDurationSeconds
            )
        case .lead:
            return .init(
                role: role,
                dryGain: 1,
                pitchDriftCents: rolePlan.pitchDriftCents,
                wowFlutterDepth: 0,
                stereoSeparationAddition: 0,
                delayTimeVariation: 0,
                saturationAmount: rolePlan.saturationAmount,
                timingDriftMilliseconds: 0,
                dropoutAttenuationDecibels: 0,
                dropoutReleaseSeconds: 0,
                rampDurationSeconds: Self.rampDurationSeconds
            )
        case .percussion, .timingAnchorKick:
            return .neutral(role: role)
        }
    }

    private func signed(_ value: Double, maximum: Double) -> Double {
        guard value.isFinite, maximum.isFinite else { return 0 }
        return min(max(value, -maximum), maximum)
    }

    private static func linearGain(decibels: Double) -> Double {
        pow(10, decibels / 20)
    }
}

extension DayObjectsGlitchCommand {
    static func neutral(role: GlitchRole) -> Self {
        .init(
            role: role,
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
        dropoutAttenuationDecibels: Double? = nil,
        dropoutReleaseSeconds: TimeInterval? = nil
    ) -> Self {
        .init(
            role: role,
            dryGain: dryGain ?? self.dryGain,
            pitchDriftCents: pitchDriftCents ?? self.pitchDriftCents,
            wowFlutterDepth: wowFlutterDepth,
            stereoSeparationAddition: stereoSeparationAddition,
            delayTimeVariation: delayTimeVariation ?? self.delayTimeVariation,
            saturationAmount: saturationAmount,
            timingDriftMilliseconds: timingDriftMilliseconds,
            dropoutAttenuationDecibels: dropoutAttenuationDecibels ?? self.dropoutAttenuationDecibels,
            dropoutReleaseSeconds: dropoutReleaseSeconds ?? self.dropoutReleaseSeconds,
            rampDurationSeconds: rampDurationSeconds
        )
    }
}
#endif
