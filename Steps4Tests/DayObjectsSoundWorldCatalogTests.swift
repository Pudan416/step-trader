import XCTest
@testable import Steps4

final class DayObjectsSoundWorldCatalogTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: type(of: self)) }

    func testResolutionAppliesBaseThenMoodAndClampsOnlyTheResolvedVoice() throws {
        let sourceID = DayObjectsInstrumentID(rawValue: "pad.interstellar")
        let source = SynthOnePresetAdapter.convert(.init(uid: "fixture", name: "Fixture")).voice
        let recipe = DayObjectsSynthRecipe(
            id: .init(rawValue: "fixture"), world: .feltAndWood, role: .harmony, family: "fixture",
            sourceInstrumentID: sourceID,
            basePatch: .init(oscillator1WaveOffset: 0.8, cutoffMultiplier: 0.5,
                             attackMultiplier: 2, releaseMultiplier: 3, lfoRateMultiplier: 2,
                             delayMixOffset: 0.2),
            moodPatches: DayObjectsSoundMood.allCases.map {
                .init(mood: $0, patch: .init(oscillator1WaveOffset: -0.4, subLevelOffset: 2,
                                            cutoffMultiplier: 0.5, attackMultiplier: 3,
                                            releaseMultiplier: 2, lfoRateMultiplier: 3, reverbMixOffset: 0.4))
            },
            referenceMIDI: 72, outputTrimDB: 6
        )
        let voice = try recipe.resolvedVoice(mood: .moving, sourceVoices: [sourceID: source])
        XCTAssertEqual(voice.oscillator1.wavePosition, 0.9, accuracy: 0.000001)
        XCTAssertEqual(voice.subOscillator.level, 1)
        XCTAssertEqual(voice.filter.cutoffHz, 3000)
        XCTAssertEqual(voice.amplitudeEnvelope.attackSeconds, 0.3, accuracy: 0.000001)
        XCTAssertEqual(voice.filter.envelope.attackSeconds, 0.3, accuracy: 0.000001)
        XCTAssertEqual(voice.amplitudeEnvelope.releaseSeconds, 2.4, accuracy: 0.000001)
        XCTAssertEqual(voice.lfo.rateHz, 6)
        XCTAssertEqual(voice.delay.mix, 0.2)
        XCTAssertTrue(voice.delay.isEnabled)
        XCTAssertEqual(voice.reverb.mix, 0.4)
        XCTAssertTrue(voice.reverb.isEnabled)
        XCTAssertEqual(voice.referenceMIDI, 72)
        XCTAssertEqual(voice.outputTrimDB, -6)
    }

    func testCatalogHasFourFamiliesPerWorldAndRoleAndThreeRuntimeVoicesPerFamily() throws {
        let catalog = try DayObjectsSoundWorldCatalog.load(from: bundle)
        XCTAssertEqual(catalog.recipes.count, 48)
        XCTAssertEqual(catalog.groups.count, 12)
        XCTAssertEqual(catalog.resolvedInstruments.count, 144)
        XCTAssertEqual(Set(catalog.descriptors.map(\.id)).count, 144)
        for recipe in catalog.recipes {
            XCTAssertEqual(try Set(DayObjectsSoundMood.allCases.map {
                try recipe.fingerprint(mood: $0, sourceVoices: catalog.sourceVoices)
            }).count, 3, recipe.id.rawValue)
        }
        for world in DayObjectsSoundWorld.allCases {
            for role in DayObjectsSynthRole.allCases {
                XCTAssertEqual(catalog.recipes(world: world, role: role).count, 4)
                for mood in DayObjectsSoundMood.allCases {
                    let voices = try catalog.resolvedVoices(world: world, role: role, mood: mood)
                    XCTAssertEqual(Set(voices.map(\.stableFingerprint)).count, 4)
                    XCTAssertTrue(voices.allSatisfy { $0.fingerprintScalars.allSatisfy(\.isFinite) })
                }
            }
        }
        let recipe = try XCTUnwrap(catalog.recipes.first { $0.family == "felt-haze" })
        XCTAssertEqual(recipe.resolvedInstrumentID(for: .sparse).rawValue, "acoustic.harmony.felt-haze.sparse")
        XCTAssertEqual(recipe.resolvedInstrumentID(for: .moving).rawValue, "acoustic.harmony.felt-haze.moving")
        XCTAssertEqual(recipe.resolvedInstrumentID(for: .strange).rawValue, "acoustic.harmony.felt-haze.strange")
        XCTAssertEqual(try Set(DayObjectsSoundMood.allCases.map {
            try recipe.fingerprint(mood: $0, sourceVoices: catalog.sourceVoices)
        }).count, 3)
        try catalog.validate()
    }

    func testInvalidSchemaRecipesAndReferencesAreRejected() throws {
        let recipesURL = try XCTUnwrap(bundle.url(forResource: "synth-recipes-v1", withExtension: "json", subdirectory: "SoundWorlds"))
        let groupsURL = try XCTUnwrap(bundle.url(forResource: "world-groups-v1", withExtension: "json", subdirectory: "SoundWorlds"))
        let recipesData = try Data(contentsOf: recipesURL)
        let groupsData = try Data(contentsOf: groupsURL)
        let sources = try DayObjectsSoundWorldCatalog.load(from: bundle).sourceVoices
        func rejectRecipes(_ edit: (inout [String: Any]) -> Void) throws {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: recipesData) as? [String: Any])
            edit(&json)
            XCTAssertThrowsError(try DayObjectsSoundWorldCatalog.load(
                recipesData: JSONSerialization.data(withJSONObject: json), groupsData: groupsData, sourceVoices: sources
            ))
        }
        try rejectRecipes { $0["schemaVersion"] = 2 }
        for mutation in 0..<5 {
            try rejectRecipes { json in
                var recipes = json["recipes"] as! [[String: Any]]
                switch mutation {
                case 0: recipes[1]["id"] = recipes[0]["id"]
                case 1: recipes[0]["moodPatches"] = []
                case 2: recipes[0]["sourceInstrumentID"] = "missing"
                case 3: recipes[0]["outputTrimDB"] = 7
                default: recipes[0]["outputTrimDB"] = -31
                }
                json["recipes"] = recipes
            }
        }
        for mutation in 0..<6 {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: groupsData) as? [String: Any])
            var groups = json["groups"] as! [[String: Any]]
            switch mutation {
            case 0: json["schemaVersion"] = 2
            case 1: groups[1]["id"] = groups[0]["id"]
            case 2: groups[0]["harmonyRecipeIDs"] = ["missing"]
            case 3: groups[0]["drumKitID"] = "missing"
            case 4: groups[0]["guestRecipeIDs"] = ["living.lead.bird-reed", "living.lead.leaf-flute"]
            default: groups[0]["happeningRecipeIDs"] = [99]
            }
            json["groups"] = groups
            XCTAssertThrowsError(try DayObjectsSoundWorldCatalog.load(
                recipesData: recipesData, groupsData: JSONSerialization.data(withJSONObject: json), sourceVoices: sources
            ))
        }
    }

    func testNonFinitePatchIsRejectedBeforeClamping() throws {
        let catalog = try DayObjectsSoundWorldCatalog.load(from: bundle)
        let original = try XCTUnwrap(catalog.recipes.first)
        var patch = original.basePatch
        patch.cutoffMultiplier = .infinity
        let invalid = DayObjectsSynthRecipe(
            id: original.id, world: original.world, role: original.role, family: original.family,
            sourceInstrumentID: original.sourceInstrumentID, basePatch: patch, moodPatches: original.moodPatches,
            referenceMIDI: original.referenceMIDI, outputTrimDB: original.outputTrimDB
        )
        XCTAssertThrowsError(try invalid.resolvedVoice(mood: .sparse, sourceVoices: catalog.sourceVoices))
    }

    func testEveryGroupHasOneCompatibleLeadGuestAndBothNeighborsAreCovered() throws {
        let catalog = try DayObjectsSoundWorldCatalog.load(from: bundle)
        for world in DayObjectsSoundWorld.allCases {
            var neighbors: Set<DayObjectsSoundWorld> = []
            for group in catalog.groups where group.world == world {
                XCTAssertEqual(group.guestRecipeIDs.count, 1)
                let id = try XCTUnwrap(group.guestRecipeIDs.first)
                let recipe = try XCTUnwrap(catalog.recipes.first { $0.id == id })
                XCTAssertEqual(recipe.role, .lead)
                XCTAssertTrue(world.guestNeighbors.contains(recipe.world))
                neighbors.insert(recipe.world)
                for seed in UInt64(0)..<64 {
                    let selection = DayObjectsWorldSelector.makeSelection(
                        remixSeed: seed, forcedWorld: world, forcedMood: group.mood
                    )
                    if let guest = selection.guestWorld { XCTAssertEqual(guest, recipe.world) }
                }
            }
            XCTAssertEqual(neighbors, Set(world.guestNeighbors))
        }
    }

    func testNonAdjacentGuestIsRejected() throws {
        let recipesURL = try XCTUnwrap(bundle.url(forResource: "synth-recipes-v1", withExtension: "json", subdirectory: "SoundWorlds"))
        let groupsURL = try XCTUnwrap(bundle.url(forResource: "world-groups-v1", withExtension: "json", subdirectory: "SoundWorlds"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: groupsURL)) as? [String: Any])
        var groups = json["groups"] as! [[String: Any]]
        groups[0]["guestRecipeIDs"] = ["electric.lead.verbacious"]
        json["groups"] = groups
        XCTAssertThrowsError(try DayObjectsSoundWorldCatalog.load(
            recipesData: Data(contentsOf: recipesURL),
            groupsData: JSONSerialization.data(withJSONObject: json),
            sourceVoices: DayObjectsSoundWorldCatalog.load(from: bundle).sourceVoices
        ))
    }
}
