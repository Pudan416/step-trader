import XCTest
@testable import Steps4

/// The `Happening` model and the ten built-ins that replace the 31-option,
/// three-category set. Purely additive at this stage — `EnergyOption` and
/// friends still exist and still compile; Task 5 cuts them over.
final class HappeningModelTests: XCTestCase {

    // MARK: - Built-in set

    func testBuiltInSetIsExactlyTen() {
        XCTAssertEqual(HappeningDefaults.builtIns.count, 10)
    }

    func testBuiltInIdsAreUnique() {
        let ids = HappeningDefaults.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate built-in happening id")
    }

    func testBuiltInsStartUnused() {
        for happening in HappeningDefaults.builtIns {
            XCTAssertTrue(happening.isBuiltIn, "\(happening.id) must be built-in")
            XCTAssertEqual(happening.useCount, 0, "\(happening.id) must start at 0")
            XCTAssertNil(happening.lastUsedAt, "\(happening.id) must start unused")
        }
    }

    func testBuiltInIdsSetMatchesList() {
        XCTAssertEqual(
            HappeningDefaults.builtInIds,
            Set(HappeningDefaults.builtIns.map(\.id))
        )
    }

    /// Built-in ids must not collide with the old `body_`/`mind_`/`heart_`
    /// namespace — those ids still live in users' saved days and get
    /// reconstituted as user happenings.
    func testBuiltInIdsDoNotCollideWithLegacyNamespace() {
        for id in HappeningDefaults.builtInIds {
            XCTAssertTrue(
                id.hasPrefix("happening_"),
                "\(id) must use the happening_ namespace"
            )
        }
    }

    // MARK: - Economy constants

    func testThreePartFormulaStillTotalsOneHundred() {
        XCTAssertEqual(
            EnergyDefaults.stepsMaxPoints
            + EnergyDefaults.sleepMaxPoints
            + HappeningDefaults.happeningsMaxPoints,
            EnergyDefaults.maxBaseEnergy,
            "steps(20) + sleep(20) + happenings(60) = 100"
        )
    }

    func testAdditionPointsReachTheCapAtTen() {
        XCTAssertEqual(
            HappeningDefaults.pointsPerAddition * 10,
            HappeningDefaults.happeningsMaxPoints,
            "Ten additions must exactly reach the ceiling"
        )
    }

    // MARK: - Model behaviour

    func testRoundTripsThroughCodable() throws {
        let original = Happening(
            id: "user_1", title: "Rooftop coffee", isBuiltIn: false,
            useCount: 3, lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Happening.self, from: data), original)
    }

    func testRecordUseIncrementsAndStamps() {
        var happening = HappeningDefaults.builtIns[0]
        let when = Date(timeIntervalSince1970: 500)
        happening.recordUse(at: when)

        XCTAssertEqual(happening.useCount, 1)
        XCTAssertEqual(happening.lastUsedAt, when)
    }

    func testRecordUseAccumulates() {
        var happening = HappeningDefaults.builtIns[0]
        happening.recordUse(at: Date(timeIntervalSince1970: 100))
        happening.recordUse(at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(happening.useCount, 2)
        XCTAssertEqual(happening.lastUsedAt, Date(timeIntervalSince1970: 200))
    }

    /// User happenings carry their title directly — it is already in whatever
    /// language they typed. Only built-ins resolve through the string catalog.
    func testUserHappeningTitleIsUsedVerbatim() {
        let happening = Happening(
            id: "user_1", title: "Крыша, кофе", isBuiltIn: false
        )
        XCTAssertEqual(happening.localizedTitle(), "Крыша, кофе")
    }

    /// Built-ins resolve through `option.title.<id>`, falling back to the
    /// English source string when the key is missing from the catalog.
    func testBuiltInTitleResolvesOrFallsBack() {
        for happening in HappeningDefaults.builtIns {
            XCTAssertFalse(
                happening.localizedTitle().isEmpty,
                "\(happening.id) resolved to an empty title"
            )
        }
    }
}
