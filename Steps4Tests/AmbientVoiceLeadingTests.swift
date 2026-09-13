import XCTest
@testable import Steps4

final class AmbientVoiceLeadingTests: XCTestCase {
    func testLivingFieldVoicingsAreWiderThanEveryOtherWorldForIdenticalChordTones() {
        let fixtures: [(DayObjectsSoundMood, [Int])] = [
            (.sparse, [0, 7]), (.moving, [0, 7]), (.strange, [0, 7, 9])
        ]
        for (mood, intervals) in fixtures {
            for center in [0, 2, 4, 5, 7, 9] {
                let pitchClasses = intervals.map { (center + $0) % 12 }
                // Hold a sufficiently wide register fixed to isolate spacing;
                // every transposed fifth needs room for more than 19 semitones.
                for register: ClosedRange<UInt8>? in [nil, 48...84] {
                    for previous: [UInt8]? in [nil, intervals.map { UInt8(48 + $0) }] {
                        let living = AmbientVoiceLeading.nearestVoicing(
                            chordPitchClasses: pitchClasses, previousNotes: previous,
                            world: .livingField, mood: mood, register: register
                        )
                        XCTAssertEqual(living.count, intervals.count)
                        let livingSpan = Int(living.last ?? 0) - Int(living.first ?? 0)
                        for world in [DayObjectsSoundWorld.feltAndWood, .metalAndCurrent, .electricDream] {
                            let other = AmbientVoiceLeading.nearestVoicing(
                                chordPitchClasses: pitchClasses, previousNotes: previous,
                                world: world, mood: mood, register: register
                            )
                            XCTAssertEqual(other.count, intervals.count)
                            XCTAssertGreaterThan(
                                livingSpan, Int(other.last ?? 0) - Int(other.first ?? 0),
                                "Living must be wider than \(world), \(mood), center \(center)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testWorldVoicingsExpressCloseOpenDroneAndMovingInversions() {
        let acoustic = AmbientVoiceLeading.nearestVoicing(chordPitchClasses: [0, 7, 2], previousNotes: nil, world: .feltAndWood, mood: .moving)
        XCTAssertEqual(acoustic.count, 3)
        XCTAssertLessThanOrEqual(Int(acoustic.last ?? 0) - Int(acoustic.first ?? 0), 12)
        let living = AmbientVoiceLeading.nearestVoicing(chordPitchClasses: [0, 7, 9], previousNotes: nil, world: .livingField, mood: .moving)
        XCTAssertGreaterThanOrEqual(Int(living.last ?? 0) - Int(living.first ?? 0), 12)
        XCTAssertTrue(zip(living, living.dropFirst()).allSatisfy { Int($1) - Int($0) >= 5 })
        let industrial = AmbientVoiceLeading.nearestVoicing(chordPitchClasses: [0, 7, 8], previousNotes: nil, world: .metalAndCurrent, mood: .strange)
        XCTAssertEqual(industrial, [36, 55, 56])
        let electric = AmbientVoiceLeading.nearestVoicing(chordPitchClasses: [0, 7, 10, 2], previousNotes: nil, world: .electricDream, mood: .moving)
        let inverted = AmbientVoiceLeading.nearestVoicing(chordPitchClasses: [0, 7, 10, 2], previousNotes: electric, world: .electricDream, mood: .moving, chordIndex: 1)
        XCTAssertEqual(Set(electric.map { Int($0) % 12 }), [0, 7, 10, 2])
        XCTAssertNotEqual(electric.first.map { Int($0) % 12 }, inverted.first.map { Int($0) % 12 })
    }

    func testCandidatesStayInRegisterUseEveryChordToneAndRemainAscending() {
        let candidates = AmbientVoiceLeading.candidates(
            chordPitchClasses: [0, 4, 7],
            register: 48...72,
            voiceCount: 3
        )

        XCTAssertFalse(candidates.isEmpty)
        for candidate in candidates {
            XCTAssertEqual(candidate.count, 3)
            XCTAssertTrue(candidate.allSatisfy { (48...72).contains($0) })
            XCTAssertEqual(Set(candidate.map { Int($0) % 12 }), [0, 4, 7])
            XCTAssertEqual(candidate, candidate.sorted())
        }
    }

    func testNearestVoicingMinimizesTotalSemitoneMovement() {
        let selected = AmbientVoiceLeading.nearestVoicing(
            chordPitchClasses: [0, 5, 9],
            previousNotes: [52, 55, 60],
            register: 48...72,
            voiceCount: 3
        )

        XCTAssertEqual(selected, [53, 57, 60])
    }

    func testTiedMovementPrefersTheLowerMaximumNote() {
        let selected = AmbientVoiceLeading.nearestVoicing(
            chordPitchClasses: [0],
            previousNotes: [54],
            register: 48...60,
            voiceCount: 1
        )

        XCTAssertEqual(selected, [48])
    }

    func testDyadsMayRepeatNotesToFillTheConfiguredVoiceCount() {
        let selected = AmbientVoiceLeading.nearestVoicing(
            chordPitchClasses: [0, 7],
            previousNotes: nil,
            register: 48...60,
            voiceCount: 3
        )

        XCTAssertEqual(selected, [48, 48, 55])
    }

    func testSearchRejectsVoiceCountsBeyondTheAmbientBoundBeforeEnumeration() {
        XCTAssertEqual(
            AmbientVoiceLeading.candidates(
                chordPitchClasses: [0],
                register: 48...60,
                voiceCount: 5
            ),
            []
        )
        XCTAssertEqual(
            AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: [0, 4, 7],
                previousNotes: nil,
                register: 48...72,
                voiceCount: 5
            ),
            []
        )
    }

    func testSearchHandlesTheLowestAndHighestMIDIBoundsWithoutOverflow() {
        XCTAssertEqual(
            AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: [0, 11],
                previousNotes: nil,
                register: 0...11,
                voiceCount: 2
            ),
            [0, 11]
        )
        XCTAssertEqual(
            AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: [0, 7],
                previousNotes: nil,
                register: 120...127,
                voiceCount: 2
            ),
            [120, 127]
        )
    }

    func testPitchClassesNormalizeAndImpossibleSearchesReturnNoVoicing() {
        XCTAssertEqual(
            AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: [-12, 19],
                previousNotes: nil,
                register: 0...11,
                voiceCount: 2
            ),
            [0, 7]
        )
        XCTAssertEqual(
            AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: [0, 7],
                previousNotes: nil,
                register: 1...6,
                voiceCount: 2
            ),
            []
        )
        XCTAssertEqual(
            AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: [],
                previousNotes: nil,
                register: 0...127,
                voiceCount: 3
            ),
            []
        )
    }
}
