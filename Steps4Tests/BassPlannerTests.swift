import XCTest
@testable import Steps4

final class BassPlannerTests: XCTestCase {
    func testPercussionModePublishesNoBassPlan() {
        XCTAssertNil(makeBass(mode: .percussion, steps: 1))
    }

    func testEveryBassCandidateIsMonophonicInRangeAndSafeForItsChord() throws {
        for mode in [GrooveMode.bassPulse, .bassArp, .bassBed] {
            let plan = try XCTUnwrap(makeBass(mode: mode, steps: 1))

            XCTAssertTrue(plan.events.allSatisfy { (29...52).contains($0.midiNote) })
            XCTAssertEqual(Set(plan.events.map(\.startSubdivision)).count, plan.events.count)
            XCTAssertTrue(plan.events.allSatisfy { $0.durationSubdivisions > 0 })
            assertDoesNotOverlap(plan.events)
            for event in plan.events {
                XCTAssertTrue(event.allowedPitchClasses.contains(Int(event.midiNote) % 12))
            }
        }
    }

    func testIncreasingStepsOnlyActivatesAdditionalPreauthoredCandidates() throws {
        let low = try XCTUnwrap(makeBass(mode: .bassPulse, steps: 0.25))
        let full = try XCTUnwrap(makeBass(mode: .bassPulse, steps: 1))

        XCTAssertEqual(low.events.map(\.stableID), full.events.map(\.stableID))
        XCTAssertTrue(Set(low.activeEvents.map(\.stableID)).isSubset(of: Set(full.activeEvents.map(\.stableID))))
        XCTAssertEqual(makeBass(mode: .bassPulse, steps: 1), makeBass(mode: .bassPulse, steps: 9))
    }

    func testPulseCandidatesUseOnlyChordRootsAndFifths() throws {
        let world = makeWorld()
        let plan = try XCTUnwrap(makeBass(mode: .bassPulse, steps: 1))

        XCTAssertEqual(plan.articulation, .pulse)
        for event in plan.events {
            let root = world.progression[event.chordIndex].rootPitchClass
            XCTAssertTrue([root, (root + 7) % 12].contains(Int(event.midiNote) % 12))
        }
    }

    func testArpeggioLeavesRestsAndKeepsAdjacentJumpsWithinAnOctave() throws {
        let plan = try XCTUnwrap(makeBass(mode: .bassArp, steps: 1))

        XCTAssertEqual(plan.articulation, .arpeggio)
        XCTAssertTrue(zip(plan.events, plan.events.dropFirst()).contains {
            $1.startSubdivision > $0.startSubdivision + $0.durationSubdivisions
        })
        for pair in zip(plan.events, plan.events.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(Int(pair.1.midiNote) - Int(pair.0.midiNote)), 12)
        }
    }

    func testArpeggioCandidatesDoNotCrossTheirChordBoundaries() throws {
        let world = makeWorld()
        let plan = try XCTUnwrap(makeBass(mode: .bassArp, steps: 1))
        let chordEnds = world.progression.reduce(into: [Int64]()) { ends, chord in
            ends.append((ends.last ?? 0) + Int64(chord.durationBars * 16))
        }

        for event in plan.events {
            XCTAssertLessThanOrEqual(
                event.startSubdivision + event.durationSubdivisions,
                chordEnds[event.chordIndex]
            )
        }
    }

    func testBedEventsCoverExactlyTheirChordBoundariesWithoutOverlap() throws {
        let world = makeWorld()
        let plan = try XCTUnwrap(makeBass(mode: .bassBed, steps: 1))
        let chordStarts = world.progression.reduce(into: [Int64]()) { starts, chord in
            let previousEnd = starts.last.map { $0 + Int64(world.progression[starts.count - 1].durationBars * 16) } ?? 0
            starts.append(previousEnd)
        }

        XCTAssertEqual(plan.articulation, .sustained)
        XCTAssertEqual(plan.events.map(\.startSubdivision), chordStarts)
        XCTAssertEqual(
            plan.events.map(\.durationSubdivisions),
            world.progression.map { Int64($0.durationBars * 16) }
        )
        assertDoesNotOverlap(plan.events)
    }

    func testModeCompatibleInstrumentPreferencesAndApprovedFallbacksAreDeterministic() throws {
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors

        let pulse = try XCTUnwrap(makeBass(mode: .bassPulse, steps: 1, descriptors: descriptors))
        XCTAssertTrue(["bass.analog-boom", "bass.hey-jakob"].contains(pulse.instrumentID.rawValue))

        let arpeggio = try XCTUnwrap(makeBass(mode: .bassArp, steps: 1, descriptors: descriptors))
        XCTAssertEqual(arpeggio.instrumentID.rawValue, "bass.bb-roys-phaser")

        let bed = try XCTUnwrap(makeBass(mode: .bassBed, steps: 1, descriptors: descriptors))
        XCTAssertTrue(["bass.jec-hollores-2", "bass.hey-jakob"].contains(bed.instrumentID.rawValue))

        let onlyApprovedFallback = descriptors.filter { $0.id.rawValue == "bass.analog-boom" }
        XCTAssertEqual(
            BassPlanner.makePlan(
                input: makeInput(steps: 1),
                tonalWorld: makeWorld(),
                groove: makeGroove(mode: .bassArp),
                instrumentDescriptors: onlyApprovedFallback,
                remixSeed: 42
            )?.instrumentID.rawValue,
            "bass.analog-boom"
        )
        XCTAssertNil(makeBass(mode: .bassPulse, steps: 1, descriptors: []))
    }

    func testModeProfilesStayWithinTheirApprovedBounds() throws {
        let expected: [(GrooveMode, ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>)] = [
            (.bassPulse, 0...45, 0.03...0.08, 3.5...5, 2...6),
            (.bassArp, 15...70, 0.04...0.10, 3...4.5, 2...4),
            (.bassBed, 40...120, 0.02...0.06, 2.5...3.5, 16...256),
        ]

        for (mode, glide, reverb, duckDepth, duration) in expected {
            let plan = try XCTUnwrap(makeBass(mode: mode, steps: 1))
            XCTAssertTrue(glide.contains(plan.glideMilliseconds))
            XCTAssertTrue(reverb.contains(plan.reverbSend))
            XCTAssertTrue(duckDepth.contains(plan.ducking.maximumAttenuationDecibels))
            if mode != .bassBed {
                XCTAssertTrue(plan.events.allSatisfy { duration.contains(Double($0.durationSubdivisions)) })
            }
        }
    }

    private func makeBass(
        mode: GrooveMode,
        steps: Double,
        descriptors: [DayObjectsInstrumentDescriptor] = DayObjectsInstrumentManifest.defaultDescriptors
    ) -> BassPlan? {
        BassPlanner.makePlan(
            input: makeInput(steps: steps),
            tonalWorld: makeWorld(),
            groove: makeGroove(mode: mode),
            instrumentDescriptors: descriptors,
            remixSeed: 42
        )
    }

    private func makeInput(steps: Double) -> NormalizedDayMusicInput {
        DayMusicInput(
            countedSteps: steps * 10_000,
            stepGoal: 10_000,
            countedSleepHours: 8,
            sleepGoalHours: 8,
            happeningIDs: [],
            spentColors: 0
        ).normalized()
    }

    private func makeWorld() -> TonalWorldPlan {
        TonalWorldPlanner.makePlan(input: makeInput(steps: 1), remixSeed: 42)
    }

    private func makeGroove(mode: GrooveMode) -> GroovePlan {
        GroovePlan(
            mode: mode,
            auxiliaryRetention: mode == .percussion ? 1 : 0.5,
            maximumAnchorKicksPerBar: mode == .bassPulse ? 2 : 1,
            thinningSeed: 77
        )
    }

    private func assertDoesNotOverlap(_ events: [BassEventPlan], file: StaticString = #filePath, line: UInt = #line) {
        for pair in zip(events, events.dropFirst()) {
            XCTAssertLessThanOrEqual(
                pair.0.startSubdivision + pair.0.durationSubdivisions,
                pair.1.startSubdivision,
                file: file,
                line: line
            )
        }
    }
}
