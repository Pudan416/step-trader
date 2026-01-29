import XCTest
@testable import Steps4

/// Tests for DeviceActivityMonitor minute-charge logic: applyMinuteCharge math.
/// Formula (from DeviceActivityMonitorExtension): consume from stepsBalance first, then from bonusSteps.
final class MinuteChargeLogicTests: XCTestCase {

    // MARK: - applyMinuteCharge formula (mirrors DeviceActivityMonitorExtension)

    /// Given (stepsBalance, bonusSteps, spentStepsToday, cost) -> (newStepsBalance, newBonusSteps, newSpentStepsToday)
    func testApplyMinuteChargeConsumesFromBalanceFirst() {
        var stepsBalance = 30
        var bonusSteps = 20
        var spentStepsToday = 0
        let cost = 10

        let consumeFromBase = min(cost, stepsBalance)
        spentStepsToday += consumeFromBase
        stepsBalance = max(0, stepsBalance - consumeFromBase)
        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            bonusSteps = max(0, bonusSteps - remainingCost)
        }

        XCTAssertEqual(stepsBalance, 20)
        XCTAssertEqual(bonusSteps, 20)
        XCTAssertEqual(spentStepsToday, 10)
    }

    func testApplyMinuteChargeUsesBonusWhenBalanceExhausted() {
        var stepsBalance = 5
        var bonusSteps = 20
        var spentStepsToday = 0
        let cost = 10

        let consumeFromBase = min(cost, stepsBalance)
        spentStepsToday += consumeFromBase
        stepsBalance = max(0, stepsBalance - consumeFromBase)
        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            bonusSteps = max(0, bonusSteps - remainingCost)
        }

        XCTAssertEqual(stepsBalance, 0)
        XCTAssertEqual(bonusSteps, 15)
        XCTAssertEqual(spentStepsToday, 5)
    }

    func testApplyMinuteChargeZeroCost() {
        var stepsBalance = 50
        var bonusSteps = 10
        var spentStepsToday = 0
        let cost = 0

        let consumeFromBase = min(cost, stepsBalance)
        spentStepsToday += consumeFromBase
        stepsBalance = max(0, stepsBalance - consumeFromBase)
        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            bonusSteps = max(0, bonusSteps - remainingCost)
        }

        XCTAssertEqual(stepsBalance, 50)
        XCTAssertEqual(bonusSteps, 10)
        XCTAssertEqual(spentStepsToday, 0)
    }

    func testApplyMinuteChargeDepletesBoth() {
        var stepsBalance = 3
        var bonusSteps = 5
        var spentStepsToday = 0
        let cost = 6

        let consumeFromBase = min(cost, stepsBalance)
        spentStepsToday += consumeFromBase
        stepsBalance = max(0, stepsBalance - consumeFromBase)
        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            bonusSteps = max(0, bonusSteps - remainingCost)
        }

        XCTAssertEqual(stepsBalance, 0)
        XCTAssertEqual(bonusSteps, 2)
        XCTAssertEqual(spentStepsToday, 3)
    }

    /// remainingMinutes = (balance + bonusSteps) / cost (from monitor)
    func testRemainingMinutesFormula() {
        XCTAssertEqual(remainingMinutes(balance: 30, bonusSteps: 0, cost: 10), 3)
        XCTAssertEqual(remainingMinutes(balance: 25, bonusSteps: 5, cost: 10), 3)
        XCTAssertEqual(remainingMinutes(balance: 0, bonusSteps: 15, cost: 10), 1)
        XCTAssertEqual(remainingMinutes(balance: 0, bonusSteps: 0, cost: 10), 0)
        XCTAssertEqual(remainingMinutes(balance: 10, bonusSteps: 0, cost: 0), 0)
    }

    // MARK: - Tariff entry cost (used as cost per minute in monitor)

    func testTariffEntryCostUsedAsMinuteCost() {
        XCTAssertEqual(Tariff.hard.entryCostSteps, 100)
        XCTAssertEqual(Tariff.medium.entryCostSteps, 50)
        XCTAssertEqual(Tariff.easy.entryCostSteps, 10)
        XCTAssertEqual(Tariff.free.entryCostSteps, 0)
    }
}

private func remainingMinutes(balance: Int, bonusSteps: Int, cost: Int) -> Int {
    guard cost > 0 else { return 0 }
    return max(0, (balance + bonusSteps) / cost)
}
