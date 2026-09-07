#if DEBUG || INTERNAL_BUILD
import Foundation

enum DeterministicMusicDirector {
    static func makePlan(input: DayMusicInput, remixSeed: UInt64) -> DayMusicPlan {
        makePlanLegacy(input: input, instrumentDescriptors: DayObjectsInstrumentManifest.defaultDescriptors, remixSeed: remixSeed)
    }

    static func makePlan(
        input: DayMusicInput, remixSeed: UInt64,
        soundWorld: DayObjectsSoundWorld, mood: DayObjectsSoundMood = .moving
    ) -> DayMusicPlan {
        makePlan(input: input, remixSeed: remixSeed,
                 selection: DayObjectsWorldSelector.makeSelection(remixSeed: remixSeed, forcedWorld: soundWorld, forcedMood: mood))
    }

    static func makePlan(
        input: DayMusicInput, remixSeed: UInt64, selection: DayObjectsWorldSelection,
        resources: DayObjectsSoundWorldResources = .bundled
    ) -> DayMusicPlan {
        makePlan(input: input,
                 instrumentDescriptors: resources.descriptors,
                 remixSeed: remixSeed, selection: selection, resources: resources)
    }

    static func makePlan(
        input: DayMusicInput, instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64, soundWorld: DayObjectsSoundWorld? = nil, mood: DayObjectsSoundMood = .moving
    ) -> DayMusicPlan {
        guard let soundWorld else {
            return makePlanLegacy(input: input, instrumentDescriptors: instrumentDescriptors, remixSeed: remixSeed)
        }
        return makePlan(
            input: input, instrumentDescriptors: instrumentDescriptors, remixSeed: remixSeed,
            selection: DayObjectsWorldSelector.makeSelection(remixSeed: remixSeed, forcedWorld: soundWorld, forcedMood: mood)
        )
    }

    static func makePlan(
        input: DayMusicInput, instrumentDescriptors: [DayObjectsInstrumentDescriptor],
        remixSeed: UInt64, selection: DayObjectsWorldSelection,
        resources: DayObjectsSoundWorldResources = .bundled
    ) -> DayMusicPlan {
        guard let catalog = resources.catalog else {
            return makePlanLegacy(input: input, instrumentDescriptors: instrumentDescriptors, remixSeed: remixSeed)
        }
        let soundWorld = selection.world
        let mood = selection.mood
        let normalizedInput = input.normalized()
        let arrangement = DayObjectsArrangementProfile.for(world: soundWorld, mood: mood)
        let group = catalog.groups.first { $0.world == soundWorld && $0.mood == mood }
        let calibration = group?.calibration
        let reverbScale = calibration?.reverbSendScale ?? 1
        func runtimeIDs(_ ids: [DayObjectsInstrumentID]?) -> [DayObjectsInstrumentID]? {
            guard let ids else { return nil }
            return catalog.recipes.filter { ids.contains($0.id) }.map { $0.resolvedInstrumentID(for: mood) }
        }
        let world = TonalWorldPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed, world: soundWorld, mood: mood)
        var groove = GroovePlanner.makePlan(remixSeed: remixSeed, soundWorld: soundWorld, mood: mood)
        let bass = BassPlanner.makePlan(
            input: normalizedInput, tonalWorld: world, groove: groove,
            instrumentDescriptors: instrumentDescriptors, remixSeed: remixSeed, soundWorld: soundWorld,
            recipeIDs: runtimeIDs(group?.bassRecipeIDs), reverbSendScale: reverbScale
        )
        if groove.usesBass && bass == nil { groove = .percussion }
        let rhythm = RhythmPlanner.makePlan(
            input: normalizedInput, remixSeed: remixSeed, groove: groove,
            kitID: group?.drumKitID ?? "legacy", arrangement: arrangement, reverbSendScale: reverbScale
        )
        let harmony = HarmonyPlanner.makePlan(
            input: normalizedInput, tonalWorld: world, instrumentDescriptors: instrumentDescriptors,
            remixSeed: remixSeed, soundWorld: soundWorld, mood: mood,
            recipeIDs: runtimeIDs(group?.harmonyRecipeIDs), arrangement: arrangement, reverbSendScale: reverbScale
        )
        let happenings = HappeningMusicPlanner.makePlans(
            input: normalizedInput, tonalWorld: world, remixSeed: remixSeed, soundWorld: soundWorld,
            recipeIDs: group?.happeningRecipeIDs, arrangement: arrangement
        )
        let audibleRoleCount = (rhythm.rhythmicRichness > 0 ? 1 : 0)
            + (bass?.activeEvents.isEmpty == false ? 1 : 0)
            + harmony.activeRoleCount + (happenings.isEmpty ? 0 : 1) + 1
        var leadRecipeIDs = runtimeIDs(group?.leadRecipeIDs)
        var guestInstrumentIDs: Set<DayObjectsInstrumentID> = []
        // A guest occupies one lead role only. Below five audible roles a native
        // fallback preserves the 80% palette share while retaining Remix identity.
        if audibleRoleCount >= 5, let guestWorld = selection.guestWorld,
           soundWorld.guestNeighbors.contains(guestWorld),
           let guest = catalog.recipes.first(where: {
               group?.guestRecipeIDs.contains($0.id) == true && $0.world == guestWorld && $0.role == .lead
           }) {
            let id = guest.resolvedInstrumentID(for: mood)
            if instrumentDescriptors.contains(where: { $0.id == id && $0.category == .lead }) {
                leadRecipeIDs = [id]
                guestInstrumentIDs = [id]
            }
        }
        guard let lead = LeadPlanner.makePlan(
            tonalWorld: world, instrumentDescriptors: instrumentDescriptors, remixSeed: remixSeed,
            soundWorld: soundWorld, recipeIDs: leadRecipeIDs, arrangement: arrangement, reverbSendScale: reverbScale
        ) else {
            preconditionFailure("The checked-in instrument manifest must contain an approved Lead")
        }
        return DayMusicPlan(
            seed: remixSeed, soundWorld: soundWorld, mood: mood, guestWorld: selection.guestWorld,
            guestInstrumentIDs: guestInstrumentIDs, input: normalizedInput, world: world,
            rhythm: rhythm, groove: groove, bass: bass, harmony: harmony, happenings: happenings, lead: lead,
            glitch: GlitchPlanner.makePlan(input: normalizedInput, remixSeed: remixSeed),
            mix: LayerMixPlanner.makePlan(happeningCount: happenings.count, soundWorld: soundWorld,
                                          arrangement: arrangement, worldGroupCalibration: calibration)
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
