#if DEBUG || INTERNAL_BUILD
enum BassPlanner {
    private static let register: ClosedRange<UInt8> = 24...40
    private static let subdivisionsPerBar: Int64 = 16
    private static let approvedInstrumentIDs = [
        "bass.analog-boom",
        "bass.hey-jakob",
        "bass.bassliner",
        "bass.jec-hollores-2",
    ]

    static func makePlan(
        input: NormalizedDayMusicInput,
        tonalWorld: TonalWorldPlan,
        groove: GroovePlan,
        instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld? = nil
    ) -> BassPlan? {
        guard groove.usesBass,
              let instrument = selectedInstrument(
                from: instrumentDescriptors,
                mode: groove.mode,
                remixSeed: remixSeed,
                soundWorld: soundWorld
              )
        else {
            return nil
        }

        let profile = profile(for: groove.mode)
        var patternRandom = StableMusicRandom(seed: remixSeed, domain: .bassPattern)
        var activationRandom = StableMusicRandom(seed: remixSeed, domain: .bassPattern)
        var articulationRandom = StableMusicRandom(seed: remixSeed, domain: .bassArticulation)
        let candidates = makeCandidates(
            tonalWorld: tonalWorld,
            mode: groove.mode,
            referenceNote: instrument.referenceMIDI,
            random: &patternRandom
        )
        let events = candidates.map { candidate in
            BassEventPlan(
                stableID: stableID(mode: groove.mode, startSubdivision: candidate.startSubdivision),
                chordIndex: candidate.chordIndex,
                startSubdivision: candidate.startSubdivision,
                durationSubdivisions: candidate.durationSubdivisions,
                midiNote: candidate.midiNote,
                velocity: candidate.velocity,
                activationThreshold: activationThreshold(
                    for: candidate,
                    mode: groove.mode,
                    random: &activationRandom
                ),
                allowedPitchClasses: candidate.allowedPitchClasses
            )
        }.sorted { left, right in
            if left.startSubdivision != right.startSubdivision {
                return left.startSubdivision < right.startSubdivision
            }
            return left.stableID < right.stableID
        }

        return BassPlan(
            mode: groove.mode,
            instrumentID: instrument.id,
            register: register,
            articulation: profile.articulation,
            stepsProgress: unitValue(input.stepsProgress),
            cutoffMultiplier: profile.cutoffMultiplier,
            glideMilliseconds: randomValue(in: profile.glideMilliseconds, random: &articulationRandom),
            reverbSend: randomValue(in: profile.reverbSend, random: &articulationRandom),
            ducking: BassDuckingPlan(
                maximumAttenuationDecibels: randomValue(
                    in: profile.duckingDecibels,
                    random: &articulationRandom
                ),
                attackSeconds: profile.duckAttackSeconds,
                holdSeconds: profile.duckHoldSeconds,
                releaseSeconds: profile.duckReleaseSeconds
            ),
            events: events
        )
    }

    private struct Profile {
        let articulation: BassArticulation
        let glideMilliseconds: ClosedRange<Double>
        let reverbSend: ClosedRange<Double>
        let duckingDecibels: ClosedRange<Double>
        let cutoffMultiplier: Double
        let duckAttackSeconds: Double
        let duckHoldSeconds: Double
        let duckReleaseSeconds: Double
    }

    private struct Candidate {
        let chordIndex: Int
        let startSubdivision: Int64
        let durationSubdivisions: Int64
        let midiNote: UInt8
        let velocity: Double
        let allowedPitchClasses: Set<Int>
        let isStructural: Bool
    }

    private static func selectedInstrument(
        from descriptors: [DayObjectsInstrumentDescriptor],
        mode: GrooveMode,
        remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld?
    ) -> DayObjectsInstrumentDescriptor? {
        var approvedByID: [String: DayObjectsInstrumentDescriptor] = [:]
        for descriptor in descriptors where descriptor.category == .bass {
            guard approvedInstrumentIDs.contains(descriptor.id.rawValue),
                  (soundWorld?.bassInstrumentIDs.contains(descriptor.id.rawValue) ?? true),
                  approvedByID[descriptor.id.rawValue] == nil
            else {
                continue
            }
            approvedByID[descriptor.id.rawValue] = descriptor
        }
        guard !approvedByID.isEmpty else { return nil }

        var random = StableMusicRandom(seed: remixSeed, domain: .bassInstrument)
        let preferredIDs = preferredInstrumentIDs(for: mode)
        let preferred = preferredIDs.compactMap { approvedByID[$0] }
        if !preferred.isEmpty {
            return random.choice(from: preferred)
        }

        let startIndex = random.nextInt(upperBound: approvedInstrumentIDs.count) ?? 0
        for offset in approvedInstrumentIDs.indices {
            let index = (startIndex + offset) % approvedInstrumentIDs.count
            if let descriptor = approvedByID[approvedInstrumentIDs[index]] {
                return descriptor
            }
        }
        return nil
    }

    private static func preferredInstrumentIDs(for mode: GrooveMode) -> [String] {
        switch mode {
        case .percussion:
            return []
        case .bassPulse:
            return ["bass.analog-boom", "bass.hey-jakob"]
        case .bassArp:
            return ["bass.bassliner"]
        case .bassBed:
            return ["bass.jec-hollores-2", "bass.hey-jakob"]
        }
    }

    private static func profile(for mode: GrooveMode) -> Profile {
        switch mode {
        case .percussion:
            preconditionFailure("Percussion mode does not have a bass profile")
        case .bassPulse:
            return Profile(
                articulation: .pulse,
                glideMilliseconds: 80...220,
                reverbSend: 0.05...0.12,
                duckingDecibels: 3.5...5,
                cutoffMultiplier: 0.76,
                duckAttackSeconds: 0.012,
                duckHoldSeconds: 0.050,
                duckReleaseSeconds: 0.180
            )
        case .bassArp:
            return Profile(
                articulation: .arpeggio,
                glideMilliseconds: 120...360,
                reverbSend: 0.06...0.14,
                duckingDecibels: 3...4.5,
                cutoffMultiplier: 0.82,
                duckAttackSeconds: 0.009,
                duckHoldSeconds: 0.040,
                duckReleaseSeconds: 0.140
            )
        case .bassBed:
            return Profile(
                articulation: .sustained,
                glideMilliseconds: 160...420,
                reverbSend: 0.05...0.12,
                duckingDecibels: 2.5...3.5,
                cutoffMultiplier: 0.66,
                duckAttackSeconds: 0.020,
                duckHoldSeconds: 0.070,
                duckReleaseSeconds: 0.220
            )
        }
    }

    private static func makeCandidates(
        tonalWorld: TonalWorldPlan,
        mode: GrooveMode,
        referenceNote: UInt8,
        random: inout StableMusicRandom
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        var chordStart: Int64 = 0
        let loweredReference = min(
            max(Int(referenceNote) - 12, Int(register.lowerBound)),
            Int(register.upperBound)
        )
        var previousNote = UInt8(loweredReference)

        for (chordIndex, chord) in tonalWorld.progression.enumerated() {
            let chordDuration = Int64(chord.durationBars) * subdivisionsPerBar
            let allowedPitchClasses = Set(chord.chordPitchClasses)
            let positions = candidatePositions(
                mode: mode,
                chordDuration: chordDuration
            )

            for position in positions {
                let preferredPitchClass = preferredPitchClass(
                    mode: mode,
                    chord: chord,
                    isStructural: position == 0,
                    random: &random
                )
                let duration = duration(
                    position: position,
                    chordDuration: chordDuration
                )
                let midiNote = nearestLegalMIDINote(
                    pitchClass: preferredPitchClass,
                    reference: previousNote
                )
                previousNote = midiNote
                candidates.append(Candidate(
                    chordIndex: chordIndex,
                    startSubdivision: chordStart + position,
                    durationSubdivisions: duration,
                    midiNote: midiNote,
                    velocity: 0.46 + (random.nextUnitDouble() * 0.18),
                    allowedPitchClasses: allowedPitchClasses,
                    isStructural: position == 0
                ))
            }
            chordStart += chordDuration
        }
        return candidates
    }

    private static func candidatePositions(mode: GrooveMode, chordDuration: Int64) -> [Int64] {
        switch mode {
        case .percussion:
            return []
        case .bassPulse, .bassArp:
            guard chordDuration >= subdivisionsPerBar * 2 else { return [0] }
            return [0, chordDuration / 2]
        case .bassBed:
            return [0]
        }
    }

    private static func preferredPitchClass(
        mode: GrooveMode,
        chord: ChordPlan,
        isStructural: Bool,
        random: inout StableMusicRandom
    ) -> Int {
        if isStructural { return chord.rootPitchClass }
        switch mode {
        case .percussion:
            return chord.rootPitchClass
        case .bassPulse:
            return random.bernoulli(probability: 0.72)
                ? chord.rootPitchClass
                : normalizedPitchClass(chord.rootPitchClass + 7)
        case .bassArp:
            return random.choice(from: chord.chordPitchClasses) ?? chord.rootPitchClass
        case .bassBed:
            return chord.rootPitchClass
        }
    }

    private static func duration(
        position: Int64,
        chordDuration: Int64
    ) -> Int64 {
        max(chordDuration - position, 1)
    }

    private static func activationThreshold(
        for candidate: Candidate,
        mode: GrooveMode,
        random: inout StableMusicRandom
    ) -> Double {
        let sample = random.nextUnitDouble()
        if candidate.isStructural {
            return 0.02 + (sample * 0.20)
        }

        switch mode {
        case .percussion:
            return 1
        case .bassPulse:
            return 0.35 + (sample * 0.65)
        case .bassArp:
            return 0.40 + (sample * 0.60)
        case .bassBed:
            return 0.25 + (sample * 0.75)
        }
    }

    private static func nearestLegalMIDINote(pitchClass: Int, reference: UInt8) -> UInt8 {
        let legalNotes = register.filter { Int($0) % 12 == normalizedPitchClass(pitchClass) }
        return legalNotes.min { left, right in
            let leftDistance = abs(Int(left) - Int(reference))
            let rightDistance = abs(Int(right) - Int(reference))
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return left < right
        } ?? register.lowerBound
    }

    private static func stableID(mode: GrooveMode, startSubdivision: Int64) -> UInt64 {
        let modeOffset: UInt64
        switch mode {
        case .percussion: modeOffset = 0
        case .bassPulse: modeOffset = 1
        case .bassArp: modeOffset = 2
        case .bassBed: modeOffset = 3
        }
        return (modeOffset * 1_000_000) + UInt64(max(0, startSubdivision))
    }

    private static func randomValue(
        in range: ClosedRange<Double>,
        random: inout StableMusicRandom
    ) -> Double {
        range.lowerBound + ((range.upperBound - range.lowerBound) * random.nextUnitDouble())
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func normalizedPitchClass(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }
}
#endif
