import XCTest
@testable import Steps4

final class BassPlannerTests: XCTestCase {
    func testWorldBassRoutesOnlyAvailableGroupRecipesAndKeepsHealthCandidates() throws {
        for world in DayObjectsSoundWorld.allCases {
            let full = WorldArrangementFixture.plan(world, .strange)
            let low = WorldArrangementFixture.plan(world, .strange, steps: 0)
            let bass = try XCTUnwrap(full.bass)
            let group = WorldArrangementFixture.group(world, .strange)
            let allowed = WorldArrangementFixture.runtimeIDs(group.bassRecipeIDs, mood: .strange)
            XCTAssertTrue(allowed.contains(bass.instrumentID))
            XCTAssertEqual(low.bass?.events, bass.events)
            XCTAssertEqual(low.bass?.activeEvents.count, 0)
            let remaining = WorldArrangementFixture.catalog.descriptors.filter { $0.id != bass.instrumentID }
            let fallback = WorldArrangementFixture.plan(world, .strange, descriptors: remaining)
            XCTAssertTrue(allowed.contains(try XCTUnwrap(fallback.bass).instrumentID))
            XCTAssertNotEqual(fallback.bass?.instrumentID, bass.instrumentID)
        }
    }
    func testPercussionModePublishesNoBassPlan() {
        XCTAssertNil(makeBass(mode: .percussion, steps: 1))
    }

    func testEveryBassCandidateIsMonophonicInRangeAndSafeForItsChord() throws {
        for mode in [GrooveMode.bassPulse, .bassArp, .bassBed] {
            let plan = try XCTUnwrap(makeBass(mode: mode, steps: 1))

            XCTAssertEqual(plan.register, 24...40)
            XCTAssertTrue(plan.events.allSatisfy { (24...40).contains($0.midiNote) })
            XCTAssertEqual(Set(plan.events.map(\.startSubdivision)).count, plan.events.count)
            XCTAssertTrue(plan.events.allSatisfy { $0.durationSubdivisions > 0 })
            for event in plan.events {
                XCTAssertTrue(event.allowedPitchClasses.contains(Int(event.midiNote) % 12))
            }
        }
    }

    func testSoundWorldShapesBassProcessingWithoutChangingItsNotes() throws {
        let felt = try XCTUnwrap(makeBass(mode: .bassBed, steps: 1, soundWorld: .feltAndWood))
        let metal = try XCTUnwrap(makeBass(mode: .bassBed, steps: 1, soundWorld: .metalAndCurrent))

        XCTAssertEqual(felt.events, metal.events)
        XCTAssertLessThan(felt.cutoffMultiplier, metal.cutoffMultiplier)
        XCTAssertGreaterThan(felt.glideMilliseconds, metal.glideMilliseconds)
        XCTAssertGreaterThan(felt.reverbSend, metal.reverbSend)
    }

    func testBassKeepsItsAuthoredPitchClassWhileStartingInTheLowerOctave() throws {
        let plan = try XCTUnwrap(makeBass(mode: .bassPulse, steps: 1))
        let first = try XCTUnwrap(plan.events.first)

        XCTAssertEqual(first.midiNote, 31)
        XCTAssertEqual(Int(first.midiNote) % 12, 7)
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

    func testMovingBassUsesSlowTransitionsAndKeepsAdjacentJumpsWithinAnOctave() throws {
        let plan = try XCTUnwrap(makeBass(mode: .bassArp, steps: 1))

        XCTAssertEqual(plan.articulation, .arpeggio)
        XCTAssertTrue(plan.events.allSatisfy { $0.durationSubdivisions >= 16 })
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

    func testArpeggioAddsAtMostOneMidChordTransitionThatLastsToTheBoundary() throws {
        let world = try makeWorld(progressionLength: 3, cycleBars: 16)
        let plan = try XCTUnwrap(makeBass(mode: .bassArp, steps: 1, tonalWorld: world))
        var chordStart: Int64 = 0

        for (index, chord) in world.progression.enumerated() {
            let chordDuration = Int64(chord.durationBars * 16)
            let chordEvents = plan.events.filter { $0.chordIndex == index }
            XCTAssertEqual(chordEvents.map(\.startSubdivision), [
                chordStart,
                chordStart + chordDuration / 2,
            ])
            XCTAssertEqual(chordEvents.map(\.durationSubdivisions), [
                chordDuration,
                chordDuration - chordDuration / 2,
            ])
            chordStart += chordDuration
        }
    }

    func testPartialStepsKeepOneStructuralBassNoteAliveForEveryWholeChord() throws {
        let world = try makeWorld(progressionLength: 4, cycleBars: 12)

        for mode in [GrooveMode.bassPulse, .bassArp, .bassBed] {
            let plan = try XCTUnwrap(makeBass(mode: mode, steps: 0.25, tonalWorld: world))
            var chordStart: Int64 = 0
            for (index, chord) in world.progression.enumerated() {
                let chordDuration = Int64(chord.durationBars * 16)
                let active = plan.activeEvents.filter { $0.chordIndex == index }
                XCTAssertEqual(active.map(\.startSubdivision), [chordStart])
                XCTAssertEqual(active.map(\.durationSubdivisions), [chordDuration])
                chordStart += chordDuration
            }
        }
    }

    func testEverySupportedWorldShapeKeepsCandidatesStableAndPartialStepsCycleWide() throws {
        for progressionLength in 1...4 {
            for cycleBars in [8, 12, 16] {
                let world = try makeWorld(
                    progressionLength: progressionLength,
                    cycleBars: cycleBars
                )
                let expectedChordIndexes = Set(world.progression.indices)

                for mode in [GrooveMode.bassPulse, .bassArp, .bassBed] {
                    let partial = try XCTUnwrap(makeBass(
                        mode: mode,
                        steps: 0.25,
                        tonalWorld: world
                    ))
                    let full = try XCTUnwrap(makeBass(
                        mode: mode,
                        steps: 1,
                        tonalWorld: world
                    ))

                    XCTAssertEqual(partial.events, full.events)
                    XCTAssertEqual(Set(partial.activeEvents.map(\.chordIndex)), expectedChordIndexes)

                    switch mode {
                    case .bassPulse:
                        XCTAssertTrue(full.events.allSatisfy { $0.durationSubdivisions >= 16 })
                    case .bassArp:
                        XCTAssertTrue(full.events.allSatisfy { $0.durationSubdivisions >= 16 })
                    case .bassBed:
                        XCTAssertEqual(partial.activeEvents.count, world.progression.count)
                    case .percussion:
                        XCTFail("Percussion does not create Bass candidates")
                    }
                }
            }
        }
    }

    func testPartialPulseAndArpeggioPreferOneChordAnchorBeforeExtraCandidates() throws {
        let world = try makeWorld(progressionLength: 4, cycleBars: 8)
        var chordStarts: [Int64] = []
        var nextChordStart: Int64 = 0
        for chord in world.progression {
            chordStarts.append(nextChordStart)
            nextChordStart += Int64(chord.durationBars * 16)
        }

        for mode in [GrooveMode.bassPulse, .bassArp] {
            let partial = try XCTUnwrap(makeBass(mode: mode, steps: 0.25, tonalWorld: world))
            let full = try XCTUnwrap(makeBass(mode: mode, steps: 1, tonalWorld: world))

            XCTAssertEqual(partial.activeEvents.count, world.progression.count)
            XCTAssertGreaterThan(full.events.count, partial.activeEvents.count)
            for chordIndex in world.progression.indices {
                let anchors = partial.activeEvents.filter { $0.chordIndex == chordIndex }
                XCTAssertEqual(anchors.map(\.startSubdivision), [chordStarts[chordIndex]])
            }
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
        XCTAssertEqual(arpeggio.instrumentID.rawValue, "bass.bassliner")

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
            (.bassPulse, 80...220, 0.05...0.12, 3.5...5, 16...256),
            (.bassArp, 120...360, 0.06...0.14, 3...4.5, 16...256),
            (.bassBed, 160...420, 0.05...0.12, 2.5...3.5, 16...256),
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
        tonalWorld: TonalWorldPlan? = nil,
        descriptors: [DayObjectsInstrumentDescriptor] = DayObjectsInstrumentManifest.defaultDescriptors,
        soundWorld: DayObjectsSoundWorld? = nil
    ) -> BassPlan? {
        BassPlanner.makePlan(
            input: makeInput(steps: steps),
            tonalWorld: tonalWorld ?? makeWorld(),
            groove: makeGroove(mode: mode),
            instrumentDescriptors: descriptors,
            remixSeed: 42,
            soundWorld: soundWorld
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

    private func makeWorld(progressionLength: Int, cycleBars: Int) throws -> TonalWorldPlan {
        try XCTUnwrap(TonalWorldPlanner.makePlan(
            centerPitchClass: 0,
            mode: .dorian,
            progressionLength: progressionLength,
            cycleBars: cycleBars
        ))
    }

    private func makeGroove(mode: GrooveMode) -> GroovePlan {
        GroovePlan(
            mode: mode,
            auxiliaryRetention: mode == .percussion ? 1 : 0.5,
            maximumAnchorKicksPerBar: mode == .bassPulse ? 2 : 1,
            thinningSeed: 77
        )
    }

    private func assertDoesNotOverlap(
        _ events: [BassEventPlan],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (current, next) in zip(events, events.dropFirst()) {
            XCTAssertLessThanOrEqual(
                current.startSubdivision + current.durationSubdivisions,
                next.startSubdivision,
                file: file,
                line: line
            )
        }
    }

}
