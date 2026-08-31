#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsTransportSnapshot: Equatable, Sendable {
    let position: MusicalPosition
    let isRunning: Bool
    let activeSchedulingTaskCount: Int
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

    private var schedulingTask: Task<Void, Never>?
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
            isRunning: schedulingTask != nil,
            activeSchedulingTaskCount: schedulingTask == nil ? 0 : 1,
            currentTempoBPM: currentTempoBPM,
            pendingTempoBPM: pendingTempoBPM
        )
    }

    func start(tempoBPM: Double, harmonicCycleBars: Int) async {
        guard schedulingTask == nil else { return }

        currentPosition = MusicalPosition(absoluteSubdivision: 0)
        currentHostTime = clock.now()
        currentTempoBPM = Self.validTempo(tempoBPM, fallback: 60)
        pendingTempoBPM = nil
        tempoRamp = nil
        self.harmonicCycleBars = max(1, harmonicCycleBars)

        await emitEvents(at: currentPosition, hostTime: currentHostTime)
        schedulingTask = Task { [weak self] in
            await self?.runSchedulingLoop()
        }
    }

    func stop() async {
        guard let task = schedulingTask else { return }
        schedulingTask = nil
        task.cancel()
        await task.value
    }

    func setTempoBPM(_ tempoBPM: Double) {
        guard schedulingTask != nil else { return }
        pendingTempoBPM = Self.validTempo(tempoBPM, fallback: currentTempoBPM)
    }

    private func runSchedulingLoop() async {
        while !Task.isCancelled {
            let intervalTempo = tempoForNextInterval()
            let intervalSeconds = 15 / intervalTempo
            let nextHostTime = currentHostTime + intervalSeconds

            do {
                try await clock.sleep(untilHostTime: nextHostTime)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let nextPosition = MusicalPosition(
                absoluteSubdivision: currentPosition.absoluteSubdivision + 1
            )
            if nextPosition.subdivisionInBar == 0 {
                beginPendingTempoRampIfNeeded()
            }
            await emitEvents(at: nextPosition, hostTime: nextHostTime)
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

    private func emitEvents(at position: MusicalPosition, hostTime: TimeInterval) async {
        guard let eventHandler else { return }

        await eventHandler(event(kind: .subdivision, at: position, hostTime: hostTime))
        if position.subdivisionInBeat == 0 {
            await eventHandler(event(kind: .beat, at: position, hostTime: hostTime))
        }
        if position.subdivisionInBar == 0 {
            await eventHandler(event(kind: .barBoundary, at: position, hostTime: hostTime))
        }
        let subdivisionsPerCycle = Int64(harmonicCycleBars) * MusicalPosition.subdivisionsPerBar
        if position.absoluteSubdivision % subdivisionsPerCycle == 0 {
            await eventHandler(event(kind: .harmonicCycleBoundary, at: position, hostTime: hostTime))
        }
    }

    private func event(
        kind: DayObjectsTransportEventKind,
        at position: MusicalPosition,
        hostTime: TimeInterval
    ) -> DayObjectsTransportEvent {
        DayObjectsTransportEvent(
            kind: kind,
            position: position,
            hostTimeSeconds: hostTime,
            tempoBPM: currentTempoBPM
        )
    }

    private static func validTempo(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }
}
#endif
