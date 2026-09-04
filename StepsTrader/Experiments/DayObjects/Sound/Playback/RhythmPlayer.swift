#if DEBUG || INTERNAL_BUILD
import Foundation

struct RhythmPlaybackHit: Equatable, Sendable {
    let role: RhythmRole
    let drumVoice: DayObjectsDrumVoice
    let cycleIndex: Int
    let stepIndex: Int
    let velocity: Double
    let microtimingMilliseconds: Double
    let scheduledHostTimeSeconds: TimeInterval
    let roomSend: Double
    let pitchDriftCents: Double
    let stereoOffset: Double
    let delayTimeVariation: Double
    let shouldDropOut: Bool
    let isTimingAnchor: Bool
}

struct RhythmPlaybackFrame: Equatable, Sendable {
    let position: MusicalPosition
    let hits: [RhythmPlaybackHit]
    let harmonyDuckingDecibels: Double

    var anchorKickHostTimes: [TimeInterval] {
        hits.compactMap { $0.isTimingAnchor ? $0.scheduledHostTimeSeconds : nil }
    }
}

struct RhythmPlayerMetrics: Equatable, Sendable {
    let allocatedDrumPlayerCount: Int
    let processedSubdivisionCount: Int
    let renderedLogicalHitCount: Int
    let activeLogicalHitCount: Int
}

@MainActor
final class RhythmPlayer {
    private let drumBank: DayObjectsDrumBankProtocol
    private var processedSubdivisionCount = 0
    private var renderedLogicalHitCount = 0
    private var activeLogicalHitCount = 0
    private var mixGain = 1.0

    var metrics: RhythmPlayerMetrics {
        .init(
            allocatedDrumPlayerCount: drumBank.metrics.allocatedPlayerCount,
            processedSubdivisionCount: processedSubdivisionCount,
            renderedLogicalHitCount: renderedLogicalHitCount,
            activeLogicalHitCount: activeLogicalHitCount
        )
    }

    init(drumBank: DayObjectsDrumBankProtocol) {
        self.drumBank = drumBank
    }

    @discardableResult
    func render(
        _ transportEvent: DayObjectsTransportEvent,
        rhythmPlan: RhythmPlan,
        glitchPlan: GlitchPlan
    ) -> RhythmPlaybackFrame {
        guard transportEvent.kind == .subdivision else {
            return .init(
                position: transportEvent.position,
                hits: [],
                harmonyDuckingDecibels: ducking(for: rhythmPlan)
            )
        }

        processedSubdivisionCount += 1
        let cycleIndex = Int(transportEvent.position.bar)
        let stepIndex = transportEvent.position.subdivisionInBar
        let realized = rhythmPlan.realizedEvents(
            cycleIndex: cycleIndex,
            stepIndex: stepIndex
        )
        let hits = realized.compactMap { event -> RhythmPlaybackHit? in
            guard let voicePlan = rhythmPlan.voice(for: event.role) else { return nil }
            let glitch = !voicePlan.isTimingAnchor && glitchPlan.sanitizedProgress > 0
                ? glitchPlan.realizedEvent(
                    for: .percussion,
                    cycleIndex: cycleIndex,
                    stepIndex: stepIndex
                )
                : nil

            let textureTimingMilliseconds: Double
            let pitchDriftCents: Double
            let stereoOffset: Double
            if let glitch {
                textureTimingMilliseconds = glitch.timingDriftMilliseconds
                pitchDriftCents = glitch.pitchDriftCents
                let direction = pitchDriftCents == 0
                    ? (stepIndex.isMultiple(of: 2) ? -1.0 : 1.0)
                    : (pitchDriftCents < 0 ? -1.0 : 1.0)
                stereoOffset = direction * glitchPlan.sanitizedStereoSeparationAddition
            } else {
                textureTimingMilliseconds = 0
                pitchDriftCents = 0
                stereoOffset = 0
            }
            let boundedTiming = min(
                max(
                    event.microtimingMilliseconds + textureTimingMilliseconds,
                    -rhythmPlan.maximumMicrotimingMilliseconds
                ),
                rhythmPlan.maximumMicrotimingMilliseconds
            )
            let hit = RhythmPlaybackHit(
                role: event.role,
                drumVoice: event.drumVoice,
                cycleIndex: cycleIndex,
                stepIndex: stepIndex,
                velocity: event.velocity * mixGain,
                microtimingMilliseconds: voicePlan.isTimingAnchor ? 0 : boundedTiming,
                scheduledHostTimeSeconds: transportEvent.hostTimeSeconds
                    + ((voicePlan.isTimingAnchor ? 0 : boundedTiming) / 1_000),
                roomSend: voicePlan.roomSend,
                pitchDriftCents: pitchDriftCents,
                stereoOffset: stereoOffset,
                delayTimeVariation: 0,
                shouldDropOut: false,
                isTimingAnchor: voicePlan.isTimingAnchor
            )
            drumBank.schedule(.init(
                voice: hit.drumVoice,
                velocity: hit.velocity,
                scheduledHostTimeSeconds: hit.scheduledHostTimeSeconds,
                microtimingMilliseconds: hit.microtimingMilliseconds,
                roomSend: hit.roomSend,
                stereoOffset: hit.stereoOffset,
                pitchDriftCents: hit.pitchDriftCents
            ))
            return hit
        }
        renderedLogicalHitCount += hits.count
        activeLogicalHitCount = hits.count

        return .init(
            position: transportEvent.position,
            hits: hits,
            harmonyDuckingDecibels: ducking(for: rhythmPlan)
        )
    }

    func releaseAll() {
        drumBank.releaseAll()
        activeLogicalHitCount = 0
    }

    func applyMixTargetDecibels(_ decibels: Double) {
        mixGain = Self.linearGain(decibels: decibels)
    }

    private func ducking(for plan: RhythmPlan) -> Double {
        let highStepsAmount = smoothActivation(plan.stepsProgress, start: 0.75, end: 1)
        return min(max(plan.maximumHarmonyDuckingDecibels, 0), 2.5) * highStepsAmount
    }

    private static func linearGain(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return pow(10, min(max(decibels, -60), 0) / 20)
    }
}
#endif
