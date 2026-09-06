#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class DayObjectsWorldSelectorTests: XCTestCase {
    func testWorldAndMoodCasesStayStable() {
        XCTAssertEqual(DayObjectsSoundWorld.allCases, [
            .feltAndWood, .livingField, .metalAndCurrent, .electricDream,
        ])
        XCTAssertEqual(DayObjectsSoundMood.allCases, [.sparse, .moving, .strange])
        XCTAssertEqual(DayObjectsSoundWorld.feltAndWood.displayName, "Acoustic Oddities")
        XCTAssertEqual(DayObjectsSoundWorld.metalAndCurrent.displayName, "Industrial Ritual")
    }

    func testSelectionIsDeterministicAndGuestIsAdjacent() {
        for seed in UInt64(0)..<512 {
            let value = DayObjectsWorldSelector.makeSelection(remixSeed: seed)
            XCTAssertEqual(value, DayObjectsWorldSelector.makeSelection(remixSeed: seed))
            XCTAssertTrue(value.guestWorld.map(value.world.guestNeighbors.contains) ?? true)
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
}
#endif
