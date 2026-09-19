import XCTest
@testable import Nowhere

/// The happening catalog's persistence: seeding, use counts, user-created
/// happenings, and the orphan reconstitution that keeps past days labelled
/// after 31 built-ins are cut to 10.
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
        store.recordUse(id: "happening_walk", at: Date(timeIntervalSince1970: 100))

        // Simulate a catalog written by an older build that lacked one built-in.
        let trimmed = store.all.filter { $0.id != "happening_laughed" }
        XCTAssertEqual(trimmed.count, HappeningDefaults.builtIns.count - 1)
        defaults.set(try JSONEncoder().encode(trimmed), forKey: SharedKeys.happeningCatalog)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.all.count, HappeningDefaults.builtIns.count)
        XCTAssertNotNil(reloaded.happening(id: "happening_laughed"))
        XCTAssertEqual(
            reloaded.happening(id: "happening_walk")?.useCount, 1,
            "Existing counts must survive a built-in top-up"
        )
    }

    func testUpgradeFromTenExpandsCatalogAndKeepsCustomNamesAndUseHistory() throws {
        var old = Array(HappeningDefaults.builtIns.prefix(10))
        old[0].useCount = 7
        old[0].lastUsedAt = Date(timeIntervalSince1970: 1234)
        old.append(Happening(id: "user_existing", title: "Coffee with my sister", isBuiltIn: false, useCount: 3))
        defaults.set(try JSONEncoder().encode(old), forKey: SharedKeys.happeningCatalog)
        let upgraded = makeStore()
        XCTAssertEqual(upgraded.all.count, HappeningDefaults.builtIns.count + 1)
        XCTAssertEqual(Set(upgraded.all.filter(\.isBuiltIn).map(\.id)), HappeningDefaults.builtInIds)
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
        store.recordUse(id: "happening_walk", at: when)

        let walk = store.happening(id: "happening_walk")
        XCTAssertEqual(walk?.useCount, 1)
        XCTAssertEqual(walk?.lastUsedAt, when)
    }

    func testRepeatUsesAccumulate() {
        let store = makeStore()
        store.recordUse(id: "happening_read", at: Date(timeIntervalSince1970: 100))
        store.recordUse(id: "happening_read", at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(store.happening(id: "happening_read")?.useCount, 2)
        XCTAssertEqual(
            store.happening(id: "happening_read")?.lastUsedAt,
            Date(timeIntervalSince1970: 200)
        )
    }

    func testRecordUsePersistsAcrossInstances() {
        makeStore().recordUse(id: "happening_read", at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(makeStore().happening(id: "happening_read")?.useCount, 1)
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

    func testCreateLimitsTitleToFifteenCharacters() {
        let made = makeStore().create(title: "1234567890123456", at: .now)

        XCTAssertEqual(made.title, "123456789012345")
    }

    func testCreateCountsAnEmojiSequenceAsOneCharacter() {
        let made = makeStore().create(title: "12345678901234👨‍👩‍👧‍👦Z", at: .now)

        XCTAssertEqual(made.title, "12345678901234👨‍👩‍👧‍👦")
        XCTAssertEqual(made.title.count, 15)
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

    func testCreateAllowsDuplicateTitles() {
        let store = makeStore()
        let first = store.create(title: "Sauna", at: .now)
        let second = store.create(title: "Sauna", at: .now)

        XCTAssertNotEqual(first.id, second.id, "Two happenings, not one merged")
        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count + 2)
    }

    // MARK: - Orphan reconstitution

    /// Cutting 31 built-ins to 10 would otherwise orphan ids sitting in a
    /// user's saved days, and those days would lose their labels.
    func testReconstitutesOrphanedHistoryIds() {
        let store = makeStore()
        store.reconstituteOrphans(
            fromHistoryIds: ["body_walking", "heart_joy", "happening_walk"],
            titleResolver: { $0 == "body_walking" ? "Walking" : "Joy" }
        )

        XCTAssertEqual(store.all.count, HappeningDefaults.builtIns.count + 2, "Two orphans; happening_walk already present")

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
        store.reconstituteOrphans(fromHistoryIds: ["happening_walk"], titleResolver: { $0 })
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
        XCTAssertTrue(Set(FrequentHappeningSelection.healthCoreIDs + [running.id]).isSubset(of: Set(ids)))
        XCTAssertEqual(ids.filter { HappeningPaletteSelection.choiceID($0) == "happening_walk" }.count, 1)
    }

    func testOnlyOneEstablishedFrequentChoiceEntersOnNextDayAndRetainsOtherPositions() {
        var catalog = HappeningDefaults.builtIns
        let initial = FrequentHappeningSelection.resolve(catalog: catalog, previous: [], healthIDs: [], protectedIDs: [], allowsPromotion: true)
        for id in ["happening_danced", "happening_cooked"] {
            let index = catalog.firstIndex { $0.id == id }!
            catalog[index].useCount = 5
        }
        let sameDay = FrequentHappeningSelection.resolve(catalog: catalog, previous: initial, healthIDs: [], protectedIDs: [], allowsPromotion: false)
        XCTAssertEqual(sameDay, initial)
        let nextDay = FrequentHappeningSelection.resolve(catalog: catalog, previous: initial, healthIDs: [], protectedIDs: [], allowsPromotion: true)
        XCTAssertEqual(zip(initial, nextDay).filter { $0 != $1 }.count, 1)
        XCTAssertTrue(Set(FrequentHappeningSelection.healthCoreIDs).isSubset(of: Set(nextDay)))
    }

    func testDailySelectionSurvivesRelaunchAndPromotesAtMostOncePerDay() {
        let name = "FrequentHappeningStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var catalog = HappeningDefaults.builtIns
        let store = FrequentHappeningStore(defaults: defaults)
        let initial = store.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-15")
        catalog[catalog.firstIndex { $0.id == "happening_danced" }!].useCount = 5
        let relaunched = FrequentHappeningStore(defaults: defaults)
        XCTAssertEqual(relaunched.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-15"), initial)
        let nextDay = relaunched.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-16")
        XCTAssertTrue(nextDay.contains("happening_danced"))
        catalog[catalog.firstIndex { $0.id == "happening_cooked" }!].useCount = 10
        XCTAssertEqual(relaunched.resolve(catalog: catalog, healthIDs: [], protectedIDs: [], dayKey: "2026-09-16"), nextDay)
    }

    func testNewDetectedHealthActivityCanEnterTodayWithoutMovingExistingHealthSlots() {
        let initial = FrequentHappeningSelection.resolve(catalog: HappeningDefaults.builtIns, previous: [], healthIDs: [], protectedIDs: [], allowsPromotion: true)
        let running = Happening(id: "health_workout_37", title: "Running", isBuiltIn: false)
        let next = FrequentHappeningSelection.resolve(catalog: HappeningDefaults.builtIns + [running], previous: initial,
            healthIDs: [running.id], protectedIDs: [initial.last!], allowsPromotion: false)
        XCTAssertTrue(next.contains(running.id))
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
