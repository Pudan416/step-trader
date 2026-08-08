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

    /// A missing anchor key must seed the anchor, not wipe the day. The old
    /// version of this guarded the three category arrays; the state it protects
    /// is now `todayAdditions`, but the regression is the same one.
    func testLoadDailyEnergyState_MissingAnchor_DoesNotResetAdditionsOrBaseEnergy() throws {
        let today = AppModel.dayKey(for: .now)
        let additions = [
            OptionEntry(id: "a", dayKey: today, optionId: "happening_walk",
                        colorHex: "#CC5050", timestamp: .now, assetVariant: nil),
            OptionEntry(id: "b", dayKey: today, optionId: "happening_read",
                        colorHex: "#6098CC", timestamp: .now, assetVariant: nil),
        ]
        defaults.set(try JSONEncoder().encode(additions), forKey: SharedKeys.todayAdditions)
        defaults.set(65, forKey: SharedKeys.baseEnergyToday)
        defaults.removeObject(forKey: SharedKeys.dailyEnergyAnchor)

        let model = makeModel()
        model.loadDailyEnergyState()

        XCTAssertEqual(model.todayAdditions.map(\.id), ["a", "b"])
        XCTAssertEqual(model.baseEnergyToday, 65)
        XCTAssertNotNil(
            defaults.object(forKey: SharedKeys.dailyEnergyAnchor),
            "Anchor should be initialized, not reset state"
        )
    }

    /// The canvas is the backstop when the additions key is missing — a user
    /// upgrading mid-day must not see their day emptied.
    func testLoadDailyEnergyState_RecoversAdditionsFromSavedCanvas() throws {
        let today = AppModel.dayKey(for: .now)
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        defaults.set(Date.now, forKey: SharedKeys.dailyEnergyAnchor)

        var canvas = DayCanvas(dayKey: today)
        canvas.elements = [
            CanvasElement.spawn(
                optionId: "happening_walk", color: "#CC5050", label: "Walk",
                existingElements: [], dayKey: today
            )
        ]
        _ = CanvasStorageService.shared.saveCanvas(canvas)
        defer { CanvasStorageService.shared.deleteCanvas(for: today) }

        let model = makeModel()
        model.loadDailyEnergyState()

        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk"])
    }

    private func clearEnergyDefaults() {
        let keys = [
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.dailySleepHours,
            SharedKeys.baseEnergyToday,
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            "dailyEnergySelections_v1_body",
            "dailyEnergySelections_v1_mind",
            "dailyEnergySelections_v1_heart",
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    private func makeModel() -> AppModel {
        AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore.shared
        )
    }
}
