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
                expectedGuestWorld(remixSeed: seed, world: value.world),
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
        world: DayObjectsSoundWorld
    ) -> DayObjectsSoundWorld? {
        var random = StableMusicRandom(
            seed: remixSeed,
            domain: MusicSeedDomain("world.guest")
        )
        guard random.bernoulli(probability: 0.15) else { return nil }
        return random.choice(from: expectedGuestNeighbors(for: world))
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
