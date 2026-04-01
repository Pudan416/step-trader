import XCTest
import HealthKit
@testable import Steps4

@MainActor
final class CanvasPersistenceRegressionTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults.stepsTrader()
        clearEnergyDefaults()
    }

    override func tearDown() {
        clearEnergyDefaults()
        super.tearDown()
    }

    func testLoadDailyEnergyState_MissingAnchor_DoesNotResetSelectionsOrBaseEnergy() throws {
        // Given persisted daily state exists but anchor key is missing.
        saveStringArray(["activity_pushups", "activity_walking"], key: SharedKeys.dailySelectionsKey("body"))
        saveStringArray(["creativity_reading"], key: SharedKeys.dailySelectionsKey("mind"))
        saveStringArray(["joys_family"], key: SharedKeys.dailySelectionsKey("heart"))
        defaults.set(65, forKey: SharedKeys.baseEnergyToday)
        defaults.set(2, forKey: "energyMigrationVersion_v1")
        defaults.removeObject(forKey: SharedKeys.dailyEnergyAnchor)

        let model = makeModel()
        model.loadDailyEnergyState()

        XCTAssertEqual(model.dailyActivitySelections, ["activity_pushups", "activity_walking"])
        XCTAssertEqual(model.dailyRestSelections, ["creativity_reading"])
        XCTAssertEqual(model.dailyJoysSelections, ["joys_family"])
        XCTAssertEqual(model.baseEnergyToday, 65)
        XCTAssertNotNil(defaults.object(forKey: SharedKeys.dailyEnergyAnchor), "Anchor should be initialized, not reset state")
    }

    func testLoadDailyEnergyState_SlotsDoNotOverridePersistedSelections() throws {
        // Given persisted selections are broader than 4 slots.
        let expectedBody = ["activity_pushups", "activity_walking"]
        let expectedMind = ["creativity_reading", "creativity_journaling"]
        let expectedHeart = ["joys_friends", "joys_music"]
        saveStringArray(expectedBody, key: SharedKeys.dailySelectionsKey("body"))
        saveStringArray(expectedMind, key: SharedKeys.dailySelectionsKey("mind"))
        saveStringArray(expectedHeart, key: SharedKeys.dailySelectionsKey("heart"))
        defaults.set(2, forKey: "energyMigrationVersion_v1")
        defaults.set(Date(), forKey: SharedKeys.dailyEnergyAnchor)

        // Persist 4 slots with only a subset (legacy/truncated UI projection).
        let subsetSlots: [DayCanvasSlot] = [
            DayCanvasSlot(category: .body, optionId: "activity_pushups"),
            DayCanvasSlot(category: .body, optionId: "activity_walking"),
            DayCanvasSlot(category: .mind, optionId: "creativity_reading"),
            DayCanvasSlot(category: nil, optionId: nil),
        ]
        defaults.set(try JSONEncoder().encode(subsetSlots), forKey: SharedKeys.dailyCanvasSlots)

        let model = makeModel()
        model.loadDailyEnergyState()

        XCTAssertEqual(model.dailyActivitySelections, expectedBody)
        XCTAssertEqual(model.dailyRestSelections, expectedMind)
        XCTAssertEqual(model.dailyJoysSelections, expectedHeart)
    }

    private func clearEnergyDefaults() {
        let keys = [
            "dailyEnergyAnchor_v1",
            "dailySleepHours_v1",
            "baseEnergyToday_v1",
            "dailyEnergySelections_v1_body",
            "dailyEnergySelections_v1_mind",
            "dailyEnergySelections_v1_heart",
            "preferredEnergyOptions_v1_body",
            "preferredEnergyOptions_v1_mind",
            "preferredEnergyOptions_v1_heart",
            "dailyChoiceSlots_v1",
            "energyMigrationVersion_v1",
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    private func saveStringArray(_ value: [String], key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func makeModel() -> AppModel {
        AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine()
        )
    }
}
