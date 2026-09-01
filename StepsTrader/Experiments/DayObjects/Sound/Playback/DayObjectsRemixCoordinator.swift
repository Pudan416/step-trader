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

struct DayObjectsRemixCoordinatorMetrics: Equatable, Sendable {
    let allocatedBankCount: Int
    let preparedBankCount: Int
    let pendingRemixCount: Int
    let transitionCount: Int
    let activeBank: PlaybackWorldBankSlot
    let inactiveBank: PlaybackWorldBankSlot
    let inactiveBankIsAvailable: Bool
    let allocatedTonalVoiceCount: Int
    let allocatedPianoVoiceCount: Int
    let allocatedDrumPlayerCount: Int
    let runtime: DayObjectsRemixRuntimeMetrics
}

@MainActor
protocol DayObjectsRemixRuntime: AnyObject {
    var metrics: DayObjectsRemixRuntimeMetrics { get }

    func configure(bank: PlaybackWorldBank, plan: DayMusicPlan) throws
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
    )
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
        let crossfadeEndSubdivision: Int64
    }

    private let bankA: PlaybackWorldBank
    private let bankB: PlaybackWorldBank
    private let runtime: DayObjectsRemixRuntime
    private var activeSlot: PlaybackWorldBankSlot = .a
    private var transition: Transition?
    private var lastTransitionBoundarySubdivision: Int64?
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
            allocatedTonalVoiceCount: bankMetrics.reduce(0) { $0 + $1.allocatedTonalVoiceCount },
            allocatedPianoVoiceCount: bankMetrics.reduce(0) { $0 + $1.allocatedPianoVoiceCount },
            allocatedDrumPlayerCount: bankMetrics.reduce(0) { $0 + $1.allocatedDrumPlayerCount },
            runtime: runtime.metrics
        )
    }

    init(bankA: PlaybackWorldBank, bankB: PlaybackWorldBank, runtime: DayObjectsRemixRuntime) {
        precondition(bankA !== bankB, "Remix requires two distinct preallocated world banks")
        self.bankA = bankA
        self.bankB = bankB
        self.runtime = runtime
    }

    func prepare(initialPlan: DayMusicPlan) throws {
        try bankA.prepare()
        try bankB.prepare()
        try runtime.configure(bank: bankA, plan: initialPlan)
        currentPlan = initialPlan
        pendingPlan = nil
        transition = nil
        lastTransitionBoundarySubdivision = nil
        activeSlot = .a
        result = .idle
    }

    func schedule(_ plan: DayMusicPlan) {
        pendingPlan = plan
        result = .scheduled(seed: plan.seed)
    }

    func render(_ event: DayObjectsTransportEvent) {
        finishTransitionIfPossible(at: event)

        guard isEligibleBoundary(event), transition == nil,
              lastTransitionBoundarySubdivision != event.position.absoluteSubdivision,
              let targetPlan = pendingPlan, let oldPlan = currentPlan else { return }
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
            runtime.replaceHappeningsAndScheduleFirstCycle(
                from: oldBank,
                to: newBank,
                oldPlan: oldPlan,
                newPlan: targetPlan,
                at: event
            )
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
            transition = .init(
                oldSlot: oldSlot,
                crossfadeEndSubdivision: event.position.absoluteSubdivision
                    + 2 * MusicalPosition.subdivisionsPerBar
            )
            result = .transitioned(seed: targetPlan.seed)
        } catch {
            runtime.rollbackFailedTransition(
                newBank: newBank,
                restoring: oldBank,
                currentPlan: oldPlan,
                at: event
            )
            pendingPlan = nil
            result = .failed(.init(String(describing: error)))
        }
    }

    func stop() {
        pendingPlan = nil
        transition = nil
        lastTransitionBoundarySubdivision = nil
        runtime.stop(bankA)
        runtime.stop(bankB)
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

    private func isEligibleBoundary(_ event: DayObjectsTransportEvent) -> Bool {
        guard event.position.subdivisionInBar == 0 else { return false }
        return event.kind == .subdivision || event.kind == .barBoundary
    }

    private func bank(for slot: PlaybackWorldBankSlot) -> PlaybackWorldBank {
        slot == .a ? bankA : bankB
    }

    private var activeBank: PlaybackWorldBank { activeSlot == .a ? bankA : bankB }
    private var inactiveBank: PlaybackWorldBank { activeSlot == .a ? bankB : bankA }
}
#endif
