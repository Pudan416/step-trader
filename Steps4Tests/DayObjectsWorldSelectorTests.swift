#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayObjectsWorldSelectorTests: XCTestCase {
    func testWorldAndMoodCasesStayStable() {
        XCTAssertEqual(DayObjectsSoundWorld.allCases, [
            .feltAndWood, .livingField, .metalAndCurrent, .electricDream,
        ])
        XCTAssertEqual(DayObjectsSoundMood.allCases, [.sparse, .moving, .strange])
        XCTAssertEqual(DayObjectsSoundWorld.feltAndWood.rawValue, "feltAndWood")
        XCTAssertEqual(DayObjectsSoundWorld.metalAndCurrent.rawValue, "metalAndCurrent")
        XCTAssertEqual(MusicSeedDomain.worldGuest.rawValue, "world.guest")
        XCTAssertEqual(DayObjectsSoundWorld.feltAndWood.displayName, "Acoustic Oddities")
        XCTAssertEqual(DayObjectsSoundWorld.metalAndCurrent.displayName, "Industrial Ritual")
    }

    func testGuestNeighborsMatchTheApprovedAdjacencyGraph() {
        XCTAssertEqual(
            DayObjectsSoundWorld.feltAndWood.guestNeighbors,
            [.livingField, .metalAndCurrent]
        )
        XCTAssertEqual(
            DayObjectsSoundWorld.livingField.guestNeighbors,
            [.feltAndWood, .electricDream]
        )
        XCTAssertEqual(
            DayObjectsSoundWorld.metalAndCurrent.guestNeighbors,
            [.electricDream, .feltAndWood]
        )
        XCTAssertEqual(
            DayObjectsSoundWorld.electricDream.guestNeighbors,
            [.livingField, .metalAndCurrent]
        )
    }

    func testSelectionIsDeterministicAndMatchesIndependentGuestOracle() {
        for seed in UInt64(0)..<512 {
            let value = DayObjectsWorldSelector.makeSelection(remixSeed: seed)
            XCTAssertEqual(value, DayObjectsWorldSelector.makeSelection(remixSeed: seed))
            XCTAssertEqual(
                value.guestWorld,
                expectedGuestWorld(remixSeed: seed, world: value.world, mood: value.mood),
                "seed=\(seed) world=\(value.world.rawValue)"
            )
        }
    }

    func testForcedWorldAndMoodOverrideOnlyTheirIndependentSelections() {
        let automatic = DayObjectsWorldSelector.makeSelection(remixSeed: 42)
        let forcedWorld = DayObjectsWorldSelector.makeSelection(
            remixSeed: 42,
            forcedWorld: .electricDream
        )
        let forcedMood = DayObjectsWorldSelector.makeSelection(
            remixSeed: 42,
            forcedMood: .strange
        )

        XCTAssertEqual(forcedWorld.world, .electricDream)
        XCTAssertEqual(forcedWorld.mood, automatic.mood)
        XCTAssertEqual(forcedMood.world, automatic.world)
        XCTAssertEqual(forcedMood.mood, .strange)
    }

    private func expectedGuestWorld(
        remixSeed: UInt64,
        world: DayObjectsSoundWorld,
        mood: DayObjectsSoundMood
    ) -> DayObjectsSoundWorld? {
        var random = StableMusicRandom(
            seed: remixSeed,
            domain: MusicSeedDomain("world.guest")
        )
        guard random.bernoulli(probability: 0.15) else { return nil }
        return expectedGuestNeighbors(for: world)[mood == .moving ? 1 : 0]
    }

    func testEveryForcedWorldMoodUsesExactIndependentFifteenPercentGate() {
        for world in DayObjectsSoundWorld.allCases {
            for mood in DayObjectsSoundMood.allCases {
                for seed in UInt64(0)..<512 {
                    let selection = DayObjectsWorldSelector.makeSelection(
                        remixSeed: seed, forcedWorld: world, forcedMood: mood
                    )
                    XCTAssertEqual(selection.guestWorld,
                                   expectedGuestWorld(remixSeed: seed, world: world, mood: mood))
                }
            }
        }
    }

    private func expectedGuestNeighbors(
        for world: DayObjectsSoundWorld
    ) -> [DayObjectsSoundWorld] {
        switch world {
        case .feltAndWood: [.livingField, .metalAndCurrent]
        case .livingField: [.feltAndWood, .electricDream]
        case .metalAndCurrent: [.electricDream, .feltAndWood]
        case .electricDream: [.livingField, .metalAndCurrent]
        }
    }
}
#endif
