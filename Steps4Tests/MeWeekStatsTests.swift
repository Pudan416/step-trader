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

    func testTopHappeningsIncludeCountAndRelativeIntensity() {
        let summary = MeWeekStats.summary(snapshots: [
            snap(happenings: ["walk", "read", "stretch"]),
            snap(happenings: ["walk", "read"]),
            snap(happenings: ["walk"]),
            snap(happenings: ["friends"])
        ])

        XCTAssertEqual(summary.topHappenings, [
            .init(id: "walk", count: 3, relativeIntensity: 1),
            .init(id: "read", count: 2, relativeIntensity: 2.0 / 3.0),
            .init(id: "friends", count: 1, relativeIntensity: 1.0 / 3.0)
        ])
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

    func testComparisonReportsSleepDeltaAndRoundedStepPercentage() {
        let comparison = MeWeekStats.comparison(
            current: .init(avgSteps: 9_200, avgSleepHours: 7.3),
            previous: .init(avgSteps: 8_000, avgSleepHours: 6.9)
        )

        XCTAssertEqual(comparison.sleepHoursDelta ?? .nan, 0.4, accuracy: 0.0001)
        XCTAssertEqual(comparison.stepsPercentDelta, 15)
    }
}

final class MeCalendarTimelineTests: XCTestCase {

    func testPagingMotionMovesNewerPosterInFromTrailingEdgeAndOlderFromLeadingEdge() {
        XCTAssertEqual(
            MePosterPagingMotion.transition(for: .newer, reduceMotion: false),
            .init(insertionEdge: .trailing, removalEdge: .leading, duration: 0.28)
        )
        XCTAssertEqual(
            MePosterPagingMotion.transition(for: .older, reduceMotion: false),
            .init(insertionEdge: .leading, removalEdge: .trailing, duration: 0.28)
        )
    }

    func testPagingMotionDoesNotDragPastNewestDay() {
        let keys = ["2026-08-20", "2026-08-21", "2026-08-22"]

        XCTAssertEqual(
            MePosterPagingMotion.permittedDragTranslation(
                -80,
                from: "2026-08-22",
                dayKeys: keys,
                reduceMotion: false
            ),
            0
        )
        XCTAssertEqual(
            MePosterPagingMotion.permittedDragTranslation(
                80,
                from: "2026-08-22",
                dayKeys: keys,
                reduceMotion: false
            ),
            80
        )
    }

    func testPagingMotionDisablesSpatialMovementForReduceMotion() {
        XCTAssertEqual(
            MePosterPagingMotion.transition(for: .newer, reduceMotion: true),
            .init(insertionEdge: nil, removalEdge: nil, duration: 0.15)
        )
        XCTAssertEqual(
            MePosterPagingMotion.permittedDragTranslation(
                80,
                from: "2026-08-21",
                dayKeys: ["2026-08-20", "2026-08-21", "2026-08-22"],
                reduceMotion: true
            ),
            0
        )
    }

    func testPosterRailAlignsMetricsToArtworkTopAndUnlocksToArtworkBottom() {
        let metrics = MePosterRailLayout.placement(
            for: .metrics,
            ruleRight: 566.02,
            artworkTop: 91,
            artworkBottom: 750,
            railLength: 245,
            lineHeight: 15
        )
        let unlocks = MePosterRailLayout.placement(
            for: .unlocks,
            ruleRight: 566.02,
            artworkTop: 91,
            artworkBottom: 750,
            railLength: 245,
            lineHeight: 15
        )

        XCTAssertEqual(metrics.rotatedFrame.minY, 91, accuracy: 0.001)
        XCTAssertEqual(metrics.rotatedFrame.maxX, 566.02, accuracy: 0.001)
        XCTAssertEqual(metrics.textAlignment, .leading)
        XCTAssertEqual(unlocks.rotatedFrame.maxY, 750, accuracy: 0.001)
        XCTAssertEqual(unlocks.rotatedFrame.maxX, 566.02, accuracy: 0.001)
        XCTAssertEqual(unlocks.textAlignment, .trailing)
    }

    func testPosterPagingStopsAtNewestAndOldestRecentDay() {
        let keys = ["2026-08-20", "2026-08-21", "2026-08-22"]

        XCTAssertNil(MePosterPaging.destination(
            from: "2026-08-22",
            direction: .newer,
            dayKeys: keys
        ))
        XCTAssertNil(MePosterPaging.destination(
            from: "2026-08-20",
            direction: .older,
            dayKeys: keys
        ))
    }

    func testPosterPagingMovesOneCalendarDayInTheRequestedDirection() {
        let keys = ["2026-08-20", "2026-08-21", "2026-08-22"]

        XCTAssertEqual(MePosterPaging.destination(
            from: "2026-08-21",
            direction: .newer,
            dayKeys: keys
        ), "2026-08-22")
        XCTAssertEqual(MePosterPaging.destination(
            from: "2026-08-21",
            direction: .older,
            dayKeys: keys
        ), "2026-08-20")
    }

    func testSevenCompactCalendarTilesNeverExceedTheirContainer() {
        let width = MeCalendarTileLayout.tileWidth(
            containerWidth: 320,
            count: 7,
            spacing: 4,
            displayScale: 3
        )

        XCTAssertLessThanOrEqual(width * 7 + 4 * 6, 320.001)
        XCTAssertGreaterThan(width, 0)
        XCTAssertEqual((width * 3).rounded(), width * 3)
    }

    func testTimelineShowsSevenConsecutiveDaysEndingTodayWhenHistoryIsShort() throws {
        let calendar = makeCalendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 16
        )))

        let keys = MeCalendarTimeline.dayKeys(
            trackedDayKeys: ["2026-08-15"],
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(keys, [
            "2026-08-10",
            "2026-08-11",
            "2026-08-12",
            "2026-08-13",
            "2026-08-14",
            "2026-08-15",
            "2026-08-16"
        ])
    }

    func testTimelineIgnoresOlderHistoryAndShowsOnlyTheLatestSevenDays() throws {
        let calendar = makeCalendar()
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 16
        )))

        let keys = MeCalendarTimeline.dayKeys(
            trackedDayKeys: ["2026-08-02", "2026-08-15"],
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(keys, [
            "2026-08-10",
            "2026-08-11",
            "2026-08-12",
            "2026-08-13",
            "2026-08-14",
            "2026-08-15",
            "2026-08-16"
        ])
    }

    func testMonthGridStartsOnTheConfiguredFirstWeekday() throws {
        let calendar = makeCalendar()
        let august = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 16
        )))

        let cells = MeCalendarTimeline.monthDays(containing: august, calendar: calendar)

        XCTAssertEqual(cells.prefix(5).compactMap { $0 }.count, 0)
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)
        XCTAssertEqual(cells.compactMap { $0 }.first.map {
            MeCalendarTimeline.dayKey(for: $0, calendar: calendar)
        }, "2026-08-01")
        XCTAssertEqual(cells.count, 36)
    }

    func testLogicalTodayStaysOnPreviousDateBeforeConfiguredDayEnd() throws {
        let calendar = makeCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 1,
            hour: 2
        )))

        let logicalToday = MeCalendarTimeline.logicalToday(
            now: now,
            dayEndHour: 4,
            dayEndMinute: 0,
            calendar: calendar
        )

        XCTAssertEqual(
            MeCalendarTimeline.dayKey(for: logicalToday, calendar: calendar),
            "2026-08-31"
        )
    }

    func testRemoteRecoveryOnlyRunsForKnownTrackedDays() {
        XCTAssertTrue(MeCalendarTimeline.shouldAttemptRemoteRecovery(
            hasTrackedSnapshot: true,
            localCanvasMissing: true
        ))
        XCTAssertFalse(MeCalendarTimeline.shouldAttemptRemoteRecovery(
            hasTrackedSnapshot: false,
            localCanvasMissing: true
        ))
        XCTAssertFalse(MeCalendarTimeline.shouldAttemptRemoteRecovery(
            hasTrackedSnapshot: true,
            localCanvasMissing: false
        ))
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}

final class MePosterEventLedgerTests: XCTestCase {

    func testUnlocksCountOnlySuccessfulEntriesFromTheSelectedLogicalDay() throws {
        let calendar = makeCalendar()
        let records = [
            MePosterUnlockRecord(
                timestamp: try date(2026, 8, 20, 8, calendar: calendar),
                target: "group_instagram",
                targetName: "Instagram",
                minutes: 10
            ),
            MePosterUnlockRecord(
                timestamp: try date(2026, 8, 20, 21, calendar: calendar),
                target: "group_instagram",
                targetName: "Instagram",
                minutes: 20
            ),
            MePosterUnlockRecord(
                timestamp: try date(2026, 8, 21, 1, calendar: calendar),
                target: "group_telegram",
                targetName: "Telegram",
                minutes: 15
            ),
            MePosterUnlockRecord(
                timestamp: try date(2026, 8, 21, 6, calendar: calendar),
                target: "group_instagram",
                targetName: "Instagram",
                minutes: 60
            )
        ]

        let unlocks = MePosterEventLedger.unlocks(
            records: records,
            dayKey: "2026-08-20",
            dayEndHour: 4,
            dayEndMinute: 0,
            calendar: calendar
        )

        XCTAssertEqual(unlocks, [
            .init(title: "Instagram", count: 2, minutes: 30),
            .init(title: "Telegram", count: 1, minutes: 15)
        ])
    }

    func testDisplayEventsUseSentenceCaseAndDoNotMixUnlocksIntoHappenings() {
        let events = MePosterEventLedger.displayEvents(
            happeningTitles: ["WALK", "READ", "WALK", "TIME OUTSIDE"]
        )

        XCTAssertEqual(events, [
            "Walk",
            "Read",
            "Time outside"
        ])
    }

    func testDisplayEventsPreserveIntentionalMixedCaseNames() {
        let events = MePosterEventLedger.displayEvents(
            happeningTitles: ["Call iPhone repair", "Read"]
        )

        XCTAssertEqual(events, ["Call iPhone repair", "Read"])
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }
}

final class MePosterPresentationPolicyTests: XCTestCase {

    func testTodayUsesTheLiveCanvasWithoutAStoredTrace() {
        XCTAssertEqual(
            MePosterPresentationPolicy.mode(
                isToday: true,
                hasSavedElements: false
            ),
            .liveToday
        )
    }

    func testPastDayWithoutSavedElementsUsesTheEmptyState() {
        XCTAssertEqual(
            MePosterPresentationPolicy.mode(
                isToday: false,
                hasSavedElements: false,
                hasHealthData: false
            ),
            .emptyPast
        )
    }

    func testPastDayWithHealthDataUsesItsEnergyBackgroundWithoutSavedElements() {
        XCTAssertEqual(
            MePosterPresentationPolicy.mode(
                isToday: false,
                hasSavedElements: false,
                hasHealthData: true
            ),
            .healthPast
        )
    }

    func testPastDayWithSavedElementsUsesItsPersistedCanvas() {
        XCTAssertEqual(
            MePosterPresentationPolicy.mode(
                isToday: false,
                hasSavedElements: true
            ),
            .savedPast
        )
    }

    func testTodayCanShareMeaningfulLiveHealthDataWithoutHappenings() {
        XCTAssertTrue(MePosterPresentationPolicy.canShare(
            mode: .liveToday,
            hasElements: false,
            hasStepsData: true,
            hasSleepData: false
        ))
    }

    func testEmptyPastDayCannotShare() {
        XCTAssertFalse(MePosterPresentationPolicy.canShare(
            mode: .emptyPast,
            hasElements: false,
            hasStepsData: true,
            hasSleepData: true
        ))
    }
}

final class MeHappeningPreviewStyleTests: XCTestCase {

    private let ids = ["walk", "read", "friends"]
    private let palette = ["#CC5050", "#8878B8", "#6098CC"]

    func testPreviewAssignmentsExcludeRaysAndUseDistinctPaletteColours() {
        let assignments = MeHappeningPreviewStyle.assignments(
            for: ids,
            dayKey: "2026-08-16",
            allowedShapes: [.circle, .snowflake, .rays, .organicBlob],
            palette: palette
        )

        XCTAssertEqual(Set(assignments.values.map(\.colorHex)), Set(palette))
        XCTAssertTrue(assignments.values.allSatisfy { $0.shapeType != .rays })
    }

    func testPreviewAssignmentsStayStableForTheDayAndChangeTheNextDay() {
        let today = MeHappeningPreviewStyle.assignments(
            for: ids,
            dayKey: "2026-08-16",
            allowedShapes: [.circle, .snowflake, .organicBlob],
            palette: palette
        )
        let todayAgain = MeHappeningPreviewStyle.assignments(
            for: ids,
            dayKey: "2026-08-16",
            allowedShapes: [.circle, .snowflake, .organicBlob],
            palette: palette
        )
        let tomorrow = MeHappeningPreviewStyle.assignments(
            for: ids,
            dayKey: "2026-08-17",
            allowedShapes: [.circle, .snowflake, .organicBlob],
            palette: palette
        )

        XCTAssertEqual(today, todayAgain)
        XCTAssertNotEqual(today, tomorrow)
    }

    func testPreviewFallsBackToClosedShapesWhenRaysAreTheOnlyUserChoice() {
        let assignments = MeHappeningPreviewStyle.assignments(
            for: ids,
            dayKey: "2026-08-16",
            allowedShapes: [.rays],
            palette: palette
        )

        XCTAssertEqual(assignments.count, ids.count)
        XCTAssertTrue(assignments.values.allSatisfy { $0.shapeType != .rays })
    }

    func testPreviewElementUsesTheAssignedColourInsteadOfASectionWideTint() throws {
        let assignment = HappeningShapeAssignment(
            shapeType: .organicBlob,
            colorHex: "#6098CC",
            seed: 42,
            rotation: 0.5
        )

        let element = MeHappeningPreviewStyle.previewElement(
            optionId: "walk",
            label: "Walk",
            assignment: assignment
        )

        XCTAssertEqual(element.hexColor, "#6098CC")
        XCTAssertEqual(element.frozenShapeType, .organicBlob)
        XCTAssertEqual(element.shapeSeed, 42)
    }
}
