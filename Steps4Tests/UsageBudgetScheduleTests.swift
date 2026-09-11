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

/// Purchased usage survives idle time until the custom day closes.
final class PurchaseExpiryTests: XCTestCase {
    func testTenUsageMinutesRemainAvailableUntilCustomDayBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Belgrade")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 14))!
        let expiry = DayBoundary.purchaseExpiry(minutes: 10, dayEndHour: 1, dayEndMinute: 0,
            now: now, calendar: calendar)
        XCTAssertEqual(expiry, DayBoundary.nextBoundary(after: now, dayEndHour: 1, dayEndMinute: 0, calendar: calendar))
    }
}
