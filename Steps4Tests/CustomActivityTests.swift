import XCTest
import HealthKit
@testable import Steps4

final class CustomActivityTests: XCTestCase {
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

    func testAddCustomOptionAppearsInOrderedOptions() {
        let model = makeModel()
        let id = model.addCustomOption(
            category: .activity,
            titleEn: "Test Activity",
            titleRu: "Test Activity",
            icon: "figure.run"
        )

        let options = model.orderedOptions(for: .activity)
        XCTAssertTrue(options.contains(where: { $0.id == id }))

        let reloaded = makeModel()
        reloaded.loadCustomEnergyOptions()
        XCTAssertTrue(reloaded.customEnergyOptions.contains(where: { $0.id == id }))
    }

    func testDeleteCustomOptionRemovesFromOrderAndPreferred() {
        let model = makeModel()
        let id = model.addCustomOption(
            category: .activity,
            titleEn: "Disposable Activity",
            titleRu: "Disposable Activity",
            icon: "figure.walk"
        )
        model.updatePreferredOptions([id], category: .activity)

        model.deleteCustomOption(optionId: id)

        let options = model.orderedOptions(for: .activity)
        XCTAssertFalse(options.contains(where: { $0.id == id }))
        XCTAssertFalse(model.isPreferredOptionSelected(id, category: .activity))

        let reloaded = makeModel()
        reloaded.loadCustomEnergyOptions()
        XCTAssertFalse(reloaded.customEnergyOptions.contains(where: { $0.id == id }))
    }

    private func makeModel() -> AppModel {
        AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine()
        )
    }

    private func clearDefaults() {
        let keys = [
            "customEnergyOptions_v1",
            "energyOptionsOrder_activity",
            "energyOptionsOrder_rest",
            "energyOptionsOrder_joys",
            "preferredEnergyOptions_v1_activity",
            "preferredEnergyOptions_v1_rest",
            "preferredEnergyOptions_v1_joys",
            "dailyEnergySelections_v1_activity",
            "dailyEnergySelections_v1_rest",
            "dailyEnergySelections_v1_joys"
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}

// MARK: - Mocks

private final class MockHealthKitService: HealthKitServiceProtocol {
    func fetchTodaySleep() async throws -> Double { 0 }
    func fetchSleep(from: Date, to: Date) async throws -> Double { 0 }
    @MainActor func requestAuthorization() async throws {}
    @MainActor func authorizationStatus() -> HKAuthorizationStatus { .sharingAuthorized }
    func fetchTodaySteps() async throws -> Double { 0 }
    func fetchSteps(from: Date, to: Date) async throws -> Double { 0 }
    func startObservingSteps(updateHandler: @escaping (Double) -> Void) {}
    func stopObservingSteps() {}
}

@MainActor
private final class MockFamilyControlsService: FamilyControlsServiceProtocol {
    var isAuthorized: Bool = false
    var selection: FamilyActivitySelection = FamilyActivitySelection()
    func requestAuthorization() async throws {}
    func updateSelection(_ newSelection: FamilyActivitySelection) {}
    func updateMinuteModeMonitoring() {}
    func updateShieldSchedule() {}
}

private final class MockNotificationService: NotificationServiceProtocol {
    func requestPermission() async throws {}
    func sendTimeExpiredNotification() {}
    func sendTimeExpiredNotification(remainingMinutes: Int) {}
    func sendUnblockNotification(remainingMinutes: Int) {}
    func sendRemainingTimeNotification(remainingMinutes: Int) {}
    func sendMinuteModeSummary(bundleId: String, minutesUsed: Int, stepsCharged: Int) {}
    func sendTestNotification() {}
    func sendAccessWindowReminder(remainingSeconds: Int, bundleId: String) {}
    func scheduleAccessWindowStatus(remainingSeconds: Int, bundleId: String) {}
}

private final class MockBudgetEngine: BudgetEngineProtocol {
    var tariff: Tariff = .medium
    var stepsPerMinute: Double { tariff.stepsPerMinute }
    var dailyBudgetMinutes: Int = 0
    var remainingMinutes: Int = 0

    func minutes(from steps: Double) -> Int { max(0, Int(steps / stepsPerMinute)) }
    func setBudget(minutes: Int) {
        dailyBudgetMinutes = minutes
        remainingMinutes = minutes
    }
    func consume(mins: Int) { remainingMinutes = max(0, remainingMinutes - mins) }
    func resetIfNeeded() {}
    func updateTariff(_ newTariff: Tariff) { tariff = newTariff }
    func updateDayEnd(hour: Int, minute: Int) {}
    func reloadFromStorage() {}
    var difficultyLevel: DifficultyLevel {
        get { tariff }
        set { tariff = newValue }
    }
}
