#if DEBUG || INTERNAL_BUILD
import Foundation

enum HappeningPitchResolver {
    static func resolve(
        recipe: HappeningSoundRecipe,
        chord: ChordPlan,
        tonalWorld: TonalWorldPlan
    ) -> ResolvedHappeningSound {
        precondition(!recipe.sources.isEmpty, "Happening recipes must declare a sample source")

        switch recipe.pitch {
        case let .tonal(preferredRange):
            let target = chordTarget(
                in: preferredRange,
                chordPitchClasses: chord.chordPitchClasses,
                centerPitchClass: tonalWorld.centerPitchClass
            )
            let source = nearestSource(to: target, in: recipe.sources)
            let semitoneOffset = min(max(Int(target) - Int(source.rootMIDI), -2), 2)
            return ResolvedHappeningSound(
                recipeID: recipe.id,
                resourceName: source.resourceName,
                sourceRootMIDI: source.rootMIDI,
                targetMIDI: target,
                playbackRate: pow(2.0, Double(semitoneOffset) / 12.0),
                resonantFilterHz: nil
            )

        case let .resonantNoise(referenceMIDI, preferredRange, resonatorTargetPitchClasses):
            let source = nearestSource(to: referenceMIDI, in: recipe.sources)
            let chordTarget = chordTarget(
                in: preferredRange,
                chordPitchClasses: chord.chordPitchClasses,
                centerPitchClass: tonalWorld.centerPitchClass
            )
            let resonantTarget = nearestNote(
                in: preferredRange,
                pitchClasses: resonatorTargetPitchClasses.map(Int.init),
                to: chordTarget
            ) ?? referenceMIDI
            return ResolvedHappeningSound(
                recipeID: recipe.id,
                resourceName: source.resourceName,
                sourceRootMIDI: nil,
                targetMIDI: resonantTarget,
                playbackRate: 1.0,
                resonantFilterHz: 440.0 * pow(2.0, (Double(resonantTarget) - 69.0) / 12.0)
            )

        case .unpitched:
            let source = recipe.sources[0]
            return ResolvedHappeningSound(
                recipeID: recipe.id,
                resourceName: source.resourceName,
                sourceRootMIDI: nil,
                targetMIDI: nil,
                playbackRate: 1.0,
                resonantFilterHz: nil
            )
        }
    }

    static func resolve(
        motifScaleDegrees: [Int],
        octave: Int,
        tonalWorld: TonalWorldPlan,
        chord: ChordPlan
    ) -> [UInt8] {
        motifScaleDegrees.compactMap {
            resolve(motifScaleDegree: $0, octave: octave, tonalWorld: tonalWorld, chord: chord)
        }
    }

    static func resolve(
        motifScaleDegree: Int,
        octave: Int,
        tonalWorld: TonalWorldPlan,
        chord: ChordPlan
    ) -> UInt8? {
        let allowedPitchClasses = Set(
            (chord.chordPitchClasses + chord.safePassingPitchClasses).map(normalizedPitchClass)
        )
        guard !allowedPitchClasses.isEmpty else { return nil }

        let safeRange = Int(DayObjectsAudioParameters.minimumMIDINote)...Int(DayObjectsAudioParameters.maximumMIDINote)
        let requestedBase = (octave + 1) * 12
        let desired = requestedBase + tonalWorld.centerPitchClass + motifScaleDegree
        let requestedRegister = requestedBase...(requestedBase + 23)
        var candidates = safeRange.filter {
            requestedRegister.contains($0) && allowedPitchClasses.contains(normalizedPitchClass($0))
        }
        if candidates.isEmpty {
            candidates = safeRange.filter { allowedPitchClasses.contains(normalizedPitchClass($0)) }
        }
        guard let resolved = candidates.min(by: {
            let leftDistance = abs($0 - desired)
            let rightDistance = abs($1 - desired)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return $0 < $1
        }) else { return nil }
        return UInt8(resolved)
    }

    private static func normalizedPitchClass(_ value: Int) -> Int {
        let remainder = value % 12
        return remainder >= 0 ? remainder : remainder + 12
    }

    private static func chordTarget(
        in preferredRange: ClosedRange<UInt8>,
        chordPitchClasses: [Int],
        centerPitchClass: Int
    ) -> UInt8 {
        let preferredCenter = nearestNote(
            in: preferredRange,
            pitchClasses: [centerPitchClass],
            to: UInt8((Int(preferredRange.lowerBound) + Int(preferredRange.upperBound)) / 2)
        ) ?? preferredRange.lowerBound
        return nearestNote(
            in: preferredRange,
            pitchClasses: chordPitchClasses,
            to: preferredCenter
        ) ?? preferredCenter
    }

    private static func nearestNote(
        in range: ClosedRange<UInt8>,
        pitchClasses: [Int],
        to desired: UInt8
    ) -> UInt8? {
        let allowedPitchClasses = Set(pitchClasses.map(normalizedPitchClass))
        return range
            .filter { allowedPitchClasses.contains(Int($0) % 12) }
            .min {
                let leftDistance = abs(Int($0) - Int(desired))
                let rightDistance = abs(Int($1) - Int(desired))
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return $0 < $1
            }
    }

    private static func nearestSource(
        to target: UInt8,
        in sources: [HappeningSampleSource]
    ) -> HappeningSampleSource {
        sources.min {
            let leftDistance = abs(Int($0.rootMIDI) - Int(target))
            let rightDistance = abs(Int($1.rootMIDI) - Int(target))
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            if $0.rootMIDI != $1.rootMIDI { return $0.rootMIDI < $1.rootMIDI }
            return $0.resourceName < $1.resourceName
        }!
    }
}
#endif
