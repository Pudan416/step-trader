import XCTest
@testable import Steps4

final class UnlockTimerModelTests: XCTestCase {

    func testStartsFull() {
        var model = UnlockTimerModel(initialMinutes: 10)
        let state = model.observe(remainingMinutes: 10)
        XCTAssertEqual(state.remainingMinutes, 10)
        XCTAssertEqual(state.fraction, 1.0, accuracy: 0.0001)
    }

    func testDepletesInWholeMinuteSteps() {
        var model = UnlockTimerModel(initialMinutes: 10)
        _ = model.observe(remainingMinutes: 10)
        XCTAssertEqual(model.observe(remainingMinutes: 9).fraction, 0.9, accuracy: 0.0001)
        XCTAssertEqual(model.observe(remainingMinutes: 5).fraction, 0.5, accuracy: 0.0001)
    }

    func testNeverRunsBackwards() {
        var model = UnlockTimerModel(initialMinutes: 10)
        _ = model.observe(remainingMinutes: 4)
        // A late or replayed tick reports more time left than we last showed.
        let state = model.observe(remainingMinutes: 7)
        XCTAssertEqual(state.remainingMinutes, 4, "a rising reading must be clamped to the last shown value")
        XCTAssertEqual(state.fraction, 0.4, accuracy: 0.0001)
    }

    func testRepeatedIdenticalReadingsDoNotDrift() {
        var model = UnlockTimerModel(initialMinutes: 30)
        let first = model.observe(remainingMinutes: 12)
        let second = model.observe(remainingMinutes: 12)
        XCTAssertEqual(first.fraction, second.fraction)
        XCTAssertEqual(first.digits, second.digits)
    }

    func testClampsAtZeroAndDoesNotGoNegative() {
        var model = UnlockTimerModel(initialMinutes: 10)
        let state = model.observe(remainingMinutes: -3)
        XCTAssertEqual(state.remainingMinutes, 0)
        XCTAssertEqual(state.fraction, 0.0, accuracy: 0.0001)
    }

    func testReadingAboveInitialIsClampedToInitial() {
        var model = UnlockTimerModel(initialMinutes: 10)
        let state = model.observe(remainingMinutes: 99)
        XCTAssertEqual(state.remainingMinutes, 10)
        XCTAssertEqual(state.fraction, 1.0, accuracy: 0.0001)
    }

    func testExtendingTheWindowResetsAndIsAllowedToRise() {
        var model = UnlockTimerModel(initialMinutes: 10)
        _ = model.observe(remainingMinutes: 3)
        model.reset(initialMinutes: 33)
        let state = model.observe(remainingMinutes: 33)
        XCTAssertEqual(state.remainingMinutes, 33)
        XCTAssertEqual(state.fraction, 1.0, accuracy: 0.0001)
    }

    func testZeroInitialDoesNotDivideByZero() {
        var model = UnlockTimerModel(initialMinutes: 0)
        let state = model.observe(remainingMinutes: 0)
        XCTAssertEqual(state.fraction, 0.0, accuracy: 0.0001)
    }

    // MARK: - Digits

    func testDigitsUseZeroPaddedMinutesAndSeconds() {
        var model = UnlockTimerModel(initialMinutes: 60)
        XCTAssertEqual(model.observe(remainingMinutes: 60).digits, "60:00")
        XCTAssertEqual(model.observe(remainingMinutes: 9).digits, "09:00")
        XCTAssertEqual(model.observe(remainingMinutes: 0).digits, "00:00")
    }
}
