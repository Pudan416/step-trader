#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsRemixRuntimeMetrics: Equatable, Sendable {
    let nodeCount: Int
    let poolCount: Int
    let taskCount: Int
    let transportCount: Int
    let leadTokenCount: Int
    let happeningTokenCount: Int
}

struct DayObjectsHappeningHandoffState: Equatable, Sendable {
    let retainedAndReplacedIDs: [String]
    let removedAndCanceledIDs: [String]
    let addedIDs: [String]
    let firstCycleScheduledIDs: [String]
}

enum DayObjectsRemixLeadCompatibility: Equatable, Sendable {
    case notHeld
    case safeCommonPitch(UInt8)
    case requiresRestart
}

enum DayObjectsRemixResult: Equatable, Sendable {
    case idle
    case scheduled(seed: UInt64)
    case transitioned(seed: UInt64)
    case failed(DayObjectsAudioError)
}

enum PlaybackWorldBankSlot: Equatable, Sendable { case a, b }

enum DayObjectsRemixCoordinatorError: Error, Equatable, Sendable {
    case duplicateInstrumentBank
}

struct DayObjectsEqualPowerCrossfadeState: Equatable, Sendable {
    let progress: Double
    let oldGain: Double
    let newGain: Double

    init(progress: Double) {
        let bounded = min(max(progress.isFinite ? progress : 0, 0), 1)
        self.progress = bounded
        oldGain = cos(.pi * 0.5 * bounded)
        newGain = sin(.pi * 0.5 * bounded)
    }
}

struct DayObjectsRemixCoordinatorMetrics: Equatable, Sendable {
    let allocatedBankCount: Int
    let preparedBankCount: Int
    let pendingRemixCount: Int
    let transitionCount: Int
    let activeBank: PlaybackWorldBankSlot
    let inactiveBank: PlaybackWorldBankSlot
    let inactiveBankIsAvailable: Bool
    let crossfadeState: DayObjectsEqualPowerCrossfadeState?
    let happeningHandoffState: DayObjectsHappeningHandoffState?
    let allocatedTonalVoiceCount: Int
    let allocatedPianoVoiceCount: Int
    let allocatedDrumPlayerCount: Int
    let runtime: DayObjectsRemixRuntimeMetrics
}

@MainActor
protocol DayObjectsRemixRuntime: AnyObject {
    var metrics: DayObjectsRemixRuntimeMetrics { get }

    func prepare(bank: PlaybackWorldBank) throws
    func configure(bank: PlaybackWorldBank, plan: DayMusicPlan) throws
    func rollbackInitialConfiguration(in bank: PlaybackWorldBank)
    func renderTransport(
        _ event: DayObjectsTransportEvent,
        activeBank: PlaybackWorldBank,
        releasingBank: PlaybackWorldBank?
    )
    func stopAttackScheduling(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent)
    func beginRelease(in bank: PlaybackWorldBank, at event: DayObjectsTransportEvent)
    func startRhythm(
        in bank: PlaybackWorldBank,
        plan: DayMusicPlan,
        at event: DayObjectsTransportEvent
    ) throws
    func beginEqualPowerCrossfade(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        plan: DayMusicPlan,
        startingAt event: DayObjectsTransportEvent,
        durationBars: Int
    )
    func replaceHappeningsAndScheduleFirstCycle(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        oldPlan: DayMusicPlan,
        newPlan: DayMusicPlan,
        at event: DayObjectsTransportEvent
    ) throws -> DayObjectsHappeningHandoffState
    func leadCompatibility(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        oldPlan: DayMusicPlan,
        newPlan: DayMusicPlan
    ) -> DayObjectsRemixLeadCompatibility
    func glideHeldLead(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        midiNote: UInt8,
        newPlan: DayMusicPlan
    )
    func releaseAndRestartHeldLead(
        from oldBank: PlaybackWorldBank,
        to newBank: PlaybackWorldBank,
        newPlan: DayMusicPlan
    )
    func isDrained(_ bank: PlaybackWorldBank) -> Bool
    func recycle(_ bank: PlaybackWorldBank)
    func rollbackFailedTransition(
        newBank: PlaybackWorldBank,
        restoring oldBank: PlaybackWorldBank,
        currentPlan: DayMusicPlan,
        at event: DayObjectsTransportEvent
    )
    func stop(_ bank: PlaybackWorldBank)
}

@MainActor
final class DayObjectsRemixCoordinator {
    private struct Transition {
        let oldSlot: PlaybackWorldBankSlot
        let startSubdivision: Int64
        let crossfadeEndSubdivision: Int64
        var crossfadeState: DayObjectsEqualPowerCrossfadeState
        var lastObservedSubdivision: Int64
        var scheduledThroughSubdivision: Int64
    }

    private let bankA: PlaybackWorldBank
    private let bankB: PlaybackWorldBank
    private let runtime: DayObjectsRemixRuntime
    private var activeSlot: PlaybackWorldBankSlot = .a
    private var transition: Transition?
    private var lastTransitionBoundarySubdivision: Int64?
    private var highWaterSubdivision: Int64?
    private var highWaterHostTimeSeconds: TimeInterval?
    private var latestHappeningHandoffState: DayObjectsHappeningHandoffState?
    private(set) var currentPlan: DayMusicPlan?
    private(set) var pendingPlan: DayMusicPlan?
    private(set) var result: DayObjectsRemixResult = .idle

    var metrics: DayObjectsRemixCoordinatorMetrics {
        let bankMetrics = [bankA.metrics, bankB.metrics]
        return .init(
            allocatedBankCount: 2,
            preparedBankCount: [bankA, bankB].filter(\.isPrepared).count,
            pendingRemixCount: pendingPlan == nil ? 0 : 1,
            transitionCount: transition == nil ? 0 : 1,
            activeBank: activeSlot,
            inactiveBank: activeSlot == .a ? .b : .a,
            inactiveBankIsAvailable: transition == nil,
            crossfadeState: transition?.crossfadeState,
            happeningHandoffState: latestHappeningHandoffState,
            allocatedTonalVoiceCount: bankMetrics.reduce(0) { $0 + $1.allocatedTonalVoiceCount },
            allocatedPianoVoiceCount: bankMetrics.reduce(0) { $0 + $1.allocatedPianoVoiceCount },
            allocatedDrumPlayerCount: bankMetrics.reduce(0) { $0 + $1.allocatedDrumPlayerCount },
            runtime: runtime.metrics
        )
    }

    init(bankA: PlaybackWorldBank, bankB: PlaybackWorldBank, runtime: DayObjectsRemixRuntime) throws {
        guard bankA !== bankB,
              bankA.instrumentBank !== bankB.instrumentBank
        else { throw DayObjectsRemixCoordinatorError.duplicateInstrumentBank }
        self.bankA = bankA
        self.bankB = bankB
        self.runtime = runtime
    }

    func prepare(initialPlan: DayMusicPlan) throws {
        try bankA.prepare()
        try runtime.prepare(bank: bankA)
        try bankB.prepare()
        try runtime.prepare(bank: bankB)
        do {
            try runtime.configure(bank: bankA, plan: initialPlan)
        } catch {
            runtime.rollbackInitialConfiguration(in: bankA)
            bankA.setOutputGain(0, rampDurationSeconds: 0)
            bankB.setOutputGain(0, rampDurationSeconds: 0)
            currentPlan = nil
            pendingPlan = nil
            transition = nil
            result = .failed(.init(String(describing: error)))
            throw error
        }
        bankA.setOutputGain(1, rampDurationSeconds: 0)
        bankB.setOutputGain(0, rampDurationSeconds: 0)
        currentPlan = initialPlan
        pendingPlan = nil
        transition = nil
        lastTransitionBoundarySubdivision = nil
        highWaterSubdivision = nil
        highWaterHostTimeSeconds = nil
        latestHappeningHandoffState = nil
        activeSlot = .a
        result = .idle
    }

    func schedule(_ plan: DayMusicPlan) {
        pendingPlan = plan
        result = .scheduled(seed: plan.seed)
    }

    func cancelPending() {
        pendingPlan = nil
        if transition == nil { result = .idle }
    }

    func render(_ event: DayObjectsTransportEvent) {
        guard acceptMonotonic(event) else { return }
        advanceCrossfade(at: event)
        finishTransitionIfPossible(at: event)

        if isEligibleBoundary(event), transition == nil,
           lastTransitionBoundarySubdivision != event.position.absoluteSubdivision,
           let targetPlan = pendingPlan, let oldPlan = currentPlan {
            lastTransitionBoundarySubdivision = event.position.absoluteSubdivision
            let oldBank = activeBank
            let newBank = inactiveBank
            let oldSlot = activeSlot
            let newSlot: PlaybackWorldBankSlot = activeSlot == .a ? .b : .a
            do {
                runtime.stopAttackScheduling(in: oldBank, at: event)
                runtime.beginRelease(in: oldBank, at: event)
                try runtime.configure(bank: newBank, plan: targetPlan)
                try runtime.startRhythm(in: newBank, plan: targetPlan, at: event)
                runtime.beginEqualPowerCrossfade(
                    from: oldBank,
                    to: newBank,
                    plan: targetPlan,
                    startingAt: event,
                    durationBars: 2
                )
                let happeningState = try runtime.replaceHappeningsAndScheduleFirstCycle(
                    from: oldBank,
                    to: newBank,
                    oldPlan: oldPlan,
                    newPlan: targetPlan,
                    at: event
                )
                try validate(happeningState, oldPlan: oldPlan, newPlan: targetPlan)
                switch runtime.leadCompatibility(from: oldBank, to: newBank, oldPlan: oldPlan, newPlan: targetPlan) {
                case .notHeld: break
                case let .safeCommonPitch(note):
                    runtime.glideHeldLead(from: oldBank, to: newBank, midiNote: note, newPlan: targetPlan)
                case .requiresRestart:
                    runtime.releaseAndRestartHeldLead(from: oldBank, to: newBank, newPlan: targetPlan)
                }
                activeSlot = newSlot
                currentPlan = targetPlan
                pendingPlan = nil
                latestHappeningHandoffState = happeningState
                var newTransition = Transition(
                    oldSlot: oldSlot,
                    startSubdivision: event.position.absoluteSubdivision,
                    crossfadeEndSubdivision: event.position.absoluteSubdivision
                        + 2 * MusicalPosition.subdivisionsPerBar,
                    crossfadeState: .init(progress: 0),
                    lastObservedSubdivision: event.position.absoluteSubdivision,
                    scheduledThroughSubdivision: event.position.absoluteSubdivision
                )
                scheduleCrossfadeGains(
                    .init(progress: 0),
                    oldBank: oldBank,
                    newBank: newBank,
                    startingAtHostTime: event.hostTimeSeconds,
                    endingAtHostTime: event.hostTimeSeconds
                )
                scheduleNextCrossfadePoint(
                    transition: &newTransition,
                    from: event,
                    oldBank: oldBank,
                    newBank: newBank
                )
                transition = newTransition
                result = .transitioned(seed: targetPlan.seed)
            } catch {
                runtime.rollbackFailedTransition(
                    newBank: newBank,
                    restoring: oldBank,
                    currentPlan: oldPlan,
                    at: event
                )
                oldBank.setOutputGain(1, rampDurationSeconds: 0)
                newBank.setOutputGain(0, rampDurationSeconds: 0)
                pendingPlan = nil
                result = .failed(.init(String(describing: error)))
            }
        }

        runtime.renderTransport(
            event,
            activeBank: activeBank,
            releasingBank: transition.map { bank(for: $0.oldSlot) }
        )
    }

    func stop() {
        pendingPlan = nil
        transition = nil
        lastTransitionBoundarySubdivision = nil
        highWaterSubdivision = nil
        highWaterHostTimeSeconds = nil
        latestHappeningHandoffState = nil
        runtime.stop(bankA)
        runtime.stop(bankB)
        bankA.setOutputGain(0, rampDurationSeconds: 0)
        bankB.setOutputGain(0, rampDurationSeconds: 0)
        bankA.releaseAll()
        bankB.releaseAll()
        currentPlan = nil
        activeSlot = .a
        result = .idle
    }

    private func finishTransitionIfPossible(at event: DayObjectsTransportEvent) {
        guard let transition,
              event.position.absoluteSubdivision >= transition.crossfadeEndSubdivision else { return }
        let oldBank = bank(for: transition.oldSlot)
        guard runtime.isDrained(oldBank) else { return }
        runtime.recycle(oldBank)
        oldBank.recycleAfterTailsDrain()
        self.transition = nil
    }

    private func advanceCrossfade(at event: DayObjectsTransportEvent) {
        guard var transition else { return }
        guard transition.crossfadeState.progress < 1 else { return }
        guard event.position.absoluteSubdivision > transition.lastObservedSubdivision else { return }
        let observedSubdivision = min(
            event.position.absoluteSubdivision,
            transition.crossfadeEndSubdivision
        )
        let elapsed = max(observedSubdivision - transition.startSubdivision, 0)
        let duration = max(
            transition.crossfadeEndSubdivision - transition.startSubdivision,
            1
        )
        let state = DayObjectsEqualPowerCrossfadeState(
            progress: Double(elapsed) / Double(duration)
        )
        guard state.progress >= transition.crossfadeState.progress else { return }
        let oldBank = bank(for: transition.oldSlot)
        let newBank = activeBank

        if observedSubdivision > transition.scheduledThroughSubdivision {
            // A skipped callback cannot start a late ramp toward a point whose
            // musical host time has already passed. Realize that point now.
            scheduleCrossfadeGains(
                state,
                oldBank: oldBank,
                newBank: newBank,
                startingAtHostTime: event.hostTimeSeconds,
                endingAtHostTime: event.hostTimeSeconds
            )
            transition.scheduledThroughSubdivision = observedSubdivision
        }
        transition.crossfadeState = state
        transition.lastObservedSubdivision = event.position.absoluteSubdivision
        scheduleNextCrossfadePoint(
            transition: &transition,
            from: event,
            oldBank: oldBank,
            newBank: newBank
        )
        self.transition = transition
    }

    private func scheduleNextCrossfadePoint(
        transition: inout Transition,
        from event: DayObjectsTransportEvent,
        oldBank: PlaybackWorldBank,
        newBank: PlaybackWorldBank
    ) {
        let currentSubdivision = min(
            event.position.absoluteSubdivision,
            transition.crossfadeEndSubdivision
        )
        guard currentSubdivision < transition.crossfadeEndSubdivision else { return }
        let nextSubdivision = currentSubdivision + 1
        guard nextSubdivision > transition.scheduledThroughSubdivision else { return }
        let duration = max(
            transition.crossfadeEndSubdivision - transition.startSubdivision,
            1
        )
        let state = DayObjectsEqualPowerCrossfadeState(
            progress: Double(nextSubdivision - transition.startSubdivision) / Double(duration)
        )
        let authoritativeNextHostTime = event.nextSubdivisionHostTimeSeconds
        let nextHostTime = authoritativeNextHostTime.isFinite
            && authoritativeNextHostTime >= event.hostTimeSeconds
            ? authoritativeNextHostTime
            : event.hostTimeSeconds
        scheduleCrossfadeGains(
            state,
            oldBank: oldBank,
            newBank: newBank,
            startingAtHostTime: event.hostTimeSeconds,
            endingAtHostTime: nextHostTime
        )
        transition.scheduledThroughSubdivision = nextSubdivision
    }

    private func scheduleCrossfadeGains(
        _ state: DayObjectsEqualPowerCrossfadeState,
        oldBank: PlaybackWorldBank,
        newBank: PlaybackWorldBank,
        startingAtHostTime startHostTime: TimeInterval,
        endingAtHostTime endHostTime: TimeInterval
    ) {
        oldBank.scheduleOutputGain(
            state.oldGain,
            startingAtHostTime: startHostTime,
            endingAtHostTime: endHostTime
        )
        newBank.scheduleOutputGain(
            state.newGain,
            startingAtHostTime: startHostTime,
            endingAtHostTime: endHostTime
        )
    }

    private func isEligibleBoundary(_ event: DayObjectsTransportEvent) -> Bool {
        guard event.position.subdivisionInBar == 0 else { return false }
        return event.kind == .subdivision || event.kind == .barBoundary
    }

    private func acceptMonotonic(_ event: DayObjectsTransportEvent) -> Bool {
        let position = event.position.absoluteSubdivision
        let hostTime = event.hostTimeSeconds
        if let highWaterSubdivision, position < highWaterSubdivision { return false }
        if let highWaterHostTimeSeconds, hostTime < highWaterHostTimeSeconds { return false }
        highWaterSubdivision = max(highWaterSubdivision ?? position, position)
        highWaterHostTimeSeconds = max(highWaterHostTimeSeconds ?? hostTime, hostTime)
        return true
    }

    private func validate(
        _ state: DayObjectsHappeningHandoffState,
        oldPlan: DayMusicPlan,
        newPlan: DayMusicPlan
    ) throws {
        let oldIDs = Set(oldPlan.happenings.map(\.happeningID))
        let newIDs = Set(newPlan.happenings.map(\.happeningID))
        let expected = DayObjectsHappeningHandoffState(
            retainedAndReplacedIDs: oldIDs.intersection(newIDs).sorted(),
            removedAndCanceledIDs: oldIDs.subtracting(newIDs).sorted(),
            addedIDs: newIDs.subtracting(oldIDs).sorted(),
            firstCycleScheduledIDs: newIDs.sorted()
        )
        guard state == expected else {
            throw DayObjectsAudioError("Invalid Happening handoff state")
        }
    }

    private func bank(for slot: PlaybackWorldBankSlot) -> PlaybackWorldBank {
        slot == .a ? bankA : bankB
    }

    private var activeBank: PlaybackWorldBank { activeSlot == .a ? bankA : bankB }
    private var inactiveBank: PlaybackWorldBank { activeSlot == .a ? bankB : bankA }
}
#endif
