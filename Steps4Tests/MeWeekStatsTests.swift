import XCTest
@testable import Steps4

final class MeWeekStatsTests: XCTestCase {

    private func snap(
        steps: Int = 0,
        sleep: Double = 0,
        happenings: [String] = []
    ) -> PastDaySnapshot {
        PastDaySnapshot(
            inkEarned: 0,
            inkSpent: 0,
            happeningIds: happenings,
            steps: steps,
            sleepHours: sleep
        )
    }

    // MARK: - Summary

    func testEmptyWeekIsAllZeros() {
        let summary = MeWeekStats.summary(snapshots: [])
        XCTAssertEqual(summary, MeWeekStats.Summary())
        XCTAssertTrue(summary.topHappeningIds.isEmpty)
    }

    func testAveragesDivideByTheNumberOfSnapshotsPresent() {
        // Three recorded days; a missing fourth day must not drag the average down.
        let summary = MeWeekStats.summary(snapshots: [
            snap(steps: 9_000, sleep: 8.0),
            snap(steps: 6_000, sleep: 7.0),
            snap(steps: 3_000, sleep: 6.0)
        ])
        XCTAssertEqual(summary.avgSteps, 6_000)
        XCTAssertEqual(summary.avgSleepHours, 7.0, accuracy: 0.0001)
    }

    func testTopHappeningsAreRankedByCountAcrossTheWeek() {
        let summary = MeWeekStats.summary(snapshots: [
            snap(happenings: ["walk", "read"]),
            snap(happenings: ["walk", "call_mom"]),
            snap(happenings: ["walk", "read"])
        ])
        XCTAssertEqual(summary.topHappeningIds, ["walk", "read", "call_mom"])
    }

    func testTopHappeningsBreakTiesByIdSoOrderIsStableAcrossLaunches() {
        let summary = MeWeekStats.summary(snapshots: [
            snap(happenings: ["beta", "alpha", "gamma"])
        ])
        XCTAssertEqual(summary.topHappeningIds, ["alpha", "beta", "gamma"])
    }

    func testTopHappeningsRespectTopCount() {
        let summary = MeWeekStats.summary(
            snapshots: [snap(happenings: ["a", "b", "c", "d"])],
            topCount: 2
        )
        XCTAssertEqual(summary.topHappeningIds, ["a", "b"])
    }

    // MARK: - App spend

    func testAppSpendSumsOnlyTheGivenDays() {
        let byDay = [
            "2026-08-09": ["instagram": 12, "x": 4],
            "2026-08-10": ["instagram": 8],
            "2026-07-01": ["instagram": 999]   // outside the window
        ]
        let spend = MeWeekStats.appSpend(byDay: byDay, dayKeys: ["2026-08-09", "2026-08-10"])
        XCTAssertEqual(spend, ["instagram": 20, "x": 4])
    }

    func testAppSpendIsEmptyWhenNoDaysMatch() {
        let byDay = ["2026-08-09": ["instagram": 12]]
        XCTAssertTrue(MeWeekStats.appSpend(byDay: byDay, dayKeys: ["2026-01-01"]).isEmpty)
    }

    // MARK: - History gate

    func testProUnlocksEveryDay() {
        let keys = ["2026-08-10", "2026-08-09", "2026-08-08"]
        XCTAssertEqual(
            MeWeekStats.unlockedKeys(sortedKeys: keys, isPro: true, freeCount: 2),
            Set(keys)
        )
    }

    func testFreeUnlocksOnlyTheNewestDays() {
        let keys = ["2026-08-10", "2026-08-09", "2026-08-08"]
        XCTAssertEqual(
            MeWeekStats.unlockedKeys(sortedKeys: keys, isPro: false, freeCount: 2),
            ["2026-08-10", "2026-08-09"]
        )
    }

    func testFreeWithFewerDaysThanTheLimitUnlocksEverything() {
        let keys = ["2026-08-10"]
        XCTAssertEqual(
            MeWeekStats.unlockedKeys(sortedKeys: keys, isPro: false, freeCount: 7),
            Set(keys)
        )
    }
}
