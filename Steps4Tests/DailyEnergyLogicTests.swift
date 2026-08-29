import XCTest
@testable import Steps4

/// Tests for daily energy logic: `EnergyDefaults` constants and the formula
/// contract (`pointsFromSleep`, `pointsFromSteps`, and the happening economy as
/// used in `AppModel+DailyEnergy`).
///
/// Scoring model (3 entities, 100 max):
///   steps      = 20 × min(made_steps, target_steps) / target_steps
///   sleep      = 20 × min(today_sleep, target_sleep) / target_sleep
///   happenings = min(additions × 6, 60)
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

    func testHappeningEconomyConstants() {
        XCTAssertEqual(HappeningDefaults.pointsPerAddition, 6)
        XCTAssertEqual(HappeningDefaults.happeningsMaxPoints, 60)
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

    /// The economy counts additions, so this is the whole happening formula.
    func testHappeningPointsFormula() {
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 0), 0)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 1), 6)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 9), 54)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 10), 60)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 11), 60, "Capped at ten additions")
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 1_000), 60)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: -3), 0, "Negative clamped to 0")
    }

    // MARK: - Three-entity total contract

    /// With all three entities maxed the total is exactly 100. The ceiling is
    /// deliberately unchanged from the five-part model — onboarding has a slide
    /// built on it.
    func testThreeEntityMaxTotal() {
        let total = EnergyDefaults.stepsMaxPoints
            + EnergyDefaults.sleepMaxPoints
            + HappeningDefaults.happeningsMaxPoints
        XCTAssertEqual(total, EnergyDefaults.maxBaseEnergy, "20 + 20 + 60 must equal 100")
    }

    func testEachEntityIsCapped() {
        XCTAssertEqual(pointsFromSteps(steps: 999_999, target: 10_000, maxPoints: 20), 20)
        XCTAssertEqual(pointsFromSleep(hours: 24, target: 8, maxPoints: 20), 20)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 100), 60)
    }

    func testEmptyDayYieldsZero() {
        let total = pointsFromSteps(steps: 0, target: 10_000, maxPoints: 20)
            + pointsFromSleep(hours: 0, target: 8, maxPoints: 20)
            + HappeningEconomy.points(forAdditionCount: 0)
        XCTAssertEqual(total, 0)
    }

    /// Half of everything is half of 100.
    func testHalfEffortDay() {
        let steps = pointsFromSteps(steps: 5_000, target: 10_000, maxPoints: 20)  // 10
        let sleep = pointsFromSleep(hours: 4, target: 8, maxPoints: 20)            // 10
        let happenings = HappeningEconomy.points(forAdditionCount: 5)              // 30
        XCTAssertEqual(steps + sleep + happenings, 50)
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

    /// Happenings are independent of steps and sleep — logging nothing earns
    /// nothing however far you walked.
    func testHappeningsIndependentOfStepsAndSleep() {
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 0), 0)
    }

    // MARK: - Legacy option titles

    /// Ids from the old 31-option set still appear in saved days. They must
    /// resolve to a real label rather than a raw id.
    func testLegacyOptionTitlesCoverTheOldSet() {
        XCTAssertEqual(EnergyDefaults.legacyOptionTitles.count, 31)
        XCTAssertEqual(EnergyDefaults.legacyTitle(for: "body_walking"), "Walking")
        XCTAssertEqual(EnergyDefaults.legacyTitle(for: "mind_focusing"), "Focusing")
        XCTAssertEqual(EnergyDefaults.legacyTitle(for: "heart_joy"), "Joy")
    }

    func testLegacyTitleReturnsNilForUnknownId() {
        XCTAssertNil(EnergyDefaults.legacyTitle(for: "happening_walk"))
        XCTAssertNil(EnergyDefaults.legacyTitle(for: "user_abc"))
    }

    // MARK: - PastDaySnapshot codable

    func testPastDaySnapshotRoundTrip() throws {
        let original = PastDaySnapshot(
            inkEarned: 75,
            inkSpent: 30,
            happeningIds: ["happening_walk", "happening_read"],
            steps: 8_000,
            sleepHours: 7.5,
            stepsTarget: 9_000,
            sleepTargetHours: 7.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PastDaySnapshot.self, from: data)
        XCTAssertEqual(decoded, original)

        // The three category keys must not be written back.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["bodyIds"])
        XCTAssertNil(json["mindIds"])
        XCTAssertNil(json["heartIds"])
    }

    /// Snapshots saved before the flattening carry three arrays; they must
    /// concatenate in the order the app used to show them.
    func testPastDaySnapshotDecodesCategoryArrays() throws {
        let legacy = """
        {
          "inkEarned": 40, "inkSpent": 0,
          "bodyIds": ["body_walking"],
          "mindIds": ["mind_focusing"],
          "heartIds": ["heart_joy"],
          "steps": 100, "sleepHours": 1
        }
        """
        let decoded = try JSONDecoder().decode(
            PastDaySnapshot.self, from: try XCTUnwrap(legacy.data(using: .utf8))
        )
        XCTAssertEqual(decoded.happeningIds, ["body_walking", "mind_focusing", "heart_joy"])
    }

    /// The generation before that used activity/creativity/recovery/rest/joys.
    func testPastDaySnapshotDecodesPreRenameArrays() throws {
        let ancient = """
        {
          "controlGained": 20, "controlSpent": 5,
          "activityIds": ["a"],
          "creativityIds": ["c"], "recoveryIds": ["r"], "restIds": ["s"],
          "joysIds": ["j"]
        }
        """
        let decoded = try JSONDecoder().decode(
            PastDaySnapshot.self, from: try XCTUnwrap(ancient.data(using: .utf8))
        )
        XCTAssertEqual(decoded.happeningIds, ["a", "c", "r", "s", "j"])
        XCTAssertEqual(decoded.inkEarned, 20)
        XCTAssertEqual(decoded.inkSpent, 5)
    }

    func testPastDaySnapshotLegacyDecodeUsesDefaultTargets() throws {
        let legacyJSON = """
        {
          "inkEarned": 55,
          "inkSpent": 10,
          "happeningIds": ["happening_walk"],
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
            happeningIds: [],
            steps: 6_000,
            sleepHours: 6.0,
            stepsTarget: 8_000,
            sleepTargetHours: 6.0
        )
        let stepsPoints = pointsFromSteps(
            steps: Double(snapshot.steps), target: snapshot.stepsTarget,
            maxPoints: EnergyDefaults.stepsMaxPoints
        )
        let sleepPoints = pointsFromSleep(
            hours: snapshot.sleepHours, target: snapshot.sleepTargetHours,
            maxPoints: EnergyDefaults.sleepMaxPoints
        )
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
