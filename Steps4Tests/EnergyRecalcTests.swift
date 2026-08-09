import XCTest
import HealthKit
@testable import Steps4

/// Energy recalculation against the three-part model:
///
///     steps(20) + sleep(20) + happenings(60) = 100
///     happenings = min(additions × 10, 60)
///
/// Replaces the five-part per-category assertions this file used to carry.
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
        addAdditions(to: model, count: 6)
        model.spentStepsToday = 0

        model.recalculateDailyEnergy()

        XCTAssertEqual(model.baseEnergyToday, 100, "20 steps + 20 sleep + 60 happenings")
        XCTAssertEqual(model.stepsBalance, 100)
    }

    /// Acceptance criterion: a day of 2 happenings plus full steps and sleep
    /// totals 60, not 100. Two additions earn 20, not a whole category's worth.
    func testRecalculate_twoHappeningsWithFullStepsAndSleepTotalsSixty() {
        let model = makeModel()
        defaults.set(10_000.0, forKey: SharedKeys.userStepsTarget)
        defaults.set(8.0, forKey: SharedKeys.userSleepTarget)
        model.stepsToday = 10_000
        model.dailySleepHours = 8.0
        addAdditions(to: model, count: 2)
        model.spentStepsToday = 0

        model.recalculateDailyEnergy()

        XCTAssertEqual(model.baseEnergyToday, 60, "20 steps + 20 sleep + 20 happenings")
    }

    func testRecalculate_cappedAt100() {
        let model = makeModel()
        defaults.set(5_000.0, forKey: SharedKeys.userStepsTarget)
        defaults.set(4.0, forKey: SharedKeys.userSleepTarget)
        model.stepsToday = 50_000
        model.dailySleepHours = 20.0
        addAdditions(to: model, count: 20)
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
        addAdditions(to: model, count: 4)
        model.spentStepsToday = 0
        model.recalculateDailyEnergy()
        let fullBase = model.baseEnergyToday
        _ = model.pay(cost: fullBase)
        XCTAssertEqual(model.stepsBalance, 0)

        model.todayAdditions = []
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
        // The assumption gate requires ≥6h since the custom day boundary.
        // Anchor the boundary ~12h in the past so the test passes at any
        // wall-clock time (it used to fail when run between 00:00 and 06:00).
        model.dayEndHour = (Calendar.current.component(.hour, from: .now) + 12) % 24
        model.dayEndMinute = 0

        XCTAssertEqual(model.sleepPointsToday, EnergyDefaults.assumedSleepPoints)
        XCTAssertTrue(model.isSleepAssumed)
    }

    func testSleepPointsToday_realWhenHasHours() {
        let model = makeModel()
        defaults.set(8.0, forKey: SharedKeys.userSleepTarget)
        model.dailySleepHours = 8.0

        XCTAssertEqual(model.sleepPointsToday, EnergyDefaults.sleepMaxPoints)
        XCTAssertFalse(model.isSleepAssumed)
    }

    // MARK: - Happening points

    func testHappeningPoints_tenPerAddition() {
        let model = makeModel()
        XCTAssertEqual(model.happeningPointsToday, 0)

        addAdditions(to: model, count: 1)
        XCTAssertEqual(model.happeningPointsToday, 10)

        addAdditions(to: model, count: 2)
        XCTAssertEqual(model.happeningPointsToday, 30, "Three additions total")
    }

    /// Distinct additions past the sixth still land on the canvas and still
    /// increment `useCount` — they just stop earning.
    func testHappeningPoints_capAtSixtyRegardlessOfCount() {
        let model = makeModel()
        addAdditions(to: model, count: 6)
        XCTAssertEqual(model.happeningPointsToday, 60)

        addAdditions(to: model, count: 1)
        XCTAssertEqual(model.happeningPointsToday, 60, "Seventh addition earns nothing")
        XCTAssertEqual(model.todayAdditions.count, 7, "But it is still recorded")

        addAdditions(to: model, count: 50)
        XCTAssertEqual(model.happeningPointsToday, 60)
    }

    func testHappeningPoints_distinctHappeningsCountSeparately() {
        let model = makeModel()
        model.addHappening(id: HappeningDefaults.builtIns[0].id, colorHex: "#CC5050")
        model.addHappening(id: HappeningDefaults.builtIns[1].id, colorHex: "#CC5050")

        XCTAssertEqual(model.todayAdditions.count, 2)
        XCTAssertEqual(model.happeningPointsToday, 20)
    }

    // MARK: - Routines

    func testSaveAndApplyRoutine_roundTrip() {
        let model = makeModel()
        let ids = HappeningDefaults.builtIns.prefix(3).map(\.id)
        for id in ids {
            model.addHappening(id: id, colorHex: "#CC5050")
        }

        model.saveCurrentAsRoutine(name: "Morning")
        model.loadSavedRoutines()
        XCTAssertEqual(model.savedRoutines.count, 1)
        XCTAssertEqual(model.savedRoutines[0].name, "Morning")
        XCTAssertEqual(model.savedRoutines[0].happeningIds, Array(ids))

        model.todayAdditions = []
        model.applyRoutine(model.savedRoutines[0])

        XCTAssertEqual(model.todayAdditions.map(\.optionId), Array(ids))
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

    /// Appends `count` distinct catalog additions so the economy tests exercise
    /// the one-happening-per-custom-day rule as well as its points cap.
    private func addAdditions(to model: AppModel, count: Int) {
        for index in 0..<count {
            let happening = model.createHappening(title: "Test happening \(index)")
            model.addHappening(id: happening.id, colorHex: "#CC5050")
        }
    }

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
        // Production loads the catalog in `loadDailyEnergyState`. `applyRoutine`
        // validates ids against it, so without this every routine applies empty.
        model.happeningStore.load()
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
            SharedKeys.savedRoutines,
            SharedKeys.baseEnergyToday,
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: SharedKeys.restDayOverrideEnabled)
    }
}
