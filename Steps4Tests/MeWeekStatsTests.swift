import XCTest
import SwiftUI
import MetalKit
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

final class MeConnectedAppFillTests: XCTestCase {

    func testLargestWeeklySpendFillsTheWholeBlock() {
        XCTAssertEqual(
            MeConnectedAppFill.fraction(spent: 24, maximumSpent: 24),
            1,
            accuracy: 0.0001
        )
    }

    func testHalfTheLargestWeeklySpendFillsHalfTheBlock() {
        XCTAssertEqual(
            MeConnectedAppFill.fraction(spent: 12, maximumSpent: 24),
            0.5,
            accuracy: 0.0001
        )
    }

    func testMissingOrInvalidSpendProducesNoFill() {
        XCTAssertEqual(MeConnectedAppFill.fraction(spent: 0, maximumSpent: 24), 0)
        XCTAssertEqual(MeConnectedAppFill.fraction(spent: 12, maximumSpent: 0), 0)
    }

    func testSpendCannotOverfillTheBlock() {
        XCTAssertEqual(MeConnectedAppFill.fraction(spent: 30, maximumSpent: 24), 1)
    }
}

final class MeCalendarTimelineTests: XCTestCase {

    @MainActor
    func testPosterArtworkLoadingKeepsTheExistingFrameVisible() {
        var existing = DayCanvas(dayKey: "2026-08-29")
        existing.lastModified = Date(timeIntervalSince1970: 100)
        var fallback = DayCanvas(dayKey: "2026-08-29")
        fallback.lastModified = Date(timeIntervalSince1970: 200)

        let visible = MePosterArtworkLoadingPolicy.visibleArtwork(
            existing: existing,
            fallback: fallback
        )

        XCTAssertEqual(visible.lastModified, existing.lastModified)
    }

    @MainActor
    func testPosterCanvasLoaderSharesOneInFlightLoadBetweenConsumers() async {
        var attempts = 0
        let loader = MePosterCanvasLoadCoordinator { dayKey, _ in
            attempts += 1
            try? await Task.sleep(for: .milliseconds(50))
            return DayCanvas(dayKey: dayKey)
        }

        async let posterCanvas = loader.canvas(
            for: "2026-08-28",
            hasTrackedSnapshot: true
        )
        async let tileCanvas = loader.canvas(
            for: "2026-08-28",
            hasTrackedSnapshot: true
        )
        let (poster, tile) = await (posterCanvas, tileCanvas)

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(poster?.dayKey, "2026-08-28")
        XCTAssertEqual(tile?.dayKey, "2026-08-28")
    }

    @MainActor
    func testPosterCanvasLoaderReusesCompletedPastDayLoad() async {
        var attempts = 0
        let loader = MePosterCanvasLoadCoordinator { dayKey, _ in
            attempts += 1
            return DayCanvas(dayKey: dayKey)
        }

        _ = await loader.canvas(
            for: "2026-08-27",
            hasTrackedSnapshot: true
        )
        _ = await loader.canvas(
            for: "2026-08-27",
            hasTrackedSnapshot: true
        )

        XCTAssertEqual(attempts, 1)
    }

    @MainActor
    func testPosterCanvasLoaderRetriesUnresolvedTrackedDayAfterRecovery() async {
        var recovered = false
        let loader = MePosterCanvasLoadCoordinator { dayKey, _ in
            recovered ? DayCanvas(dayKey: dayKey) : nil
        }

        let unavailable = await loader.canvas(for: "2026-08-27", hasTrackedSnapshot: true)
        XCTAssertNil(unavailable)
        recovered = true
        let restored = await loader.canvas(for: "2026-08-27", hasTrackedSnapshot: true)
        XCTAssertEqual(restored?.dayKey, "2026-08-27",
                       "A temporary failure must not hide saved artwork after connectivity recovers")
    }

    func testHistoryThumbnailUsesSavedCanvasEvenWithoutHappenings() throws {
        var canvas = DayCanvas(dayKey: "2026-08-26")
        canvas.gradientPalette = GradientPalette.aurora.rawValue

        let resolved = try XCTUnwrap(
            MeHistoryThumbnailPolicy.canvasForRendering(canvas)
        )

        XCTAssertTrue(resolved.elements.isEmpty)
        XCTAssertEqual(resolved.gradientPalette, GradientPalette.aurora.rawValue)
    }

    func testPosterCarouselHidesAdjacentPagesUntilTheUserScrolls() {
        let viewportWidth: CGFloat = 393
        let sizing = MePosterCarouselLayout.sizing(viewportWidth: viewportWidth)

        XCTAssertEqual(sizing.pageWidth, viewportWidth)
        XCTAssertEqual(sizing.outerContentInset, 0)
        XCTAssertEqual(sizing.pageSpacing, 0)
        XCTAssertLessThan(sizing.posterWidth, sizing.pageWidth)
    }

    func testEveryUnselectedCalendarTileKeepsADiscernibleFullBorder() {
        let metrics = MeCalendarTileBorderStyle.metrics(isSelected: false)

        XCTAssertGreaterThanOrEqual(metrics.lineWidth, 1)
        XCTAssertGreaterThanOrEqual(metrics.opacity, 0.18)
    }

    func testPosterRailAlignsMetricsToLeftArtworkTopAndUnlocksToRightArtworkBottom() {
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
        XCTAssertLessThan(metrics.rotatedFrame.maxX, unlocks.rotatedFrame.minX)
        XCTAssertEqual(metrics.textAlignment, .leading)
        XCTAssertEqual(unlocks.rotatedFrame.maxY, 750, accuracy: 0.001)
        XCTAssertEqual(unlocks.rotatedFrame.maxX, 566.02, accuracy: 0.001)
        XCTAssertEqual(unlocks.textAlignment, .trailing)
    }

    func testCanvasReloadIdentityChangesWhenRemoteSnapshotArrives() {
        let initial = MePosterCanvasLoadID(
            dayKey: "2026-08-22",
            hasTrackedSnapshot: false
        )
        let recovered = MePosterCanvasLoadID(
            dayKey: "2026-08-22",
            hasTrackedSnapshot: true
        )

        XCTAssertNotEqual(initial, recovered)
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

    func testTodayUsesTheCurrentCapturedCanvasWithoutAStoredTrace() {
        XCTAssertEqual(
            MePosterPresentationPolicy.mode(
                isToday: true,
                hasSavedElements: false
            ),
            .currentDay
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
            mode: .currentDay,
            hasElements: false,
            hasStepsData: true,
            hasSleepData: false
        ))
    }

    func testTodayCanShareItsCurrentCanvasBeforeAnyDataArrives() {
        XCTAssertTrue(MePosterPresentationPolicy.canShare(
            mode: .currentDay,
            hasElements: false,
            hasStepsData: false,
            hasSleepData: false
        ))
    }

    func testPersistedPastDayCanShareWhileItsCanvasIsStillLoading() {
        XCTAssertTrue(MePosterPresentationPolicy.canShare(
            mode: .savedPast,
            hasElements: false,
            hasStepsData: true,
            hasSleepData: true
        ))
    }

    func testNeutralPastDayBackgroundCanShareWhenHealthKitIsUnavailable() {
        XCTAssertTrue(MePosterPresentationPolicy.canShare(
            mode: .healthPast,
            hasElements: false,
            hasStepsData: false,
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

@MainActor
final class MePosterSnapshotTests: XCTestCase {
    private func fixtureImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func testSaveDuringAnExistingLoadReadsTheNewCanvasAfterward() async {
        let started = expectation(description: "old canvas read")
        var continuation: CheckedContinuation<DayCanvas?, Never>?
        var reads = 0
        let old = DayCanvas(dayKey: "2026-09-07")
        var updated = old
        updated.remixSeed = 99
        let coordinator = MePosterCanvasLoadCoordinator { _, _ in
            reads += 1
            if reads == 1 {
                return await withCheckedContinuation { continuation = $0; started.fulfill() }
            }
            return updated
        }
        let first = Task { await coordinator.canvas(for: old.dayKey, hasTrackedSnapshot: false) }
        await fulfillment(of: [started], timeout: 2)
        // The actor cannot resume the old read until this task suspends inside
        // the forced reload, so this always exercises the in-flight branch.
        Task { @MainActor in continuation?.resume(returning: old) }
        let loaded = await coordinator.canvas(for: old.dayKey, hasTrackedSnapshot: false, forceRefresh: true)
        _ = await first.value
        XCTAssertEqual(loaded?.remixSeed, 99)
        XCTAssertEqual(reads, 2)
    }

    func testFailedRefreshRetainsThePreviousImageAndRetries() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = fixtureImage(.red), next = fixtureImage(.blue)
        var renders = 0
        let cache = MePosterSnapshotCache(directory: directory) { _, _ in
            renders += 1
            return renders == 1 ? first : (renders == 2 ? nil : next)
        }
        var canvas = DayCanvas(dayKey: "2026-09-07")
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        canvas.remixSeed = 5
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        XCTAssertTrue(cache.cachedImage(for: canvas.dayKey) === first)
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        XCTAssertTrue(cache.cachedImage(for: canvas.dayKey) === next)
        XCTAssertEqual(renders, 3)
    }

    func testSnapshotSurvivesReopeningAndTimestampOnlySavesWithoutRenderingAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = fixtureImage(.red)
        var renders = 0
        let cache = MePosterSnapshotCache(directory: directory) { _, _ in renders += 1; return image }
        var canvas = DayCanvas(dayKey: "2026-09-07")
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        canvas.lastModified = canvas.lastModified.addingTimeInterval(100)
        canvas.soundMoodRaw = "changed-music-only"
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        XCTAssertEqual(renders, 1)
        let reopened = MePosterSnapshotCache(directory: directory) { _, _ in renders += 1; return nil }
        XCTAssertNotNil(reopened.cachedImage(for: canvas.dayKey), "A cached poster must be available synchronously on entry")
        let restored = await reopened.image(for: canvas, categories: ModernPaletteSelection.all)
        XCTAssertNotNil(restored)
        XCTAssertEqual(renders, 1, "App relaunch must reuse the saved bitmap")
    }

    func testSnapshotRefreshesWhenAnElementIsAddedRemovedOrCanvasIsRemixed() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var renders = 0
        let cache = MePosterSnapshotCache(directory: directory) { _, _ in
            renders += 1
            return self.fixtureImage(.blue)
        }
        var canvas = DayCanvas(dayKey: "2026-09-07")
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        canvas.elements = [CanvasElement(id: UUID(), kind: .circle, optionId: "walk", label: "Walk",
            hexColor: "#FF0000", size: 0.2, basePosition: CGPoint(x: 0.5, y: 0.5), phaseOffset: 0,
            driftSpeed: 0, driftAmplitude: 0, pulseFrequency: 0, pulseAmplitude: 0,
            rotationSpeed: 0, opacity: 1, createdAt: Date(timeIntervalSince1970: 100))]
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        canvas.elements.removeAll()
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        canvas.remixSeed = 99
        _ = await cache.image(for: canvas, categories: ModernPaletteSelection.all)
        XCTAssertEqual(renders, 4)
    }

    func testConcurrentRequestsShareRenderingAndAnOlderResultCannotReplaceTheNewSnapshot() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldImage = fixtureImage(.red), newImage = fixtureImage(.blue)
        var pending: CheckedContinuation<UIImage?, Never>?
        var renders = 0
        let started = expectation(description: "old render started")
        let cache = MePosterSnapshotCache(directory: directory) { canvas, _ in
            renders += 1
            if canvas.remixSeed == nil {
                return await withCheckedContinuation { pending = $0; started.fulfill() }
            }
            return newImage
        }
        let original = DayCanvas(dayKey: "2026-09-07")
        let first = Task { await cache.image(for: original, categories: ModernPaletteSelection.all) }
        await fulfillment(of: [started], timeout: 2)
        let duplicate = Task { await cache.image(for: original, categories: ModernPaletteSelection.all) }
        await Task.yield()
        var updated = original
        updated.remixSeed = 42
        _ = await cache.image(for: updated, categories: ModernPaletteSelection.all)
        pending?.resume(returning: oldImage)
        _ = await first.value
        _ = await duplicate.value
        XCTAssertEqual(renders, 2)
        XCTAssertTrue(cache.cachedImage(for: original.dayKey) === newImage)
    }

    func testPosterDisplaysRasterArtworkWithoutStartingAnotherMetalCanvas() async throws {
        let model = AppModel(healthKitService: MockHealthKitService(), familyControlsService: MockFamilyControlsService(),
                             notificationService: MockNotificationService(), budgetEngine: MockBudgetEngine(),
                             subscriptionStore: SubscriptionStore())
        let key = "2099-12-30"
        var saved = DayCanvas(dayKey: key)
        saved.visualStyleRaw = CanvasVisualStyle.editorial.rawValue
        XCTAssertTrue(CanvasStorageService.shared.saveCanvas(saved))
        defer { CanvasStorageService.shared.deleteCanvas(for: key) }
        let loaded = await MePosterCanvasLoadCoordinator.shared.canvas(
            for: key, hasTrackedSnapshot: false, forceRefresh: true)
        XCTAssertEqual(loaded?.resolvedVisualStyle, .editorial)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MePosterSnapshotCache(directory: directory) { _, _ in self.fixtureImage(.red) }
        let poster = MeSelectedDayPoster(snapshots: cache, model: model, dayKey: key,
            snapshot: nil, health: nil, unlockRecords: [], shareRequestID: 0, onShareAvailabilityChange: { _ in })
            .environment(\.appTheme, .night)
            .environment(\.renderingIsActive, true)
        let host = UIHostingController(rootView: poster)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 544))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.beginAppearanceTransition(true, animated: false)
        host.endAppearanceTransition()
        host.view.layoutIfNeeded()
        for _ in 0..<100 {
            if cache.cachedImage(for: key) != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotNil(cache.cachedImage(for: key),
                        "The poster must contain rendered artwork, not just an empty placeholder")
        host.view.layoutIfNeeded()
        func countMetalViews(_ view: UIView) -> Int {
            (view is MTKView ? 1 : 0) + view.subviews.reduce(0) { $0 + countMetalViews($1) }
        }
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let cg = try XCTUnwrap(image.cgImage)
        let center = try XCTUnwrap(cg.cropping(to: CGRect(x: cg.width / 2, y: cg.height / 2, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(pixel[0], 240, "The cached red bitmap must actually be visible in the artwork area")
        XCTAssertLessThan(pixel[1], 15)
        XCTAssertLessThan(pixel[2], 15)
        let attachment = XCTAttachment(image: image)
        attachment.name = "me-static-poster"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(countMetalViews(host.view), 0,
                       "Me must display a cached bitmap, not start a second animated Canvas")
    }
}
