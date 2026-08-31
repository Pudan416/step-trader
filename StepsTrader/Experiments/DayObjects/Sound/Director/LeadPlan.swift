#if DEBUG || INTERNAL_BUILD
enum LeadPitchPreference: Equatable, Sendable {
    case chordTone
    case modeTone
}

struct LeadPitchRegion: Equatable, Sendable {
    let index: Int
    let normalizedRange: ClosedRange<Double>
    let preference: LeadPitchPreference
    let midiNotesByChord: [UInt8]
}

struct LeadPlan: Equatable, Sendable {
    let instrumentID: DayObjectsInstrumentID
    let maximumSimultaneousVoices: Int
    let register: ClosedRange<UInt8>
    let pitchRegions: [LeadPitchRegion]
    let compatibleChordMIDINotes: [[UInt8]]
    let portamentoMilliseconds: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let cutoffMultiplierRange: ClosedRange<Double>
    let pitchSmoothingMilliseconds: Double
    let expressionSmoothingMilliseconds: Double
    let maximumExpressionDepth: Double
    let delaySend: Double
    let reverbSend: Double

    func nearestCompatibleNote(to midiNote: UInt8, chordIndex: Int) -> UInt8? {
        guard compatibleChordMIDINotes.indices.contains(chordIndex) else { return nil }
        return compatibleChordMIDINotes[chordIndex].min { left, right in
            let leftDistance = abs(Int(left) - Int(midiNote))
            let rightDistance = abs(Int(right) - Int(midiNote))
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return left < right
        }
    }
}
#endif
