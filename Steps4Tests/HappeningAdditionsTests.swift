import XCTest
@testable import Steps4

@MainActor
final class HappeningAdditionsTests: XCTestCase {

    /// The legacy selection keys are written by several cases here and read by
    /// the migration path, so they have to be cleared around every one of them.
    private static let legacyKeys = [
        "dailyEnergySelections_v1_body",
        "dailyEnergySelections_v1_mind",
        "dailyEnergySelections_v1_heart",
    ]

    override func setUp() {
        super.setUp()
        clearLegacyKeys()
    }

    override func tearDown() {
        clearLegacyKeys()
        super.tearDown()
    }

    private func clearLegacyKeys() {
        let defaults = UserDefaults.stepsTrader()
        Self.legacyKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        defaults.removeObject(forKey: SharedKeys.happeningCatalog)
        defaults.removeObject(forKey: SharedKeys.happeningPaletteSelection)
    }

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

    func testDuplicateHappeningIsRejectedWithinCustomDay() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()

        let first = model.addHappening(
            id: "happening_walk", colorHex: "#AABBCC", at: date
        )
        let second = model.addHappening(
            id: "happening_walk", colorHex: "#DDEEFF", at: date.addingTimeInterval(1)
        )

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk"])
        XCTAssertEqual(model.happeningStore.happening(id: "happening_walk")?.useCount, 1)
        XCTAssertEqual(model.happeningPointsToday, 10)

        XCTAssertNotNil(model.addHappening(id: "happening_read", colorHex: "#DDEEFF", at: date))
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk", "happening_read"])
    }

    func testRemovingAdditionMakesHappeningAvailableAgain() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        _ = model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date)

        model.removeAddition(entryId: model.todayAdditions[0].id)

        XCTAssertTrue(model.availablePaletteHappenings(on: date).contains { $0.id == "happening_walk" })
        XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#DDEEFF", at: date))
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk"])
    }

    func testHappeningCanBeAddedAgainOnNewCustomDay() {
        let model = makeModel()
        let firstDate = Date(timeIntervalSince1970: 1_786_176_000)
        let nextDay = firstDate.addingTimeInterval(24 * 60 * 60)

        XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: firstDate))
        XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#DDEEFF", at: nextDay))
        XCTAssertEqual(model.todayAdditions.map(\.dayKey), [
            AppModel.dayKey(for: firstDate),
            AppModel.dayKey(for: nextDay),
        ])
    }

    func testCreateIsCatalogOnlyUntilSuccessfulAdditionRecordsUse() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        let happening = model.createHappening(title: "Sauna", at: date)

        XCTAssertEqual(happening.useCount, 0)
        XCTAssertNil(happening.lastUsedAt)

        _ = model.addHappening(id: happening.id, colorHex: "#AABBCC", at: date)
        XCTAssertEqual(model.happeningStore.happening(id: happening.id)?.useCount, 1)
        XCTAssertEqual(model.happeningStore.happening(id: happening.id)?.lastUsedAt, date)
    }

    func testPaletteOrderUsesPersistedConfiguredSelection() {
        let defaults = UserDefaults.stepsTrader()
        let configuredIDs = Array(HappeningDefaults.builtIns.map(\.id).reversed())
        defaults.set(configuredIDs, forKey: SharedKeys.happeningPaletteSelection)
        let model = makeModel()

        model.loadDailyEnergyState()

        XCTAssertEqual(model.paletteOrder().map(\.id), configuredIDs)
    }

    func testAvailablePaletteHappeningsExcludesOnlyCurrentCustomDayAdditions() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()

        XCTAssertEqual(
            model.configuredPaletteHappenings().map(\.id),
            HappeningDefaults.builtIns.map(\.id)
        )
        XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date))
        XCTAssertFalse(model.availablePaletteHappenings(on: date).contains { $0.id == "happening_walk" })
        XCTAssertTrue(
            model.availablePaletteHappenings(on: date.addingTimeInterval(24 * 60 * 60))
                .contains { $0.id == "happening_walk" }
        )
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

    /// The old build persisted selections as JSON-encoded Data, not as a native
    /// array — its `saveStringArray` went through `JSONEncoder`. Writing them
    /// the native way here would make this test pass while the production path
    /// silently read nothing, which is exactly the failure mode this migration
    /// exists to prevent.
    func testLoadMigratesLegacyCategorySelectionsWhenAdditionsKeyIsAbsent() throws {
        let defaults = UserDefaults.stepsTrader()
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        try setLegacySelections(["body_walking"], category: "body", in: defaults)
        try setLegacySelections(["mind_learning"], category: "mind", in: defaults)
        try setLegacySelections(["heart_joy"], category: "heart", in: defaults)
        defaults.set(Date.now, forKey: SharedKeys.dailyEnergyAnchor)

        let model = makeModel(clearAdditions: false)
        model.loadDailyEnergyState()

        XCTAssertEqual(
            model.todayAdditions.map(\.optionId),
            ["body_walking", "mind_learning", "heart_joy"]
        )
        XCTAssertEqual(model.happeningStore.happening(id: "body_walking")?.title, "Walking")
        XCTAssertFalse(model.happeningStore.happening(id: "body_walking")?.isBuiltIn ?? true)
        XCTAssertNotNil(defaults.data(forKey: SharedKeys.todayAdditions))
    }

    /// Some values may have been written as a native array by other code paths.
    /// Tolerated, so neither shape is lost.
    func testLoadMigratesLegacySelectionsStoredAsNativeArray() {
        let defaults = UserDefaults.stepsTrader()
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        defaults.set(["body_walking"], forKey: "dailyEnergySelections_v1_body")
        defaults.set(Date.now, forKey: SharedKeys.dailyEnergyAnchor)

        let model = makeModel(clearAdditions: false)
        model.loadDailyEnergyState()

        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["body_walking"])
    }

    /// Exactly how the pre-migration build wrote them.
    private func setLegacySelections(
        _ ids: [String], category: String, in defaults: UserDefaults
    ) throws {
        defaults.set(
            try JSONEncoder().encode(ids),
            forKey: "dailyEnergySelections_v1_\(category)"
        )
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
