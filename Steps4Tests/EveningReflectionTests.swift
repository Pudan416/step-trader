import XCTest
#if canImport(Steps4)
@testable import Steps4
#endif

final class EveningReflectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Belgrade")!
        return value
    }

    private func date(_ day: Int = 16, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testOnlyAnEmptyEveningQualifiesNeverNightOrDaytime() {
        for (hour, minute, expected) in [(1, 0, false), (19, 59, false), (20, 0, true), (23, 59, true), (0, 0, false)] {
            XCTAssertEqual(EveningReflection.isEligible(at: date(16, hour, minute), isCanvasEmpty: true,
                dismissedDay: "", calendar: calendar), expected, "\(hour):\(minute)")
        }
        XCTAssertFalse(EveningReflection.isEligible(at: date(16, 20), isCanvasEmpty: false,
            dismissedDay: "", calendar: calendar))
    }

    func testDismissalSuppressesOnlyThatCalendarEvening() {
        XCTAssertFalse(EveningReflection.isEligible(at: date(16, 21), isCanvasEmpty: true,
            dismissedDay: "2026-09-16", calendar: calendar))
        XCTAssertTrue(EveningReflection.isEligible(at: date(17, 20), isCanvasEmpty: true,
            dismissedDay: "2026-09-16", calendar: calendar))
    }

    func testPushRequiresOptInAndSkipsFilledAndDismissedDays() {
        XCTAssertTrue(EveningReflection.reminderDates(after: date(16, 10), enabled: false,
            dismissedDay: "", calendar: calendar, isCanvasEmpty: { _ in true }).isEmpty)
        let filled = EveningReflection.reminderDates(after: date(16, 10), enabled: true,
            dismissedDay: "", calendar: calendar, isCanvasEmpty: { $0 >= self.date(17, 0) })
        XCTAssertEqual(filled.first, date(17, 20))
        let dismissed = EveningReflection.reminderDates(after: date(16, 10), enabled: true,
            dismissedDay: "2026-09-16", calendar: calendar, isCanvasEmpty: { _ in true })
        XCTAssertEqual(dismissed.first, date(17, 20))
    }

    func testPushNeverCatchesUpLateAndPlansAreBoundedAndUnique() {
        let dates = EveningReflection.reminderDates(after: date(16, 21), enabled: true,
            dismissedDay: "", calendar: calendar, isCanvasEmpty: { _ in true })
        XCTAssertEqual(dates.first, date(17, 20))
        XCTAssertLessThanOrEqual(dates.count, 14)
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertTrue(dates.allSatisfy { self.calendar.component(.hour, from: $0) == 20 })
    }

    func testLocalClockAndDSTKeepEightPM() {
        var losAngeles = calendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertFalse(EveningReflection.isEligible(at: date(16, 20), isCanvasEmpty: true,
            dismissedDay: "", calendar: losAngeles))
        let beforeDST = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 10))!
        let dates = EveningReflection.reminderDates(after: beforeDST, enabled: true,
            dismissedDay: "", calendar: calendar, isCanvasEmpty: { _ in true })
        XCTAssertGreaterThan(dates.count, 2)
        XCTAssertTrue(dates.allSatisfy { self.calendar.component(.hour, from: $0) == 20 })
        if dates.count > 1 { XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 25 * 3600) }
    }
}
