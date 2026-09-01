#if DEBUG || INTERNAL_BUILD
import Foundation
import XCTest
@testable import Steps4

final class HappeningPitchResolverTests: XCTestCase {
    func testTonalRecipeTargetsTheNearestCurrentChordToneInsteadOfAPassingTone() {
        let recipe = makeRecipe(
            id: 1,
            sources: [makeSource("root", rootMIDI: 63)],
            pitch: .tonal(preferredRange: 60...71)
        )
        let world = makeWorld(mode: .dorian, center: 1)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 4,
            chordPitchClasses: [4, 8, 11],
            safePassingPitchClasses: [1],
            voicedMIDINotes: [64, 68, 71],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.recipeID, recipe.id)
        XCTAssertEqual(resolved.resourceName, "root.wav")
        XCTAssertEqual(resolved.sourceRootMIDI, 63)
        XCTAssertEqual(resolved.targetMIDI, 64)
        XCTAssertEqual(resolved.playbackRate, pow(2.0, 1.0 / 12.0), accuracy: 0.000_001)
        XCTAssertNil(resolved.resonantFilterHz)
    }

    func testTonalTargetStaysInsideTheRecipesPreferredRegister() {
        let recipe = makeRecipe(
            id: 2,
            sources: [makeSource("root", rootMIDI: 63)],
            pitch: .tonal(preferredRange: 60...71)
        )
        let world = makeWorld(mode: .majorPentatonic, center: 11)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 0,
            chordPitchClasses: [0, 4],
            safePassingPitchClasses: [],
            voicedMIDINotes: [60, 64],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.targetMIDI, 64)
        XCTAssertTrue((60...71).contains(resolved.targetMIDI ?? 0))
    }

    func testTonalTargetTieBreaksTowardTheLowerChordNote() {
        let recipe = makeRecipe(
            id: 3,
            sources: [makeSource("lower", rootMIDI: 60), makeSource("upper", rootMIDI: 63)],
            pitch: .tonal(preferredRange: 60...71)
        )
        let world = makeWorld(mode: .majorPentatonic, center: 2)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 0,
            chordPitchClasses: [0, 4],
            safePassingPitchClasses: [],
            voicedMIDINotes: [60, 64],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.targetMIDI, 60)
        XCTAssertEqual(resolved.sourceRootMIDI, 60)
        XCTAssertEqual(resolved.resourceName, "lower.wav")
    }

    func testTonalResolverUsesALegalRootAtTheExactTwoSemitoneBoundary() {
        let recipe = makeRecipe(
            id: 4,
            sources: [makeSource("distant", rootMIDI: 60), makeSource("boundary", rootMIDI: 63)],
            pitch: .tonal(preferredRange: 60...71)
        )
        let world = makeWorld(mode: .dorian, center: 5)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 5,
            chordPitchClasses: [5],
            safePassingPitchClasses: [],
            voicedMIDINotes: [65],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.resourceName, "boundary.wav")
        XCTAssertEqual(resolved.sourceRootMIDI, 63)
        XCTAssertEqual(resolved.targetMIDI, 65)
        XCTAssertEqual(Int(resolved.targetMIDI ?? 0) - Int(resolved.sourceRootMIDI ?? 0), 2)
        XCTAssertEqual(resolved.playbackRate, pow(2.0, 2.0 / 12.0), accuracy: 0.000_001)
    }

    func testEveryProductionTonalRecipeUsesAnExactLegalRawIntervalAcrossGeneratedWorlds() {
        let tonalRecipes = HappeningSoundCatalog.recipes.filter {
            if case .tonal = $0.pitch { return true }
            return false
        }

        for recipe in tonalRecipes {
            for world in generatedWorlds() {
                for chord in world.progression {
                    let resolved = HappeningPitchResolver.resolve(
                        recipe: recipe,
                        chord: chord,
                        tonalWorld: world
                    )
                    guard let resolvedSourceRoot = resolved.sourceRootMIDI,
                          let resolvedTarget = resolved.targetMIDI else {
                        XCTFail("Tonal recipe \(recipe.label) must resolve pitch metadata")
                        continue
                    }
                    let sourceRoot = Int(resolvedSourceRoot)
                    let target = Int(resolvedTarget)
                    let rawInterval = target - sourceRoot

                    XCTAssertTrue(
                        (-2...2).contains(rawInterval),
                        "recipe \(recipe.label), center \(world.centerPitchClass), \(world.mode), chord \(chord.chordPitchClasses)"
                    )
                    XCTAssertEqual(
                        resolved.playbackRate,
                        pow(2.0, Double(rawInterval) / 12.0),
                        accuracy: 0.000_000_000_001,
                        "recipe \(recipe.label), target \(target), source \(sourceRoot)"
                    )
                }
            }
        }
    }

    func testTonalResolverChoosesAnAlternativeRootBeforeCalculatingPlaybackRate() {
        let recipe = makeRecipe(
            id: 5,
            sources: [makeSource("distant", rootMIDI: 60), makeSource("near", rootMIDI: 63)],
            pitch: .tonal(preferredRange: 60...71)
        )
        let world = makeWorld(mode: .majorPentatonic, center: 4)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 4,
            chordPitchClasses: [4],
            safePassingPitchClasses: [],
            voicedMIDINotes: [64],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.resourceName, "near.wav")
        XCTAssertEqual(resolved.sourceRootMIDI, 63)
        XCTAssertEqual(resolved.targetMIDI, 64)
        XCTAssertEqual(resolved.playbackRate, pow(2.0, 1.0 / 12.0), accuracy: 0.000_001)
    }

    func testDorianResonantNoiseKeepsItsFilterOnTheCurrentChordTone() throws {
        let recipeID = try XCTUnwrap(HappeningSoundRecipeID(rawValue: 25))
        let recipe = try XCTUnwrap(HappeningSoundCatalog.recipe(for: recipeID))
        let world = makeWorld(mode: .dorian, center: 2)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 2,
            chordPitchClasses: [2, 5, 9],
            safePassingPitchClasses: [],
            voicedMIDINotes: [62, 65, 69],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.resourceName, "Happenings/25/noise.wav")
        XCTAssertNil(resolved.sourceRootMIDI)
        XCTAssertEqual(resolved.targetMIDI, 62)
        XCTAssertEqual(resolved.playbackRate, 1.0)
        XCTAssertEqual(resolved.resonantFilterHz ?? 0, 293.664_767_917, accuracy: 0.000_001)
    }

    func testEveryProductionResonantRecipeTunesToAChordToneAcrossGeneratedWorlds() {
        let resonantRecipes = HappeningSoundCatalog.recipes.filter {
            if case .resonantNoise = $0.pitch { return true }
            return false
        }

        for recipe in resonantRecipes {
            guard case let .resonantNoise(_, preferredRange, _) = recipe.pitch else {
                return XCTFail("Expected resonant recipe \(recipe.label)")
            }
            for world in generatedWorlds() {
                for chord in world.progression {
                    let resolved = HappeningPitchResolver.resolve(
                        recipe: recipe,
                        chord: chord,
                        tonalWorld: world
                    )
                    let target = Int(resolved.targetMIDI ?? 255)
                    let expectedHz = 440.0 * pow(2.0, (Double(target) - 69.0) / 12.0)

                    XCTAssertTrue(
                        preferredRange.contains(resolved.targetMIDI ?? 255),
                        "recipe \(recipe.label), target \(target)"
                    )
                    XCTAssertTrue(
                        chord.chordPitchClasses.contains(target % 12),
                        "recipe \(recipe.label), target \(target), chord \(chord.chordPitchClasses)"
                    )
                    XCTAssertEqual(
                        resolved.resonantFilterHz ?? 0,
                        expectedHz,
                        accuracy: 0.000_000_001,
                        "recipe \(recipe.label), target \(target)"
                    )
                }
            }
        }
    }

    func testResonatorPreferenceRanksEquidistantChordTonesWithoutReplacingThem() {
        let recipe = makeRecipe(
            id: 25,
            sources: [makeSource("noise", rootMIDI: 60)],
            pitch: .resonantNoise(
                referenceMIDI: 60,
                preferredRange: 60...71,
                resonatorTargetPitchClasses: [3]
            )
        )
        let world = makeWorld(mode: .dorian, center: 2)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 0,
            chordPitchClasses: [0, 4],
            safePassingPitchClasses: [],
            voicedMIDINotes: [60, 64],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.targetMIDI, 64)
        XCTAssertEqual(resolved.resonantFilterHz ?? 0, 329.627_556_913, accuracy: 0.000_001)
    }

    func testResonatorRankingBreaksEqualPreferenceTiesTowardTheLowerChordTone() {
        let recipe = makeRecipe(
            id: 26,
            sources: [makeSource("noise", rootMIDI: 60)],
            pitch: .resonantNoise(
                referenceMIDI: 60,
                preferredRange: 60...71,
                resonatorTargetPitchClasses: [1, 3]
            )
        )
        let world = makeWorld(mode: .dorian, center: 2)
        let chord = ChordPlan(
            modalDegree: 0,
            rootPitchClass: 0,
            chordPitchClasses: [0, 4],
            safePassingPitchClasses: [],
            voicedMIDINotes: [60, 64],
            durationBars: 4
        )

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.targetMIDI, 60)
        XCTAssertEqual(resolved.resonantFilterHz ?? 0, 261.625_565_301, accuracy: 0.000_001)
    }

    func testUnpitchedRecipeUsesItsOriginalRateWithoutPitchMetadata() {
        let recipe = makeRecipe(
            id: 30,
            sources: [makeSource("texture", rootMIDI: 60)],
            pitch: .unpitched
        )
        let world = makeWorld(mode: .dorian, center: 2)
        let chord = world.progression[0]

        let resolved = HappeningPitchResolver.resolve(recipe: recipe, chord: chord, tonalWorld: world)

        XCTAssertEqual(resolved.resourceName, "texture.wav")
        XCTAssertNil(resolved.sourceRootMIDI)
        XCTAssertNil(resolved.targetMIDI)
        XCTAssertEqual(resolved.playbackRate, 1.0)
        XCTAssertNil(resolved.resonantFilterHz)
    }

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

    private func generatedWorlds() -> [TonalWorldPlan] {
        (0..<12).flatMap { center in
            DayMusicMode.allCases.compactMap { mode in
                TonalWorldPlanner.makePlan(
                    centerPitchClass: center,
                    mode: mode,
                    progressionLength: 4,
                    cycleBars: 16
                )
            }
        }
    }

    private func makeSource(_ name: String, rootMIDI: UInt8) -> HappeningSampleSource {
        HappeningSampleSource(
            resourceName: "\(name).wav",
            rootMIDI: rootMIDI,
            sha256: String(repeating: "a", count: 64)
        )
    }

    private func makeRecipe(
        id rawID: Int,
        sources: [HappeningSampleSource],
        pitch: HappeningPitchBehavior
    ) -> HappeningSoundRecipe {
        guard let id = HappeningSoundRecipeID(rawValue: rawID) else {
            preconditionFailure("Test recipe ID must be valid")
        }
        return HappeningSoundRecipe(
            id: id,
            label: String(format: "%02d", rawID),
            family: .texture,
            sources: sources,
            pitch: pitch,
            gainDB: -12,
            attackSeconds: 0.01,
            releaseSeconds: 1,
            delayMix: 0,
            delayFeedback: 0,
            reverbMix: 0,
            filterStartHz: 200,
            filterEndHz: 2_000
        )
    }
}
#endif
