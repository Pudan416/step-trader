import XCTest
#if canImport(DeviceActivity)
import DeviceActivity
#endif
@testable import Steps4

/// Regression cover for `ShieldRebuildHelper.usageBudgetSchedule`.
///
/// The bug it guards: `usageBudget_*` monitoring used a fixed
/// `00:00:00 → 23:59:59` interval, and DeviceActivity evaluates event
/// thresholds as usage accumulated **since `intervalStart`**, back-filled from
/// Screen Time history recorded before `startMonitoring` was called. So a
/// 30-minute unlock bought after the user had already watched 30+ minutes of
/// that app the same day satisfied every threshold at once — `usageBudgetDone_`
/// included — and the shield returned roughly a minute after purchase while the
/// colors stayed spent.
#if canImport(DeviceActivity)
final class UsageBudgetScheduleTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Podgorica")!
        return c
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 27
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return calendar.date(from: comps)!
    }

    // MARK: - Anchoring

    /// The core regression: the interval must start at the purchase moment so
    /// thresholds count from zero, not from local midnight.
    func testSchedule_anchorsAtPurchaseMoment_notMidnight() throws {
        // 20:45:36 — the moment `intervalDidStart: usageBudget_…` fired in the
        // report that surfaced this bug.
        let schedule = try XCTUnwrap(
            ShieldRebuildHelper.usageBudgetSchedule(anchoredAt: date(20, 45, 36), calendar: calendar)
        )

        XCTAssertEqual(schedule.intervalStart.hour, 20)
        XCTAssertEqual(schedule.intervalStart.minute, 45)
        XCTAssertEqual(schedule.intervalStart.second, 36)

        // The shape of the old bug: anchored at midnight.
        XCTAssertFalse(
            schedule.intervalStart.hour == 0
                && schedule.intervalStart.minute == 0
                && schedule.intervalStart.second == 0,
            "Interval anchored at midnight — thresholds would count the whole day's usage"
        )
    }

    /// `end < start` is treated as already-ended and kills the monitor, so the
    /// interval must always terminate at end of day rather than wrapping.
    func testSchedule_alwaysEndsAtEndOfDay() throws {
        for hour in [0, 6, 13, 20, 23] {
            let schedule = try XCTUnwrap(
                ShieldRebuildHelper.usageBudgetSchedule(anchoredAt: date(hour, 0, 0), calendar: calendar),
                "Expected a schedule at \(hour):00"
            )
            XCTAssertEqual(schedule.intervalEnd.hour, 23)
            XCTAssertEqual(schedule.intervalEnd.minute, 59)
            XCTAssertEqual(schedule.intervalEnd.second, 59)

            let startSeconds = (schedule.intervalStart.hour ?? 0) * 3600
                + (schedule.intervalStart.minute ?? 0) * 60
                + (schedule.intervalStart.second ?? 0)
            XCTAssertLessThan(startSeconds, 23 * 3600 + 59 * 60 + 59, "Interval must not wrap past midnight")
        }
    }

    func testSchedule_atMidnight_isValid() throws {
        let schedule = try XCTUnwrap(
            ShieldRebuildHelper.usageBudgetSchedule(anchoredAt: date(0, 0, 0), calendar: calendar)
        )
        XCTAssertEqual(schedule.intervalStart.hour, 0)
        XCTAssertEqual(schedule.intervalStart.minute, 0)
        XCTAssertEqual(schedule.intervalStart.second, 0)
    }

    // MARK: - 15-minute minimum interval

    /// Exactly 15 minutes before 23:59:59 — the last moment DeviceActivity accepts.
    func testSchedule_atExactlyMinimumInterval_isValid() {
        XCTAssertNotNil(
            ShieldRebuildHelper.usageBudgetSchedule(anchoredAt: date(23, 44, 59), calendar: calendar)
        )
    }

    /// One second past the limit: `startMonitoring` would throw `intervalTooShort`,
    /// so the builder must report failure and let callers fall back to wall clock.
    func testSchedule_oneSecondUnderMinimumInterval_returnsNil() {
        XCTAssertNil(
            ShieldRebuildHelper.usageBudgetSchedule(anchoredAt: date(23, 45, 0), calendar: calendar)
        )
    }

    func testSchedule_lateEvening_returnsNil() {
        XCTAssertNil(
            ShieldRebuildHelper.usageBudgetSchedule(anchoredAt: date(23, 50, 0), calendar: calendar)
        )
        XCTAssertNil(
            ShieldRebuildHelper.usageBudgetSchedule(anchoredAt: date(23, 59, 59), calendar: calendar)
        )
    }

    // MARK: - Wall-clock fallback

    private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suiteName = "UsageBudgetScheduleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    func testFallbackExpiry_withNoStoredExpiry_isNowPlusBudget() {
        withTemporaryDefaults { defaults in
            let now = date(23, 50, 0)
            let expiry = ShieldRebuildHelper.wallClockFallbackExpiry(
                defaults: defaults, groupId: "G", minutes: 30, now: now
            )
            XCTAssertEqual(expiry.timeIntervalSince(now), 30 * 60, accuracy: 1)
        }
    }

    /// A late-evening fallback must not outlive the day boundary the purchase was
    /// anchored to, otherwise the budget survives the daily reset.
    func testFallbackExpiry_clampsToEarlierStoredExpiry() {
        withTemporaryDefaults { defaults in
            let now = date(23, 50, 0)
            let dayBoundary = date(23, 59, 59)
            defaults.set(dayBoundary, forKey: SharedKeys.usageBudgetExpiryKey("G"))

            let expiry = ShieldRebuildHelper.wallClockFallbackExpiry(
                defaults: defaults, groupId: "G", minutes: 30, now: now
            )
            XCTAssertEqual(expiry, dayBoundary, "Fallback must not extend past the stored day boundary")
        }
    }

    func testFallbackExpiry_keepsBudgetWhenStoredExpiryIsLater() {
        withTemporaryDefaults { defaults in
            let now = date(20, 0, 0)
            defaults.set(date(23, 59, 59), forKey: SharedKeys.usageBudgetExpiryKey("G"))

            let expiry = ShieldRebuildHelper.wallClockFallbackExpiry(
                defaults: defaults, groupId: "G", minutes: 30, now: now
            )
            XCTAssertEqual(expiry.timeIntervalSince(now), 30 * 60, accuracy: 1)
        }
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
}
