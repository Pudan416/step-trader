#if DEBUG || INTERNAL_BUILD
enum DeterministicMusicDirector {
    static func makePlan(
        input: DayMusicInput,
        remixSeed: UInt64
    ) -> DayMusicPlan {
        makePlanLegacy(
            input: input,
            instrumentDescriptors: DayObjectsInstrumentManifest.defaultDescriptors,
            remixSeed: remixSeed
        )
    }

    static func makePlan(
        input: DayMusicInput,
        remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld
    ) -> DayMusicPlan {
        makePlan(
            input: input,
            instrumentDescriptors: DayObjectsInstrumentManifest.defaultDescriptors,
            remixSeed: remixSeed,
            soundWorld: soundWorld
        )
    }

    static func makePlan(
        input: DayMusicInput,
        instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld? = nil
    ) -> DayMusicPlan {
        if soundWorld == nil {
            return makePlanLegacy(
                input: input,
                instrumentDescriptors: instrumentDescriptors,
                remixSeed: remixSeed
            )
        }
        let soundWorld = soundWorld ?? .feltAndWood
        let normalizedInput = input.normalized()
        let world = TonalWorldPlanner.makePlan(
            input: normalizedInput,
            remixSeed: remixSeed
        )
        var groove = GroovePlanner.makePlan(remixSeed: remixSeed, soundWorld: soundWorld)
        var rhythm = RhythmPlanner.makePlan(
            input: normalizedInput,
            remixSeed: remixSeed,
            groove: groove
        )
        let bass = BassPlanner.makePlan(
            input: normalizedInput,
            tonalWorld: world,
            groove: groove,
            instrumentDescriptors: instrumentDescriptors,
            remixSeed: remixSeed,
            soundWorld: soundWorld
        )
        if groove.usesBass && bass == nil {
            groove = .percussion
            rhythm = RhythmPlanner.makePlan(
                input: normalizedInput,
                remixSeed: remixSeed,
                groove: groove
            )
        }
        let harmony = HarmonyPlanner.makePlan(
            input: normalizedInput,
            tonalWorld: world,
            instrumentDescriptors: instrumentDescriptors,
            remixSeed: remixSeed,
            soundWorld: soundWorld
        )
        let happenings = HappeningMusicPlanner.makePlans(
            input: normalizedInput,
            tonalWorld: world,
            remixSeed: remixSeed,
            soundWorld: soundWorld
        )
        guard let lead = LeadPlanner.makePlan(
            tonalWorld: world,
            instrumentDescriptors: instrumentDescriptors,
            remixSeed: remixSeed,
            soundWorld: soundWorld
        ) else {
            preconditionFailure("The checked-in instrument manifest must contain an approved Lead")
        }

        return DayMusicPlan(
            seed: remixSeed,
            soundWorld: soundWorld,
            input: normalizedInput,
            world: world,
            rhythm: rhythm,
            groove: groove,
            bass: bass,
            harmony: harmony,
            happenings: happenings,
            lead: lead,
            glitch: GlitchPlanner.makePlan(
                input: normalizedInput,
                remixSeed: remixSeed
            ),
            mix: LayerMixPlanner.makePlan(
                happeningCount: happenings.count,
                soundWorld: soundWorld
            )
        )
    }

    private static func makePlanLegacy(
        input: DayMusicInput,
        instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64
    ) -> DayMusicPlan {
        let normalizedInput = input.normalized()
        let world = TonalWorldPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed)
        var groove = GroovePlanner.makePlan(remixSeed: remixSeed)
        var rhythm = RhythmPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed, groove: groove)
        let bass = BassPlanner.makePlan(
            input: normalizedInput,
            tonalWorld: world,
            groove: groove,
            instrumentDescriptors: instrumentDescriptors,
            remixSeed: remixSeed
        )
        if groove.usesBass && bass == nil {
            groove = .percussion
            rhythm = RhythmPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed, groove: groove)
        }
        let harmony = HarmonyPlanner.makePlan(
            input: normalizedInput,
            tonalWorld: world,
            instrumentDescriptors: instrumentDescriptors,
            remixSeed: remixSeed
        )
        let happenings = HappeningMusicPlanner.makePlans(
            input: normalizedInput,
            tonalWorld: world,
            remixSeed: remixSeed
        )
        guard let lead = LeadPlanner.makePlan(
            tonalWorld: world,
            instrumentDescriptors: instrumentDescriptors,
            remixSeed: remixSeed
        ) else {
            preconditionFailure("The checked-in instrument manifest must contain an approved Lead")
        }
        return DayMusicPlan(
            seed: remixSeed,
            soundWorld: .feltAndWood,
            input: normalizedInput,
            world: world,
            rhythm: rhythm,
            groove: groove,
            bass: bass,
            harmony: harmony,
            happenings: happenings,
            lead: lead,
            glitch: GlitchPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed),
            mix: LayerMixPlanner.makePlan(happeningCount: happenings.count)
        )
    }
}
#endif
