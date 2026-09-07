#if DEBUG || INTERNAL_BUILD
enum GroovePlanner {
    static func makePlan(remixSeed: UInt64) -> GroovePlan {
        var modeRandom = StableMusicRandom(seed: remixSeed, domain: .grooveMode)
        let mode = mode(forBucket: Int(modeRandom.nextUInt64() % 100))
        var thinningRandom = StableMusicRandom(seed: remixSeed, domain: .grooveThinning)

        switch mode {
        case .percussion:
            return GroovePlan(
                mode: mode,
                auxiliaryRetention: 1,
                maximumAnchorKicksPerBar: 2,
                thinningSeed: thinningRandom.nextUInt64()
            )
        case .bassPulse:
            return GroovePlan(
                mode: mode,
                auxiliaryRetention: 0.65,
                maximumAnchorKicksPerBar: 2,
                thinningSeed: thinningRandom.nextUInt64()
            )
        case .bassArp:
            return GroovePlan(
                mode: mode,
                auxiliaryRetention: 0.40,
                maximumAnchorKicksPerBar: 1,
                thinningSeed: thinningRandom.nextUInt64()
            )
        case .bassBed:
            return GroovePlan(
                mode: mode,
                auxiliaryRetention: 0.50,
                maximumAnchorKicksPerBar: 1,
                thinningSeed: thinningRandom.nextUInt64()
            )
        }
    }

    static func makePlan(
        remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld,
        mood: DayObjectsSoundMood = .moving
    ) -> GroovePlan {
        var modeRandom = StableMusicRandom(seed: remixSeed, domain: .grooveMode)
        let profile = DayObjectsArrangementProfile.for(world: soundWorld, mood: mood)
        let sample = modeRandom.nextUnitDouble()
        let mode: GrooveMode
        if !profile.usesBass {
            mode = .percussion
        } else {
            let pulse = profile.bassArticulationWeights[.pulse, default: 0]
            let arpeggio = profile.bassArticulationWeights[.arpeggio, default: 0]
            mode = sample < pulse ? .bassPulse : sample < pulse + arpeggio ? .bassArp : .bassBed
        }
        var thinningRandom = StableMusicRandom(seed: remixSeed, domain: .grooveThinning)
        return plan(mode: mode, thinningSeed: thinningRandom.nextUInt64())
    }

    static func mode(forBucket bucket: Int) -> GrooveMode {
        precondition((0..<100).contains(bucket))
        switch bucket {
        case 0..<40: return .percussion
        case 40..<65: return .bassPulse
        case 65..<85: return .bassArp
        default: return .bassBed
        }
    }

    private static func plan(mode: GrooveMode, thinningSeed: UInt64) -> GroovePlan {
        switch mode {
        case .percussion:
            GroovePlan(mode: mode, auxiliaryRetention: 1, maximumAnchorKicksPerBar: 2, thinningSeed: thinningSeed)
        case .bassPulse:
            GroovePlan(mode: mode, auxiliaryRetention: 0.65, maximumAnchorKicksPerBar: 2, thinningSeed: thinningSeed)
        case .bassArp:
            GroovePlan(mode: mode, auxiliaryRetention: 0.40, maximumAnchorKicksPerBar: 1, thinningSeed: thinningSeed)
        case .bassBed:
            GroovePlan(mode: mode, auxiliaryRetention: 0.50, maximumAnchorKicksPerBar: 1, thinningSeed: thinningSeed)
        }
    }
}
#endif
