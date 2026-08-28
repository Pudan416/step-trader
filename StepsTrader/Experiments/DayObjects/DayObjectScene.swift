import Foundation

struct DayObjectScene: Equatable {
    static let maxActors = 10

    let input: DayObjectSceneInput
    let rootSeed: UInt64
    let composition: DayObjectComposition
    let compositionPlan: DayObjectCompositionPlan
    let paletteSet: DayObjectPaletteSet
    let visualLanguage: DayObjectVisualLanguage
    let motionPlan: DayObjectMotionPlan
    let palette: DayObjectPalette
    let meshGradientStyle: DayObjectMeshGradientStyle
    let score: DayObjectChoreographyScore
    let actors: [DayObjectActor]

    var actorIDs: [DayObjectActorID] { actors.map(\.id) }

    func replacingActors(_ actors: [DayObjectActor]) -> DayObjectScene {
        precondition(
            actors.count <= Self.maxActors,
            "Day Objects transition admission exceeded the ten-actor render capacity"
        )
        return DayObjectScene(
            input: input,
            rootSeed: rootSeed,
            composition: composition,
            compositionPlan: compositionPlan,
            paletteSet: paletteSet,
            visualLanguage: visualLanguage,
            motionPlan: motionPlan,
            palette: palette,
            meshGradientStyle: meshGradientStyle,
            score: score,
            actors: actors
        )
    }

    static func make(input rawInput: DayObjectSceneInput) -> DayObjectScene {
        let input = normalized(rawInput)
        let rootSeed = CanvasElement.makeSeed(
            optionId: "dayObjects:\(input.identity)",
            dayKey: input.dayKey,
            index: 0
        )
        let composition = DayObjectComposition.forDay(
            dayKey: input.dayKey,
            identity: input.identity
        )
        let compositionPlan = DayObjectCompositionPlan.make(
            seed: rootSeed,
            uiExclusionRegion: input.uiExclusionRegion,
            canvasCoverage: input.canvasCoverage
        )
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: rootSeed,
            categories: input.paletteCategories
        )
        let visualLanguage = DayObjectVisualLanguage.make(
            rootSeed: rootSeed,
            paletteSet: paletteSet
        )
        let eventIDs = Array(chronologicalUniqueEventIDs(from: input.eventIDs).prefix(maxActors))
        let motionPlan = DayObjectMotionPlan.make(
            rootSeed: rootSeed,
            eventIDs: eventIDs
        )
        let palette = DayObjectPalette.make(modernPalette: paletteSet.background)
        let meshGradientStyle = DayObjectMeshGradientStyle.make(seed: rootSeed, palette: palette)
        let score = DayObjectChoreographyScore.make(seed: rootSeed)
        let appearances = visualLanguage.appearances(
            eventIDs: eventIDs,
            rootSeed: rootSeed
        )
        var actors = [DayObjectActor]()
        actors.reserveCapacity(maxActors)

        for eventID in eventIDs {
            guard let appearance = appearances[eventID],
                  let route = motionPlan.routes[eventID],
                  let depthSchedule = motionPlan.depths[eventID],
                  let encounter = motionPlan.encounters[eventID] else { continue }
            let id = DayObjectActorID(eventID: eventID, memberIndex: 0)
            actors.append(makeActor(
                id: id,
                input: input,
                composition: composition,
                appearance: appearance,
                route: route,
                depthSchedule: depthSchedule,
                encounter: encounter
            ))
        }

        return DayObjectScene(
            input: input,
            rootSeed: rootSeed,
            composition: composition,
            compositionPlan: compositionPlan,
            paletteSet: paletteSet,
            visualLanguage: visualLanguage,
            motionPlan: motionPlan,
            palette: palette,
            meshGradientStyle: meshGradientStyle,
            score: score,
            actors: actors
        )
    }

    private static func normalized(_ input: DayObjectSceneInput) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: input.dayKey,
            identity: input.identity.isEmpty ? "anonymous" : input.identity,
            eventIDs: input.eventIDs,
            motionEnergy: normalizedUnitValue(input.motionEnergy),
            visualClarity: normalizedUnitValue(input.visualClarity),
            reduceMotion: input.reduceMotion,
            uiExclusionRegion: input.uiExclusionRegion,
            canvasCoverage: input.canvasCoverage,
            paletteCategories: input.paletteCategories
        )
    }

    private static func normalizedUnitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func chronologicalUniqueEventIDs(from eventIDs: [String]) -> [String] {
        var seen = Set<String>()
        return eventIDs.filter { seen.insert($0).inserted }
    }

    private static func makeActor(
        id: DayObjectActorID,
        input: DayObjectSceneInput,
        composition: DayObjectComposition,
        appearance: DayObjectAppearance,
        route: DayObjectRoute,
        depthSchedule: DayObjectDepthSchedule,
        encounter: DayObjectEncounter
    ) -> DayObjectActor {
        let actorIdentity = "\(input.identity.utf8.count):\(input.identity):\(id.eventID.utf8.count):\(id.eventID)"
        let seed = CanvasElement.makeSeed(
            optionId: "dayObjects:actor:\(actorIdentity)",
            dayKey: input.dayKey,
            index: id.memberIndex
        )

        func pick<T>(_ options: [T], domain: StaticString) -> T {
            var rng = SeededRNG.derived(from: seed, domain: domain)
            return options[rng.nextInt(in: 0...(options.count - 1))]
        }
        func value(_ range: ClosedRange<Double>, domain: StaticString) -> Double {
            var rng = SeededRNG.derived(from: seed, domain: domain)
            return rng.nextDouble(in: range)
        }

        let role = pick(DayObjectActorRole.allCases, domain: "role")
        let depthBand = pick([0, 1, 2, 3], domain: "depth")
        let sizeOrdinal: Int = {
            let digits = id.eventID.reversed().prefix { $0.isNumber }.reversed()
            if !digits.isEmpty, let ordinal = Int(String(digits)) { return ordinal % 10 }
            var rng = SeededRNG.derived(from: seed, domain: "sizeBand")
            return rng.nextInt(in: 0...9)
        }()
        let sizeBand = composition.sizeComposition.band(for: sizeOrdinal)

        return DayObjectActor(
            id: id,
            seed: seed,
            appearance: appearance,
            route: route,
            depthSchedule: depthSchedule,
            encounter: encounter,
            role: role,
            shape: appearance.shape,
            elongation: .round,
            sizeBand: sizeBand,
            fill: composition.fill,
            trajectory: composition.trajectory,
            spin: composition.spin,
            speedRatio: pick([0.5, 0.75, 1, 1.5, 2], domain: "speed"),
            phaseOffset: value(0...(2 * .pi), domain: "phase"),
            depthBand: depthBand,
            zIndex: Double(depthBand) + value(0...0.999, domain: "zIndex")
        )
    }
}
