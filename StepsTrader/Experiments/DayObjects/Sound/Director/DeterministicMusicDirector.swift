#if DEBUG || INTERNAL_BUILD
enum DeterministicMusicDirector {
    static func makePlan(
        input: DayMusicInput,
        remixSeed: UInt64
    ) -> DayMusicPlan {
        let normalizedInput = input.normalized()
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        let world = TonalWorldPlanner.makePlan(
            input: normalizedInput,
            remixSeed: remixSeed
        )
        var groove = GroovePlanner.makePlan(remixSeed: remixSeed)
        var rhythm = RhythmPlanner.makePlan(
            input: normalizedInput,
            remixSeed: remixSeed,
            groove: groove
        )
        let bass = BassPlanner.makePlan(
            input: normalizedInput,
            tonalWorld: world,
            groove: groove,
            instrumentDescriptors: descriptors,
            remixSeed: remixSeed
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
            instrumentDescriptors: descriptors,
            remixSeed: remixSeed
        )
        let happenings = HappeningMusicPlanner.makePlans(
            input: normalizedInput,
            tonalWorld: world,
            remixSeed: remixSeed
        )
        guard let lead = LeadPlanner.makePlan(
            tonalWorld: world,
            instrumentDescriptors: descriptors,
            remixSeed: remixSeed
        ) else {
            preconditionFailure("The checked-in instrument manifest must contain an approved Lead")
        }

        return DayMusicPlan(
            seed: remixSeed,
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
            mix: LayerMixPlanner.makePlan(happeningCount: happenings.count)
        )
    }
}
#endif
