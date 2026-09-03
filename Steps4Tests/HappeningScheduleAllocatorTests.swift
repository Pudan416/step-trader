import XCTest
@testable import Steps4

final class HappeningScheduleAllocatorTests: XCTestCase {
    func testCountsZeroThroughTenUseExactBandsAndGuaranteeFirstCycleAndNoStarvation() throws {
        let expectedBands: [ClosedRange<Int>] = [
            6...10, 6...10,
            14...24, 14...24, 14...24, 14...24,
            28...48, 28...48, 28...48, 28...48
        ]

        for count in 0...10 {
            for seed in seeds {
                let plans = makePlans(count: count, seed: seed)
                let allocation = HappeningScheduleAllocator.allocate(
                    plans: plans,
                    remixSeed: seed,
                    cycleCount: 4
                )

                if count == 0 {
                    XCTAssertEqual(allocation.cycleBars, 0)
                    XCTAssertTrue(allocation.events.isEmpty)
                    XCTAssertTrue(allocation.nextCursors.isEmpty)
                    continue
                }

                let band = expectedBands[count - 1]
                XCTAssertEqual(allocation.intervalBandBars, band)
                XCTAssertEqual(allocation.cycleBars, band.upperBound)
                for plan in plans {
                    let events = allocation.events
                        .filter { $0.happeningID == plan.happeningID }
                        .sorted { $0.sequenceIndex < $1.sequenceIndex }
                    let cursor = try XCTUnwrap(
                        allocation.nextCursors.first { $0.happeningID == plan.happeningID }
                    )
                    let first = try XCTUnwrap(events.first)
                    XCTAssertLessThan(first.startBeat, Double(allocation.cycleBars * allocation.beatsPerBar))
                    XCTAssertTrue(events.allSatisfy { band.contains($0.intervalBars) })
                    XCTAssertEqual(events.map(\.sequenceIndex), Array(0..<events.count))
                    XCTAssertEqual(cursor.nextSequenceIndex, events.count)
                    for pair in zip(events, events.dropFirst()) {
                        XCTAssertGreaterThanOrEqual(
                            pair.1.startBeat - pair.0.startBeat,
                            Double(band.lowerBound * allocation.beatsPerBar) - 0.000_001
                        )
                        XCTAssertLessThanOrEqual(
                            pair.1.startBeat - pair.0.startBeat,
                            Double(band.upperBound * allocation.beatsPerBar) + 0.000_001
                        )
                    }
                    XCTAssertLessThanOrEqual(
                        Double(allocation.horizonBars * allocation.beatsPerBar)
                            - (try XCTUnwrap(events.last)).startBeat,
                        Double(band.upperBound * allocation.beatsPerBar) + 0.000_001
                    )
                }
            }
        }
    }

    func testAlignmentQuotaFloatingBoundsAndCollisionCapsHoldForAllCountsAndSeeds() {
        for count in 1...10 {
            for seed in seeds {
                let allocation = HappeningScheduleAllocator.allocate(
                    plans: makePlans(count: count, seed: seed),
                    remixSeed: seed,
                    cycleCount: 4
                )
                let firstByID = Dictionary(
                    grouping: allocation.events,
                    by: \.happeningID
                ).compactMapValues(\.first)
                let gridCount = firstByID.values.filter { $0.alignment == .gridAligned }.count
                let lower = Int(ceil(Double(count) * 0.35))
                let upper = Int(floor(Double(count) * 0.60))
                if lower <= upper {
                    XCTAssertTrue((lower...upper).contains(gridCount), "count=\(count), seed=\(seed)")
                }

                for event in allocation.events {
                    let distanceToGrid = abs(event.startBeat - event.startBeat.rounded())
                    switch event.alignment {
                    case .gridAligned:
                        XCTAssertEqual(distanceToGrid, 0, accuracy: 0.000_001)
                    case .floating:
                        XCTAssertGreaterThan(distanceToGrid, 0)
                        XCTAssertLessThanOrEqual(distanceToGrid, 0.5 + 0.000_001)
                    }
                }

                let ordered = allocation.events.sorted { $0.startBeat < $1.startBeat }
                for pair in zip(ordered, ordered.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(
                        pair.1.startBeat - pair.0.startBeat,
                        0.25 - 0.000_001,
                        "count=\(count), seed=\(seed)"
                    )
                }
                let attacksByBeat = Dictionary(grouping: allocation.events) {
                    Int(floor($0.startBeat))
                }
                XCTAssertTrue(attacksByBeat.values.allSatisfy { $0.count <= 2 })
            }
        }
    }

    func testCandidateStreamsCanUseBothEndpointsOfEveryDeclaredIntervalBand() {
        let representatives: [(count: Int, band: ClosedRange<Int>)] = [
            (1, 6...10),
            (3, 14...24),
            (7, 28...48)
        ]

        for representative in representatives {
            var observed: Set<Int> = []
            for seed in UInt64(0)..<128 {
                let allocation = HappeningScheduleAllocator.allocate(
                    plans: makePlans(count: representative.count, seed: seed),
                    remixSeed: seed,
                    cycleCount: 4
                )
                observed.formUnion(allocation.events.map(\.intervalBars))
            }
            XCTAssertTrue(observed.contains(representative.band.lowerBound))
            XCTAssertTrue(observed.contains(representative.band.upperBound))
        }
    }

    func testSeed2159DoesNotDropSequenceIndicesOrStarveTheTail() throws {
        let allocation = HappeningScheduleAllocator.allocate(
            plans: makePlans(count: 3, seed: 2_159),
            remixSeed: 2_159,
            cycleCount: 4
        )
        let maximumGap = Double(24 * allocation.beatsPerBar)
        let horizonBeat = Double(allocation.horizonBars * allocation.beatsPerBar)

        for cursor in allocation.nextCursors {
            let events = allocation.events
                .filter { $0.happeningID == cursor.happeningID }
                .sorted { $0.sequenceIndex < $1.sequenceIndex }
            XCTAssertEqual(events.map(\.sequenceIndex), Array(0..<events.count))
            XCTAssertEqual(cursor.nextSequenceIndex, events.count)
            let last = try XCTUnwrap(events.last)
            XCTAssertLessThanOrEqual(horizonBeat - last.startBeat, maximumGap)
        }
    }

    func testSeed6052KeepsActualPostCollisionGapsInsideBothBandEndpoints() {
        let allocation = HappeningScheduleAllocator.allocate(
            plans: makePlans(count: 4, seed: 6_052),
            remixSeed: 6_052,
            cycleCount: 4
        )
        let minimumGap = Double(14 * allocation.beatsPerBar)
        let maximumGap = Double(24 * allocation.beatsPerBar)

        for events in Dictionary(grouping: allocation.events, by: \.happeningID).values {
            let ordered = events.sorted { $0.sequenceIndex < $1.sequenceIndex }
            for pair in zip(ordered, ordered.dropFirst()) {
                let actualGap = pair.1.startBeat - pair.0.startBeat
                XCTAssertGreaterThanOrEqual(actualGap, minimumGap)
                XCTAssertLessThanOrEqual(actualGap, maximumGap)
            }
        }
    }

    func testSeed9088SingleCycleNeverCollapsesToTotalStarvation() throws {
        let plans = makePlans(count: 3, seed: 9_088)
        let allocation = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: 9_088,
            cycleCount: 1,
            beatsPerBar: 4
        )

        XCTAssertEqual(allocation.cycleBars, 24)
        XCTAssertEqual(Set(allocation.events.map(\.happeningID)), Set(plans.map(\.happeningID)))
        XCTAssertEqual(allocation.nextCursors.count, plans.count)
        for plan in plans {
            let events = allocation.events
                .filter { $0.happeningID == plan.happeningID }
                .sorted { $0.sequenceIndex < $1.sequenceIndex }
            XCTAssertFalse(events.isEmpty)
            XCTAssertEqual(events.map(\.sequenceIndex), Array(0..<events.count))
            for pair in zip(events, events.dropFirst()) {
                XCTAssertTrue((56.0...96.0).contains(pair.1.startBeat - pair.0.startBeat))
            }
            XCTAssertLessThan(try XCTUnwrap(events.first).startBeat, 96)
            XCTAssertLessThanOrEqual(96 - (try XCTUnwrap(events.last)).startBeat, 96)
        }
    }

    func testAcceptedCycleAndBeatBoundariesAlwaysProduceCompleteSchedules() throws {
        for count in 1...10 {
            for seed in seeds {
                for cycleCount in [1, 16] {
                    for beatsPerBar in [1, 16] {
                        let plans = makePlans(count: count, seed: seed)
                        let allocation = HappeningScheduleAllocator.allocate(
                            plans: plans,
                            remixSeed: seed,
                            cycleCount: cycleCount,
                            beatsPerBar: beatsPerBar
                        )
                        let band = try XCTUnwrap(allocation.intervalBandBars)
                        let horizonBeat = Double(allocation.horizonBars * beatsPerBar)

                        XCTAssertEqual(Set(allocation.events.map(\.happeningID)), Set(plans.map(\.happeningID)))
                        XCTAssertEqual(allocation.nextCursors.count, plans.count)
                        let ordered = allocation.events.sorted { $0.startBeat < $1.startBeat }
                        for pair in zip(ordered, ordered.dropFirst()) {
                            XCTAssertGreaterThanOrEqual(
                                pair.1.startBeat - pair.0.startBeat,
                                0.25 - 0.000_001,
                                "count=\(count), seed=\(seed), cycles=\(cycleCount), beats=\(beatsPerBar)"
                            )
                        }
                        let attacksByBeat = Dictionary(grouping: allocation.events) {
                            Int(floor($0.startBeat))
                        }
                        XCTAssertTrue(attacksByBeat.values.allSatisfy { $0.count <= 2 })
                        for event in allocation.events {
                            let distanceToGrid = abs(event.startBeat - event.startBeat.rounded())
                            switch event.alignment {
                            case .gridAligned:
                                XCTAssertEqual(distanceToGrid, 0, accuracy: 0.000_001)
                            case .floating:
                                XCTAssertGreaterThan(distanceToGrid, 0)
                                XCTAssertLessThanOrEqual(distanceToGrid, 0.5 + 0.000_001)
                            }
                        }
                        for plan in plans {
                            let events = allocation.events
                                .filter { $0.happeningID == plan.happeningID }
                                .sorted { $0.sequenceIndex < $1.sequenceIndex }
                            XCTAssertEqual(events.map(\.sequenceIndex), Array(0..<events.count))
                            XCTAssertFalse(events.isEmpty)
                            XCTAssertLessThan(
                                try XCTUnwrap(events.first).startBeat,
                                Double(allocation.cycleBars * beatsPerBar)
                            )
                            for pair in zip(events, events.dropFirst()) {
                                let gap = pair.1.startBeat - pair.0.startBeat
                                XCTAssertGreaterThanOrEqual(gap, Double(band.lowerBound * beatsPerBar))
                                XCTAssertLessThanOrEqual(gap, Double(band.upperBound * beatsPerBar))
                            }
                            XCTAssertLessThanOrEqual(
                                horizonBeat - (try XCTUnwrap(events.last)).startBeat,
                                Double(band.upperBound * beatsPerBar)
                            )
                        }
                    }
                }
            }
        }
    }

    func testOversizedPublicHorizonInputsAreRejectedBeforeAllocation() {
        let plans = makePlans(count: 10, seed: 42)
        let tooManyCycles = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: 42,
            cycleCount: 17,
            beatsPerBar: 4
        )
        let tooManyBeats = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: 42,
            cycleCount: 4,
            beatsPerBar: 17
        )
        let overflowingCycles = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: 42,
            cycleCount: .max,
            beatsPerBar: 4
        )
        let overflowingBeats = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: 42,
            cycleCount: 4,
            beatsPerBar: .max
        )

        for rejected in [tooManyCycles, tooManyBeats, overflowingCycles, overflowingBeats] {
            XCTAssertEqual(rejected.cycleBars, 0)
            XCTAssertEqual(rejected.horizonBars, 0)
            XCTAssertNil(rejected.intervalBandBars)
            XCTAssertTrue(rejected.events.isEmpty)
            XCTAssertTrue(rejected.nextCursors.isEmpty)
        }
    }

    func testAllocationIsRepeatableAndLongerHorizonPreservesPublishedPrefixState() {
        let plans = makePlans(count: 10, seed: seeds[0])
        let short = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: seeds[0],
            cycleCount: 2
        )
        let repeated = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: seeds[0],
            cycleCount: 2
        )
        let long = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: seeds[0],
            cycleCount: 4
        )

        XCTAssertEqual(short, repeated)
        XCTAssertEqual(
            short.events,
            long.events.filter { $0.startBeat < Double(short.horizonBars * short.beatsPerBar) }
        )
        XCTAssertEqual(short.nextCursors.count, plans.count)
        XCTAssertTrue(short.nextCursors.allSatisfy {
            $0.nextSequenceIndex > 0 && $0.nextCandidateBeat.isFinite
        })
    }

    func testCollisionMovementNeverChangesMusicalIdentity() {
        let plans = makePlans(count: 10, seed: seeds[1])
        let allocation = HappeningScheduleAllocator.allocate(
            plans: plans,
            remixSeed: seeds[1],
            cycleCount: 3
        )

        XCTAssertEqual(Set(allocation.events.map(\.happeningID)), Set(plans.map(\.happeningID)))
        XCTAssertEqual(plans, makePlans(count: 10, seed: seeds[1]))
    }

    private let seeds: [UInt64] = [0, 1, 0xD4A0_B1EC_75ED_0001, UInt64.max]

    private func makePlans(count: Int, seed: UInt64) -> [HappeningMusicPlan] {
        let ids = (0..<count).map { "event-\($0)" }
        let input = NormalizedDayMusicInput(
            stepsProgress: 0.61,
            sleepProgress: 0.74,
            happeningIDs: ids,
            glitchProgress: 0.31,
            motionEnergy: 0.625,
            visualClarity: 0.625,
            diagnostics: []
        )
        return HappeningMusicPlanner.makePlans(
            input: input,
            tonalWorld: TonalWorldPlanner.makePlan(input: input, remixSeed: seed),
            remixSeed: seed
        )
    }
}
