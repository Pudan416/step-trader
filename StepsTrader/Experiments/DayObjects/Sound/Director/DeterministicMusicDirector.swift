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
        let rhythm = RhythmPlanner.makePlan(
            input: normalizedInput,
            remixSeed: remixSeed
        )
        let harmony = HarmonyPlanner.makePlan(
            input: normalizedInput,
            tonalWorld: world,
            instrumentDescriptors: descriptors,
            remixSeed: remixSeed
        )
        let happenings = HappeningMusicPlanner.makePlans(
            input: normalizedInput,
            tonalWorld: world,
            instrumentDescriptors: descriptors,
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
            harmony: harmony,
            happenings: happenings,
            lead: lead,
            glitch: GlitchPlanner.makePlan(input: normalizedInput),
            mix: LayerMixPlanner.makePlan(happeningCount: happenings.count)
        )
    }
}
#endif
