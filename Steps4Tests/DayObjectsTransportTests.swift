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
}

private actor TransportEventRecorder {
    private(set) var events: [DayObjectsTransportEvent] = []

    func append(_ event: DayObjectsTransportEvent) {
        events.append(event)
    }
}
#endif
