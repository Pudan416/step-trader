import XCTest
import HealthKit
@testable import Steps4

@MainActor
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
            category: .body,
            titleEn: "Test Activity",
            titleRu: "Test Activity",
            icon: "figure.run"
        )

        let options = model.orderedOptions(for: .body)
        XCTAssertTrue(options.contains(where: { $0.id == id }))

        let reloaded = makeModel()
        reloaded.loadCustomEnergyOptions()
        XCTAssertTrue(reloaded.customEnergyOptions.contains(where: { $0.id == id }))
    }

    func testDeleteCustomOptionRemovesFromOrderAndPreferred() {
        let model = makeModel()
        let id = model.addCustomOption(
            category: .body,
            titleEn: "Disposable Activity",
            titleRu: "Disposable Activity",
            icon: "figure.walk"
        )
        model.updatePreferredOptions([id], category: .body)

        model.deleteCustomOption(optionId: id)

        let options = model.orderedOptions(for: .body)
        XCTAssertFalse(options.contains(where: { $0.id == id }))
        XCTAssertFalse(model.isPreferredOptionSelected(id, category: .body))

        let reloaded = makeModel()
        reloaded.loadCustomEnergyOptions()
        XCTAssertFalse(reloaded.customEnergyOptions.contains(where: { $0.id == id }))
    }

    private func makeModel() -> AppModel {
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
        let proStore = SubscriptionStore(defaults: defaults)
        return AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: proStore
        )
    }

    private func clearDefaults() {
        let keys = [
            "customEnergyOptions_v1",
            "energyOptionsOrder_body",
            "energyOptionsOrder_mind",
            "energyOptionsOrder_heart",
            "preferredEnergyOptions_v1_body",
            "preferredEnergyOptions_v1_mind",
            "preferredEnergyOptions_v1_heart",
            "dailyEnergySelections_v1_body",
            "dailyEnergySelections_v1_mind",
            "dailyEnergySelections_v1_heart",
            SharedKeys.isGrandfathered
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}
