#if DEBUG || INTERNAL_BUILD
enum AmbientVoiceLeading {
    static let ambientRegister: ClosedRange<UInt8> = 48...72
    static let ambientVoiceCount = 3
    static let maximumVoiceCount = 4

    static func nearestVoicing(
        chordPitchClasses: [Int],
        previousNotes: [UInt8]?,
        register: ClosedRange<UInt8> = ambientRegister,
        voiceCount: Int = ambientVoiceCount
    ) -> [UInt8] {
        let generatedCandidates = candidates(
            chordPitchClasses: chordPitchClasses,
            register: register,
            voiceCount: voiceCount
        )
        guard !generatedCandidates.isEmpty else { return [] }

        return generatedCandidates.min { left, right in
            isPreferred(left, over: right, previousNotes: previousNotes)
        } ?? []
    }

    static func candidates(
        chordPitchClasses: [Int],
        register: ClosedRange<UInt8> = ambientRegister,
        voiceCount: Int = ambientVoiceCount
    ) -> [[UInt8]] {
        let normalizedPitchClasses = uniquePitchClasses(chordPitchClasses)
        guard
            !normalizedPitchClasses.isEmpty,
            voiceCount > 0,
            voiceCount <= maximumVoiceCount,
            voiceCount >= normalizedPitchClasses.count
        else {
            return []
        }

        let requiredPitchClasses = Set(normalizedPitchClasses)
        let eligibleNotes = (Int(register.lowerBound)...Int(register.upperBound)).compactMap { note -> UInt8? in
            requiredPitchClasses.contains(note % 12) ? UInt8(note) : nil
        }
        guard !eligibleNotes.isEmpty else { return [] }

        var result: [[UInt8]] = []
        var candidate: [UInt8] = []

        func appendCandidates(startingAt startIndex: Int) {
            if candidate.count == voiceCount {
                let representedPitchClasses = Set(candidate.map { Int($0) % 12 })
                if representedPitchClasses == requiredPitchClasses {
                    result.append(candidate)
                }
                return
            }

            for index in startIndex..<eligibleNotes.count {
                candidate.append(eligibleNotes[index])
                appendCandidates(startingAt: index)
                candidate.removeLast()
            }
        }

        appendCandidates(startingAt: 0)
        return result
    }

    private static func uniquePitchClasses(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.compactMap { value in
            let normalized = ((value % 12) + 12) % 12
            return seen.insert(normalized).inserted ? normalized : nil
        }
    }

    private static func isPreferred(
        _ candidate: [UInt8],
        over other: [UInt8],
        previousNotes: [UInt8]?
    ) -> Bool {
        let candidateMovement = totalMovement(candidate, from: previousNotes)
        let otherMovement = totalMovement(other, from: previousNotes)
        if candidateMovement != otherMovement {
            return candidateMovement < otherMovement
        }

        let candidateMaximum = candidate.last ?? 0
        let otherMaximum = other.last ?? 0
        if candidateMaximum != otherMaximum {
            return candidateMaximum < otherMaximum
        }

        return candidate.lexicographicallyPrecedes(other)
    }

    private static func totalMovement(_ candidate: [UInt8], from previousNotes: [UInt8]?) -> Int {
        guard let previousNotes, previousNotes.count == candidate.count else { return 0 }
        return zip(candidate, previousNotes).reduce(into: 0) { movement, pair in
            movement += abs(Int(pair.0) - Int(pair.1))
        }
    }
}
#endif
