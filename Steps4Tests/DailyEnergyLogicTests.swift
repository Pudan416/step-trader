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
        XCTAssertEqual(EnergyCategory.activity.rawValue, "activity")
        XCTAssertEqual(EnergyCategory.recovery.rawValue, "recovery")
        XCTAssertEqual(EnergyCategory.joys.rawValue, "joys")
    }

    func testEnergyDefaultsOptionsCount() {
        let activityCount = EnergyDefaults.options.filter { $0.category == .activity }.count
        let recoveryCount = EnergyDefaults.options.filter { $0.category == .recovery }.count
        let joysCount = EnergyDefaults.options.filter { $0.category == .joys }.count
        XCTAssertGreaterThan(activityCount, 0)
        XCTAssertGreaterThan(recoveryCount, 0)
        XCTAssertGreaterThan(joysCount, 0)
    }

    // MARK: - Choice tab: Other option IDs

    func testOtherOptionIds() {
        XCTAssertTrue(EnergyDefaults.otherOptionIds.contains("activity_other"))
        XCTAssertTrue(EnergyDefaults.otherOptionIds.contains("recovery_other"))
        XCTAssertTrue(EnergyDefaults.otherOptionIds.contains("joys_other"))
        XCTAssertEqual(EnergyDefaults.otherOptionIds.count, 3)
    }

    // MARK: - CustomEnergyOption

    func testCustomEnergyOption_title() {
        let custom = CustomEnergyOption(id: "custom_activity_abc", titleEn: "Jogging", titleRu: "Бег", category: .activity)
        XCTAssertEqual(custom.title(for: "en"), "Jogging")
        XCTAssertEqual(custom.title(for: "ru"), "Бег")
    }

    func testCustomEnergyOption_asEnergyOption() {
        let custom = CustomEnergyOption(id: "custom_activity_xyz", titleEn: "Yoga", titleRu: "Йога", category: .activity, icon: "figure.yoga")
        let option = custom.asEnergyOption()
        XCTAssertEqual(option.id, custom.id)
        XCTAssertEqual(option.titleEn, custom.titleEn)
        XCTAssertEqual(option.category, .activity)
        XCTAssertEqual(option.icon, "figure.yoga")
    }

    func testCustomEnergyOption_codable() throws {
        let custom = CustomEnergyOption(id: "custom_recovery_1", titleEn: "Slept well", titleRu: "Выспался", category: .recovery)
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(CustomEnergyOption.self, from: data)
        XCTAssertEqual(decoded.id, custom.id)
        XCTAssertEqual(decoded.titleEn, custom.titleEn)
        XCTAssertEqual(decoded.category, custom.category)
    }

    // MARK: - Toggle selection contract (max 4 per category)

    /// Simulates toggleDailySelection logic: add if < 4, remove if present.
    func testToggleSelectionContract_maxFourPerCategory() {
        func toggle(selections: inout [String], optionId: String, maxCount: Int) {
            if let idx = selections.firstIndex(of: optionId) {
                selections.remove(at: idx)
            } else if selections.count < maxCount {
                selections.append(optionId)
            }
        }
        let maxCount = EnergyDefaults.maxSelectionsPerCategory
        var sel: [String] = []
        toggle(selections: &sel, optionId: "a", maxCount: maxCount)
        XCTAssertEqual(sel, ["a"])
        toggle(selections: &sel, optionId: "b", maxCount: maxCount)
        toggle(selections: &sel, optionId: "c", maxCount: maxCount)
        toggle(selections: &sel, optionId: "d", maxCount: maxCount)
        XCTAssertEqual(sel.count, 4)
        toggle(selections: &sel, optionId: "e", maxCount: maxCount)
        XCTAssertEqual(sel.count, 4)
        toggle(selections: &sel, optionId: "a", maxCount: maxCount)
        XCTAssertEqual(sel, ["b", "c", "d"])
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
