import XCTest
@testable import Steps4

/// Palette ranking and the once-a-day freeze.
///
/// Re-sorting after every tap moves buttons under the user's thumb and stops
/// muscle memory forming, so the order is computed once per `dayKey` and cached.
final class HappeningPaletteOrderTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PaletteOrderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func make(_ id: String, count: Int, lastUsed: TimeInterval?) -> Happening {
        Happening(
            id: id, title: id, isBuiltIn: true, useCount: count,
            lastUsedAt: lastUsed.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// `h0` most used … `h(n-1)` least, so the expected top-ten is h0…h9.
    private func catalog(_ n: Int) -> [Happening] {
        (0..<n).map { make("h\($0)", count: n - $0, lastUsed: TimeInterval($0)) }
    }

    private func cache() -> HappeningPaletteOrderCache {
        HappeningPaletteOrderCache(defaults: defaults)
    }

    // MARK: - Ranking

    func testRanksByUseCountDescending() {
        XCTAssertEqual(
            HappeningPaletteOrder.rank([
                make("a", count: 1, lastUsed: nil),
                make("b", count: 9, lastUsed: nil),
                make("c", count: 5, lastUsed: nil)
            ]),
            ["b", "c", "a"]
        )
    }

    func testBreaksTiesByMoreRecentUse() {
        XCTAssertEqual(
            HappeningPaletteOrder.rank([
                make("older", count: 3, lastUsed: 100),
                make("newer", count: 3, lastUsed: 900)
            ]),
            ["newer", "older"]
        )
    }

    func testNeverUsedSortsBelowUsedAtTheSameCount() {
        XCTAssertEqual(
            HappeningPaletteOrder.rank([
                make("never", count: 0, lastUsed: nil),
                make("used", count: 0, lastUsed: 50)
            ]),
            ["used", "never"]
        )
    }

    /// Ranking runs on every palette open; two calls on identical input must
    /// agree, so the comparator falls through to id.
    func testRankIsTotalAndDeterministicForFullTies() {
        let all = [make("b", count: 0, lastUsed: nil), make("a", count: 0, lastUsed: nil)]
        XCTAssertEqual(HappeningPaletteOrder.rank(all), ["a", "b"])
        XCTAssertEqual(HappeningPaletteOrder.rank(all), HappeningPaletteOrder.rank(all))
    }

    /// Built-in and user happenings rank together, with no distinction.
    func testUserHappeningsOutrankBuiltInsOnUse() {
        let ranked = HappeningPaletteOrder.rank([
            make("builtin", count: 1, lastUsed: 10),
            Happening(id: "user_1", title: "Sauna", isBuiltIn: false,
                      useCount: 5, lastUsedAt: Date(timeIntervalSince1970: 10))
        ])
        XCTAssertEqual(ranked, ["user_1", "builtin"])
    }

    func testRankHandlesEmptyInput() {
        XCTAssertTrue(HappeningPaletteOrder.rank([]).isEmpty)
    }

    // MARK: - The day freeze

    func testTakesTopTen() {
        let order = cache().order(for: "2026-08-08", happenings: catalog(15))
        XCTAssertEqual(order.count, 10)
        XCTAssertEqual(order.first, "h0")
        XCTAssertFalse(order.contains("h10"))
    }

    func testReturnsEverythingWhenFewerThanTen() {
        XCTAssertEqual(cache().order(for: "2026-08-08", happenings: catalog(4)).count, 4)
    }

    func testOrderIsStableAcrossOpensWithinOneDay() {
        let c = cache()
        var happenings = catalog(12)
        let first = c.order(for: "2026-08-08", happenings: happenings)

        // A tap happened: the bottom entry is now the most-used by a mile.
        happenings[9].useCount = 999
        happenings[9].lastUsedAt = Date()

        XCTAssertEqual(
            c.order(for: "2026-08-08", happenings: happenings), first,
            "Buttons must not move under the user's thumb mid-day"
        )
    }

    func testOrderReRanksAfterDayKeyRollsOver() {
        let c = cache()
        var happenings = catalog(12)
        let first = c.order(for: "2026-08-08", happenings: happenings)
        XCTAssertNotEqual(first.first, "h11")

        happenings[11].useCount = 999
        happenings[11].lastUsedAt = Date()

        let next = c.order(for: "2026-08-09", happenings: happenings)
        XCTAssertEqual(next.first, "h11", "A new day re-ranks")
        XCTAssertEqual(next.count, 10)
    }

    func testFrozenOrderSurvivesANewCacheInstance() {
        let first = cache().order(for: "2026-08-08", happenings: catalog(12))
        XCTAssertEqual(cache().order(for: "2026-08-08", happenings: catalog(12)), first)
    }

    func testDeletedHappeningDropsOutOfAFrozenOrder() {
        let c = cache()
        let happenings = catalog(12)
        _ = c.order(for: "2026-08-08", happenings: happenings)

        let survivors = happenings.filter { $0.id != "h3" }
        let order = c.order(for: "2026-08-08", happenings: survivors)
        XCTAssertFalse(order.contains("h3"), "A frozen id that no longer exists must not be returned")
    }

    // MARK: - Mid-day creation

    func testMidDayCreationAppendsWithoutReordering() {
        let c = cache()
        var happenings = catalog(12)
        let before = c.order(for: "2026-08-08", happenings: happenings)

        let made = Happening(id: "user_new", title: "Sauna", isBuiltIn: false,
                             useCount: 1, lastUsedAt: Date())
        happenings.append(made)
        c.append(id: made.id, dayKey: "2026-08-08")

        let after = c.order(for: "2026-08-08", happenings: happenings)
        XCTAssertEqual(after.count, 11, "The palette holds eleven on the day of creation")
        XCTAssertEqual(Array(after.prefix(10)), before, "Nothing already on screen moves")
        XCTAssertEqual(after.last, "user_new")
    }

    func testCreatedHappeningTakesItsRankedPositionNextDay() {
        let c = cache()
        var happenings = catalog(12)
        _ = c.order(for: "2026-08-08", happenings: happenings)

        let made = Happening(id: "user_new", title: "Sauna", isBuiltIn: false,
                             useCount: 99, lastUsedAt: Date())
        happenings.append(made)
        c.append(id: made.id, dayKey: "2026-08-08")

        let nextDay = c.order(for: "2026-08-09", happenings: happenings)
        XCTAssertEqual(nextDay.count, 10, "Back to ten the next day")
        XCTAssertEqual(nextDay.first, "user_new", "And it takes its ranked position")
    }

    func testAppendingTwiceDoesNotDuplicate() {
        let c = cache()
        var happenings = catalog(12)
        _ = c.order(for: "2026-08-08", happenings: happenings)

        happenings.append(Happening(id: "user_new", title: "Sauna", isBuiltIn: false,
                                    useCount: 1, lastUsedAt: Date()))
        c.append(id: "user_new", dayKey: "2026-08-08")
        c.append(id: "user_new", dayKey: "2026-08-08")

        XCTAssertEqual(c.order(for: "2026-08-08", happenings: happenings).count, 11)
    }

    /// Appending against a stale day must not corrupt today's frozen order —
    /// the app can be backgrounded across the day boundary.
    func testAppendForAnotherDayIsIgnored() {
        let c = cache()
        var happenings = catalog(12)
        let before = c.order(for: "2026-08-08", happenings: happenings)

        happenings.append(Happening(id: "user_new", title: "Sauna", isBuiltIn: false,
                                    useCount: 1, lastUsedAt: Date()))
        c.append(id: "user_new", dayKey: "2026-08-07")

        XCTAssertEqual(c.order(for: "2026-08-08", happenings: happenings), before)
    }

    func testSeveralMidDayCreationsAllAppendInOrder() {
        let c = cache()
        var happenings = catalog(12)
        _ = c.order(for: "2026-08-08", happenings: happenings)

        for id in ["user_a", "user_b"] {
            happenings.append(Happening(id: id, title: id, isBuiltIn: false,
                                        useCount: 1, lastUsedAt: Date()))
            c.append(id: id, dayKey: "2026-08-08")
        }

        let after = c.order(for: "2026-08-08", happenings: happenings)
        XCTAssertEqual(after.count, 12)
        XCTAssertEqual(Array(after.suffix(2)), ["user_a", "user_b"])
    }
}
