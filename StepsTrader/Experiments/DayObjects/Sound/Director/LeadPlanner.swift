#if DEBUG || INTERNAL_BUILD
enum LeadPlanner {
    private static let approvedLeadIDs = Set([
        "lead.verbacious",
        "lead.jec-softwah-2",
        "lead.bb-silver-screen"
    ])
    private static let register: ClosedRange<UInt8> = 57...81
    private static let regionCount = 21

    static func makePlan(
        tonalWorld: TonalWorldPlan,
        instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld? = nil
    ) -> LeadPlan? {
        guard !tonalWorld.progression.isEmpty else { return nil }
        let descriptors = instrumentDescriptors
            .filter { descriptor in
                descriptor.category == .lead
                    && approvedLeadIDs.contains(descriptor.id.rawValue)
                    && (soundWorld?.leadInstrumentIDs.contains(descriptor.id.rawValue) ?? true)
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        var random = StableMusicRandom(seed: remixSeed, domain: .effects)
        guard let instrument = random.choice(from: descriptors) else { return nil }

        let scaleNotes = midiNotes(
            pitchClasses: tonalWorld.scalePitchClasses,
            register: register
        )
        let chordNotes = tonalWorld.progression.map {
            midiNotes(pitchClasses: $0.chordPitchClasses, register: register)
        }
        guard !scaleNotes.isEmpty, chordNotes.allSatisfy({ !$0.isEmpty }) else { return nil }

        let regions = (0..<regionCount).map { index -> LeadPitchRegion in
            let preference: LeadPitchPreference = index.isMultiple(of: 3) ? .chordTone : .modeTone
            let target = regionTarget(index: index)
            let notes = chordNotes.map { compatibleNotes in
                nearestNote(
                    to: target,
                    in: preference == .chordTone ? compatibleNotes : scaleNotes
                )
            }
            return LeadPitchRegion(
                index: index,
                normalizedRange: (Double(index) / Double(regionCount))...(Double(index + 1) / Double(regionCount)),
                preference: preference,
                midiNotesByChord: notes
            )
        }

        let processing = processing(for: soundWorld)
        return LeadPlan(
            instrumentID: instrument.id,
            maximumSimultaneousVoices: 1,
            register: register,
            pitchRegions: regions,
            compatibleChordMIDINotes: chordNotes,
            portamentoMilliseconds: processing.portamentoMilliseconds,
            attackSeconds: processing.attackSeconds,
            releaseSeconds: processing.releaseSeconds,
            cutoffMultiplierRange: processing.cutoffMultiplierRange,
            pitchSmoothingMilliseconds: processing.pitchSmoothingMilliseconds,
            expressionSmoothingMilliseconds: processing.expressionSmoothingMilliseconds,
            maximumExpressionDepth: processing.maximumExpressionDepth,
            delaySend: processing.delaySend,
            reverbSend: processing.reverbSend
        )
    }

    private struct Processing {
        let portamentoMilliseconds: Double
        let attackSeconds: Double
        let releaseSeconds: Double
        let cutoffMultiplierRange: ClosedRange<Double>
        let pitchSmoothingMilliseconds: Double
        let expressionSmoothingMilliseconds: Double
        let maximumExpressionDepth: Double
        let delaySend: Double
        let reverbSend: Double
    }

    private static func processing(for soundWorld: DayObjectsSoundWorld?) -> Processing {
        switch soundWorld {
        case .feltAndWood:
            return Processing(
                portamentoMilliseconds: 165,
                attackSeconds: 0.065,
                releaseSeconds: 1.05,
                cutoffMultiplierRange: 0.42...1.05,
                pitchSmoothingMilliseconds: 62,
                expressionSmoothingMilliseconds: 115,
                maximumExpressionDepth: 0.18,
                delaySend: 0.16,
                reverbSend: 0.46
            )
        case .metalAndCurrent:
            return Processing(
                portamentoMilliseconds: 72,
                attackSeconds: 0.018,
                releaseSeconds: 0.72,
                cutoffMultiplierRange: 0.70...1.55,
                pitchSmoothingMilliseconds: 34,
                expressionSmoothingMilliseconds: 58,
                maximumExpressionDepth: 0.31,
                delaySend: 0.34,
                reverbSend: 0.50
            )
        case nil:
            return Processing(
                portamentoMilliseconds: 110,
                attackSeconds: 0.035,
                releaseSeconds: 0.65,
                cutoffMultiplierRange: 0.55...1.35,
                pitchSmoothingMilliseconds: 45,
                expressionSmoothingMilliseconds: 80,
                maximumExpressionDepth: 0.25,
                delaySend: 0.24,
                reverbSend: 0.38
            )
        }
    }

    private static func midiNotes(
        pitchClasses: [Int],
        register: ClosedRange<UInt8>
    ) -> [UInt8] {
        let allowed = Set(pitchClasses.map(normalizedPitchClass))
        return (Int(register.lowerBound)...Int(register.upperBound)).compactMap { midiNote in
            allowed.contains(midiNote % 12) ? UInt8(midiNote) : nil
        }
    }

    private static func regionTarget(index: Int) -> UInt8 {
        let extent = Int(register.upperBound) - Int(register.lowerBound)
        let offset = Int((Double(index * extent) / Double(regionCount - 1)).rounded())
        return UInt8(Int(register.lowerBound) + offset)
    }

    private static func nearestNote(to target: UInt8, in candidates: [UInt8]) -> UInt8 {
        candidates.min { left, right in
            let leftDistance = abs(Int(left) - Int(target))
            let rightDistance = abs(Int(right) - Int(target))
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return left < right
        } ?? register.lowerBound
    }

    private static func normalizedPitchClass(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }
}
#endif
