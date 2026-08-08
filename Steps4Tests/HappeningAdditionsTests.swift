import XCTest
@testable import Steps4

@MainActor
final class HappeningAdditionsTests: XCTestCase {
    func testEnergyRoutineRoundTripsFlatHappeningIds() throws {
        let original = EnergyRoutine(name: "Morning", happeningIds: ["happening_walk", "happening_coffee"])
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["happeningIds"] as? [String], original.happeningIds)
        XCTAssertNil(json["bodyIds"])
        XCTAssertEqual(try JSONDecoder().decode(EnergyRoutine.self, from: data), original)
    }

    func testEnergyRoutineDecodesLegacyCategoryArrays() throws {
        let data = try XCTUnwrap("""
        {"id":"legacy","name":"Old","bodyIds":["a"],"mindIds":["b"],"heartIds":["c"]}
        """.data(using: .utf8))

        let routine = try JSONDecoder().decode(EnergyRoutine.self, from: data)
        XCTAssertEqual(routine.happeningIds, ["a", "b", "c"])
    }
    func testRepeatAdditionsHaveIndependentEntryIds() {
        let first = OptionEntry(
            id: "entry-1",
            dayKey: "2026-08-08",
            optionId: "happening_walk",
            colorHex: "#AABBCC",
            timestamp: Date(timeIntervalSince1970: 1),
            assetVariant: nil
        )
        let second = OptionEntry(
            id: "entry-2",
            dayKey: "2026-08-08",
            optionId: "happening_walk",
            colorHex: "#DDEEFF",
            timestamp: Date(timeIntervalSince1970: 2),
            assetVariant: nil
        )

        XCTAssertEqual(first.optionId, second.optionId)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testRepeatAdditionsCountSeparatelyTowardEconomy() {
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 0), 0)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 1), 10)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 2), 20)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 6), 60)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 7), 60)
    }

    func testEntryRoundTripsWithoutCategory() throws {
        let original = OptionEntry(
            id: "entry-1",
            dayKey: "2026-08-08",
            optionId: "happening_read",
            colorHex: "#AABBCC",
            timestamp: Date(timeIntervalSince1970: 123),
            assetVariant: 2
        )

        let decoded = try JSONDecoder().decode(
            OptionEntry.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }

    func testAppModelAppendsRepeatsAndRemovesOnlyOneEntry() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)

        let first = model.addHappening(
            id: "happening_walk", colorHex: "#AABBCC", at: date
        )
        let second = model.addHappening(
            id: "happening_walk", colorHex: "#DDEEFF", at: date.addingTimeInterval(1)
        )

        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk", "happening_walk"])
        XCTAssertEqual(model.happeningPointsToday, 20)

        model.removeAddition(entryId: first.id)

        XCTAssertEqual(model.todayAdditions.map(\.id), [second.id])
        XCTAssertEqual(model.happeningPointsToday, 10)
    }

    func testLoadDailyEnergyStateRestoresOnlyTodaysAdditions() throws {
        let todayKey = AppModel.dayKey(for: .now)
        let entries = [
            OptionEntry(
                id: "today", dayKey: todayKey, optionId: "happening_walk",
                colorHex: "#AABBCC", timestamp: .now, assetVariant: nil
            ),
            OptionEntry(
                id: "old", dayKey: "2001-01-01", optionId: "happening_read",
                colorHex: "#DDEEFF", timestamp: .distantPast, assetVariant: nil
            )
        ]
        let defaults = UserDefaults.stepsTrader()
        defaults.set(try JSONEncoder().encode(entries), forKey: SharedKeys.todayAdditions)
        defaults.set(Date.now, forKey: SharedKeys.dailyEnergyAnchor)

        let restored = makeModel(clearAdditions: false)
        restored.loadDailyEnergyState()

        XCTAssertEqual(restored.todayAdditions.map(\.id), ["today"])
    }

    func testLoadMigratesLegacyCategorySelectionsWhenAdditionsKeyIsAbsent() {
        let defaults = UserDefaults.stepsTrader()
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        defaults.set(["body_walking"], forKey: "dailyEnergySelections_v1_body")
        defaults.set(["mind_learning"], forKey: "dailyEnergySelections_v1_mind")
        defaults.set(["heart_joy"], forKey: "dailyEnergySelections_v1_heart")
        defaults.set(Date.now, forKey: SharedKeys.dailyEnergyAnchor)

        let model = makeModel(clearAdditions: false)
        model.loadDailyEnergyState()

        XCTAssertEqual(
            model.todayAdditions.map(\.optionId),
            ["body_walking", "mind_learning", "heart_joy"]
        )
        XCTAssertNotNil(defaults.data(forKey: SharedKeys.todayAdditions))
    }

    private func makeModel(clearAdditions: Bool = true) -> AppModel {
        let defaults = UserDefaults.stepsTrader()
        if clearAdditions {
            defaults.removeObject(forKey: SharedKeys.todayAdditions)
        }
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
        return AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore(defaults: defaults)
        )
    }
}
