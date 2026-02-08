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
}
