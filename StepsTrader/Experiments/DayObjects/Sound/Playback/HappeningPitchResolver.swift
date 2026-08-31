#if DEBUG || INTERNAL_BUILD
enum HappeningPitchResolver {
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
}
#endif
