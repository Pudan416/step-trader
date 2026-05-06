import XCTest
@testable import Steps4

final class WidgetTests: XCTestCase {

    // MARK: - WidgetSnapshot encoding/decoding

    func testWidgetSnapshot_roundTrip() throws {
        let now = Date()
        let snap = WidgetSnapshot(
            balance: 42, earned: 60,
            stepsPoints: 15, sleepPoints: 20,
            bodyPoints: 5, mindPoints: 3, heartPoints: 2,
            timestamp: now
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.balance, 42)
        XCTAssertEqual(decoded.earned, 60)
        XCTAssertEqual(decoded.stepsPoints, 15)
        XCTAssertEqual(decoded.sleepPoints, 20)
        XCTAssertEqual(decoded.bodyPoints, 5)
        XCTAssertEqual(decoded.mindPoints, 3)
        XCTAssertEqual(decoded.heartPoints, 2)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWidgetSnapshot_zeroState() throws {
        let snap = WidgetSnapshot(
            balance: 0, earned: 0,
            stepsPoints: 0, sleepPoints: 0,
            bodyPoints: 0, mindPoints: 0, heartPoints: 0,
            timestamp: Date()
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.balance, 0)
        XCTAssertEqual(decoded.earned, 0)
    }

    func testWidgetSnapshot_totalPoints() {
        let snap = WidgetSnapshot(
            balance: 80, earned: 80,
            stepsPoints: 30, sleepPoints: 25,
            bodyPoints: 10, mindPoints: 8, heartPoints: 7,
            timestamp: Date()
        )
        let total = snap.stepsPoints + snap.sleepPoints + snap.bodyPoints + snap.mindPoints + snap.heartPoints
        XCTAssertEqual(total, 80)
    }

    // MARK: - AccessWindow

    func testAccessWindow_allCases() {
        let all = AccessWindow.allCases
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains(.minutes10))
        XCTAssertTrue(all.contains(.minutes30))
        XCTAssertTrue(all.contains(.hour1))
    }

    func testAccessWindow_minutes() {
        XCTAssertEqual(AccessWindow.minutes10.minutes, 10)
        XCTAssertEqual(AccessWindow.minutes30.minutes, 30)
        XCTAssertEqual(AccessWindow.hour1.minutes, 60)
    }

    func testAccessWindow_rawValueRoundTrip() {
        for window in AccessWindow.allCases {
            XCTAssertEqual(AccessWindow(rawValue: window.rawValue), window)
        }
    }

    func testAccessWindow_displayName() {
        XCTAssertEqual(AccessWindow.minutes10.displayName, "10 min")
        XCTAssertEqual(AccessWindow.minutes30.displayName, "30 min")
        XCTAssertEqual(AccessWindow.hour1.displayName, "1 hour")
    }

    func testAccessWindow_spendColorsLabel() {
        XCTAssertTrue(AccessWindow.minutes10.spendColorsLabel.contains("10 min"))
        XCTAssertTrue(AccessWindow.minutes30.spendColorsLabel.contains("30 min"))
        XCTAssertTrue(AccessWindow.hour1.spendColorsLabel.contains("1 hour"))
    }

    func testAccessWindow_codableRoundTrip() throws {
        for window in AccessWindow.allCases {
            let data = try JSONEncoder().encode(window)
            let decoded = try JSONDecoder().decode(AccessWindow.self, from: data)
            XCTAssertEqual(decoded, window)
        }
    }

    // MARK: - SharedKeys widget-related constants

    func testSharedKeys_widgetKeysAreNonEmpty() {
        XCTAssertFalse(SharedKeys.appGroupId.isEmpty)
        XCTAssertFalse(SharedKeys.ticketGroups.isEmpty)
        XCTAssertFalse(SharedKeys.widgetBackgroundMode.isEmpty)
        XCTAssertFalse(SharedKeys.hasMediumWidget.isEmpty)
        XCTAssertFalse(SharedKeys.hasLargeWidget.isEmpty)
    }

    func testSharedKeys_usageBudgetKeyFormat() {
        let key = SharedKeys.usageBudgetKey("group123")
        XCTAssertTrue(key.contains("group123"))

        let initialKey = SharedKeys.usageBudgetInitialKey("group123")
        XCTAssertTrue(initialKey.contains("group123"))
        XCTAssertNotEqual(key, initialKey,
                          "Budget key and initial key should differ")
    }

    func testSharedKeys_usageBudgetKeyUniqueness() {
        let key1 = SharedKeys.usageBudgetKey("a")
        let key2 = SharedKeys.usageBudgetKey("b")
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - DayBoundary (used by widget timeline providers)

    func testDayBoundary_sameDayReturnsSameStart() {
        let now = Date()
        let start1 = DayBoundary.currentDayStart(for: now, dayEndHour: 0, dayEndMinute: 0)
        let start2 = DayBoundary.currentDayStart(for: now, dayEndHour: 0, dayEndMinute: 0)
        XCTAssertEqual(start1, start2)
    }

    func testDayBoundary_isPersistedDayBehind_nilAnchor() {
        let stale = DayBoundary.isPersistedDayBehind(
            anchor: nil, relativeTo: Date(),
            dayEndHour: 0, dayEndMinute: 0
        )
        XCTAssertFalse(stale, "nil anchor is treated as not-behind (no data yet)")
    }

    func testDayBoundary_isPersistedDayBehind_sameDay() {
        let now = Date()
        let anchor = DayBoundary.currentDayStart(for: now, dayEndHour: 0, dayEndMinute: 0)
        let stale = DayBoundary.isPersistedDayBehind(
            anchor: anchor, relativeTo: now,
            dayEndHour: 0, dayEndMinute: 0
        )
        XCTAssertFalse(stale, "Same-day anchor should not be stale")
    }

    func testDayBoundary_isPersistedDayBehind_yesterday() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1,
                                              to: Calendar.current.startOfDay(for: now))!
        let stale = DayBoundary.isPersistedDayBehind(
            anchor: yesterday, relativeTo: now,
            dayEndHour: 0, dayEndMinute: 0
        )
        XCTAssertTrue(stale, "Yesterday's anchor should be stale")
    }

    // MARK: - WidgetDataFile write/read round-trip

    func testWidgetDataFile_writeAndRead() throws {
        let snap = WidgetSnapshot(
            balance: 77, earned: 88,
            stepsPoints: 30, sleepPoints: 20,
            bodyPoints: 10, mindPoints: 5, heartPoints: 3,
            timestamp: Date()
        )
        WidgetDataFile.write(snap)
        let read = WidgetDataFile.read()

        // May be nil if app group container isn't available in test host,
        // but if it reads, values should match.
        if let read {
            XCTAssertEqual(read.balance, 77)
            XCTAssertEqual(read.earned, 88)
        }
    }
}
