import XCTest
import HealthKit
@testable import Steps4

@MainActor
final class EnergyRecalcTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults.stepsTrader()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        super.tearDown()
    }

    // MARK: - recalculateDailyEnergy

    func testRecalculate_zeroState() {
        let model = makeModel()
        model.stepsToday = 0
        model.dailySleepHours = 0
        model.spentStepsToday = 0

        model.recalculateDailyEnergy()

        XCTAssertEqual(model.baseEnergyToday, 0)
        XCTAssertEqual(model.stepsBalance, 0)
    }

    func testRecalculate_maxTarget() {
        let model = makeModel()
        defaults.set(10_000.0, forKey: SharedKeys.userStepsTarget)
        defaults.set(8.0, forKey: SharedKeys.userSleepTarget)
        model.stepsToday = 10_000
        model.dailySleepHours = 8.0
        model.dailyActivitySelections = ["a", "b", "c", "d"]
        model.dailyRestSelections = ["e", "f", "g", "h"]
        model.dailyJoysSelections = ["i", "j", "k", "l"]
        model.spentStepsToday = 0

        model.recalculateDailyEnergy()

        XCTAssertEqual(model.baseEnergyToday, 100, "20 steps + 20 sleep + 20 body + 20 mind + 20 heart")
        XCTAssertEqual(model.stepsBalance, 100)
    }

    func testRecalculate_cappedAt100() {
        let model = makeModel()
        defaults.set(5_000.0, forKey: SharedKeys.userStepsTarget)
        defaults.set(4.0, forKey: SharedKeys.userSleepTarget)
        model.stepsToday = 50_000
        model.dailySleepHours = 20.0
        model.dailyActivitySelections = ["a", "b", "c", "d"]
        model.dailyRestSelections = ["e", "f", "g", "h"]
        model.dailyJoysSelections = ["i", "j", "k", "l"]
        model.spentStepsToday = 0

        model.recalculateDailyEnergy()

        XCTAssertEqual(model.baseEnergyToday, 100, "Capped at maxBaseEnergy")
    }

    func testRecalculate_restDayOverrideMinimum30() {
        let model = makeModel()
        defaults.set(true, forKey: SharedKeys.restDayOverrideEnabled)
        UserDefaults.standard.set(true, forKey: SharedKeys.restDayOverrideEnabled)
        model.stepsToday = 0
        model.dailySleepHours = 0
        model.spentStepsToday = 0

        model.recalculateDailyEnergy()

        XCTAssertGreaterThanOrEqual(model.baseEnergyToday, 30, "Rest day override floor")
    }

    func testRecalculate_balanceWhenSpentExceedsNewBase() {
        let model = makeModel()
        defaults.set(10_000.0, forKey: SharedKeys.userStepsTarget)
        model.stepsToday = 5_000
        model.dailySleepHours = 0
        model.spentStepsToday = 15

        model.recalculateDailyEnergy()

        let expectedBase = model.baseEnergyToday
        XCTAssertEqual(model.stepsBalance, max(0, expectedBase - 15),
                       "Balance = max(0, base - spent); spent is NOT capped to base")
    }

    func testRecalculate_spentNotCappedWhenBaseDrops() {
        let model = makeModel()
        defaults.set(10_000.0, forKey: SharedKeys.userStepsTarget)
        model.stepsToday = 10_000
        model.dailySleepHours = 0
        model.dailyActivitySelections = ["a", "b", "c", "d"]
        model.spentStepsToday = 0
        model.recalculateDailyEnergy()
        let fullBase = model.baseEnergyToday
        _ = model.pay(cost: fullBase)
        XCTAssertEqual(model.stepsBalance, 0)

        model.dailyActivitySelections = []
        model.recalculateDailyEnergy()

        XCTAssertEqual(model.spentStepsToday, fullBase,
                       "Spent preserved even though base dropped — prevents free EXP exploit")
        XCTAssertEqual(model.stepsBalance, 0)
    }

    // MARK: - Sleep points: assumed vs real

    func testSleepPointsToday_assumedWhenNoData() {
        let model = makeModel()
        model.dailySleepHours = 0
        model.healthStore.hasSleepData = true

        let pts = model.sleepPointsToday
        XCTAssertEqual(pts, EnergyDefaults.assumedSleepPoints)
        XCTAssertTrue(model.isSleepAssumed)
    }

    func testSleepPointsToday_realWhenHasHours() {
        let model = makeModel()
        defaults.set(8.0, forKey: SharedKeys.userSleepTarget)
        model.dailySleepHours = 8.0

        let pts = model.sleepPointsToday
        XCTAssertEqual(pts, EnergyDefaults.sleepMaxPoints)
        XCTAssertFalse(model.isSleepAssumed)
    }

    // MARK: - Selection points

    func testSelectionPoints_perCategory() {
        let model = makeModel()
        model.dailyActivitySelections = ["a", "b"]
        XCTAssertEqual(model.activityPointsToday, 2 * EnergyDefaults.selectionPoints)

        model.dailyRestSelections = ["x"]
        XCTAssertEqual(model.creativityPointsToday, 1 * EnergyDefaults.selectionPoints)

        model.dailyJoysSelections = ["p", "q", "r", "s"]
        XCTAssertEqual(model.joysCategoryPointsToday, 4 * EnergyDefaults.selectionPoints)
    }

    // MARK: - Routines

    func testSaveAndApplyRoutine_roundTrip() {
        let model = makeModel()
        model.dailyActivitySelections = ["body_walking"]
        model.dailyRestSelections = ["mind_focusing", "mind_learning"]
        model.dailyJoysSelections = ["heart_joy"]

        model.saveCurrentAsRoutine(name: "Morning")
        model.loadSavedRoutines()
        XCTAssertEqual(model.savedRoutines.count, 1)
        XCTAssertEqual(model.savedRoutines[0].name, "Morning")

        model.dailyActivitySelections = []
        model.dailyRestSelections = []
        model.dailyJoysSelections = []

        model.applyRoutine(model.savedRoutines[0])

        XCTAssertEqual(model.dailyActivitySelections, ["body_walking"])
        XCTAssertEqual(model.dailyRestSelections, ["mind_focusing", "mind_learning"])
        XCTAssertEqual(model.dailyJoysSelections, ["heart_joy"])
    }

    func testDeleteRoutine_removes() {
        let model = makeModel()
        model.saveCurrentAsRoutine(name: "Temp")
        model.loadSavedRoutines()
        XCTAssertEqual(model.savedRoutines.count, 1)

        model.deleteRoutine(model.savedRoutines[0])
        XCTAssertTrue(model.savedRoutines.isEmpty)

        model.loadSavedRoutines()
        XCTAssertTrue(model.savedRoutines.isEmpty)
    }

    // MARK: - Helpers

    private func makeModel() -> AppModel {
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
        let store = SubscriptionStore(defaults: defaults)
        let model = AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: store
        )
        model.isBootstrapping = true
        return model
    }

    private func clearDefaults() {
        let keys = [
            SharedKeys.userStepsTarget,
            SharedKeys.userSleepTarget,
            SharedKeys.restDayOverrideEnabled,
            SharedKeys.isGrandfathered,
            SharedKeys.spentStepsToday,
            SharedKeys.stepsBalance,
            SharedKeys.stepsBalanceAnchor,
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.bonusSteps,
            "savedEnergyRoutines_v1",
            "baseEnergyToday_v1",
            "dailyEnergySelections_v1_body",
            "dailyEnergySelections_v1_mind",
            "dailyEnergySelections_v1_heart",
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: SharedKeys.restDayOverrideEnabled)
    }
}
