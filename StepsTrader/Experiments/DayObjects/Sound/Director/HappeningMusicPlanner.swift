#if DEBUG || INTERNAL_BUILD
enum HappeningMusicPlanner {
    static func makePlans(
        input: NormalizedDayMusicInput,
        tonalWorld: TonalWorldPlan,
        instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64
    ) -> [HappeningMusicPlan] {
        let descriptors = instrumentDescriptors.sorted { $0.id.rawValue < $1.id.rawValue }
        return input.happeningIDs.compactMap { happeningID in
            makePlan(
                happeningID: happeningID,
                tonalWorld: tonalWorld,
                descriptors: descriptors,
                remixSeed: remixSeed
            )
        }
    }

    private static func makePlan(
        happeningID: String,
        tonalWorld: TonalWorldPlan,
        descriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64
    ) -> HappeningMusicPlan? {
        var identityRandom = StableMusicRandom(
            seed: remixSeed,
            domain: .happeningIdentity(stableID: happeningID)
        )
        guard let family = identityRandom.choice(from: HappeningSoundFamily.allCases) else {
            return nil
        }
        let compatibleDescriptors = descriptors.filter {
            family.compatibleCategories.contains($0.category)
        }
        guard let instrument = identityRandom.choice(from: compatibleDescriptors) else {
            return nil
        }

        let motifLength = 1 + (identityRandom.nextInt(upperBound: 3) ?? 0)
        let motif = Array(
            identityRandom.shuffled(tonalWorld.mode.scaleIntervals).prefix(motifLength)
        )
        let envelope = envelopeRange(for: family)
        let effects = effectRange(for: family)
        let gain = 0.18 + (0.12 * identityRandom.nextUnitDouble())
        let birthGain = min(0.38, gain + 0.04 + (0.04 * identityRandom.nextUnitDouble()))

        var scheduleRandom = StableMusicRandom(
            seed: remixSeed,
            domain: .happeningSchedule(stableID: happeningID)
        )
        let scheduleSeed = scheduleRandom.nextUInt64()
        let alignmentRank = scheduleRandom.nextUInt64()
        let magnitude = scheduleRandom.bernoulli(probability: 0.5) ? 0.25 : 0.50
        let floatingOffset = scheduleRandom.bernoulli(probability: 0.5) ? magnitude : -magnitude

        return HappeningMusicPlan(
            happeningID: happeningID,
            family: family,
            instrumentID: instrument.id,
            motifScaleDegrees: motif,
            octave: octave(for: family, random: &identityRandom),
            pan: -0.85 + (1.70 * identityRandom.nextUnitDouble()),
            gain: gain,
            birthGain: birthGain,
            attackSeconds: interpolate(envelope.attack, random: &identityRandom),
            releaseSeconds: interpolate(envelope.release, random: &identityRandom),
            delaySend: interpolate(effects.delay, random: &identityRandom),
            reverbSend: interpolate(effects.reverb, random: &identityRandom),
            recurrence: HappeningRecurrencePlan(
                scheduleSeed: scheduleSeed,
                alignmentRank: alignmentRank,
                floatingOffsetBeats: floatingOffset
            )
        )
    }

    private static func octave(
        for family: HappeningSoundFamily,
        random: inout StableMusicRandom
    ) -> Int {
        let range: ClosedRange<Int>
        switch family {
        case .texture:
            range = 3...4
        case .mallet, .softOneShot:
            range = 4...5
        case .pluck, .bell:
            range = 4...6
        }
        return range.lowerBound + (random.nextInt(upperBound: range.count) ?? 0)
    }

    private static func envelopeRange(
        for family: HappeningSoundFamily
    ) -> (attack: ClosedRange<Double>, release: ClosedRange<Double>) {
        switch family {
        case .pluck: return (0.006...0.025, 0.70...1.60)
        case .mallet: return (0.008...0.035, 1.00...2.20)
        case .bell: return (0.003...0.018, 2.20...4.80)
        case .softOneShot: return (0.025...0.090, 1.20...2.80)
        case .texture: return (0.30...0.80, 3.20...6.00)
        }
    }

    private static func effectRange(
        for family: HappeningSoundFamily
    ) -> (delay: ClosedRange<Double>, reverb: ClosedRange<Double>) {
        switch family {
        case .pluck: return (0.18...0.38, 0.28...0.48)
        case .mallet: return (0.10...0.30, 0.36...0.58)
        case .bell: return (0.28...0.52, 0.48...0.72)
        case .softOneShot: return (0.08...0.24, 0.30...0.52)
        case .texture: return (0.22...0.46, 0.55...0.75)
        }
    }

    private static func interpolate(
        _ range: ClosedRange<Double>,
        random: inout StableMusicRandom
    ) -> Double {
        range.lowerBound + ((range.upperBound - range.lowerBound) * random.nextUnitDouble())
    }
}
#endif
