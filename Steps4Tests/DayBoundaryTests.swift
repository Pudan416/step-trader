import XCTest
@testable import Steps4

final class DayBoundaryTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return comps.date!
    }

    func testCurrentDayStart_customEndTime() {
        let endHour = 4
        let endMinute = 0

        let beforeCutoff = date(2026, 2, 3, 3, 0)
        let startBefore = DayBoundary.currentDayStart(
            for: beforeCutoff,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(startBefore, date(2026, 2, 2, 4, 0))

        let afterCutoff = date(2026, 2, 3, 5, 0)
        let startAfter = DayBoundary.currentDayStart(
            for: afterCutoff,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(startAfter, date(2026, 2, 3, 4, 0))
    }

    func testDayKey_customEndTime() {
        let endHour = 4
        let endMinute = 0
        let beforeCutoff = date(2026, 2, 3, 3, 0)
        let key = DayBoundary.dayKey(
            for: beforeCutoff,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(key, "2026-02-02")
    }

    func testNextBoundary_customEndTime() {
        let endHour = 4
        let endMinute = 0

        let beforeCutoff = date(2026, 2, 3, 3, 0)
        let nextBefore = DayBoundary.nextBoundary(
            after: beforeCutoff,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(nextBefore, date(2026, 2, 3, 4, 0))

        let afterCutoff = date(2026, 2, 3, 5, 0)
        let nextAfter = DayBoundary.nextBoundary(
            after: afterCutoff,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(nextAfter, date(2026, 2, 4, 4, 0))
    }

    func testMidnightEndTimeUsesStartOfDay() {
        let midnight = date(2026, 2, 3, 12, 0)
        let start = DayBoundary.currentDayStart(
            for: midnight,
            dayEndHour: 0,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(start, date(2026, 2, 3, 0, 0))
    }

    // MARK: - Exactly at boundary

    func testCurrentDayStart_exactlyAtBoundary() {
        let exactly = date(2026, 2, 3, 4, 0)
        let start = DayBoundary.currentDayStart(
            for: exactly,
            dayEndHour: 4,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(start, date(2026, 2, 3, 4, 0),
                       "At the boundary, the day start should be the boundary itself")
    }

    func testNextBoundary_exactlyAtBoundary() {
        let exactly = date(2026, 2, 3, 4, 0)
        let next = DayBoundary.nextBoundary(
            after: exactly,
            dayEndHour: 4,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 2, 4, 4, 0),
                       "At the boundary, nextBoundary should be the following day's boundary")
    }

    // MARK: - Non-zero minute component

    func testCurrentDayStart_nonZeroMinute() {
        let endHour = 4
        let endMinute = 30

        let before = date(2026, 2, 3, 4, 15)
        let startBefore = DayBoundary.currentDayStart(
            for: before,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(startBefore, date(2026, 2, 2, 4, 30),
                       "Before 04:30, the day start should be yesterday's 04:30")

        let after = date(2026, 2, 3, 5, 0)
        let startAfter = DayBoundary.currentDayStart(
            for: after,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(startAfter, date(2026, 2, 3, 4, 30))
    }

    func testNextBoundary_nonZeroMinute() {
        let next = DayBoundary.nextBoundary(
            after: date(2026, 2, 3, 4, 15),
            dayEndHour: 4,
            dayEndMinute: 30,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 2, 3, 4, 30))
    }

    // MARK: - Midnight boundary edge cases

    func testNextBoundary_midnightEndTime() {
        let afternoon = date(2026, 2, 3, 14, 0)
        let next = DayBoundary.nextBoundary(
            after: afternoon,
            dayEndHour: 0,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 2, 4, 0, 0))
    }

    func testDayKey_midnightBoundary() {
        let key = DayBoundary.dayKey(
            for: date(2026, 2, 3, 23, 59),
            dayEndHour: 0,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(key, "2026-02-03")
    }

    // MARK: - Late-night boundary

    func testCurrentDayStart_lateNightBoundary() {
        let endHour = 23
        let endMinute = 30

        let before = date(2026, 2, 3, 22, 0)
        let start = DayBoundary.currentDayStart(
            for: before,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(start, date(2026, 2, 2, 23, 30),
                       "Before 23:30, day start should be previous day's 23:30")

        let after = date(2026, 2, 3, 23, 45)
        let startAfter = DayBoundary.currentDayStart(
            for: after,
            dayEndHour: endHour,
            dayEndMinute: endMinute,
            calendar: calendar
        )
        XCTAssertEqual(startAfter, date(2026, 2, 3, 23, 30))
    }

    func testNextBoundary_lateNightBoundary() {
        let next = DayBoundary.nextBoundary(
            after: date(2026, 2, 3, 23, 45),
            dayEndHour: 23,
            dayEndMinute: 30,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 2, 4, 23, 30))
    }

    // MARK: - dayKey with non-zero minute component

    func testDayKey_nonZeroMinuteBoundary() {
        let key = DayBoundary.dayKey(
            for: date(2026, 2, 3, 4, 15),
            dayEndHour: 4,
            dayEndMinute: 30,
            calendar: calendar
        )
        XCTAssertEqual(key, "2026-02-02",
                       "Before 04:30, dayKey should be the previous calendar day")

        let keyAfter = DayBoundary.dayKey(
            for: date(2026, 2, 3, 4, 30),
            dayEndHour: 4,
            dayEndMinute: 30,
            calendar: calendar
        )
        XCTAssertEqual(keyAfter, "2026-02-03",
                       "At or after 04:30, dayKey should be today")
    }

    // MARK: - Year boundary crossing

    func testCurrentDayStart_yearBoundary() {
        let earlyNewYear = date(2026, 1, 1, 2, 0)
        let start = DayBoundary.currentDayStart(
            for: earlyNewYear,
            dayEndHour: 4,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(start, date(2025, 12, 31, 4, 0),
                       "Before 04:00 on Jan 1, the logical day start is Dec 31 04:00")
    }

    func testDayKey_yearBoundary() {
        let key = DayBoundary.dayKey(
            for: date(2026, 1, 1, 2, 0),
            dayEndHour: 4,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(key, "2025-12-31",
                       "Before 04:00 on Jan 1, dayKey should be previous year's last day")
    }

    // MARK: - Midnight exactly with non-midnight boundary

    func testCurrentDayStart_atMidnightWithCustomBoundary() {
        let midnight = date(2026, 2, 4, 0, 0)
        let start = DayBoundary.currentDayStart(
            for: midnight,
            dayEndHour: 4,
            dayEndMinute: 0,
            calendar: calendar
        )
        XCTAssertEqual(start, date(2026, 2, 3, 4, 0),
                       "At midnight with 04:00 boundary, day start is previous calendar day's 04:00")
    }
}
