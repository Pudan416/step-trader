import XCTest
@testable import Steps4

final class TicketGroupCostTests: XCTestCase {

    private func makeGroup() -> TicketGroup {
        TicketGroup(name: "Test Group", settings: AppUnlockSettings(entryCostSteps: 10, dayPassCostSteps: 50))
    }

    // MARK: - Known intervals

    func testCost10Minutes() {
        let group = makeGroup()
        XCTAssertEqual(group.cost(for: .minutes10), 4)
    }

    func testCost30Minutes() {
        let group = makeGroup()
        XCTAssertEqual(group.cost(for: .minutes30), 10)
    }

    func testCost1Hour() {
        let group = makeGroup()
        XCTAssertEqual(group.cost(for: .hour1), 20)
    }

    // MARK: - All cases covered

    func testAllAccessWindowsHavePositiveCost() {
        let group = makeGroup()
        for window in AccessWindow.allCases {
            let cost = group.cost(for: window)
            XCTAssertGreaterThan(cost, 0, "\(window) should have a positive cost")
        }
    }

    // MARK: - Cost ordering

    func testCostIncreasesWithDuration() {
        let group = makeGroup()
        let cost10 = group.cost(for: .minutes10)
        let cost30 = group.cost(for: .minutes30)
        let cost60 = group.cost(for: .hour1)
        XCTAssertLessThan(cost10, cost30, "10-min cost should be less than 30-min")
        XCTAssertLessThan(cost30, cost60, "30-min cost should be less than 1-hour")
    }
}
