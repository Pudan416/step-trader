import XCTest
@testable import Steps4

final class AmbientVoiceLeadingTests: XCTestCase {
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
