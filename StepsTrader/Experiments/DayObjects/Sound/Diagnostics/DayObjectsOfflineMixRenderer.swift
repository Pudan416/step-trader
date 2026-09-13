import AVFAudio
import Foundation

enum DayObjectsOfflineMixRendererError: Error, Equatable, Sendable {
    case invalidDuration
    case invalidEventEnd
    case unsupportedSampleRate
    case unableToAllocateBuffer
    case renderFailed
    case transportStalled
    case stressAuditionFailed(DayObjectsOfflineStressActivityComponent)
}

enum DayObjectsOfflineLeadGestureProfile: Equatable, Sendable {
    case none
    case slow
    case fast
    case held
}

enum DayObjectsOfflineStressProfile: Equatable, Sendable {
    case none
    case fourHappeningTailsWithKickBassChordAndHeldLead
}

enum DayObjectsOfflineStressActivityComponent: String, Codable, Hashable, Sendable {
    case kickSoft = "kick-soft"
    case bassAttack = "bass-attack"
    case chordTransition = "chord-transition"
    case heldLead = "held-lead"
    case happeningTail = "happening-tail"
}

struct DayObjectsOfflineStressActivity: Codable, Equatable, Sendable {
    let component: DayObjectsOfflineStressActivityComponent
    let hostTimeSeconds: TimeInterval
    let identifier: String
}

struct DayObjectsOfflineHarmonyTransitionEvidence: Codable, Equatable, Sendable {
    let role: String
    let chordIndex: Int
    let startSubdivision: Int64
    let startHostTimeSeconds: TimeInterval
    let endSubdivision: Int64
    let oldVoiceCount: Int
    let newVoiceCount: Int
    let maximumAudibleProgress: Double
    let maximumNewChordExpression: Double
    let firstAudibleProgressSubdivision: Int64?
    let firstAudibleProgressHostTimeSeconds: TimeInterval?
}

struct DayObjectsOfflineMixDiagnostics: Equatable, Sendable {
    let averageRoleRMSDBFS: [DayObjectsRoleBus: Double]
    let maximumRolePeakDBFS: [DayObjectsRoleBus: Double]
    let maximumRoleActiveVoiceCount: [DayObjectsRoleBus: Int]
    /// Offline gate estimate derived from the pre-limiter peak excursion.
    /// This is not a direct observation of the limiter's gain-reduction meter.
    let maximumEstimatedLimiterReductionDB: Double
    let stressActivities: [DayObjectsOfflineStressActivity]
    let stressTransportSubdivision: Int64?
    let transportSubdivisionsWereMonotonic: Bool
    let harmonyTransition: DayObjectsOfflineHarmonyTransitionEvidence?
    let scheduledBassReleaseHostTimeSeconds: TimeInterval?
    let actualBassReleaseHostTimeSeconds: TimeInterval?
    let bassActiveVoiceCountAfterRelease: Int?
    let renderedFrameCount: Int
}

/// Debug-only deterministic capture of the shipping Day Objects player and
/// persistent five-bus master graph. The renderer owns one bank and never
/// activates the live audio-session path.
@MainActor
final class DayObjectsOfflineMixRenderer {
    static let maximumFrameCount: AVAudioFrameCount = 4_096

    private let bundle: Bundle
    private let auditionMode: DayObjectsAuditionMode
    private let leadGestureProfile: DayObjectsOfflineLeadGestureProfile
    private let stressProfile: DayObjectsOfflineStressProfile
    private let offlineBeginCheckpoint: () throws -> Void
    private let contextRetryLimit: Int

    private(set) var lastDiagnostics: DayObjectsOfflineMixDiagnostics?
    private(set) var lastEventEndFrame: Int?

    init(
        bundle: Bundle = .main,
        auditionMode: DayObjectsAuditionMode = .fullComposition,
        leadGestureProfile: DayObjectsOfflineLeadGestureProfile = .none,
        stressProfile: DayObjectsOfflineStressProfile = .none,
        contextRetryLimit: Int = 8,
        offlineBeginCheckpoint: @escaping () throws -> Void = {}
    ) {
        self.bundle = bundle
        self.auditionMode = auditionMode
        self.leadGestureProfile = leadGestureProfile
        self.stressProfile = stressProfile
        self.contextRetryLimit = max(contextRetryLimit, 0)
        self.offlineBeginCheckpoint = offlineBeginCheckpoint
    }

    func render(
        plan: DayMusicPlan,
        durationSeconds: Double,
        sampleRate: Double,
        eventEndSeconds: Double? = nil
    ) async throws -> AVAudioPCMBuffer {
        guard durationSeconds.isFinite, (1...60).contains(durationSeconds) else {
            throw DayObjectsOfflineMixRendererError.invalidDuration
        }
        guard sampleRate.isFinite, (8_000...384_000).contains(sampleRate) else {
            throw DayObjectsOfflineMixRendererError.unsupportedSampleRate
        }
        if let eventEndSeconds,
           !eventEndSeconds.isFinite || eventEndSeconds <= 0 || eventEndSeconds >= durationSeconds {
            throw DayObjectsOfflineMixRendererError.invalidEventEnd
        }
        let eventEndFrame = eventEndSeconds.map { Int(($0 * sampleRate).rounded()) }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw DayObjectsOfflineMixRendererError.unsupportedSampleRate
        }

        let totalFrameCount = Int((durationSeconds * sampleRate).rounded())
        guard totalFrameCount > 0,
              totalFrameCount <= Int(AVAudioFrameCount.max),
              let output = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(totalFrameCount)
              ),
              let scratch = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: Self.maximumFrameCount
              )
        else {
            throw DayObjectsOfflineMixRendererError.unableToAllocateBuffer
        }

        lastDiagnostics = nil
        lastEventEndFrame = nil
        let initialHostTime = 1.0
        let clock = DayObjectsOfflineTransportClock(now: initialHostTime)
        let bank = DayObjectsInstrumentBank(
            bundle: bundle,
            audioHostTimeProvider: { clock.now() }
        )
        let playbackBank = PlaybackWorldBank(instrumentBank: bank)
        let world = DayObjectsLivePlaybackRuntime.WorldState(bank: playbackBank)
        let stressCoordinator = DayObjectsOfflineStressCoordinator(
            profile: stressProfile,
            plan: plan,
            world: world,
            bank: bank
        )
        var transport: DayObjectsTransport?
        var didBeginManualRendering = false

        do {
            try playbackBank.prepare()
            try world.bindPreparedPlayersIfNeeded()
            try world.configure(plan, diagnosticAuditionMode: auditionMode)
            try bank.beginOfflineRendering(
                format: format,
                maximumFrameCount: Self.maximumFrameCount
            )
            didBeginManualRendering = true
            try offlineBeginCheckpoint()
            try Task.checkCancellation()
            try world.startScheduling()
            applyLeadGestureIfNeeded(world: world, elapsedSeconds: 0, durationSeconds: durationSeconds)

            let activeTransport = DayObjectsTransport(clock: clock) { event in
                if let eventEndSeconds,
                   event.hostTimeSeconds - initialHostTime >= eventEndSeconds { return }
                await world.render(event)
                await stressCoordinator.observe(event)
            }
            transport = activeTransport
            await activeTransport.start(
                tempoBPM: plan.rhythm.tempoBPM,
                harmonicCycleBars: plan.world.cycleBars
            )
            try await waitForTransportDeadline(clock, after: nil)
            try stressCoordinator.checkpoint()

            var renderedFrames = 0
            var didEndSchedule = false
            var diagnosticAccumulator = DayObjectsOfflineDiagnosticAccumulator()
            let modulationFrames = max(Int((sampleRate / 120).rounded()), 1)
            while renderedFrames < totalFrameCount {
                try Task.checkCancellation()
                bank.advanceOfflineModulation()
                let nextTransportDeadline = clock.nextDeadline
                let nextTransportFrame = nextTransportDeadline.map {
                    max(Int((($0 - initialHostTime) * sampleRate).rounded()), renderedFrames)
                }
                let nextLeadFrame = didEndSchedule ? nil : nextLeadGestureFrame(
                    after: renderedFrames,
                    durationSeconds: durationSeconds,
                    sampleRate: sampleRate
                )
                let nextBassReleaseFrame = stressCoordinator
                    .nextBassReleaseHostTimeSeconds
                    .map {
                        max(
                            Int((($0 - initialHostTime) * sampleRate).rounded()),
                            renderedFrames
                        )
                    }
                let nextModulationFrame = ((renderedFrames / modulationFrames) + 1) * modulationFrames
                let nextBoundary = [nextTransportFrame, nextLeadFrame, nextBassReleaseFrame, eventEndFrame, nextModulationFrame]
                    .compactMap { $0 }
                    .filter { $0 > renderedFrames }
                    .min()
                let boundaryFrames = nextBoundary.map { $0 - renderedFrames }
                    ?? Int(Self.maximumFrameCount)
                let requestedFrames = min(
                    Int(Self.maximumFrameCount),
                    totalFrameCount - renderedFrames,
                    boundaryFrames
                )

                try await render(
                    requestedFrames: AVAudioFrameCount(max(requestedFrames, 1)),
                    scratch: scratch,
                    output: output,
                    destinationFrameOffset: renderedFrames,
                    bank: bank
                )
                renderedFrames += max(requestedFrames, 1)
                let elapsedSeconds = Double(renderedFrames) / sampleRate
                let calculatedHostTime = initialHostTime + elapsedSeconds
                let reachedTransportDeadline = nextTransportDeadline.map {
                    calculatedHostTime + (0.5 / sampleRate) >= $0
                } ?? false
                let nextBassReleaseDeadline = stressCoordinator.nextBassReleaseHostTimeSeconds
                let reachedBassReleaseDeadline = nextBassReleaseDeadline.map {
                    calculatedHostTime + (0.5 / sampleRate) >= $0
                } ?? false
                let transportHostTime = reachedTransportDeadline
                    ? nextTransportDeadline ?? calculatedHostTime
                    : calculatedHostTime
                let bassReleaseHostTime = reachedBassReleaseDeadline
                    ? nextBassReleaseDeadline ?? calculatedHostTime
                    : calculatedHostTime
                let newHostTime = max(
                    calculatedHostTime,
                    max(transportHostTime, bassReleaseHostTime)
                )
                clock.advance(to: newHostTime)
                stressCoordinator.releaseBassIfDue(atHostTime: newHostTime)
                if let eventEndFrame, !didEndSchedule, renderedFrames >= eventEndFrame {
                    await activeTransport.stop()
                    world.releaseAll()
                    didEndSchedule = true
                    lastEventEndFrame = renderedFrames
                }
                if !didEndSchedule { applyLeadGestureIfNeeded(
                    world: world,
                    elapsedSeconds: elapsedSeconds,
                    durationSeconds: durationSeconds
                ) }
                diagnosticAccumulator.capture(
                    bank.diagnosticMeterSnapshot(atHostTime: newHostTime),
                    limiterInputPeakDBFS: bank.offlineLimiterInputPeakDBFS
                )
                if reachedTransportDeadline, !didEndSchedule, renderedFrames < totalFrameCount {
                    try await waitForTransportDeadline(
                        clock,
                        after: nextTransportDeadline
                    )
                }
                try stressCoordinator.checkpoint()
            }

            let stressDiagnostics = try stressCoordinator.finish()
            await activeTransport.stop()
            world.releaseAll()
            lastDiagnostics = diagnosticAccumulator.makeDiagnostics(
                renderedFrameCount: renderedFrames,
                stressDiagnostics: stressDiagnostics
            )
            bank.endOfflineRendering()
            didBeginManualRendering = false
            return output
        } catch {
            if let transport { await transport.stop() }
            world.releaseAll()
            if didBeginManualRendering { bank.endOfflineRendering() }
            throw error
        }
    }

    private func render(
        requestedFrames: AVAudioFrameCount,
        scratch: AVAudioPCMBuffer,
        output: AVAudioPCMBuffer,
        destinationFrameOffset: Int,
        bank: DayObjectsInstrumentBank
    ) async throws {
        var contextRetryCount = 0
        while true {
            scratch.frameLength = 0
            let status = try bank.renderOffline(requestedFrames, to: scratch)
            switch status {
            case .success:
                guard scratch.frameLength == requestedFrames,
                      let sourceChannels = scratch.floatChannelData,
                      let destinationChannels = output.floatChannelData
                else {
                    throw DayObjectsOfflineMixRendererError.renderFailed
                }
                let byteCount = Int(requestedFrames) * MemoryLayout<Float>.stride
                for channel in 0..<Int(output.format.channelCount) {
                    memcpy(
                        destinationChannels[channel].advanced(by: destinationFrameOffset),
                        sourceChannels[channel],
                        byteCount
                    )
                }
                output.frameLength = AVAudioFrameCount(destinationFrameOffset) + requestedFrames
                return
            case .cannotDoInCurrentContext where contextRetryCount < contextRetryLimit:
                contextRetryCount += 1
                await Task.yield()
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext, .error:
                throw DayObjectsOfflineMixRendererError.renderFailed
            @unknown default:
                throw DayObjectsOfflineMixRendererError.renderFailed
            }
        }
    }

    private func waitForTransportDeadline(
        _ clock: DayObjectsOfflineTransportClock,
        after previousDeadline: TimeInterval?
    ) async throws {
        for _ in 0..<2_000 {
            if let deadline = clock.nextDeadline,
               previousDeadline.map({ deadline > $0 + 0.000_000_1 }) ?? true {
                return
            }
            await Task.yield()
        }
        throw DayObjectsOfflineMixRendererError.transportStalled
    }

    private func nextLeadGestureFrame(
        after renderedFrames: Int,
        durationSeconds: Double,
        sampleRate: Double
    ) -> Int? {
        guard leadGestureProfile != .none else { return nil }
        let cadence: Double = leadGestureProfile == .fast ? 0.08 : 0.5
        let releaseTime = max(durationSeconds - 0.25, 0.75)
        let nextUpdate = (floor((Double(renderedFrames) / sampleRate) / cadence) + 1) * cadence
        let nextTime = min(nextUpdate, releaseTime)
        let frame = Int((nextTime * sampleRate).rounded())
        return frame > renderedFrames ? frame : nil
    }

    private func applyLeadGestureIfNeeded(
        world: DayObjectsLivePlaybackRuntime.WorldState,
        elapsedSeconds: Double,
        durationSeconds: Double
    ) {
        guard leadGestureProfile != .none else { return }
        let releaseTime = max(durationSeconds - 0.25, 0.75)
        if elapsedSeconds + 0.000_001 >= releaseTime {
            world.lead?.end()
            return
        }
        let speed: Double = leadGestureProfile == .fast ? 0.95 : 0.18
        let phaseRate: Double = leadGestureProfile == .fast ? 3.5 : 0.45
        let phase = elapsedSeconds * phaseRate
        let gesture = LeadGestureSample(
            normalizedX: 0.5 + (0.42 * sin(phase)),
            normalizedY: 0.55 + (0.30 * cos(phase * 0.7)),
            speed: leadGestureProfile == .held ? 0.08 : speed
        )
        if world.lead?.heldState == nil {
            world.lead?.begin(gesture)
        } else {
            world.lead?.update(gesture)
        }
    }

}

private struct DayObjectsOfflineStressDiagnostics {
    let activities: [DayObjectsOfflineStressActivity]
    let transportSubdivision: Int64?
    let transportSubdivisionsWereMonotonic: Bool
    let harmonyTransition: DayObjectsOfflineHarmonyTransitionEvidence?
    let scheduledBassReleaseHostTimeSeconds: TimeInterval?
    let actualBassReleaseHostTimeSeconds: TimeInterval?
    let bassActiveVoiceCountAfterRelease: Int?
}

/// Coordinates the stress audition only from events emitted by the production
/// transport. It never advances Harmony independently of that transport.
@MainActor
private final class DayObjectsOfflineStressCoordinator {
    private static let bassStimulusDurationSeconds = 0.220
    private static let timeTolerance = 0.000_000_1

    private let profile: DayObjectsOfflineStressProfile
    private let plan: DayMusicPlan
    private let world: DayObjectsLivePlaybackRuntime.WorldState
    private let bank: DayObjectsInstrumentBank
    private let targetTransition: HarmonyChordScheduleEntry?
    private let targetSubdivision: Int64?

    private var lastObservedTransportSubdivision: Int64?
    private var transportSubdivisionsWereMonotonic = true
    private var failure: DayObjectsOfflineMixRendererError?
    private var didTrigger = false
    private var activities: [DayObjectsOfflineStressActivity] = []
    private var harmonyTransition: DayObjectsOfflineHarmonyTransitionEvidence?
    private var scheduledBassReleaseHostTimeSeconds: TimeInterval?
    private var actualBassReleaseHostTimeSeconds: TimeInterval?
    private var bassActiveVoiceCountAfterRelease: Int?

    var nextBassReleaseHostTimeSeconds: TimeInterval? {
        actualBassReleaseHostTimeSeconds == nil ? scheduledBassReleaseHostTimeSeconds : nil
    }

    init(
        profile: DayObjectsOfflineStressProfile,
        plan: DayMusicPlan,
        world: DayObjectsLivePlaybackRuntime.WorldState,
        bank: DayObjectsInstrumentBank
    ) {
        self.profile = profile
        self.plan = plan
        self.world = world
        self.bank = bank
        let transition = Self.nextStressChordTransition(in: plan)
        targetTransition = transition
        targetSubdivision = transition.map {
            Int64($0.startBar) * MusicalPosition.subdivisionsPerBar
        }
    }

    func observe(_ event: DayObjectsTransportEvent) {
        let subdivision = event.position.absoluteSubdivision
        if let previous = lastObservedTransportSubdivision, subdivision < previous {
            transportSubdivisionsWereMonotonic = false
            failure = failure ?? .stressAuditionFailed(.chordTransition)
        }
        lastObservedTransportSubdivision = subdivision

        guard profile == .fourHappeningTailsWithKickBassChordAndHeldLead else { return }
        refreshHarmonyTransitionEvidence()
        guard !didTrigger,
              event.kind == .barBoundary,
              subdivision == targetSubdivision
        else { return }

        do {
            try trigger(at: event)
            didTrigger = true
            refreshHarmonyTransitionEvidence()
        } catch let rendererError as DayObjectsOfflineMixRendererError {
            failure = rendererError
        } catch {
            failure = .stressAuditionFailed(.happeningTail)
        }
    }

    func releaseBassIfDue(atHostTime hostTime: TimeInterval) {
        guard profile == .fourHappeningTailsWithKickBassChordAndHeldLead,
              actualBassReleaseHostTimeSeconds == nil,
              let deadline = nextBassReleaseHostTimeSeconds,
              hostTime + Self.timeTolerance >= deadline
        else { return }

        world.bass?.releaseDiagnosticAudition(restoring: plan.bass)
        actualBassReleaseHostTimeSeconds = hostTime
        bassActiveVoiceCountAfterRelease = world.bass?.metrics.activeVoiceCount ?? 0
        if bassActiveVoiceCountAfterRelease != 0 {
            failure = failure ?? .stressAuditionFailed(.bassAttack)
        }
    }

    func checkpoint() throws {
        if let failure { throw failure }
    }

    func finish() throws -> DayObjectsOfflineStressDiagnostics {
        try checkpoint()
        guard profile == .fourHappeningTailsWithKickBassChordAndHeldLead else {
            return .init(
                activities: [],
                transportSubdivision: nil,
                transportSubdivisionsWereMonotonic: transportSubdivisionsWereMonotonic,
                harmonyTransition: nil,
                scheduledBassReleaseHostTimeSeconds: nil,
                actualBassReleaseHostTimeSeconds: nil,
                bassActiveVoiceCountAfterRelease: nil
            )
        }

        refreshHarmonyTransitionEvidence()
        guard didTrigger,
              activities.count == 8,
              transportSubdivisionsWereMonotonic,
              let transition = harmonyTransition,
              transition.oldVoiceCount > 0,
              transition.newVoiceCount > 0,
              transition.maximumAudibleProgress > 0,
              transition.maximumNewChordExpression > 0,
              transition.firstAudibleProgressHostTimeSeconds != nil
        else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.chordTransition)
        }
        guard let scheduledBassReleaseHostTimeSeconds,
              let actualBassReleaseHostTimeSeconds,
              bassActiveVoiceCountAfterRelease == 0
        else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.bassAttack)
        }
        return .init(
            activities: activities,
            transportSubdivision: targetSubdivision,
            transportSubdivisionsWereMonotonic: transportSubdivisionsWereMonotonic,
            harmonyTransition: transition,
            scheduledBassReleaseHostTimeSeconds: scheduledBassReleaseHostTimeSeconds,
            actualBassReleaseHostTimeSeconds: actualBassReleaseHostTimeSeconds,
            bassActiveVoiceCountAfterRelease: bassActiveVoiceCountAfterRelease
        )
    }

    private func trigger(at event: DayObjectsTransportEvent) throws {
        let candidate = matchingHarmonyTransitionObservation()
        guard let targetTransition,
              let targetSubdivision,
              event.position.absoluteSubdivision == targetSubdivision,
              world.currentChordIndex == targetTransition.chordIndex,
              let observedTransition = candidate,
              observedTransition.startSubdivision == event.position.absoluteSubdivision,
              abs(observedTransition.startHostTimeSeconds - event.hostTimeSeconds)
                <= Self.timeTolerance,
              observedTransition.oldVoiceCount > 0,
              observedTransition.newVoiceCount > 0,
              (world.harmony?.metrics.pendingReleaseTokenCount ?? 0) > 0
        else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.chordTransition)
        }
        guard world.lead?.metrics.voiceCount == 1,
              world.lead?.heldState != nil
        else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.heldLead)
        }

        let hostTime = event.hostTimeSeconds
        activities.append(.init(
            component: .heldLead,
            hostTimeSeconds: hostTime,
            identifier: "lead.held"
        ))

        guard let kickBass = world.auditionKickBassSidechain(
            preferredBassID: plan.bass?.instrumentID,
            hostTime: hostTime,
            automaticallyReleaseAfterWallClock: false,
            forceFreshDuckingCommand: true
        ) else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.bassAttack)
        }
        guard kickBass.scheduledKick.voice == .kickSoft,
              abs(kickBass.scheduledKick.scheduledHostTimeSeconds - hostTime)
                <= Self.timeTolerance
        else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.kickSoft)
        }
        guard world.bass?.metrics.activeVoiceCount == 1,
              world.bass?.lastDiagnosticHostTimeSeconds == hostTime
        else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.bassAttack)
        }
        activities.append(.init(
            component: .kickSoft,
            hostTimeSeconds: kickBass.scheduledKick.scheduledHostTimeSeconds,
            identifier: kickBass.scheduledKick.voice.rawValue
        ))
        activities.append(.init(
            component: .bassAttack,
            hostTimeSeconds: hostTime,
            identifier: kickBass.instrumentID.rawValue
        ))
        activities.append(.init(
            component: .chordTransition,
            hostTimeSeconds: observedTransition.startHostTimeSeconds,
            identifier: "chord-\(observedTransition.chordIndex)-bar-\(targetTransition.startBar)"
        ))

        guard plan.happenings.count >= 4,
              plan.world.progression.indices.contains(world.currentChordIndex)
        else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.happeningTail)
        }
        let chord = plan.world.progression[world.currentChordIndex]
        let perVoiceCompensation = pow(10, -6.0 / 20)
        for happening in plan.happenings.prefix(4) {
            guard let recipe = HappeningSoundCatalog.recipe(for: happening.recipeID) else {
                throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.happeningTail)
            }
            let resolved = HappeningPitchResolver.resolve(
                recipe: recipe,
                chord: chord,
                tonalWorld: plan.world
            )
            _ = try bank.happenings.play(
                resolved,
                gain: happening.gain * perVoiceCompensation,
                priority: .manualAudition,
                effects: .init(
                    filterCutoffHz: recipe.filterEndHz,
                    delayMix: recipe.delayMix,
                    delayFeedback: recipe.delayFeedback,
                    reverbMix: recipe.reverbMix
                ),
                pan: happening.pan
            )
            activities.append(.init(
                component: .happeningTail,
                hostTimeSeconds: hostTime,
                identifier: String(happening.recipeID.rawValue)
            ))
        }
        guard bank.happenings.metrics.activeVoiceCount >= 4 else {
            throw DayObjectsOfflineMixRendererError.stressAuditionFailed(.happeningTail)
        }
        scheduledBassReleaseHostTimeSeconds = hostTime + Self.bassStimulusDurationSeconds
    }

    private func refreshHarmonyTransitionEvidence() {
        guard let observation = matchingHarmonyTransitionObservation() else { return }
        harmonyTransition = .init(
            role: String(describing: observation.role),
            chordIndex: observation.chordIndex,
            startSubdivision: observation.startSubdivision,
            startHostTimeSeconds: observation.startHostTimeSeconds,
            endSubdivision: observation.endSubdivision,
            oldVoiceCount: observation.oldVoiceCount,
            newVoiceCount: observation.newVoiceCount,
            maximumAudibleProgress: observation.maximumAudibleProgress,
            maximumNewChordExpression: observation.maximumNewChordExpression,
            firstAudibleProgressSubdivision: observation.firstAudibleProgressSubdivision,
            firstAudibleProgressHostTimeSeconds: observation.firstAudibleProgressHostTimeSeconds
        )
    }

    private func matchingHarmonyTransitionObservation() -> HarmonyTransitionObservation? {
        guard let targetTransition, let targetSubdivision else { return nil }
        return world.harmony?.transitionObservations.first {
            $0.chordIndex == targetTransition.chordIndex
                && $0.startSubdivision == targetSubdivision
                && $0.oldVoiceCount > 0
                && $0.newVoiceCount > 0
        }
    }

    private static func nextStressChordTransition(
        in plan: DayMusicPlan
    ) -> HarmonyChordScheduleEntry? {
        plan.harmony.roles
            .filter { $0.gain > 0 }
            .flatMap(\.chordSchedule)
            .filter { $0.startBar > 0 }
            .min {
                if $0.startBar == $1.startBar { return $0.chordIndex < $1.chordIndex }
                return $0.startBar < $1.startBar
            }
    }
}

private final class DayObjectsOfflineTransportClock: DayObjectsTransportClock, @unchecked Sendable {
    private struct Waiter {
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentHostTime: TimeInterval
    private var waiters: [UUID: Waiter] = [:]
    private var cancelledWaiterIDs: Set<UUID> = []

    init(now: TimeInterval) {
        currentHostTime = now
    }

    func now() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return currentHostTime
    }

    var nextDeadline: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return waiters.values.map(\.deadline).min()
    }

    func advance(to hostTime: TimeInterval) {
        lock.lock()
        currentHostTime = max(currentHostTime, hostTime)
        let dueIDs = waiters.compactMap { id, waiter in
            waiter.deadline <= currentHostTime ? id : nil
        }
        let dueWaiters = dueIDs.compactMap { waiters.removeValue(forKey: $0) }
        lock.unlock()
        dueWaiters.sorted { $0.deadline < $1.deadline }
            .forEach { $0.continuation.resume() }
    }

    func sleep(untilHostTime hostTime: TimeInterval) async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelledWaiterIDs.remove(waiterID) != nil || Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if hostTime <= currentHostTime {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters[waiterID] = Waiter(
                        deadline: hostTime,
                        continuation: continuation
                    )
                    lock.unlock()
                }
            }
        } onCancel: {
            self.cancelWaiter(id: waiterID)
        }
    }

    private func cancelWaiter(id: UUID) {
        lock.lock()
        if let waiter = waiters.removeValue(forKey: id) {
            lock.unlock()
            waiter.continuation.resume(throwing: CancellationError())
        } else {
            cancelledWaiterIDs.insert(id)
            lock.unlock()
        }
    }
}

private struct DayObjectsOfflineDiagnosticAccumulator {
    private var roleSquaredSums: [DayObjectsRoleBus: Double] = [:]
    private var roleCounts: [DayObjectsRoleBus: Int] = [:]
    private var rolePeaks: [DayObjectsRoleBus: Double] = [:]
    private var roleActiveVoiceCounts: [DayObjectsRoleBus: Int] = [:]
    private var maximumEstimatedLimiterReductionDB = 0.0

    mutating func capture(
        _ snapshot: DayObjectsDiagnosticMeterSnapshot,
        limiterInputPeakDBFS: Double
    ) {
        for role in DayObjectsRoleBus.allCases {
            let metrics = snapshot.roleBusMetrics.metrics(for: role)
            if metrics.rmsDBFS > -120 {
                roleSquaredSums[role, default: 0] += pow(10, metrics.rmsDBFS / 10)
                roleCounts[role, default: 0] += 1
            }
            rolePeaks[role] = max(rolePeaks[role] ?? -120, metrics.peakDBFS)
            roleActiveVoiceCounts[role] = max(
                roleActiveVoiceCounts[role, default: 0],
                metrics.activeVoiceCount
            )
        }
        // The real-time pre/post meter estimator aligns windows by render
        // timestamps. AVAudioEngine manual mode gives taps from some effects
        // different timeline origins, so comparing those windows can invent
        // large reductions for a quiet signal. PeakLimiter has 0 dB pre-gain;
        // its required peak attenuation is therefore the measured input
        // excursion above 0 dBFS.
        maximumEstimatedLimiterReductionDB = max(
            maximumEstimatedLimiterReductionDB,
            max(limiterInputPeakDBFS, 0)
        )
    }

    func makeDiagnostics(
        renderedFrameCount: Int,
        stressDiagnostics: DayObjectsOfflineStressDiagnostics
    ) -> DayObjectsOfflineMixDiagnostics {
        let rms = Dictionary(uniqueKeysWithValues: DayObjectsRoleBus.allCases.map { role in
            let count = roleCounts[role, default: 0]
            let averagePower = count > 0
                ? roleSquaredSums[role, default: 0] / Double(count)
                : 0
            return (role, averagePower > 0 ? 10 * log10(averagePower) : -120)
        })
        return .init(
            averageRoleRMSDBFS: rms,
            maximumRolePeakDBFS: Dictionary(uniqueKeysWithValues: DayObjectsRoleBus.allCases.map {
                ($0, rolePeaks[$0] ?? -120)
            }),
            maximumRoleActiveVoiceCount: Dictionary(uniqueKeysWithValues: DayObjectsRoleBus.allCases.map {
                ($0, roleActiveVoiceCounts[$0, default: 0])
            }),
            maximumEstimatedLimiterReductionDB: maximumEstimatedLimiterReductionDB,
            stressActivities: stressDiagnostics.activities,
            stressTransportSubdivision: stressDiagnostics.transportSubdivision,
            transportSubdivisionsWereMonotonic: stressDiagnostics.transportSubdivisionsWereMonotonic,
            harmonyTransition: stressDiagnostics.harmonyTransition,
            scheduledBassReleaseHostTimeSeconds: stressDiagnostics.scheduledBassReleaseHostTimeSeconds,
            actualBassReleaseHostTimeSeconds: stressDiagnostics.actualBassReleaseHostTimeSeconds,
            bassActiveVoiceCountAfterRelease: stressDiagnostics.bassActiveVoiceCountAfterRelease,
            renderedFrameCount: renderedFrameCount
        )
    }
}
