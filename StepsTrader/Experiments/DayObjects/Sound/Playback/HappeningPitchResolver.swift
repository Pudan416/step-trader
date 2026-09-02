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
            guard let source = nearestSource(
                to: target,
                in: recipe.sources,
                maximumDistance: 2
            ) else {
                preconditionFailure("Tonal happening recipes must provide a source within two semitones of the target")
            }
            let semitoneOffset = Int(target) - Int(source.rootMIDI)
            return ResolvedHappeningSound(
                recipeID: recipe.id,
                resourceName: source.resourceName,
                sourceRootMIDI: source.rootMIDI,
                targetMIDI: target,
                playbackRate: pow(2.0, Double(semitoneOffset) / 12.0),
                resonantFilterHz: nil
            )

        case let .resonantNoise(referenceMIDI, preferredRange, resonatorTargetPitchClasses):
            guard let source = nearestSource(to: referenceMIDI, in: recipe.sources) else {
                preconditionFailure("Happening recipes must declare a sample source")
            }
            let resonantTarget = resonantChordTarget(
                in: preferredRange,
                chordPitchClasses: chord.chordPitchClasses,
                centerPitchClass: tonalWorld.centerPitchClass,
                preferredPitchClasses: resonatorTargetPitchClasses.map(Int.init)
            )
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

    private static func normalizedPitchClass(_ value: Int) -> Int {
        let remainder = value % 12
        return remainder >= 0 ? remainder : remainder + 12
    }

    private static func chordTarget(
        in preferredRange: ClosedRange<UInt8>,
        chordPitchClasses: [Int],
        centerPitchClass: Int
    ) -> UInt8 {
        let preferredCenter = preferredCenter(
            in: preferredRange,
            centerPitchClass: centerPitchClass
        )
        return nearestNote(
            in: preferredRange,
            pitchClasses: chordPitchClasses,
            to: preferredCenter
        ) ?? preferredCenter
    }

    private static func preferredCenter(
        in preferredRange: ClosedRange<UInt8>,
        centerPitchClass: Int
    ) -> UInt8 {
        nearestNote(
            in: preferredRange,
            pitchClasses: [centerPitchClass],
            to: UInt8((Int(preferredRange.lowerBound) + Int(preferredRange.upperBound)) / 2)
        ) ?? preferredRange.lowerBound
    }

    private static func resonantChordTarget(
        in preferredRange: ClosedRange<UInt8>,
        chordPitchClasses: [Int],
        centerPitchClass: Int,
        preferredPitchClasses: [Int]
    ) -> UInt8 {
        let desired = preferredCenter(
            in: preferredRange,
            centerPitchClass: centerPitchClass
        )
        let allowedPitchClasses = Set(chordPitchClasses.map(normalizedPitchClass))
        guard let target = (preferredRange
            .filter { allowedPitchClasses.contains(Int($0) % 12) }
            .min(by: {
                let leftCenterDistance = abs(Int($0) - Int(desired))
                let rightCenterDistance = abs(Int($1) - Int(desired))
                if leftCenterDistance != rightCenterDistance {
                    return leftCenterDistance < rightCenterDistance
                }

                let leftPreferenceDistance = pitchClassDistance(
                    from: Int($0) % 12,
                    to: preferredPitchClasses
                )
                let rightPreferenceDistance = pitchClassDistance(
                    from: Int($1) % 12,
                    to: preferredPitchClasses
                )
                if leftPreferenceDistance != rightPreferenceDistance {
                    return leftPreferenceDistance < rightPreferenceDistance
                }

                return $0 < $1
            })) else {
                preconditionFailure("Resonant happening ranges must contain a current chord tone")
            }
        return target
    }

    private static func pitchClassDistance(from pitchClass: Int, to preferredPitchClasses: [Int]) -> Int {
        preferredPitchClasses
            .map(normalizedPitchClass)
            .map {
                let distance = abs(normalizedPitchClass(pitchClass) - $0)
                return min(distance, 12 - distance)
            }
            .min() ?? 0
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
        in sources: [HappeningSampleSource],
        maximumDistance: Int? = nil
    ) -> HappeningSampleSource? {
        sources
            .filter { source in
                maximumDistance.map { abs(Int(source.rootMIDI) - Int(target)) <= $0 } ?? true
            }
            .min {
                let leftDistance = abs(Int($0.rootMIDI) - Int(target))
                let rightDistance = abs(Int($1.rootMIDI) - Int(target))
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                if $0.rootMIDI != $1.rootMIDI { return $0.rootMIDI < $1.rootMIDI }
                return $0.resourceName < $1.resourceName
            }
    }
}
#endif
