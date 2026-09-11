import XCTest
#if canImport(DeviceActivity)
import DeviceActivity
#endif
@testable import Steps4

#if canImport(DeviceActivity)
final class UsageBudgetScheduleTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 27,
                                          hour: hour, minute: minute, second: second))!
    }

    func testScheduleEndsAtPurchaseDeadlineWithoutRepeating() throws {
        let now = date(14, 0)
        let expiry = date(15, 0)
        let schedule = try XCTUnwrap(ShieldRebuildHelper.usageBudgetSchedule(
            endingAt: expiry, anchoredAt: now, calendar: calendar))
        XCTAssertEqual(calendar.date(from: schedule.intervalStart), now)
        XCTAssertEqual(calendar.date(from: schedule.intervalEnd), expiry)
        XCTAssertFalse(schedule.repeats)
    }

    func testPaddedAbsoluteDatesDescribeTheCurrentIntervalInDeviceActivity() throws {
        let now = Date.now
        let expiry = now.addingTimeInterval(10 * 60)
        let schedule = try XCTUnwrap(ShieldRebuildHelper.usageBudgetSchedule(
            endingAt: expiry, anchoredAt: now, calendar: calendar))
        let interval = try XCTUnwrap(schedule.nextInterval)
        XCTAssertLessThanOrEqual(interval.start, now)
        XCTAssertGreaterThanOrEqual(interval.end, expiry)
        XCTAssertLessThan(interval.end.timeIntervalSince(expiry), 1)
        XCTAssertGreaterThanOrEqual(interval.duration, 15 * 60)
    }

    func testTenMinuteWindowPadsOnlyStartToMeetMinimumInterval() throws {
        let now = date(14, 0)
        let expiry = date(14, 10)
        let schedule = try XCTUnwrap(ShieldRebuildHelper.usageBudgetSchedule(
            endingAt: expiry, anchoredAt: now, calendar: calendar))
        XCTAssertEqual(calendar.date(from: schedule.intervalStart), date(13, 55))
        XCTAssertEqual(calendar.date(from: schedule.intervalEnd), expiry)
    }

    func testShortWindowAtMidnightKeepsAbsoluteDates() throws {
        let now = date(23, 58)
        let expiry = calendar.date(byAdding: .minute, value: 2, to: now)!
        let schedule = try XCTUnwrap(ShieldRebuildHelper.usageBudgetSchedule(
            endingAt: expiry, anchoredAt: now, calendar: calendar))
        XCTAssertEqual(calendar.date(from: schedule.intervalStart), date(23, 45))
        XCTAssertEqual(calendar.date(from: schedule.intervalEnd), expiry)
        XCTAssertEqual(schedule.intervalEnd.day, 28)
    }

    func testShortWindowAfterMidnightPadsIntoPreviousDate() throws {
        let now = date(0, 1)
        let expiry = date(0, 11)
        let schedule = try XCTUnwrap(ShieldRebuildHelper.usageBudgetSchedule(
            endingAt: expiry, anchoredAt: now, calendar: calendar))
        XCTAssertEqual(schedule.intervalStart.day, 26)
        XCTAssertEqual(schedule.intervalStart.hour, 23)
        XCTAssertEqual(schedule.intervalStart.minute, 56)
        XCTAssertEqual(calendar.date(from: schedule.intervalEnd), expiry)
    }

    func testExpiredDeadlineDoesNotRegisterAnotherInterval() {
        XCTAssertNil(ShieldRebuildHelper.usageBudgetSchedule(
            endingAt: date(14, 0), anchoredAt: date(14, 0), calendar: calendar))
    }

    func testFractionalDeadlineDoesNotEndBeforeExpiryCheckCanPass() throws {
        let expiry = date(14, 10).addingTimeInterval(0.75)
        let schedule = try XCTUnwrap(ShieldRebuildHelper.usageBudgetSchedule(
            endingAt: expiry, anchoredAt: date(14, 0), calendar: calendar))
        let end = try XCTUnwrap(calendar.date(from: schedule.intervalEnd))
        XCTAssertGreaterThanOrEqual(end, expiry)
        XCTAssertLessThan(end.timeIntervalSince(expiry), 1)
        let start = try XCTUnwrap(calendar.date(from: schedule.intervalStart))
        XCTAssertGreaterThanOrEqual(end.timeIntervalSince(start), 15 * 60)
    }
}
#endif

/// Cover for `DayBoundary.purchaseExpiry`.
///
/// The bug it guards: every purchase stamped `usageBudgetExpiry_*` at the end of the
/// user's custom day regardless of how many minutes were actually bought, so
/// `shouldSkipShieldingDueToActiveUsageBudget` had no real deadline to enforce. The only
/// thing that could re-shield before the day rolled over was the DeviceActivity
/// usage-tick chain — so a window whose ticks never arrived (monitoring failed to
/// register, or the user simply never accumulated that much foreground usage) stayed
/// open, and ten purchased minutes bought the rest of the evening.
///
/// The calendar is injected rather than taken from the device so these assertions mean
/// the same thing on every machine and on CI.
final class PurchaseExpiryTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Podgorica")!
        return c
    }()

    /// 2026-07-27 — no DST transition that week, so these cases exercise the expiry
    /// rule itself rather than `DayBoundary`'s clock-change behaviour.
    private func date(_ hour: Int, _ minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 27
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    private func expiry(minutes: Int, at now: Date, dayEnd: (hour: Int, minute: Int) = (4, 0)) -> Date {
        DayBoundary.purchaseExpiry(
            minutes: minutes,
            dayEndHour: dayEnd.hour,
            dayEndMinute: dayEnd.minute,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - The regression

    /// A ten-minute purchase must expire in ten minutes, not in fourteen hours.
    func testExpiryIsPurchaseMomentPlusMinutes_notEndOfDay() {
        let now = date(14, 0)
        let result = expiry(minutes: 10, at: now)

        XCTAssertEqual(result.timeIntervalSince(now), 10 * 60, accuracy: 1)

        let dayEnd = DayBoundary.nextBoundary(
            after: now, dayEndHour: 4, dayEndMinute: 0, calendar: calendar
        )
        XCTAssertEqual(dayEnd.timeIntervalSince(now), 14 * 3600, accuracy: 1,
                       "sanity: the old behaviour would have granted this much")
        XCTAssertLessThan(result, dayEnd)
    }

    // MARK: - Boundary clamp

    /// Day-boundary resets clear budgets, so an expiry past the boundary could never be
    /// honoured — it must be pulled back to the boundary itself.
    func testExpiryClampsAtCustomDayBoundary() {
        let result = expiry(minutes: 60, at: date(3, 30))
        XCTAssertEqual(result, date(4, 0))
    }

    func testExpiryClampsAtMidnightBoundary() {
        let now = date(23, 30)
        let result = expiry(minutes: 60, at: now, dayEnd: (0, 0))
        XCTAssertEqual(result.timeIntervalSince(now), 30 * 60, accuracy: 1)
    }

    // MARK: - Extending

    /// Unlike `wallClockFallbackExpiry`, which clamps against whatever is already on
    /// disk, extending a window has to be able to move the deadline later.
    func testExtendingPushesTheDeadlineOut() {
        let now = date(14, 0)
        XCTAssertGreaterThan(expiry(minutes: 40, at: now), expiry(minutes: 10, at: now))
    }

    // MARK: - Degenerate input

    func testNonPositiveMinutesNeverExpireInThePast() {
        let now = date(14, 0)
        XCTAssertEqual(expiry(minutes: 0, at: now), now)
        XCTAssertEqual(expiry(minutes: -5, at: now), now)
    }
    func testExtensionPreservesRemainingSecondsWithoutRoundingThemUp() {
        let now = date(14, 0)
        let existing = now.addingTimeInterval(30)
        let result = DayBoundary.purchaseExpiry(minutes: 10, dayEndHour: 4, dayEndMinute: 0,
            now: now, calendar: calendar, extending: existing)
        XCTAssertEqual(result.timeIntervalSince(now), 630)
    }

    func testExpiredWindowCannotBeResurrectedByAnExtension() {
        let now = date(14, 0)
        let result = DayBoundary.purchaseExpiry(minutes: 10, dayEndHour: 4, dayEndMinute: 0,
            now: now, calendar: calendar, extending: now.addingTimeInterval(-30))
        XCTAssertEqual(result.timeIntervalSince(now), 600)
    }

}
