#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class HappeningPitchResolverTests: XCTestCase {
    func testMotifResolvesToNearestChordOrDeclaredPassingToneInsideRequestedOctave() {
        let world = makeWorld(mode: .dorian, center: 2)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 2,
            chordPitchClasses: [2, 5, 9],
            safePassingPitchClasses: [0, 4],
            voicedMIDINotes: [50, 53, 57],
            durationBars: 4
        )

        XCTAssertEqual(
            HappeningPitchResolver.resolve(
                motifScaleDegrees: [0, 2, 3, 5, 7, 9, 10],
                octave: 4,
                tonalWorld: world,
                chord: chord
            ),
            [62, 64, 65, 65, 69, 72, 72]
        )
    }

    func testEqualDistanceTieBreaksTowardTheLowerCompatibleMIDINote() {
        let world = makeWorld(mode: .majorPentatonic, center: 0)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 0,
            chordPitchClasses: [0, 4],
            safePassingPitchClasses: [],
            voicedMIDINotes: [60, 64],
            durationBars: 4
        )

        XCTAssertEqual(
            HappeningPitchResolver.resolve(
                motifScaleDegrees: [2],
                octave: 4,
                tonalWorld: world,
                chord: chord
            ),
            [60]
        )
    }

    func testEveryModeAndChordProducesOnlySafeMIDINotesAndAllowedPitchClasses() {
        for mode in DayMusicMode.allCases {
            let world = makeWorld(mode: mode, center: 11)
            for chord in world.progression {
                for octave in [-20, 3, 4, 5, 6, 40] {
                    let notes = HappeningPitchResolver.resolve(
                        motifScaleDegrees: mode.scaleIntervals,
                        octave: octave,
                        tonalWorld: world,
                        chord: chord
                    )
                    let allowed = Set(chord.chordPitchClasses + chord.safePassingPitchClasses)
                    XCTAssertEqual(notes.count, mode.scaleIntervals.count)
                    XCTAssertTrue(notes.allSatisfy { (24...108).contains(Int($0)) })
                    XCTAssertTrue(notes.allSatisfy { allowed.contains(Int($0) % 12) })
                }
            }
        }
    }

    private func makeWorld(mode: DayMusicMode, center: Int) -> TonalWorldPlan {
        let scale = mode.scaleIntervals.map { (center + $0) % 12 }
        let progression = mode.progressionDegreeTemplates[3].enumerated().map { index, degree in
            let root = (center + degree) % 12
            let chordPitchClasses = [root, (root + 3) % 12, (root + 7) % 12]
            return ChordPlan(
                modalDegree: degree,
                rootPitchClass: root,
                chordPitchClasses: chordPitchClasses,
                safePassingPitchClasses: scale.filter { !chordPitchClasses.contains($0) },
                voicedMIDINotes: [48, 55, 60],
                durationBars: 4
            )
        }
        return TonalWorldPlan(
            centerPitchClass: center,
            mode: mode,
            scalePitchClasses: scale,
            progression: progression,
            cycleBars: 16
        )
    }
}
#endif
