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

    // MARK: - PayGate request freshness

    /// `payGateRequestedAt` was written by two callers and read by none, so a shield tap
    /// the user walked away from still opened the PayGate whenever they next launched
    /// the app — hours or days later, on top of whatever they came in to do.
    func testPayGateRequest_recentTapIsStillActionable() {
        let now = Date()
        XCTAssertTrue(
            AppModel.isPayGateRequestFresh(requestedAt: now.addingTimeInterval(-60), now: now)
        )
    }

    func testPayGateRequest_abandonedTapExpires() {
        let now = Date()
        let stale = now.addingTimeInterval(-(AppModel.payGateRequestMaxAge + 60))
        XCTAssertFalse(AppModel.isPayGateRequestFresh(requestedAt: stale, now: now))
    }

    /// The boundary is inclusive — a request exactly at the limit still counts.
    func testPayGateRequest_boundaryIsInclusive() {
        let now = Date()
        let edge = now.addingTimeInterval(-AppModel.payGateRequestMaxAge)
        XCTAssertTrue(AppModel.isPayGateRequestFresh(requestedAt: edge, now: now))
    }

    /// Flags written before this rule existed carry no timestamp; they should still work
    /// once rather than being silently swallowed on upgrade.
    func testPayGateRequest_missingTimestampIsTreatedAsFresh() {
        XCTAssertTrue(AppModel.isPayGateRequestFresh(requestedAt: nil, now: Date()))
    }

    /// A timestamp in the future means the clock moved backwards, not that the request
    /// is old — refusing it would strand a user who had just tapped the shield.
    func testPayGateRequest_futureTimestampIsNotTreatedAsStale() {
        let now = Date()
        XCTAssertTrue(
            AppModel.isPayGateRequestFresh(requestedAt: now.addingTimeInterval(3600), now: now)
        )
    }

    func testWidgetUnlockURLCanBeConsumedOnlyOnce() throws {
        let suite = "WidgetUnlockTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let url = WidgetUnlockRequest.url(groupId: "group-a", windowRaw: "minutes10", defaults: store)
        let request = try XCTUnwrap(WidgetUnlockRequest.consume(url, defaults: store))
        XCTAssertEqual(request.groupId, "group-a")
        XCTAssertEqual(request.windowRaw, "minutes10")
        XCTAssertNil(WidgetUnlockRequest.consume(url, defaults: store), "Repeated delivery must not charge twice")
        let refreshedURL = WidgetUnlockRequest.url(groupId: "group-a", windowRaw: "minutes10", defaults: store)
        XCTAssertNotEqual(url, refreshedURL)
        XCTAssertNotNil(WidgetUnlockRequest.consume(refreshedURL, defaults: store), "A refreshed widget permits a new intentional purchase")
        XCTAssertNil(WidgetUnlockRequest.consume(url, defaults: store))
    }

    func testWidgetUnlockURLRejectsForgedOrChangedPurchase() throws {
        let suite = "WidgetUnlockTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let url = WidgetUnlockRequest.url(groupId: "group-a", windowRaw: "minutes10", defaults: store)
        for changed in [
            url.absoluteString.replacingOccurrences(of: "minutes10", with: "hour1"),
            url.absoluteString.replacingOccurrences(of: "group-a", with: "group-b"),
            url.absoluteString.replacingOccurrences(of: "steps-trader:", with: "https:"),
            url.absoluteString + "&window=hour1",
            "steps-trader://unlock?groupId=group-a&window=minutes10&token=forged"
        ] {
            XCTAssertNil(WidgetUnlockRequest.consume(try XCTUnwrap(URL(string: changed)), defaults: store))
        }
        XCTAssertNotNil(WidgetUnlockRequest.consume(url, defaults: store), "Invalid links must not consume the actual widget action")
    }

    func testWidgetPreparationDoesNotReloadOverLiveBalance() async {
        let model = makeModel()
        await model.prepareLocalPurchaseState()
        model.stepsBalance = 12
        await model.prepareLocalPurchaseState()
        XCTAssertEqual(model.stepsBalance, 12, "Foreground startup must reuse the state already used by the widget action")
    }

    // MARK: - pay()

    func testPay_debitsBaseBeforeBonus() {
        let model = makeModel()
        model.baseEnergyToday = 50
        model.spentStepsToday = 0
        model.stepsBalance = 50
        model.bonusSteps = 20

        let success = model.pay(cost: 60)

        XCTAssertTrue(success)
        XCTAssertEqual(model.spentStepsToday, 50, "All base consumed first")
        XCTAssertEqual(model.stepsBalance, 0, "Base fully drained")
        XCTAssertEqual(model.bonusSteps, 0, "Overflow clears the whole bonus pool")
    }

    func testPay_fullBaseNoBonus() {
        let model = makeModel()
        model.baseEnergyToday = 80
        model.spentStepsToday = 0
        model.stepsBalance = 80

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

    // `consumeBonusSteps` is all-or-nothing: there is no partial bonus
    // accounting, so any positive overflow clears the entire pool. (§M5 dropped
    // the proportional `serverGrantedSteps` bookkeeping this used to carry.)

    func testConsumeBonusSteps_partialCostClearsWholePool() {
        let model = makeModel()
        model.bonusSteps = 30

        model.consumeBonusSteps(12)

        XCTAssertEqual(model.bonusSteps, 0, "No partial accounting — the pool is cleared")
    }

    func testConsumeBonusSteps_overConsumptionClampsToZero() {
        let model = makeModel()
        model.bonusSteps = 5

        model.consumeBonusSteps(100)

        XCTAssertEqual(model.bonusSteps, 0, "Never goes negative")
    }

    func testConsumeBonusSteps_zeroCostIsNoOp() {
        let model = makeModel()
        model.bonusSteps = 30

        model.consumeBonusSteps(0)

        XCTAssertEqual(model.bonusSteps, 30, "Guard leaves the pool untouched")
    }

    // MARK: - Helpers

    // MARK: - Screen Time access

    /// Access can be revoked in Screen Time at any moment, and every
    /// `ManagedSettingsStore` write is inert while it is — so the purchase has to be
    /// refused before any colors move, not discovered afterwards. The group id below is
    /// deliberately one that does not exist: if the access check ever slips behind the
    /// group lookup, this stops setting `payGateError` and the test fails.
    func testGroupUnlock_withoutScreenTimeAccess_chargesNothingAndSaysSo() async {
        let model = makeModel()
        (model.familyControlsService as? MockFamilyControlsService)?.isAuthorized = false
        model.baseEnergyToday = 500
        model.spentStepsToday = 0
        model.stepsBalance = 500
        model.bonusSteps = 0

        let unlocked = await model.handlePayGatePaymentForGroup(
            groupId: "no-such-group", window: .minutes10, costOverride: 50
        )
        XCTAssertFalse(unlocked, "A failed purchase must not launch the target app")

        XCTAssertEqual(model.stepsBalance, 500, "colors must not move while unauthorized")
        XCTAssertEqual(model.spentStepsToday, 0)
        XCTAssertEqual(model.bonusSteps, 0)
        XCTAssertNotNil(model.payGateError, "the refusal has to be visible, not silent")
    }

    /// The discriminating half of the pair: with access granted, a missing group is a
    /// different failure and must not borrow the Screen Time message.
    func testGroupUnlock_withAccessButMissingGroup_reportsNoAccessError() async {
        let model = makeModel()
        (model.familyControlsService as? MockFamilyControlsService)?.isAuthorized = true
        model.baseEnergyToday = 500
        model.spentStepsToday = 0
        model.stepsBalance = 500

        let unlocked = await model.handlePayGatePaymentForGroup(
            groupId: "no-such-group", window: .minutes10, costOverride: 50
        )
        XCTAssertFalse(unlocked, "A failed purchase must not launch the target app")

        XCTAssertEqual(model.stepsBalance, 500)
        XCTAssertNil(model.payGateError)
    }

    func testRolloverIsNotSuppressedByRecentSameDayCheck() {
        let model = makeModel()
        model.isBootstrapping = true
        model.checkDayBoundary()
        let yesterday = model.currentDayStart(for: .now).addingTimeInterval(-3600)
        defaults.set(yesterday, forKey: SharedKeys.dailyEnergyAnchor)
        defaults.set(19, forKey: SharedKeys.spentStepsToday)
        model.spentStepsToday = 19
        model.checkDayBoundary()
        XCTAssertEqual(model.spentStepsToday, 0)
        XCTAssertEqual(defaults.integer(forKey: SharedKeys.spentStepsToday), 0)
        model.recalculateDailyEnergy()
        model.loadDailyEnergyState()
        XCTAssertEqual(model.spentStepsToday, 0, "Recalculation and reload must not resurrect yesterday's spending")
    }

    private func makeModel() -> AppModel {
        let store = SubscriptionStore()
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
            "serverGrantedSteps_v1",
            "debugStepsBonus_outerworld_v1",
            "debugStepsBonus_debug_v1",
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}
