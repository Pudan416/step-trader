import XCTest
@testable import Nowhere

/// Fixed choices and backward-compatible storage for archived/custom records.
final class HappeningStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HappeningStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> HappeningStore {
        let store = HappeningStore(defaults: defaults)
        store.load()
        return store
    }

    // MARK: - Seeding

    func testSeedsBuiltInsOnFirstLoad() {
        let store = makeStore()
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count)
        XCTAssertEqual(Set(store.all.map(\.id)), HappeningDefaults.builtInIds)
    }

    func testLoadIsIdempotent() {
        let store = makeStore()
        store.load()
        store.load()
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count)
    }

    func testLoadAddsNewBuiltInsWithoutResettingCounts() throws {
        let store = makeStore()
        store.recordUse(id: "event_walk", at: Date(timeIntervalSince1970: 100))

        // Simulate a catalog written by an older build that lacked one built-in.
        let trimmed = store.all.filter { $0.id != "event_happy" }
        XCTAssertEqual(trimmed.count, HappeningDefaults.builtIns.count - 1)
        defaults.set(try JSONEncoder().encode(trimmed), forKey: SharedKeys.happeningCatalog)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.all.count, HappeningDefaults.builtIns.count)
        XCTAssertNotNil(reloaded.happening(id: "event_happy"))
        XCTAssertEqual(
            reloaded.happening(id: "event_walk")?.useCount, 1,
            "Existing counts must survive a built-in top-up"
        )
    }

    func testUpgradeFromTenExpandsCatalogAndKeepsCustomNamesAndUseHistory() throws {
        var old = Array(HappeningDefaults.legacyBuiltIns.prefix(10))
        old[0].useCount = 7
        old[0].lastUsedAt = Date(timeIntervalSince1970: 1234)
        old.append(Happening(id: "user_existing", title: "Coffee with my sister", isBuiltIn: false, useCount: 3))
        defaults.set(try JSONEncoder().encode(old), forKey: SharedKeys.happeningCatalog)
        let upgraded = makeStore()
        XCTAssertEqual(upgraded.all.count, HappeningDefaults.builtIns.count + old.count)
        XCTAssertEqual(Set(upgraded.selectable.map(\.id)), HappeningDefaults.builtInIds)
        XCTAssertEqual(upgraded.selectable.count, 100)
        XCTAssertEqual(upgraded.selectable.first { $0.id == "event_walk" }?.useCount, 7)
        XCTAssertEqual(upgraded.happening(id: "happening_walk"), old[0])
        XCTAssertEqual(upgraded.happening(id: "user_existing"), old.last)
        XCTAssertEqual(makeStore().all, upgraded.all)
    }

    func testCorruptCatalogFallsBackToBuiltIns() {
        defaults.set(Data("not json".utf8), forKey: SharedKeys.happeningCatalog)
        let store = makeStore()
        XCTAssertEqual(Set(store.all.map(\.id)), HappeningDefaults.builtInIds)
    }

    // MARK: - Use tracking

    func testRecordUseIncrementsAndStamps() {
        let store = makeStore()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordUse(id: "event_walk", at: when)

        let walk = store.happening(id: "event_walk")
        XCTAssertEqual(walk?.useCount, 1)
        XCTAssertEqual(walk?.lastUsedAt, when)
    }

    func testRepeatUsesAccumulate() {
        let store = makeStore()
        store.recordUse(id: "event_book", at: Date(timeIntervalSince1970: 100))
        store.recordUse(id: "event_book", at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(store.happening(id: "event_book")?.useCount, 2)
        XCTAssertEqual(
            store.happening(id: "event_book")?.lastUsedAt,
            Date(timeIntervalSince1970: 200)
        )
    }

    func testRecordUsePersistsAcrossInstances() {
        makeStore().recordUse(id: "event_book", at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(makeStore().happening(id: "event_book")?.useCount, 1)
    }

    func testRecordUseForUnknownIdIsIgnored() {
        let store = makeStore()
        store.recordUse(id: "nope_does_not_exist", at: .now)
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count)
        XCTAssertNil(store.happening(id: "nope_does_not_exist"))
    }

    // MARK: - User-created happenings

    func testCreateMakesAnUnusedUserHappening() {
        let store = makeStore()
        let when = Date(timeIntervalSince1970: 500)
        let made = store.create(title: "Rooftop coffee", at: when)

        XCTAssertFalse(made.isBuiltIn)
        XCTAssertEqual(made.useCount, 0, "Creating a happening only adds it to the catalog")
        XCTAssertNil(made.lastUsedAt)
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count + 1)
        XCTAssertEqual(store.happening(id: made.id)?.title, "Rooftop coffee")
    }

    func testCreateTrimsWhitespace() {
        XCTAssertEqual(makeStore().create(title: "  Sauna \n", at: .now).title, "Sauna")
    }

    func testLegacyCreateLimitsNewTitleToTwentyCharacters() {
        let made = makeStore().create(title: "123456789012345678901", at: .now)

        XCTAssertEqual(made.title, "12345678901234567890")
    }

    func testCreateCountsAnEmojiSequenceAsOneCharacter() {
        let made = makeStore().create(title: "1234567890123456789👨‍👩‍👧‍👦Z", at: .now)

        XCTAssertEqual(made.title, "1234567890123456789👨‍👩‍👧‍👦")
        XCTAssertEqual(made.title.count, 20)
    }

    func testCreatePersists() {
        let made = makeStore().create(title: "Sauna", at: .now)
        XCTAssertEqual(makeStore().happening(id: made.id)?.title, "Sauna")
    }

    func testCustomHappeningSyncRowRoundTripsTitle() throws {
        let happening = Happening(
            id: "user_123", title: "Sauna", isBuiltIn: false,
            useCount: 4, lastUsedAt: Date(timeIntervalSince1970: 500)
        )

        let row = CustomHappeningRow(happening: happening, userId: "user-id")
        let data = try JSONEncoder().encode(row)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json["last_used_at"] is String, "PostgREST timestamptz must be ISO-8601 text")
        let decoded = try JSONDecoder().decode(
            CustomHappeningRow.self,
            from: data
        )

        XCTAssertEqual(decoded.happening.title, "Sauna")
        XCTAssertEqual(decoded.happening.useCount, 4)
        XCTAssertEqual(decoded.happening.lastUsedAt, Date(timeIntervalSince1970: 500))
    }

    func testHistoricalCustomNamesStayIntactAndSystemOrphansAreNotUploaded() {
        let custom = Happening(id: "user_saved", title: "Coffee with my little sister", isBuiltIn: false, useCount: 7)
        let system = ["event_ate", "happening_walk", "body_walking", "mind_writing", "heart_joy", "health_workout_37"]
            .map { Happening(id: $0, title: $0, isBuiltIn: false) }
        XCTAssertEqual(HappeningDefaults.customHappeningsForSync(system + [custom]), [custom])
        let store = makeStore()
        store.mergeRestored([custom] + system)
        XCTAssertEqual(store.happening(id: custom.id), custom)
        XCTAssertEqual(store.selectable.count, 100)
        XCTAssertFalse(store.selectable.contains { $0.id == custom.id })
        XCTAssertEqual(makeStore().happening(id: custom.id), custom)
    }

    func testLegacyRetryExcludesSharedIDsAndPreservesCustomFieldsAndOwner() throws {
        let rows: [[String: Any]] = [
            ["id": "body_walking", "user_id": "owner", "title_en": "Walking"],
            ["id": "user_saved", "user_id": "owner", "title_en": "Coffee with my little sister", "title_ru": "Saved", "use_count": 7]
        ]
        let data = try JSONSerialization.data(withJSONObject: rows)
        guard case .ready(let filtered) = CustomHappeningRetryPayload.prepare(data, ownerID: "owner") else {
            return XCTFail("A genuine row must survive a legacy mixed retry")
        }
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: filtered) as? [[String: Any]])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0]["title_en"] as? String, rows[1]["title_en"] as? String)
        XCTAssertEqual(result[0]["title_ru"] as? String, "Saved")
        XCTAssertEqual(result[0]["use_count"] as? Int, 7)
        XCTAssertEqual(CustomHappeningRetryPayload.prepare(data, ownerID: "another-owner"), .differentOwner)
        XCTAssertEqual(CustomHappeningRetryPayload.prepare(try JSONSerialization.data(withJSONObject: [rows[0]]), ownerID: "owner"), .noUserRows)
    }

    func testLegacyEntriesKeepIdentityMetadataAndFractionalTime() throws {
        let data = Data(##"{"user_id":"owner","day_key":"2026-01-02","option_id":"body_walking","color_hex":"#123456","asset_variant":3,"created_at":"2026-01-02T12:34:56.123Z"}"##.utf8)
        let row = try JSONDecoder().decode(LegacyHappeningEntryRow.self, from: data)
        XCTAssertEqual(row.entry.optionId, "body_walking")
        XCTAssertEqual(row.entry.colorHex, "#123456")
        XCTAssertEqual(row.entry.assetVariant, 3)
        XCTAssertEqual(row.entry.timestamp, HappeningServerTimestamp.date("2026-01-02T12:34:56.123Z"))
        XCTAssertEqual(row.entry.id, try JSONDecoder().decode(LegacyHappeningEntryRow.self, from: data).entry.id)
        XCTAssertNotNil(UUID(uuidString: row.entry.id))
        XCTAssertNotEqual(row.entry.id, LegacyHappeningEntryIdentity.id(userID: "other", dayKey: row.dayKey, optionID: row.optionID))
    }

    func testRestoreRequiresAllHistoryReadsAndAcceptsAnEmptyAccount() {
        XCTAssertNotNil(HappeningHistoryRestorePayload(happenings: [], additions: [], snapshots: [:], routines: []))
        XCTAssertNil(HappeningHistoryRestorePayload(happenings: nil, additions: [], snapshots: [:], routines: []))
        XCTAssertNil(HappeningHistoryRestorePayload(happenings: [], additions: nil, snapshots: [:], routines: []))
        XCTAssertNil(HappeningHistoryRestorePayload(happenings: [], additions: [], snapshots: nil, routines: []))
        XCTAssertNil(HappeningHistoryRestorePayload(happenings: [], additions: [], snapshots: [:], routines: nil))
    }

    func testRestoreMergesLiveEditsAndDoesNotResurrectRemovals() {
        let id = UUID().uuidString
        let deletedID = UUID().uuidString
        let server = OptionEntry(id: id.lowercased(), dayKey: "2026-01-02", optionId: "happening_walk", colorHex: "#123456", timestamp: .distantPast)
        var edited = server
        edited.colorHex = "#654321"
        let deleted = OptionEntry(id: deletedID, dayKey: server.dayKey, optionId: "event_workout", colorHex: "#777777", timestamp: .distantPast)
        let added = OptionEntry(id: UUID().uuidString, dayKey: server.dayKey, optionId: "event_chilled", colorHex: "#111111", timestamp: .now)
        let merged = HappeningRestoreMerge.entries(server: [server, deleted], local: [edited, added], removedIDs: [deletedID.lowercased()])
        XCTAssertEqual(merged, [edited, added])
        XCTAssertEqual(HappeningRestoreMerge.entries(server: [server], local: [added], removedIDs: []), [server, added])
    }

    func testCreateAllowsDuplicateTitles() {
        let store = makeStore()
        let first = store.create(title: "Sauna", at: .now)
        let second = store.create(title: "Sauna", at: .now)

        XCTAssertNotEqual(first.id, second.id, "Two happenings, not one merged")
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count + 2)
    }

    // MARK: - Orphan reconstitution

    /// Retired and pre-happening identities must still resolve in saved days.
    func testReconstitutesOrphanedHistoryIds() {
        let store = makeStore()
        store.reconstituteOrphans(
            fromHistoryIds: ["body_walking", "heart_joy", "happening_walk"],
            titleResolver: { HappeningDefaults.historicalTitle(for: $0) ?? ($0 == "body_walking" ? "Walking" : "Joy") }
        )

        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count + 3, "All three historical identities remain separate")

        let walking = store.happening(id: "body_walking")
        XCTAssertEqual(walking?.title, "Walking")
        XCTAssertEqual(walking?.isBuiltIn, false)
        XCTAssertEqual(walking?.useCount, 0, "Reconstituted orphans do not fake usage")
        XCTAssertNil(walking?.lastUsedAt)
    }

    func testReconstituteIsIdempotentAndPreservesLaterUse() {
        let store = makeStore()
        store.reconstituteOrphans(fromHistoryIds: ["body_walking"], titleResolver: { _ in "Walking" })
        store.recordUse(id: "body_walking", at: Date(timeIntervalSince1970: 100))
        store.reconstituteOrphans(fromHistoryIds: ["body_walking"], titleResolver: { _ in "Walking" })

        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count + 1)
        XCTAssertEqual(
            store.happening(id: "body_walking")?.useCount, 1,
            "A second pass must not reset a reconstituted happening"
        )
    }

    func testReconstituteWithNoOrphansChangesNothing() {
        let store = makeStore()
        store.reconstituteOrphans(fromHistoryIds: ["event_walk"], titleResolver: { $0 })
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count)
    }

    func testReconstituteHandlesEmptyHistory() {
        let store = makeStore()
        store.reconstituteOrphans(fromHistoryIds: [], titleResolver: { $0 })
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count)
    }

    func testReconstitutedOrphansPersist() {
        makeStore().reconstituteOrphans(
            fromHistoryIds: ["body_walking"], titleResolver: { _ in "Walking" }
        )
        XCTAssertEqual(makeStore().happening(id: "body_walking")?.title, "Walking")
    }

    /// Reconstitution runs on every launch against the user's whole history,
    /// so its order must not depend on Set iteration order.
    func testReconstituteIsDeterministic() {
        let ids: Set<String> = ["body_walking", "heart_joy", "mind_focusing"]
        let first = { () -> [String] in
            let s = HappeningStore(defaults: UserDefaults(suiteName: "det.\(UUID().uuidString)")!)
            s.load()
            s.reconstituteOrphans(fromHistoryIds: ids, titleResolver: { $0 })
            return s.all.map(\.id).suffix(3).map { $0 }
        }
        XCTAssertEqual(first(), first())
    }
}

final class FrequentHappeningSelectionTests: XCTestCase {
    func testHealthActivitiesArePresentFromFirstOpeningWithoutDuplicateWalking() {
        let running = Happening(id: "health_workout_37", title: "Running", isBuiltIn: false)
        let catalog = HappeningDefaults.builtIns + [running, Happening(id: "health_workout_52", title: "Walking", isBuiltIn: false)]
        let ids = FrequentHappeningSelection.resolve(catalog: catalog, previous: [],
            healthIDs: [running.id, "health_workout_52"], protectedIDs: [], allowsPromotion: true)
        XCTAssertEqual(ids.count, 10)
        XCTAssertTrue(Set((FrequentHappeningSelection.healthCoreIDs + [running.id]).compactMap { HappeningDefaults.selectableHappening(id: $0)?.id }).isSubset(of: Set(ids)))
        XCTAssertEqual(ids.filter { HappeningPaletteSelection.choiceID($0) == "event_walk" }.count, 1)
    }

    func testOnlyOneEstablishedFrequentChoiceEntersOnNextDayAndRetainsOtherPositions() {
        var catalog = HappeningDefaults.builtIns
        let initial = FrequentHappeningSelection.resolve(catalog: catalog, previous: [], healthIDs: [], protectedIDs: [], allowsPromotion: true)
        for id in ["event_danced", "event_cooked"] {
            let index = catalog.firstIndex { $0.id == id }!
            catalog[index].useCount = 5
        }
        let sameDay = FrequentHappeningSelection.resolve(catalog: catalog, previous: initial, healthIDs: [], protectedIDs: [], allowsPromotion: false)
        XCTAssertEqual(sameDay, initial)
        let nextDay = FrequentHappeningSelection.resolve(catalog: catalog, previous: initial, healthIDs: [], protectedIDs: [], allowsPromotion: true)
        XCTAssertEqual(zip(initial, nextDay).filter { $0 != $1 }.count, 1)
        XCTAssertTrue(Set(FrequentHappeningSelection.healthCoreIDs.compactMap { HappeningDefaults.selectableHappening(id: $0)?.id }).isSubset(of: Set(nextDay)))
    }

    func testDailySelectionSurvivesRelaunchAndPromotesAtMostOncePerDay() {
        let name = "FrequentHappeningStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var catalog = HappeningDefaults.builtIns
        let store = FrequentHappeningStore(defaults: defaults)
        let initial = store.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-15")
        catalog[catalog.firstIndex { $0.id == "event_danced" }!].useCount = 5
        let relaunched = FrequentHappeningStore(defaults: defaults)
        XCTAssertEqual(relaunched.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-15"), initial)
        let nextDay = relaunched.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-16")
        XCTAssertTrue(nextDay.contains("event_danced"))
        catalog[catalog.firstIndex { $0.id == "event_cooked" }!].useCount = 10
        XCTAssertEqual(relaunched.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-16"), nextDay)
    }

    func testNewDetectedHealthActivityCanEnterTodayWithoutMovingExistingHealthSlots() {
        let initial = FrequentHappeningSelection.resolve(catalog: HappeningDefaults.builtIns, previous: [], healthIDs: [], protectedIDs: [], allowsPromotion: true)
        let running = Happening(id: "health_workout_37", title: "Running", isBuiltIn: false)
        let next = FrequentHappeningSelection.resolve(catalog: HappeningDefaults.builtIns + [running], previous: initial,
            healthIDs: [running.id], protectedIDs: [initial.last!], allowsPromotion: false)
        XCTAssertTrue(next.contains("event_run"))
        XCTAssertTrue(next.contains(initial.last!))
        for id in FrequentHappeningSelection.healthCoreIDs { XCTAssertEqual(initial.firstIndex(of: id), next.firstIndex(of: id)) }
    }

    func testLongAccessibleFieldFitsMetalDrawableLimitsWithoutShrinkingLabels() {
        let size = CGSize(width: 402, height: 3200)
        let scale = DayObjectsDrawableView.displayScale(for: size, nativeScale: 3)
        XCTAssertLessThanOrEqual(size.height * scale, 4096)
        XCTAssertEqual(DayObjectsDrawableView.displayScale(for: CGSize(width: 402, height: 874), nativeScale: 3), 3)
    }

    func testTodayChoicesStayReachableAndHealthOverflowNeverExceedsTen() {
        let initial = FrequentHappeningSelection.resolve(catalog: HappeningDefaults.builtIns, previous: [], healthIDs: [], protectedIDs: [], allowsPromotion: true)
        let external = (0..<20).map { Happening(id: "health_workout_\($0)", title: "Workout \($0)", isBuiltIn: false) }
        let ids = FrequentHappeningSelection.resolve(catalog: HappeningDefaults.builtIns + external,
            previous: initial, healthIDs: external.map(\.id), protectedIDs: Set(initial), allowsPromotion: true)
        XCTAssertEqual(ids, initial)
        XCTAssertEqual(ids.count, 10)
    }
}
