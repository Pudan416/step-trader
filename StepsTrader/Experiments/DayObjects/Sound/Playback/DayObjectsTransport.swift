import Foundation

enum DayObjectsTransportLifecycle: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
}

struct DayObjectsTransportSnapshot: Equatable, Sendable {
    let position: MusicalPosition
    let lifecycle: DayObjectsTransportLifecycle
    let isRunning: Bool
    let activeSchedulingTaskCount: Int
    let startedSchedulingLoopCount: Int
    let runningSchedulingLoopCount: Int
    let currentTempoBPM: Double
    let pendingTempoBPM: Double?
}

actor DayObjectsTransport {
    typealias EventHandler = @Sendable (DayObjectsTransportEvent) async -> Void

    private struct TempoRamp {
        let startBPM: Double
        let targetBPM: Double
        var completedIntervals: Int
    }

    private let clock: any DayObjectsTransportClock
    private let eventHandler: EventHandler?

    private var lifecycle: DayObjectsTransportLifecycle = .stopped
    private var generation: UInt64 = 0
    private var schedulingTask: Task<Void, Never>?
    private var startupWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var startedSchedulingLoopCount = 0
    private var runningSchedulingLoopCount = 0
    private var currentPosition = MusicalPosition(absoluteSubdivision: 0)
    private var currentHostTime: TimeInterval = 0
    private var currentTempoBPM: Double = 60
    private var pendingTempoBPM: Double?
    private var tempoRamp: TempoRamp?
    private var harmonicCycleBars = 4

    init(
        clock: any DayObjectsTransportClock = HostTimeDayObjectsTransportClock(),
        eventHandler: EventHandler? = nil
    ) {
        self.clock = clock
        self.eventHandler = eventHandler
    }

    var snapshot: DayObjectsTransportSnapshot {
        DayObjectsTransportSnapshot(
            position: currentPosition,
            lifecycle: lifecycle,
            isRunning: lifecycle != .stopped,
            activeSchedulingTaskCount: runningSchedulingLoopCount,
            startedSchedulingLoopCount: startedSchedulingLoopCount,
            runningSchedulingLoopCount: runningSchedulingLoopCount,
            currentTempoBPM: currentTempoBPM,
            pendingTempoBPM: pendingTempoBPM
        )
    }

    func start(tempoBPM: Double, harmonicCycleBars: Int) async {
        guard lifecycle == .stopped else { return }

        generation &+= 1
        let runGeneration = generation
        lifecycle = .starting
        currentPosition = MusicalPosition(absoluteSubdivision: 0)
        currentHostTime = clock.now()
        currentTempoBPM = Self.validTempo(tempoBPM, fallback: 60)
        pendingTempoBPM = nil
        tempoRamp = nil
        self.harmonicCycleBars = max(1, harmonicCycleBars)

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runSchedulingLoop(generation: runGeneration)
        }
        schedulingTask = task

        await withCheckedContinuation { continuation in
            if generation != runGeneration || lifecycle != .starting {
                continuation.resume()
            } else {
                startupWaiters[runGeneration, default: []].append(continuation)
            }
        }
    }

    func stop() async {
        guard lifecycle != .stopped,
              let task = schedulingTask else { return }
        let stoppedGeneration = generation
        lifecycle = .stopping
        task.cancel()
        await task.value

        guard generation == stoppedGeneration,
              lifecycle == .stopping else { return }
        schedulingTask = nil
        lifecycle = .stopped
        resumeStartupWaiters(for: stoppedGeneration)
    }

    func setTempoBPM(_ tempoBPM: Double) {
        guard lifecycle == .starting || lifecycle == .running else { return }
        pendingTempoBPM = Self.validTempo(tempoBPM, fallback: currentTempoBPM)
    }

    private func runSchedulingLoop(generation runGeneration: UInt64) async {
        startedSchedulingLoopCount += 1
        runningSchedulingLoopCount += 1
        defer {
            runningSchedulingLoopCount -= 1
            resumeStartupWaiters(for: runGeneration)
            if generation == runGeneration, lifecycle != .stopping {
                schedulingTask = nil
                lifecycle = .stopped
            }
        }

        guard await emitEvents(
            at: currentPosition,
            hostTime: currentHostTime,
            nextSubdivisionHostTime: currentHostTime + 15 / tempoForFollowingInterval(),
            generation: runGeneration
        ), isActive(runGeneration) else { return }
        lifecycle = .running
        resumeStartupWaiters(for: runGeneration)

        while !Task.isCancelled {
            let intervalTempo = tempoForNextInterval()
            let intervalSeconds = 15 / intervalTempo
            let nextHostTime = currentHostTime + intervalSeconds

            do {
                try await clock.sleep(untilHostTime: nextHostTime)
            } catch {
                return
            }
            guard isActive(runGeneration) else { return }

            let nextPosition = MusicalPosition(
                absoluteSubdivision: currentPosition.absoluteSubdivision + 1
            )
            if nextPosition.subdivisionInBar == 0 {
                beginPendingTempoRampIfNeeded()
            }
            let followingHostTime = nextHostTime + 15 / tempoForFollowingInterval()
            guard await emitEvents(
                at: nextPosition,
                hostTime: nextHostTime,
                nextSubdivisionHostTime: followingHostTime,
                generation: runGeneration
            ), isActive(runGeneration) else { return }
            currentHostTime = nextHostTime
            currentPosition = nextPosition
        }
    }

    private func tempoForNextInterval() -> Double {
        guard var ramp = tempoRamp else { return currentTempoBPM }

        ramp.completedIntervals += 1
        let progress = Double(ramp.completedIntervals) / Double(MusicalPosition.subdivisionsPerBar)
        currentTempoBPM = ramp.startBPM + ((ramp.targetBPM - ramp.startBPM) * progress)

        if ramp.completedIntervals >= MusicalPosition.subdivisionsPerBar {
            currentTempoBPM = ramp.targetBPM
            tempoRamp = nil
        } else {
            tempoRamp = ramp
        }
        return currentTempoBPM
    }

    private func tempoForFollowingInterval() -> Double {
        guard let ramp = tempoRamp else { return currentTempoBPM }
        let followingCompletedIntervals = min(
            ramp.completedIntervals + 1,
            Int(MusicalPosition.subdivisionsPerBar)
        )
        let progress = Double(followingCompletedIntervals)
            / Double(MusicalPosition.subdivisionsPerBar)
        return ramp.startBPM + ((ramp.targetBPM - ramp.startBPM) * progress)
    }

    private func beginPendingTempoRampIfNeeded() {
        guard let targetBPM = pendingTempoBPM else { return }
        pendingTempoBPM = nil

        guard targetBPM != currentTempoBPM else {
            tempoRamp = nil
            return
        }
        tempoRamp = TempoRamp(
            startBPM: currentTempoBPM,
            targetBPM: targetBPM,
            completedIntervals: 0
        )
    }

    private func emitEvents(
        at position: MusicalPosition,
        hostTime: TimeInterval,
        nextSubdivisionHostTime: TimeInterval,
        generation runGeneration: UInt64
    ) async -> Bool {
        guard isActive(runGeneration) else { return false }
        guard let eventHandler else { return true }

        guard await emit(
            kind: .subdivision,
            at: position,
            hostTime: hostTime,
            nextSubdivisionHostTime: nextSubdivisionHostTime,
            generation: runGeneration,
            to: eventHandler
        ) else { return false }
        if position.subdivisionInBeat == 0 {
            guard await emit(
                kind: .beat,
                at: position,
                hostTime: hostTime,
                nextSubdivisionHostTime: nextSubdivisionHostTime,
                generation: runGeneration,
                to: eventHandler
            ) else { return false }
        }
        if position.subdivisionInBar == 0 {
            guard await emit(
                kind: .barBoundary,
                at: position,
                hostTime: hostTime,
                nextSubdivisionHostTime: nextSubdivisionHostTime,
                generation: runGeneration,
                to: eventHandler
            ) else { return false }
        }
        let subdivisionsPerCycle = Int64(harmonicCycleBars) * MusicalPosition.subdivisionsPerBar
        if position.absoluteSubdivision % subdivisionsPerCycle == 0 {
            guard await emit(
                kind: .harmonicCycleBoundary,
                at: position,
                hostTime: hostTime,
                nextSubdivisionHostTime: nextSubdivisionHostTime,
                generation: runGeneration,
                to: eventHandler
            ) else { return false }
        }
        return isActive(runGeneration)
    }

    private func emit(
        kind: DayObjectsTransportEventKind,
        at position: MusicalPosition,
        hostTime: TimeInterval,
        nextSubdivisionHostTime: TimeInterval,
        generation runGeneration: UInt64,
        to eventHandler: EventHandler
    ) async -> Bool {
        guard isActive(runGeneration) else { return false }
        await eventHandler(event(
            kind: kind,
            at: position,
            hostTime: hostTime,
            nextSubdivisionHostTime: nextSubdivisionHostTime
        ))
        return isActive(runGeneration)
    }

    private func event(
        kind: DayObjectsTransportEventKind,
        at position: MusicalPosition,
        hostTime: TimeInterval,
        nextSubdivisionHostTime: TimeInterval
    ) -> DayObjectsTransportEvent {
        DayObjectsTransportEvent(
            kind: kind,
            position: position,
            hostTimeSeconds: hostTime,
            tempoBPM: currentTempoBPM,
            nextSubdivisionHostTimeSeconds: nextSubdivisionHostTime
        )
    }

    private static func validTempo(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private func isActive(_ runGeneration: UInt64) -> Bool {
        guard generation == runGeneration, !Task.isCancelled else { return false }
        return lifecycle == .starting || lifecycle == .running
    }

    private func resumeStartupWaiters(for runGeneration: UInt64) {
        let waiters = startupWaiters.removeValue(forKey: runGeneration) ?? []
        waiters.forEach { $0.resume() }
    }
}
