#if DEBUG || INTERNAL_BUILD
struct DayObjectsWorldSelection: Equatable, Codable, Sendable {
    let world: DayObjectsSoundWorld
    let mood: DayObjectsSoundMood
    let guestWorld: DayObjectsSoundWorld?
}

enum DayObjectsWorldSelector {
    private static let guestChance = 0.15

    static func makeSelection(
        remixSeed: UInt64,
        forcedWorld: DayObjectsSoundWorld? = nil,
        forcedMood: DayObjectsSoundMood? = nil
    ) -> DayObjectsWorldSelection {
        var styleRandom = StableMusicRandom(seed: remixSeed, domain: .worldStyle)
        var moodRandom = StableMusicRandom(seed: remixSeed, domain: .worldMood)
        var guestRandom = StableMusicRandom(seed: remixSeed, domain: .worldGuest)

        let world = forcedWorld
            ?? styleRandom.choice(from: DayObjectsSoundWorld.allCases)
            ?? .feltAndWood
        let mood = forcedMood
            ?? moodRandom.choice(from: DayObjectsSoundMood.allCases)
            ?? .moving
        let guestWorld = guestRandom.bernoulli(probability: guestChance)
            ? guestRandom.choice(from: world.guestNeighbors)
            : nil

        return DayObjectsWorldSelection(
            world: world,
            mood: mood,
            guestWorld: guestWorld
        )
    }
}
#endif
