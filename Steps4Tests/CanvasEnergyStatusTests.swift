import XCTest
@testable import Steps4

/// The Canvas status pill answers two questions against one fixed ceiling: how
/// much the day earned, and how much of that is still unspent. The ceiling is
/// the product's daily maximum, so a full bar means a full day — not merely
/// that nothing has been spent yet.
final class CanvasEnergyStatusTests: XCTestCase {

    private func status(balance: Int, earned: Int, max: Int = 100) -> CanvasEnergyStatus {
        CanvasEnergyStatus(stepsBalance: balance, baseEnergyToday: earned, maximum: max)
    }

    func testShowsRemainingEarnedAndCeiling() {
        let s = status(balance: 40, earned: 60)

        XCTAssertEqual(s.remaining, 40)
        XCTAssertEqual(s.earned, 60)
        XCTAssertEqual(s.maximum, 100)
    }

    /// Both bars measure the ceiling, so a day that earned 60 of 100 reads as
    /// 60% earned even when none of it has been spent.
    func testBothProgressesMeasureTheCeiling() {
        let s = status(balance: 60, earned: 60)

        XCTAssertEqual(s.progress, 0.6, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0.6, accuracy: 0.0001)
    }

    func testSpendingMovesRemainingButNotEarned() {
        let s = status(balance: 40, earned: 60)

        XCTAssertEqual(s.progress, 0.4, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0.6, accuracy: 0.0001)
    }

    func testNothingEarnedYet() {
        let s = status(balance: 0, earned: 0)

        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.earned, 0)
        XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0, accuracy: 0.0001)
    }

    func testFullDay() {
        let s = status(balance: 100, earned: 100)

        XCTAssertEqual(s.progress, 1.0, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 1.0, accuracy: 0.0001)
    }

    /// A stale balance can outrun today's earnings between a recalculation and
    /// a HealthKit refresh. Remaining still cannot exceed earned.
    func testStaleBalanceClampsToEarned() {
        let s = status(balance: 90, earned: 60)

        XCTAssertEqual(s.remaining, 60)
        XCTAssertEqual(s.progress, 0.6, accuracy: 0.0001)
    }

    /// Earnings cannot exceed the ceiling either — the formula caps
    /// `baseEnergyToday` at 100, and the pill must not draw past its track if
    /// that ever changes.
    func testEarnedClampsToTheCeiling() {
        let s = status(balance: 120, earned: 120)

        XCTAssertEqual(s.earned, 100)
        XCTAssertEqual(s.remaining, 100)
        XCTAssertEqual(s.earnedProgress, 1.0, accuracy: 0.0001)
    }

    func testNegativeInputsFloorAtZero() {
        let s = status(balance: -5, earned: -10)

        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.earned, 0)
        XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
    }

    /// A zero or negative ceiling would divide by nothing. Both progresses
    /// report empty rather than crashing or reporting a full bar.
    func testNonPositiveCeilingReportsEmpty() {
        let s = status(balance: 10, earned: 10, max: 0)

        XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0, accuracy: 0.0001)
    }

    func testEqualInputsProduceEqualStatuses() {
        XCTAssertEqual(status(balance: 12, earned: 30), status(balance: 12, earned: 30))
    }
}
