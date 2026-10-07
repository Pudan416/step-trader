import XCTest
@testable import Nowhere

@MainActor
final class HappeningAdditionsTests: XCTestCase {

    /// The legacy selection keys are written by several cases here and read by
    /// the migration path, so they have to be cleared around every one of them.
    private static let legacyKeys = [
        "dailyEnergySelections_v1_body",
        "dailyEnergySelections_v1_mind",
        "dailyEnergySelections_v1_heart",
    ]

    /// Test-owned storage directory. Without it the model reads the running
    /// app's saved history: `reconstituteHappeningsFromHistory()` turns every
    /// happening id ever recorded on the device into a custom happening, so
    /// catalog counts here depended on what the simulator was carrying.
    private var storageDirectory: URL!
    private var originalCanvas: DayCanvas?
    private var fixtureDayKey: String!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HappeningAdditionsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        // An empty snapshot file, not a missing one: `loadPastDaySnapshots()`
        // falls back to the App Group key when the file is absent — and deletes
        // that key after migrating it, which would destroy real history.
        try? Data("{}".utf8).write(to: storageDirectory.appending(path: "pastDaySnapshots.json"))
        PersistenceManager.storageDirectoryOverride = storageDirectory
        clearLegacyKeys()
        // Loading energy also recovers today's Canvas independently of the history override.
        fixtureDayKey = AppModel.dayKey(for: .now)
        originalCanvas = CanvasStorageService.shared.loadCanvas(for: fixtureDayKey)
        CanvasStorageService.shared.saveCanvas(DayCanvas(dayKey: fixtureDayKey))
    }

    override func tearDown() {
        clearLegacyKeys()
        if let originalCanvas {
            CanvasStorageService.shared.saveCanvas(originalCanvas)
        } else {
            CanvasStorageService.shared.deleteCanvas(for: fixtureDayKey)
        }
        originalCanvas = nil
        fixtureDayKey = nil
        PersistenceManager.storageDirectoryOverride = nil
        try? FileManager.default.removeItem(at: storageDirectory)
        storageDirectory = nil
        super.tearDown()
    }

    private func clearLegacyKeys() {
        let defaults = UserDefaults.nowhere()
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
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 1), 6)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 2), 12)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 9), 54)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 10), 60)
        XCTAssertEqual(HappeningEconomy.points(forAdditionCount: 11), 60)
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

    func testDuplicateCanonicalHappeningIsRejectedWithinCustomDay() {
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
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["event_walk"])
        XCTAssertEqual(model.happeningStore.happening(id: "happening_walk")?.useCount, 1)
        XCTAssertEqual(model.happeningPointsToday, 6)

        XCTAssertNotNil(model.addHappening(id: "happening_read", colorHex: "#DDEEFF", at: date))
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["event_walk", "event_book"])
    }

    func testRestedCannotBeAddedAgainAfterLegacyRestingOnTheSameDay() {
        let model = makeModel()
        model.loadDailyEnergyState()
        let now = Date.now
        model.todayAdditions = [OptionEntry(
            id: "legacy-rest", dayKey: AppModel.dayKey(for: now), optionId: "body_resting",
            colorHex: "#AABBCC", timestamp: now, assetVariant: nil
        )]
        let restedID = "event_root_chilled"
        XCTAssertFalse(model.canAddHappening(id: restedID, on: now))
        XCTAssertFalse(model.availablePaletteHappenings(on: now).contains { $0.id == restedID })
        XCTAssertTrue(model.canAddHappening(id: restedID, on: now.addingTimeInterval(86_400)))
        XCTAssertNil(model.addHappening(id: restedID, colorHex: "#DDEEFF", at: now, syncToCloud: false))
        XCTAssertEqual(model.todayAdditions.map(\.id), ["legacy-rest"])
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["body_resting"])
        XCTAssertEqual(model.happeningPointsToday, 6)
    }

    func testRemovingAdditionMakesHappeningAvailableAgain() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        _ = model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date)

        model.removeAddition(entryId: model.todayAdditions[0].id)

        XCTAssertTrue(model.availablePaletteHappenings(on: date).contains { $0.id == "event_walk" })
        XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#DDEEFF", at: date))
        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["event_walk"])
    }

    func testRemoveAndReAddOnSameDayRecordsOneUse() throws {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        let before = try XCTUnwrap(model.happeningStore.happening(id: "happening_walk")?.useCount)
        let first = try XCTUnwrap(
            model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date)
        )
        model.removeAddition(entryId: first.id)

        XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date))
        XCTAssertEqual(model.happeningStore.happening(id: "happening_walk")?.useCount, before + 1)
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

    func testLegacyCreationApiCannotAddOutsideTheFixedCatalog() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        let happening = model.createHappening(title: "Sauna", at: date)

        XCTAssertEqual(happening.useCount, 0)
        XCTAssertNil(happening.lastUsedAt)
        XCTAssertNil(model.addHappening(id: happening.id, colorHex: "#AABBCC", at: date))
        XCTAssertEqual(model.todayAdditions.count, 0)
        XCTAssertEqual(model.paletteHappeningCatalog().count, 100)
    }

    func testLegacyPaletteCreationApiRejectsCustomChoicesWithoutChangingSelection() throws {
        let model = makeModel()
        model.loadDailyEnergyState()
        let selected = model.selectedPaletteHappeningIDs()
        let catalogCount = model.paletteHappeningCatalog().count
        var synced = false
        XCTAssertThrowsError(try model.createPaletteHappening(
            title: "Coffee", selection: selected, replacingID: selected[6],
            syncCustomHappenings: { _ in synced = true }
        )) {
            XCTAssertEqual($0 as? HappeningPaletteSelectionError, .customCreationUnavailable)
        }
        XCTAssertFalse(synced)
        XCTAssertEqual(model.selectedPaletteHappeningIDs(), selected)
        XCTAssertEqual(model.paletteHappeningCatalog().count, catalogCount)
        XCTAssertTrue(model.todayAdditions.isEmpty)
    }

    func testInvalidExplicitCreationDoesNotCreateOrPersistAnything() throws {
        let model = makeModel()
        model.loadDailyEnergyState()
        let selected = model.selectedPaletteHappeningIDs()
        let count = model.paletteHappeningCatalog().count
        for target in [selected[0], "missing"] {
            XCTAssertThrowsError(try model.createPaletteHappening(
                title: "Tea", protectedIDs: [selected[0]], selection: selected,
                replacingID: target, syncCustomHappenings: { _ in XCTFail("Rejected creation must not sync") }
            ))
        }
        XCTAssertThrowsError(try model.createPaletteHappening(
            title: "Tea", selection: Array(selected.dropLast()), replacingID: selected[1],
            syncCustomHappenings: { _ in XCTFail("Rejected creation must not sync") }
        ))
        XCTAssertEqual(model.selectedPaletteHappeningIDs(), selected)
        XCTAssertEqual(model.paletteHappeningCatalog().count, count)
    }

    func testPaletteCreationReportsNoReplaceableSlotWhenEverySelectedHappeningIsOnCanvas() throws {
        let model = makeModel()
        model.loadDailyEnergyState()
        let selected = model.selectedPaletteHappeningIDs()
        let catalogCount = model.paletteHappeningCatalog().count

        XCTAssertThrowsError(
            try model.createPaletteHappening(
                title: "Sauna",
                protectedIDs: Set(selected)
            )
        ) {
            XCTAssertEqual($0 as? HappeningPaletteSelectionError, .customCreationUnavailable)
        }
        XCTAssertEqual(model.selectedPaletteHappeningIDs(), selected)
        XCTAssertEqual(model.paletteHappeningCatalog().count, catalogCount)
    }

    func testSavingPaletteSelectionUsesOnlyFixedCatalogChoices() throws {
        let model = makeModel()
        model.loadDailyEnergyState()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        var selectedIDs = model.configuredPaletteHappenings().map(\.id)
        XCTAssertNotNil(
            model.addHappening(
                id: selectedIDs[0],
                colorHex: "#AABBCC",
                at: date
            )
        )

        try model.savePaletteHappeningSelection(selectedIDs)

        XCTAssertEqual(model.paletteHappeningCatalog().count, HappeningDefaults.builtIns.count)
        XCTAssertEqual(model.selectedPaletteHappeningIDs(), selectedIDs)
        XCTAssertFalse(
            model.availablePaletteHappenings(on: date).contains { $0.id == selectedIDs[0] }
        )
        XCTAssertFalse(model.paletteHappeningCatalog().contains { !$0.id.hasPrefix("event_") })
    }

    func testConfiguredPaletteHappeningsUsesPersistedSelection() {
        let defaults = UserDefaults.nowhere()
        let configuredIDs = Array(HappeningDefaults.builtIns.prefix(10).map(\.id).reversed())
        defaults.set(configuredIDs, forKey: SharedKeys.happeningPaletteSelection)
        let model = makeModel()

        model.loadDailyEnergyState()

        XCTAssertEqual(model.configuredPaletteHappenings().map(\.id), configuredIDs)
    }

    func testMigratedWalkRecognizesTodaysImportedAdditionWithoutRewritingIt() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        for id in ["body_walking", "health_workout_52"] {
            model.todayAdditions = [OptionEntry(
                id: "old-entry", dayKey: AppModel.dayKey(for: date), optionId: id,
                colorHex: "#AABBCC", timestamp: date, assetVariant: nil
            )]
            XCTAssertFalse(model.canAddHappening(id: "happening_walk", on: date))
            XCTAssertFalse(model.availablePaletteHappenings(on: date).contains { $0.id == "event_walk" })
            XCTAssertTrue(model.canAddHappening(id: "happening_walk", on: date.addingTimeInterval(86_400)))
            XCTAssertEqual(model.todayAdditions.first?.optionId, id)
        }
    }

    func testAvailablePaletteHappeningsExcludesOnlyCurrentCustomDayAdditions() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()

        XCTAssertEqual(
            model.configuredPaletteHappenings().map(\.id),
            HappeningDefaults.builtIns.prefix(10).map(\.id)
        )
        XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date))
        XCTAssertFalse(model.availablePaletteHappenings(on: date).contains { $0.id == "event_walk" })
        XCTAssertTrue(
            model.availablePaletteHappenings(on: date.addingTimeInterval(24 * 60 * 60))
                .contains { $0.id == "event_walk" }
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
        let defaults = UserDefaults.nowhere()
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
        let defaults = UserDefaults.nowhere()
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
        let defaults = UserDefaults.nowhere()
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
        let defaults = UserDefaults.nowhere()
        if clearAdditions {
            defaults.removeObject(forKey: SharedKeys.todayAdditions)
        }
        return AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore()
        )
    }
}
