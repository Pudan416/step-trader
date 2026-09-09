#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsSoundWorldCatalogError: Error, Equatable {
    case resourceMissing(String)
    case unsupportedSchema(Int)
    case duplicateID(String)
    case unknownSource(String)
    case invalidRecipe(String)
    case invalidGroup(String)
    case incompleteCatalog
}

/// One resource decision shared by planning and playback. The optional world
/// catalog remains strict, while valid legacy sources can keep Sound available.
struct DayObjectsSoundWorldResources {
    static let bundled = Self(bundle: .main)

    let catalog: DayObjectsSoundWorldCatalog?
    let catalogError: Error?
    private let instruments: Result<[DayObjectsInstrumentID: NormalizedSynthVoice], Error>

    var descriptors: [DayObjectsInstrumentDescriptor] {
        DayObjectsInstrumentManifest.defaultDescriptors + (catalog?.descriptors ?? [])
    }

    init(
        bundle: Bundle,
        catalogLoader: (Bundle) throws -> DayObjectsSoundWorldCatalog = DayObjectsSoundWorldCatalog.load(from:)
    ) {
        do {
            let loaded = try catalogLoader(bundle)
            try loaded.validate()
            catalog = loaded
            catalogError = nil
            instruments = .success(loaded.sourceVoices.merging(loaded.resolvedInstruments) { _, recipe in recipe })
        } catch {
            catalog = nil
            catalogError = error
            // Retain a source failure as a preparation error; only optional
            // world resources are allowed to degrade to legacy playback.
            instruments = Result {
                let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: bundle)
                return try SynthOnePresetAdapter.convertSelectedRecords(records)
            }
        }
    }

    func tonalInstruments() throws -> [DayObjectsInstrumentID: NormalizedSynthVoice] {
        try instruments.get()
    }
}

struct DayObjectsCompatibilityGroup: Codable, Equatable, Sendable {
    let id: String
    let world: DayObjectsSoundWorld
    let mood: DayObjectsSoundMood
    let harmonyRecipeIDs: [DayObjectsInstrumentID]
    let bassRecipeIDs: [DayObjectsInstrumentID]
    let leadRecipeIDs: [DayObjectsInstrumentID]
    let drumKitID: String
    let happeningRecipeIDs: [HappeningSoundRecipeID]
    let guestRecipeIDs: [DayObjectsInstrumentID]
    var masterMakeupDB: Double? = nil
    var reverbSendScale: Double? = nil

    var calibration: DayObjectsWorldGroupCalibration {
        .init(masterMakeupDB: masterMakeupDB ?? 0, reverbSendScale: reverbSendScale ?? 1)
    }

    var hasValidCalibration: Bool {
        (masterMakeupDB.map { $0.isFinite && DayObjectsWorldGroupCalibration.makeupBounds.contains($0) } ?? true)
            && (reverbSendScale.map { $0.isFinite && DayObjectsWorldGroupCalibration.reverbScaleBounds.contains($0) } ?? true)
    }
}

struct DayObjectsSoundWorldCatalog: Sendable {
    let recipes: [DayObjectsSynthRecipe]
    let groups: [DayObjectsCompatibilityGroup]
    let sourceVoices: [DayObjectsInstrumentID: NormalizedSynthVoice]
    private(set) var resolvedInstruments: [DayObjectsInstrumentID: NormalizedSynthVoice] = [:]

    var descriptors: [DayObjectsInstrumentDescriptor] {
        recipes.flatMap { recipe in
            DayObjectsSoundMood.allCases.compactMap { mood in
                resolvedInstruments[recipe.resolvedInstrumentID(for: mood)].map {
                    DayObjectsInstrumentManifest.descriptor(recipe: recipe, mood: mood, voice: $0)
                }
            }
        }
    }

    static func load(from bundle: Bundle) throws -> Self {
        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "SoundWorlds") else {
                throw DayObjectsSoundWorldCatalogError.resourceMissing(name)
            }
            return try Data(contentsOf: url)
        }
        let records = try DayObjectsInstrumentManifest.loadSynthOneRecords(from: bundle)
        return try load(
            recipesData: data("synth-recipes-v1"), groupsData: data("world-groups-v1"),
            sourceVoices: SynthOnePresetAdapter.convertSelectedRecords(records)
        )
    }

    static func load(
        recipesData: Data, groupsData: Data,
        sourceVoices: [DayObjectsInstrumentID: NormalizedSynthVoice]
    ) throws -> Self {
        struct RecipeDocument: Decodable {
            let schemaVersion: Int
            let recipes: [DayObjectsSynthRecipe]
        }
        struct GroupDocument: Decodable {
            let schemaVersion: Int
            let groups: [DayObjectsCompatibilityGroup]
        }
        let recipeDocument = try JSONDecoder().decode(RecipeDocument.self, from: recipesData)
        let groupDocument = try JSONDecoder().decode(GroupDocument.self, from: groupsData)
        for version in [recipeDocument.schemaVersion, groupDocument.schemaVersion] where version != 1 {
            throw DayObjectsSoundWorldCatalogError.unsupportedSchema(version)
        }
        var catalog = Self(recipes: recipeDocument.recipes, groups: groupDocument.groups, sourceVoices: sourceVoices)
        try catalog.validate()
        for recipe in catalog.recipes {
            for mood in DayObjectsSoundMood.allCases {
                catalog.resolvedInstruments[recipe.resolvedInstrumentID(for: mood)] = try recipe.resolvedVoice(
                    mood: mood, sourceVoices: sourceVoices
                )
            }
        }
        return catalog
    }

    func recipes(world: DayObjectsSoundWorld, role: DayObjectsSynthRole) -> [DayObjectsSynthRecipe] {
        recipes.filter { $0.world == world && $0.role == role }
    }

    func resolvedVoices(
        world: DayObjectsSoundWorld, role: DayObjectsSynthRole, mood: DayObjectsSoundMood = .sparse
    ) throws -> [NormalizedSynthVoice] {
        try recipes(world: world, role: role).map { recipe in
            guard let voice = resolvedInstruments[recipe.resolvedInstrumentID(for: mood)] else {
                throw DayObjectsSoundWorldCatalogError.invalidRecipe(recipe.id.rawValue)
            }
            return voice
        }
    }

    func validate() throws {
        var recipeIDs: Set<DayObjectsInstrumentID> = []
        var runtimeIDs = Set(sourceVoices.keys)
        let licensedSources = Set(DayObjectsInstrumentManifest.defaultDescriptors.map(\.id))
        for recipe in recipes {
            guard recipeIDs.insert(recipe.id).inserted else {
                throw DayObjectsSoundWorldCatalogError.duplicateID(recipe.id.rawValue)
            }
            guard licensedSources.contains(recipe.sourceInstrumentID) else {
                throw DayObjectsSoundWorldCatalogError.unknownSource(recipe.sourceInstrumentID.rawValue)
            }
            try recipe.validate(sourceVoices: sourceVoices)
            for mood in DayObjectsSoundMood.allCases {
                let id = recipe.resolvedInstrumentID(for: mood)
                guard runtimeIDs.insert(id).inserted else {
                    throw DayObjectsSoundWorldCatalogError.duplicateID(id.rawValue)
                }
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        var groupIDs: Set<String> = []
        for group in groups {
            guard groupIDs.insert(group.id).inserted else {
                throw DayObjectsSoundWorldCatalogError.duplicateID(group.id)
            }
            let members: [(DayObjectsSynthRole, [DayObjectsInstrumentID])] = [
                (.harmony, group.harmonyRecipeIDs), (.bass, group.bassRecipeIDs), (.lead, group.leadRecipeIDs)
            ]
            guard !group.id.isEmpty, group.hasValidCalibration, group.guestRecipeIDs.count <= 1,
                  Self.drumKitIDs[group.world]?.contains(group.drumKitID) == true,
                  !group.happeningRecipeIDs.isEmpty,
                  Set(group.happeningRecipeIDs).count == group.happeningRecipeIDs.count,
                  group.happeningRecipeIDs.allSatisfy({ HappeningSoundCatalog.recipe(for: $0) != nil }),
                  group.guestRecipeIDs.allSatisfy({ id in
                      guard let recipe = byID[id] else { return false }
                      return group.world.guestNeighbors.contains(recipe.world)
                  }),
                  members.allSatisfy({ role, ids in
                      !ids.isEmpty && Set(ids).count == ids.count && ids.allSatisfy {
                          byID[$0]?.world == group.world && byID[$0]?.role == role
                      }
                  }) else {
                throw DayObjectsSoundWorldCatalogError.invalidGroup(group.id)
            }
        }
        guard recipes.count == 48, groups.count == 12 else {
            throw DayObjectsSoundWorldCatalogError.incompleteCatalog
        }
        for world in DayObjectsSoundWorld.allCases {
            for role in DayObjectsSynthRole.allCases {
                let families = recipes(world: world, role: role)
                guard families.count == 4, Set(families.map(\.family)).count == 4 else {
                    throw DayObjectsSoundWorldCatalogError.incompleteCatalog
                }
                for mood in DayObjectsSoundMood.allCases {
                    let fingerprints = try families.map { try $0.fingerprint(mood: mood, sourceVoices: sourceVoices) }
                    guard Set(fingerprints).count == 4 else {
                        throw DayObjectsSoundWorldCatalogError.invalidRecipe("\(world.rawValue).\(role.rawValue)")
                    }
                }
            }
            for mood in DayObjectsSoundMood.allCases {
                guard groups.filter({ $0.world == world && $0.mood == mood }).count == 1 else {
                    throw DayObjectsSoundWorldCatalogError.incompleteCatalog
                }
            }
        }
    }

    // Portable kit references shared with the drum recipe catalog introduced in Task 3.
    static let drumKitIDs: [DayObjectsSoundWorld: Set<String>] = [
        .feltAndWood: ["acoustic.skin-and-wood", "acoustic.brushed-room", "acoustic.prepared-table"],
        .livingField: ["living.seed-shaker", "living.rain-pulse", "living.stone-breath"],
        .metalAndCurrent: ["industrial.plate-and-piston", "industrial.foundry-pulse", "industrial.wire-ritual"],
        .electricDream: ["electric.soft-machine", "electric.neon-drum", "electric.circuit-dust"]
    ]
}
#endif
