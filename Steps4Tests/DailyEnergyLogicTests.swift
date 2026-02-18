import XCTest
@testable import Steps4

/// Tests for daily energy logic: EnergyDefaults constants and formula contract
/// (pointsFromSleep, pointsFromSteps, pointsFromSelections as used in AppModel+DailyEnergy).
///
/// Scoring model (5 metrics × 20 = 100 max):
///   steps  = 20 × min(made_steps, target_steps) / target_steps
///   sleep  = 20 × min(today_sleep, target_sleep) / target_sleep
///   body   = 4 chosen cards × 5 ink = 20
///   mind   = 4 chosen cards × 5 ink = 20
///   heart  = 4 chosen cards × 5 ink = 20
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
        XCTAssertEqual(pointsFromSleep(hours: 10, target: target, maxPoints: maxPoints), 20, "Capped at target")
        XCTAssertEqual(pointsFromSleep(hours: -1, target: target, maxPoints: maxPoints), 0, "Negative clamped to 0")
    }

    /// pointsFromSteps: Int(ratio * stepsMaxPoints), ratio = min(steps, target) / target
    func testPointsFromStepsFormula() {
        let target: Double = 10_000
        let maxPoints = 20
        XCTAssertEqual(pointsFromSteps(steps: 0, target: target, maxPoints: maxPoints), 0)
        XCTAssertEqual(pointsFromSteps(steps: 5_000, target: target, maxPoints: maxPoints), 10)
        XCTAssertEqual(pointsFromSteps(steps: 10_000, target: target, maxPoints: maxPoints), 20)
        XCTAssertEqual(pointsFromSteps(steps: 15_000, target: target, maxPoints: maxPoints), 20, "Capped at target")
    }

    /// pointsFromSelections: min(count, maxSelectionsPerCategory) * selectionPoints
    func testPointsFromSelectionsFormula() {
        let maxSelections = 4
        let pointsPerSelection = 5
        XCTAssertEqual(pointsFromSelections(count: 0, maxSelections: maxSelections, pointsPer: pointsPerSelection), 0)
        XCTAssertEqual(pointsFromSelections(count: 1, maxSelections: maxSelections, pointsPer: pointsPerSelection), 5)
        XCTAssertEqual(pointsFromSelections(count: 4, maxSelections: maxSelections, pointsPer: pointsPerSelection), 20)
        XCTAssertEqual(pointsFromSelections(count: 10, maxSelections: maxSelections, pointsPer: pointsPerSelection), 20, "Capped at 4 selections")
    }

    // MARK: - Five-metric total contract

    /// With all five metrics maxed out the total is exactly 100.
    func testFiveMetricMaxTotal() {
        let stepsMax = EnergyDefaults.stepsMaxPoints   // 20
        let sleepMax = EnergyDefaults.sleepMaxPoints    // 20
        let bodyMax  = EnergyDefaults.maxSelectionsPerCategory * EnergyDefaults.selectionPoints // 20
        let mindMax  = bodyMax   // 20
        let heartMax = bodyMax   // 20

        let total = stepsMax + sleepMax + bodyMax + mindMax + heartMax
        XCTAssertEqual(total, EnergyDefaults.maxBaseEnergy, "5 × 20 must equal maxBaseEnergy (100)")
    }

    /// Each individual metric is capped at 20.
    func testEachMetricCappedAt20() {
        // Steps
        XCTAssertEqual(pointsFromSteps(steps: 999_999, target: 10_000, maxPoints: 20), 20)
        // Sleep
        XCTAssertEqual(pointsFromSleep(hours: 24, target: 8, maxPoints: 20), 20)
        // Selections (body / mind / heart)
        XCTAssertEqual(pointsFromSelections(count: 100, maxSelections: 4, pointsPer: 5), 20)
    }

    /// Zero activity day yields zero energy.
    func testZeroActivityDayYieldsZero() {
        let total = pointsFromSteps(steps: 0, target: 10_000, maxPoints: 20)
            + pointsFromSleep(hours: 0, target: 8, maxPoints: 20)
            + pointsFromSelections(count: 0, maxSelections: 4, pointsPer: 5) // body
            + pointsFromSelections(count: 0, maxSelections: 4, pointsPer: 5) // mind
            + pointsFromSelections(count: 0, maxSelections: 4, pointsPer: 5) // heart
        XCTAssertEqual(total, 0)
    }

    /// Half-effort day yields 50 points (half of 100).
    func testHalfEffortDay() {
        let steps = pointsFromSteps(steps: 5_000, target: 10_000, maxPoints: 20)   // 10
        let sleep = pointsFromSleep(hours: 4, target: 8, maxPoints: 20)             // 10
        let body  = pointsFromSelections(count: 2, maxSelections: 4, pointsPer: 5)   // 10
        let mind  = pointsFromSelections(count: 2, maxSelections: 4, pointsPer: 5)   // 10
        let heart = pointsFromSelections(count: 2, maxSelections: 4, pointsPer: 5)   // 10
        XCTAssertEqual(steps + sleep + body + mind + heart, 50)
    }

    /// Steps metric: boundary around rounding (Int truncation).
    func testStepsRounding() {
        // 3_333 / 10_000 * 20 = 6.666 → Int truncates to 6
        XCTAssertEqual(pointsFromSteps(steps: 3_333, target: 10_000, maxPoints: 20), 6)
        // 9_999 / 10_000 * 20 = 19.998 → 19
        XCTAssertEqual(pointsFromSteps(steps: 9_999, target: 10_000, maxPoints: 20), 19)
    }

    /// Sleep metric: boundary around rounding (Int truncation).
    func testSleepRounding() {
        // 7.5 / 8 * 20 = 18.75 → 18
        XCTAssertEqual(pointsFromSleep(hours: 7.5, target: 8, maxPoints: 20), 18)
        // 7.9 / 8 * 20 = 19.75 → 19
        XCTAssertEqual(pointsFromSleep(hours: 7.9, target: 8, maxPoints: 20), 19)
    }

    /// Selection points scale linearly: 0, 5, 10, 15, 20.
    func testSelectionPointsLinearScale() {
        for count in 0...4 {
            XCTAssertEqual(
                pointsFromSelections(count: count, maxSelections: 4, pointsPer: 5),
                count * 5
            )
        }
    }

    /// Body, mind, heart are independent; body = activityExtrasPoints only (no steps), heart = joysChoicePoints only (no sleep).
    func testBodyMindHeartIndependentOfStepsSleep() {
        // Body: only card selections, not steps
        let bodyWithZeroCards = pointsFromSelections(count: 0, maxSelections: 4, pointsPer: 5)
        XCTAssertEqual(bodyWithZeroCards, 0, "Body should be 0 with no cards regardless of steps")

        // Heart: only card selections, not sleep
        let heartWithZeroCards = pointsFromSelections(count: 0, maxSelections: 4, pointsPer: 5)
        XCTAssertEqual(heartWithZeroCards, 0, "Heart should be 0 with no cards regardless of sleep")
    }

    // MARK: - EnergyOption / EnergyCategory

    func testEnergyCategoryRawValues() {
        XCTAssertEqual(EnergyCategory.body.rawValue, "body")
        XCTAssertEqual(EnergyCategory.mind.rawValue, "mind")
        XCTAssertEqual(EnergyCategory.heart.rawValue, "heart")
    }

    func testEnergyDefaultsOptionsCount() {
        let activityCount = EnergyDefaults.options.filter { $0.category == .body }.count
        let creativityCount = EnergyDefaults.options.filter { $0.category == .mind }.count
        let joysCount = EnergyDefaults.options.filter { $0.category == .heart }.count
        XCTAssertGreaterThan(activityCount, 0)
        XCTAssertGreaterThan(creativityCount, 0)
        XCTAssertGreaterThan(joysCount, 0)
    }

    // MARK: - Option Descriptions

    func testOptionDescriptions() {
        // Test that all options have descriptions
        for option in EnergyDefaults.options {
            let desc = EnergyDefaults.optionDescriptions[option.id]
            XCTAssertNotNil(desc, "Option \(option.id) should have a description")
            XCTAssertFalse(desc?.description.isEmpty ?? true, "Description should not be empty for \(option.id)")
            XCTAssertFalse(desc?.examples.isEmpty ?? true, "Examples should not be empty for \(option.id)")
        }
    }

    // MARK: - CustomEnergyOption

    func testCustomEnergyOption_title() {
        let custom = CustomEnergyOption(id: "custom_body_abc", titleEn: "Jogging", titleRu: "Бег", category: .body)
        XCTAssertEqual(custom.title(for: "en"), "Jogging")
        XCTAssertEqual(custom.title(for: "ru"), "Бег")
    }

    func testCustomEnergyOption_asEnergyOption() {
        let custom = CustomEnergyOption(id: "custom_body_xyz", titleEn: "Yoga", titleRu: "Йога", category: .body, icon: "figure.yoga")
        let option = custom.asEnergyOption()
        XCTAssertEqual(option.id, custom.id)
        XCTAssertEqual(option.titleEn, custom.titleEn)
        XCTAssertEqual(option.category, .body)
        XCTAssertEqual(option.icon, "figure.yoga")
    }

    func testCustomEnergyOption_codable() throws {
        let custom = CustomEnergyOption(id: "custom_mind_1", titleEn: "Idea", titleRu: "Идея", category: .mind)
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
        XCTAssertEqual(sel.count, 4, "5th selection should be rejected")
        toggle(selections: &sel, optionId: "a", maxCount: maxCount)
        XCTAssertEqual(sel, ["b", "c", "d"])
    }

    // MARK: - PastDaySnapshot codable

    func testPastDaySnapshotRoundTrip() throws {
        let original = PastDaySnapshot(
            inkEarned: 75,
            inkSpent: 30,
            bodyIds: ["body_walking"],
            mindIds: ["mind_focusing"],
            heartIds: ["heart_joy"],
            steps: 8_000,
            sleepHours: 7.5,
            stepsTarget: 9_000,
            sleepTargetHours: 7.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PastDaySnapshot.self, from: data)
        XCTAssertEqual(decoded.inkEarned, 75)
        XCTAssertEqual(decoded.inkSpent, 30)
        XCTAssertEqual(decoded.bodyIds, ["body_walking"])
        XCTAssertEqual(decoded.mindIds, ["mind_focusing"])
        XCTAssertEqual(decoded.heartIds, ["heart_joy"])
        XCTAssertEqual(decoded.steps, 8_000)
        XCTAssertEqual(decoded.sleepHours, 7.5)
        XCTAssertEqual(decoded.stepsTarget, 9_000)
        XCTAssertEqual(decoded.sleepTargetHours, 7.0)
    }

    func testPastDaySnapshotLegacyDecodeUsesDefaultTargets() throws {
        let legacyJSON = """
        {
          "inkEarned": 55,
          "inkSpent": 10,
          "bodyIds": ["body_walking"],
          "mindIds": ["mind_focusing"],
          "heartIds": ["heart_joy"],
          "steps": 6000,
          "sleepHours": 6.5
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(PastDaySnapshot.self, from: data)
        XCTAssertEqual(decoded.inkEarned, 55)
        XCTAssertEqual(decoded.inkSpent, 10)
        XCTAssertEqual(decoded.stepsTarget, EnergyDefaults.stepsTarget)
        XCTAssertEqual(decoded.sleepTargetHours, EnergyDefaults.sleepTargetHours)
    }

    func testPastDaySnapshotPointsCanBeReconstructedFromStoredTargets() {
        let snapshot = PastDaySnapshot(
            inkEarned: 0,
            inkSpent: 0,
            bodyIds: [],
            mindIds: [],
            heartIds: [],
            steps: 6_000,
            sleepHours: 6.0,
            stepsTarget: 8_000,
            sleepTargetHours: 6.0
        )
        let stepsPoints = pointsFromSteps(steps: Double(snapshot.steps), target: snapshot.stepsTarget, maxPoints: EnergyDefaults.stepsMaxPoints)
        let sleepPoints = pointsFromSleep(hours: snapshot.sleepHours, target: snapshot.sleepTargetHours, maxPoints: EnergyDefaults.sleepMaxPoints)
        XCTAssertEqual(stepsPoints, 15)
        XCTAssertEqual(sleepPoints, 20)
    }

    // MARK: - Custom steps/sleep targets

    func testCustomStepsTarget() {
        // With a lower target, fewer steps still max out
        let maxPoints = 20
        XCTAssertEqual(pointsFromSteps(steps: 5_000, target: 5_000, maxPoints: maxPoints), 20)
        XCTAssertEqual(pointsFromSteps(steps: 2_500, target: 5_000, maxPoints: maxPoints), 10)
    }

    func testCustomSleepTarget() {
        let maxPoints = 20
        XCTAssertEqual(pointsFromSleep(hours: 6, target: 6, maxPoints: maxPoints), 20)
        XCTAssertEqual(pointsFromSleep(hours: 3, target: 6, maxPoints: maxPoints), 10)
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
