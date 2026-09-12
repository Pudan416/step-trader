#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayObjectsTransportTests: XCTestCase {
    func testOrderedEventsUseSixteenSubdivisionsPerFourFourBar() async throws {
        let clock = ManualDayObjectsTransportClock()
        let recorder = TransportEventRecorder()
        let transport = DayObjectsTransport(clock: clock) { event in
            await recorder.append(event)
        }

        await transport.start(tempoBPM: 60, harmonicCycleBars: 2)
        clock.advance(to: 8)
        try await wait(for: MusicalPosition(absoluteSubdivision: 32), on: transport)

        let events = await recorder.events
        let atZero = events.filter { $0.position.absoluteSubdivision == 0 }
        XCTAssertEqual(atZero.map(\.kind), [
            .subdivision,
            .beat,
            .barBoundary,
            .harmonicCycleBoundary,
        ])

        let atSixteen = events.filter { $0.position.absoluteSubdivision == 16 }
        XCTAssertEqual(atSixteen.map(\.kind), [.subdivision, .beat, .barBoundary])

        let atThirtyTwo = events.filter { $0.position.absoluteSubdivision == 32 }
        XCTAssertEqual(atThirtyTwo.map(\.kind), [
            .subdivision,
            .beat,
            .barBoundary,
            .harmonicCycleBoundary,
        ])

        let subdivisions = events
            .filter { $0.kind == .subdivision }
            .map { $0.position.absoluteSubdivision }
        XCTAssertEqual(subdivisions, Array(0...32).map(Int64.init))
        XCTAssertEqual(events.filter { $0.kind == .beat }.map { $0.position.absoluteSubdivision },
                       [0, 4, 8, 12, 16, 20, 24, 28, 32])
        XCTAssertTrue(zip(events, events.dropFirst()).allSatisfy {
            $0.hostTimeSeconds <= $1.hostTimeSeconds
        })

        await transport.stop()
    }

    func testStartAndStopKeepExactlyOneSchedulingTaskAndStopIsIdempotent() async throws {
        let clock = ManualDayObjectsTransportClock()
        let recorder = TransportEventRecorder()
        let transport = DayObjectsTransport(clock: clock) { event in
            await recorder.append(event)
        }

        await transport.start(tempoBPM: 72, harmonicCycleBars: 4)
        await transport.start(tempoBPM: 96, harmonicCycleBars: 8)
        var snapshot = await transport.snapshot
        XCTAssertTrue(snapshot.isRunning)
        XCTAssertEqual(snapshot.activeSchedulingTaskCount, 1)

        await transport.stop()
        await transport.stop()
        snapshot = await transport.snapshot
        XCTAssertFalse(snapshot.isRunning)
        XCTAssertEqual(snapshot.activeSchedulingTaskCount, 0)

        let eventCountAfterStop = await recorder.events.count
        clock.advance(by: 1_000)
        for _ in 0..<20 { await Task.yield() }
        let finalEventCount = await recorder.events.count
        XCTAssertEqual(finalEventCount, eventCountAfterStop)
        XCTAssertEqual(clock.pendingWaiterCount, 0)
    }

    func testTempoChangeWaitsForNextBarThenRampsLinearlyForOneBar() async throws {
        let clock = ManualDayObjectsTransportClock()
        let recorder = TransportEventRecorder()
        let transport = DayObjectsTransport(clock: clock) { event in
            await recorder.append(event)
        }

        await transport.start(tempoBPM: 60, harmonicCycleBars: 4)
        clock.advance(to: 1.5)
        try await wait(for: MusicalPosition(absoluteSubdivision: 6), on: transport)
        await transport.setTempoBPM(100)

        clock.advance(to: 4)
        try await wait(for: MusicalPosition(absoluteSubdivision: 16), on: transport)
        var subdivisionEvents = await recorder.events.filter { $0.kind == .subdivision }
        XCTAssertEqual(subdivisionEvents[16].hostTimeSeconds, 4, accuracy: 0.000_000_001)
        XCTAssertEqual(subdivisionEvents[16].tempoBPM, 60, accuracy: 0.000_000_001)

        clock.advance(to: 8)
        try await wait(for: MusicalPosition(absoluteSubdivision: 32), on: transport)
        subdivisionEvents = await recorder.events.filter { $0.kind == .subdivision }
        let rampTempos = Array(subdivisionEvents[17...32].map(\.tempoBPM))
        XCTAssertEqual(rampTempos, stride(from: 62.5, through: 100, by: 2.5).map { $0 })
        for (current, following) in zip(subdivisionEvents, subdivisionEvents.dropFirst()) {
            XCTAssertEqual(
                current.nextSubdivisionHostTimeSeconds,
                following.hostTimeSeconds,
                accuracy: 0.000_000_001,
                "Transport lookahead must use the exact following interval during the tempo ramp"
            )
        }
        XCTAssertTrue(zip(subdivisionEvents, subdivisionEvents.dropFirst()).allSatisfy {
            $0.hostTimeSeconds < $1.hostTimeSeconds
        })
        let finalSnapshot = await transport.snapshot
        XCTAssertEqual(finalSnapshot.currentTempoBPM, 100, accuracy: 0.000_000_001)

        await transport.stop()
    }

    func testNewestPendingTempoTargetReplacesEarlierRequest() async throws {
        let clock = ManualDayObjectsTransportClock()
        let recorder = TransportEventRecorder()
        let transport = DayObjectsTransport(clock: clock) { event in
            await recorder.append(event)
        }

        await transport.start(tempoBPM: 60, harmonicCycleBars: 4)
        clock.advance(to: 1)
        try await wait(for: MusicalPosition(absoluteSubdivision: 4), on: transport)
        await transport.setTempoBPM(80)
        await transport.setTempoBPM(100)

        clock.advance(to: 8)
        try await wait(for: MusicalPosition(absoluteSubdivision: 32), on: transport)
        let subdivisionEvents = await recorder.events.filter { $0.kind == .subdivision }
        XCTAssertEqual(subdivisionEvents[17].tempoBPM, 62.5, accuracy: 0.000_000_001)
        XCTAssertEqual(subdivisionEvents[32].tempoBPM, 100, accuracy: 0.000_000_001)
        let finalSnapshot = await transport.snapshot
        XCTAssertNil(finalSnapshot.pendingTempoBPM)

        await transport.stop()
    }

    func testTenThousandBarsPreserveIntegerPositionWithoutTaskGrowth() async throws {
        let clock = ManualDayObjectsTransportClock()
        let transport = DayObjectsTransport(clock: clock)

        await transport.start(tempoBPM: 60, harmonicCycleBars: 4)
        clock.advance(to: 40)
        try await wait(for: MusicalPosition(absoluteSubdivision: 160), on: transport)
        await transport.setTempoBPM(90)

        // The pending change starts at subdivision 176. The sixteen ramp
        // intervals use 61.875 ... 90 BPM, then the remaining intervals use 90.
        let rampDuration = stride(from: 61.875, through: 90, by: 1.875)
            .reduce(0.0) { $0 + 15.0 / $1 }
        let targetHostTime = 44 + rampDuration + Double(160_000 - 192) / 6
        clock.advance(to: targetHostTime + 0.000_001)
        try await wait(
            for: MusicalPosition(absoluteSubdivision: 160_000),
            on: transport,
            maximumYields: 1_000_000
        )

        let snapshot = await transport.snapshot
        XCTAssertEqual(snapshot.position.absoluteSubdivision, 160_000)
        XCTAssertEqual(snapshot.position.bar, 10_000)
        XCTAssertEqual(snapshot.position.subdivisionInBar, 0)
        XCTAssertEqual(snapshot.activeSchedulingTaskCount, 1)
        XCTAssertTrue(snapshot.isRunning)

        await transport.stop()
        let stoppedSnapshot = await transport.snapshot
        XCTAssertEqual(stoppedSnapshot.activeSchedulingTaskCount, 0)
    }

    func testConcurrentAndReentrantStartsCreateOnlyOneActualSchedulingLoop() async throws {
        let clock = ManualDayObjectsTransportClock()
        let barrier = SuspendingEventBarrier()
        let reference = TransportReference()
        let transport = DayObjectsTransport(clock: clock) { event in
            guard event.kind == .subdivision,
                  event.position.absoluteSubdivision == 0 else { return }
            let arrival = await barrier.arriveAndSuspend()
            if arrival == 1 {
                await reference.start(tempoBPM: 96, harmonicCycleBars: 8)
            }
        }
        await reference.set(transport)

        let firstStart = Task {
            await transport.start(tempoBPM: 60, harmonicCycleBars: 4)
        }
        await barrier.waitForArrival(1)

        await transport.start(tempoBPM: 84, harmonicCycleBars: 6)
        let suspendedSnapshot = await transport.snapshot
        XCTAssertEqual(suspendedSnapshot.lifecycle, .starting)
        XCTAssertEqual(suspendedSnapshot.startedSchedulingLoopCount, 1)
        XCTAssertEqual(suspendedSnapshot.runningSchedulingLoopCount, 1)
        XCTAssertEqual(suspendedSnapshot.activeSchedulingTaskCount, 1)

        await barrier.releaseAll()
        await firstStart.value
        try await waitForPendingWaiters(1, on: clock)

        let runningSnapshot = await transport.snapshot
        XCTAssertEqual(runningSnapshot.lifecycle, .running)
        XCTAssertEqual(runningSnapshot.startedSchedulingLoopCount, 1)
        XCTAssertEqual(runningSnapshot.runningSchedulingLoopCount, 1)
        XCTAssertEqual(clock.pendingWaiterCount, 1)

        await transport.stop()
    }

    func testStopRetainsGenerationUntilJoinAndRejectsStaleCallbackUpdatesBeforeRestart() async throws {
        let clock = ManualDayObjectsTransportClock()
        let barrier = SuspendingEventBarrier()
        let recorder = TransportEventRecorder()
        let transport = DayObjectsTransport(clock: clock) { event in
            await recorder.append(event)
            if event.kind == .subdivision,
               event.position.absoluteSubdivision == 4 {
                _ = await barrier.arriveAndSuspend()
            }
        }

        await transport.start(tempoBPM: 60, harmonicCycleBars: 4)
        clock.advance(to: 1)
        await barrier.waitForArrival(1)
        let blockedSnapshot = await transport.snapshot
        XCTAssertEqual(blockedSnapshot.position.absoluteSubdivision, 3)

        let stopTask = Task { await transport.stop() }
        try await waitForLifecycle(.stopping, on: transport)
        let stoppingSnapshot = await transport.snapshot
        XCTAssertEqual(stoppingSnapshot.startedSchedulingLoopCount, 1)
        XCTAssertEqual(stoppingSnapshot.runningSchedulingLoopCount, 1)
        XCTAssertEqual(stoppingSnapshot.activeSchedulingTaskCount, 1)

        // A restart request during shutdown must not create another generation.
        await transport.start(tempoBPM: 90, harmonicCycleBars: 2)
        let rejectedRestartSnapshot = await transport.snapshot
        XCTAssertEqual(rejectedRestartSnapshot.startedSchedulingLoopCount, 1)

        await barrier.releaseAll()
        await stopTask.value

        let stoppedSnapshot = await transport.snapshot
        XCTAssertEqual(stoppedSnapshot.lifecycle, .stopped)
        XCTAssertEqual(stoppedSnapshot.position.absoluteSubdivision, 3)
        XCTAssertEqual(stoppedSnapshot.runningSchedulingLoopCount, 0)
        XCTAssertEqual(stoppedSnapshot.activeSchedulingTaskCount, 0)
        let oldBoundaryEvents = await recorder.events.filter {
            $0.position.absoluteSubdivision == 4
        }
        XCTAssertEqual(oldBoundaryEvents.map(\.kind), [.subdivision])

        await transport.start(tempoBPM: 90, harmonicCycleBars: 2)
        let restartedSnapshot = await transport.snapshot
        XCTAssertEqual(restartedSnapshot.lifecycle, .running)
        XCTAssertEqual(restartedSnapshot.position.absoluteSubdivision, 0)
        XCTAssertEqual(restartedSnapshot.startedSchedulingLoopCount, 2)
        XCTAssertEqual(restartedSnapshot.runningSchedulingLoopCount, 1)
        XCTAssertEqual(restartedSnapshot.activeSchedulingTaskCount, 1)

        for _ in 0..<100 { await Task.yield() }
        let settledRestartSnapshot = await transport.snapshot
        XCTAssertEqual(settledRestartSnapshot.position.absoluteSubdivision, 0)
        let finalOldBoundaryEvents = await recorder.events.filter {
            $0.position.absoluteSubdivision == 4
        }
        XCTAssertEqual(finalOldBoundaryEvents.map(\.kind), [.subdivision])

        await transport.stop()
    }

    private func wait(
        for position: MusicalPosition,
        on transport: DayObjectsTransport,
        maximumYields: Int = 20_000
    ) async throws {
        for _ in 0..<maximumYields {
            if await transport.snapshot.position >= position { return }
            await Task.yield()
        }
        XCTFail("Transport did not reach subdivision \(position.absoluteSubdivision)")
    }

    private func waitForLifecycle(
        _ lifecycle: DayObjectsTransportLifecycle,
        on transport: DayObjectsTransport,
        maximumYields: Int = 20_000
    ) async throws {
        for _ in 0..<maximumYields {
            if await transport.snapshot.lifecycle == lifecycle { return }
            await Task.yield()
        }
        XCTFail("Transport did not reach lifecycle \(lifecycle)")
    }

    private func waitForPendingWaiters(
        _ count: Int,
        on clock: ManualDayObjectsTransportClock,
        maximumYields: Int = 20_000
    ) async throws {
        for _ in 0..<maximumYields {
            if clock.pendingWaiterCount == count { return }
            await Task.yield()
        }
        XCTFail("Clock did not reach \(count) pending waiters")
    }
}

private actor TransportEventRecorder {
    private(set) var events: [DayObjectsTransportEvent] = []

    func append(_ event: DayObjectsTransportEvent) {
        events.append(event)
    }
}

private actor SuspendingEventBarrier {
    private var arrivalCount = 0
    private var isReleased = false
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func arriveAndSuspend() async -> Int {
        arrivalCount += 1
        let arrival = arrivalCount
        let readyWaiters = arrivalWaiters.filter { $0.count <= arrivalCount }
        arrivalWaiters.removeAll { $0.count <= arrivalCount }
        readyWaiters.forEach { $0.continuation.resume() }

        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return arrival
    }

    func waitForArrival(_ count: Int) async {
        guard arrivalCount < count else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append((count, continuation))
        }
    }

    func releaseAll() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor TransportReference {
    private var transport: DayObjectsTransport?

    func set(_ transport: DayObjectsTransport) {
        self.transport = transport
    }

    func start(tempoBPM: Double, harmonicCycleBars: Int) async {
        await transport?.start(tempoBPM: tempoBPM, harmonicCycleBars: harmonicCycleBars)
    }
}
#endif
