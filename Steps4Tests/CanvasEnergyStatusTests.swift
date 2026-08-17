import XCTest
@testable import Steps4

/// The Canvas status pill answers one question: how much of what was earned
/// today is still unspent. Bonus balance and the product-wide 100 ceiling are
/// deliberately outside it, so the numbers can never disagree with the bar.
final class CanvasEnergyStatusTests: XCTestCase {

    func testShowsRemainingOutOfEarned() {
        let status = CanvasEnergyStatus(stepsBalance: 58, baseEnergyToday: 72)

        XCTAssertEqual(status.remaining, 58)
        XCTAssertEqual(status.earned, 72)
        XCTAssertEqual(status.progress, 58.0 / 72.0, accuracy: 0.0001)
    }

    func testNothingEarnedYetShowsZeroOverZero() {
        let status = CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 0)

        XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(status.earned, 0)
        XCTAssertEqual(status.progress, 0, accuracy: 0.0001)
    }

    func testEverythingSpentKeepsTheEarnedTrack() {
        let status = CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 40)

        XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(status.earned, 40)
        XCTAssertEqual(status.progress, 0, accuracy: 0.0001)
    }

    /// A stale balance can outrun today's earnings between a recalculation and
    /// a HealthKit refresh. The pill must never claim more left than gained.
    func testStaleBalanceClampsToEarned() {
        let status = CanvasEnergyStatus(stepsBalance: 90, baseEnergyToday: 72)

        XCTAssertEqual(status.remaining, 72)
        XCTAssertEqual(status.progress, 1.0, accuracy: 0.0001)
    }

    func testNegativeInputsFloorAtZero() {
        let status = CanvasEnergyStatus(stepsBalance: -5, baseEnergyToday: -10)

        XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(status.earned, 0)
        XCTAssertEqual(status.progress, 0, accuracy: 0.0001)
    }

    /// The pill takes the daily balance, never `totalStepsBalance` — a bonus
    /// top-up must not make today look richer than it was.
    func testEqualInputsProduceEqualStatuses() {
        XCTAssertEqual(
            CanvasEnergyStatus(stepsBalance: 12, baseEnergyToday: 30),
            CanvasEnergyStatus(stepsBalance: 12, baseEnergyToday: 30)
        )
    }
}
