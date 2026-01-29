import XCTest
@testable import Steps4

/// Tests for daily energy logic: EnergyDefaults constants and formula contract
/// (pointsFromSleep, pointsFromSteps, pointsFromSelections as used in AppModel+DailyEnergy).
final class DailyEnergyLogicTests: XCTestCase {

    // MARK: - EnergyDefaults constants

    func testEnergyDefaultsMaxBaseEnergy() {
        XCTAssertEqual(EnergyDefaults.maxBaseEnergy, 100)
    }

    func testEnergyDefaultsSleepAndStepsTargets() {
        XCTAssertEqual(EnergyDefaults.sleepTargetHours, 8)
        XCTAssertEqual(EnergyDefaults.stepsTarget, 10_000)
        XCTAssertEqual(EnergyDefaults.sleepMaxPoints, 20)
        XCTAssertEqual(EnergyDefaults.stepsMaxPoints, 20)
    }

    func testEnergyDefaultsSelectionPoints() {
        XCTAssertEqual(EnergyDefaults.selectionPoints, 5)
        XCTAssertEqual(EnergyDefaults.maxSelectionsPerCategory, 4)
    }

    // MARK: - Formula contract (mirrors AppModel+DailyEnergy private logic)

    /// pointsFromSleep: Int(ratio * sleepMaxPoints), ratio = min(hours, target) / target
    func testPointsFromSleepFormula() {
        let target: Double = 8
        let maxPoints = 20
        XCTAssertEqual(pointsFromSleep(hours: 0, target: target, maxPoints: maxPoints), 0)
        XCTAssertEqual(pointsFromSleep(hours: 4, target: target, maxPoints: maxPoints), 10)
        XCTAssertEqual(pointsFromSleep(hours: 8, target: target, maxPoints: maxPoints), 20)
        XCTAssertEqual(pointsFromSleep(hours: 10, target: target, maxPoints: maxPoints), 20)
        XCTAssertEqual(pointsFromSleep(hours: -1, target: target, maxPoints: maxPoints), 0)
    }

    /// pointsFromSteps: Int(ratio * stepsMaxPoints), ratio = min(steps, target) / target
    func testPointsFromStepsFormula() {
        let target: Double = 10_000
        let maxPoints = 20
        XCTAssertEqual(pointsFromSteps(steps: 0, target: target, maxPoints: maxPoints), 0)
        XCTAssertEqual(pointsFromSteps(steps: 5_000, target: target, maxPoints: maxPoints), 10)
        XCTAssertEqual(pointsFromSteps(steps: 10_000, target: target, maxPoints: maxPoints), 20)
        XCTAssertEqual(pointsFromSteps(steps: 15_000, target: target, maxPoints: maxPoints), 20)
    }

    /// pointsFromSelections: min(count, maxSelectionsPerCategory) * selectionPoints
    func testPointsFromSelectionsFormula() {
        let maxSelections = 4
        let pointsPerSelection = 5
        XCTAssertEqual(pointsFromSelections(count: 0, maxSelections: maxSelections, pointsPer: pointsPerSelection), 0)
        XCTAssertEqual(pointsFromSelections(count: 1, maxSelections: maxSelections, pointsPer: pointsPerSelection), 5)
        XCTAssertEqual(pointsFromSelections(count: 4, maxSelections: maxSelections, pointsPer: pointsPerSelection), 20)
        XCTAssertEqual(pointsFromSelections(count: 10, maxSelections: maxSelections, pointsPer: pointsPerSelection), 20)
    }

    // MARK: - EnergyOption / EnergyCategory

    func testEnergyCategoryRawValues() {
        XCTAssertEqual(EnergyCategory.move.rawValue, "move")
        XCTAssertEqual(EnergyCategory.reboot.rawValue, "reboot")
        XCTAssertEqual(EnergyCategory.joy.rawValue, "joy")
    }

    func testEnergyDefaultsOptionsCount() {
        let moveCount = EnergyDefaults.options.filter { $0.category == .move }.count
        let rebootCount = EnergyDefaults.options.filter { $0.category == .reboot }.count
        let joyCount = EnergyDefaults.options.filter { $0.category == .joy }.count
        XCTAssertGreaterThan(moveCount, 0)
        XCTAssertGreaterThan(rebootCount, 0)
        XCTAssertGreaterThan(joyCount, 0)
    }
}

// MARK: - Local replicas of AppModel+DailyEnergy formulas (for contract tests)

private func pointsFromSleep(hours: Double, target: Double, maxPoints: Int) -> Int {
    let capped = min(max(0, hours), target)
    let ratio = target > 0 ? capped / target : 0
    return Int(ratio * Double(maxPoints))
}

private func pointsFromSteps(steps: Double, target: Double, maxPoints: Int) -> Int {
    let capped = min(max(0, steps), target)
    let ratio = target > 0 ? capped / target : 0
    return Int(ratio * Double(maxPoints))
}

private func pointsFromSelections(count: Int, maxSelections: Int, pointsPer: Int) -> Int {
    min(count, maxSelections) * pointsPer
}
