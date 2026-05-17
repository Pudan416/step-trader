import XCTest
import HealthKit
@testable import Steps4

@MainActor
final class PaymentTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults.stepsTrader()
        clearPaymentDefaults()
    }

    override func tearDown() {
        clearPaymentDefaults()
        super.tearDown()
    }

    // MARK: - pay()

    func testPay_debitsBaseBeforeBonus() {
        let model = makeModel()
        model.baseEnergyToday = 50
        model.spentStepsToday = 0
        model.stepsBalance = 50
        model.bonusSteps = 20
        model.serverGrantedSteps = 20

        let success = model.pay(cost: 60)

        XCTAssertTrue(success)
        XCTAssertEqual(model.spentStepsToday, 50, "All base consumed first")
        XCTAssertEqual(model.stepsBalance, 0, "Base fully drained")
        XCTAssertEqual(model.serverGrantedSteps, 10, "Remainder taken from server bonus")
    }

    func testPay_fullBaseNoBonus() {
        let model = makeModel()
        model.baseEnergyToday = 80
        model.spentStepsToday = 0
        model.stepsBalance = 80
        model.serverGrantedSteps = 0

        let success = model.pay(cost: 30)

        XCTAssertTrue(success)
        XCTAssertEqual(model.spentStepsToday, 30)
        XCTAssertEqual(model.stepsBalance, 50)
    }

    func testPay_rejectsInsufficientBalance() {
        let model = makeModel()
        model.baseEnergyToday = 10
        model.spentStepsToday = 0
        model.stepsBalance = 10
        model.serverGrantedSteps = 0

        let success = model.pay(cost: 20)

        XCTAssertFalse(success)
        XCTAssertEqual(model.spentStepsToday, 0, "No mutation on failure")
        XCTAssertEqual(model.stepsBalance, 10, "Balance unchanged")
    }

    func testPay_zeroCostSucceeds() {
        let model = makeModel()
        model.baseEnergyToday = 50
        model.stepsBalance = 50

        let success = model.pay(cost: 0)

        XCTAssertTrue(success)
        XCTAssertEqual(model.stepsBalance, 50)
    }

    func testPay_exactBalance() {
        let model = makeModel()
        model.baseEnergyToday = 40
        model.spentStepsToday = 0
        model.stepsBalance = 40

        let success = model.pay(cost: 40)

        XCTAssertTrue(success)
        XCTAssertEqual(model.stepsBalance, 0)
        XCTAssertEqual(model.spentStepsToday, 40)
    }

    func testPay_persistsToUserDefaults() {
        let model = makeModel()
        model.baseEnergyToday = 60
        model.spentStepsToday = 0
        model.stepsBalance = 60

        _ = model.pay(cost: 25)

        let persisted = defaults.integer(forKey: SharedKeys.spentStepsToday)
        XCTAssertEqual(persisted, 25)
    }

    // MARK: - refund()

    func testRefund_restoresSpentToBase() {
        let model = makeModel()
        model.baseEnergyToday = 100
        model.spentStepsToday = 40
        model.stepsBalance = 60

        model.refund(cost: 15)

        XCTAssertEqual(model.spentStepsToday, 25)
        XCTAssertEqual(model.stepsBalance, 75)
    }

    func testRefund_neverGoesNegativeSpent() {
        let model = makeModel()
        model.baseEnergyToday = 50
        model.spentStepsToday = 10
        model.stepsBalance = 40

        model.refund(cost: 100)

        XCTAssertEqual(model.spentStepsToday, 0, "Clamped to 0")
        XCTAssertEqual(model.stepsBalance, 50, "Full base restored")
    }

    func testRefund_zeroCostNoOp() {
        let model = makeModel()
        model.baseEnergyToday = 50
        model.spentStepsToday = 20
        model.stepsBalance = 30

        model.refund(cost: 0)

        XCTAssertEqual(model.spentStepsToday, 20)
        XCTAssertEqual(model.stepsBalance, 30)
    }

    // MARK: - payForEntry() with day pass

    func testPayForEntry_skipsCostWhenDayPassActive() {
        let model = makeModel()
        model.baseEnergyToday = 50
        model.stepsBalance = 50
        model.spentStepsToday = 0
        model.dayPassGrants["com.test.app"] = Date()

        let success = model.payForEntry(for: "com.test.app")

        XCTAssertTrue(success)
        XCTAssertEqual(model.spentStepsToday, 0, "No cost deducted with day pass")
        XCTAssertEqual(model.stepsBalance, 50)
    }

    // MARK: - loadSpentStepsBalance

    func testLoadSpentStepsBalance_resetsOnNewDay() {
        let model = makeModel()
        let yesterday = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        defaults.set(yesterday, forKey: SharedKeys.dailyEnergyAnchor)
        defaults.set(42, forKey: SharedKeys.spentStepsToday)

        model.loadSpentStepsBalance()

        XCTAssertEqual(model.spentStepsToday, 0, "Spent resets on new day")
    }

    func testLoadSpentStepsBalance_preservesSameDay() {
        let model = makeModel()
        let todayStart = model.currentDayStart(for: Date())
        defaults.set(todayStart, forKey: SharedKeys.dailyEnergyAnchor)
        defaults.set(25, forKey: SharedKeys.spentStepsToday)
        model.baseEnergyToday = 80

        model.loadSpentStepsBalance()

        XCTAssertEqual(model.spentStepsToday, 25, "Spent preserved same day")
        XCTAssertEqual(model.stepsBalance, 55)
    }

    // MARK: - consumeBonusSteps

    func testConsumeBonusSteps_drainsServerGranted() {
        let model = makeModel()
        model.serverGrantedSteps = 30

        model.consumeBonusSteps(12)

        XCTAssertEqual(model.serverGrantedSteps, 18)
    }

    func testConsumeBonusSteps_clampsToZero() {
        let model = makeModel()
        model.serverGrantedSteps = 5

        model.consumeBonusSteps(100)

        XCTAssertEqual(model.serverGrantedSteps, 0)
    }

    // MARK: - Helpers

    private func makeModel() -> AppModel {
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
        let store = SubscriptionStore(defaults: defaults)
        return AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: store
        )
    }

    private func clearPaymentDefaults() {
        let keys = [
            SharedKeys.spentStepsToday,
            SharedKeys.stepsBalance,
            SharedKeys.stepsBalanceAnchor,
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.bonusSteps,
            SharedKeys.isGrandfathered,
            "serverGrantedSteps_v1",
            "debugStepsBonus_outerworld_v1",
            "debugStepsBonus_debug_v1",
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}
