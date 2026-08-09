import XCTest
@testable import Steps4

final class HappeningPaletteSelectionTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HappeningPaletteSelectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeCatalog(counts: [Int]) -> [Happening] {
        counts.enumerated().map { index, count in
            Happening(
                id: "h\(index)",
                title: "Happening \(index)",
                isBuiltIn: true,
                useCount: count,
                lastUsedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }

    func testFirstLoadSeedsBuiltInsInSourceOrder() {
        let store = HappeningPaletteSelectionStore(defaults: defaults)

        store.load(catalog: HappeningDefaults.builtIns)

        XCTAssertEqual(store.ids, HappeningDefaults.builtIns.map(\.id))
        XCTAssertEqual(defaults.stringArray(forKey: SharedKeys.happeningPaletteSelection), store.ids)
    }

    func testLoadRemovesUnknownIdsAndRefillsInDefaultOrder() {
        let catalog = HappeningDefaults.builtIns + [
            Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)
        ]
        defaults.set(
            ["unknown", HappeningDefaults.builtIns[2].id],
            forKey: SharedKeys.happeningPaletteSelection
        )
        let store = HappeningPaletteSelectionStore(defaults: defaults)

        store.load(catalog: catalog)

        XCTAssertEqual(
            store.ids,
            [HappeningDefaults.builtIns[2].id]
                + HappeningDefaults.builtIns.map(\.id).filter { $0 != HappeningDefaults.builtIns[2].id }
        )
    }

    func testLoadRemovesDuplicatesBeforeRefilling() {
        let catalog = HappeningDefaults.builtIns
        let duplicatedID = catalog[3].id
        defaults.set(
            [duplicatedID, duplicatedID] + catalog.dropFirst(4).map(\.id),
            forKey: SharedKeys.happeningPaletteSelection
        )
        let store = HappeningPaletteSelectionStore(defaults: defaults)

        store.load(catalog: catalog)

        XCTAssertEqual(store.ids.count, 10)
        XCTAssertEqual(store.ids.filter { $0 == duplicatedID }.count, 1)
        XCTAssertEqual(store.ids.first, duplicatedID)
        XCTAssertEqual(Set(store.ids), Set(catalog.map(\.id)))
    }

    func testSaveRejectsAnythingOtherThanTenUniqueLiveIdsWithoutChangingState() throws {
        let catalog = HappeningDefaults.builtIns
        let store = HappeningPaletteSelectionStore(defaults: defaults)
        store.load(catalog: catalog)
        let original = store.ids

        XCTAssertThrowsError(try store.save(Array(original.dropLast()), catalog: catalog)) {
            XCTAssertEqual($0 as? HappeningPaletteSelectionError, .requiresExactlyTen)
        }
        XCTAssertThrowsError(try store.save(original.dropLast() + ["unknown"], catalog: catalog)) {
            XCTAssertEqual($0 as? HappeningPaletteSelectionError, .requiresExactlyTen)
        }
        XCTAssertThrowsError(try store.save([original[0]] + Array(original.dropLast()), catalog: catalog)) {
            XCTAssertEqual($0 as? HappeningPaletteSelectionError, .requiresExactlyTen)
        }
        XCTAssertEqual(store.ids, original)
        XCTAssertEqual(defaults.stringArray(forKey: SharedKeys.happeningPaletteSelection), original)
    }

    func testCancelledChooserDraftRestoresTheOriginalSelectionWithoutPersisting() {
        let catalog = makeCatalog(counts: Array(repeating: 0, count: 12))
        let store = HappeningPaletteSelectionStore(defaults: defaults)
        let original = Array(catalog.prefix(10).map(\.id))
        try! store.save(original, catalog: catalog)
        var draft = HappeningPaletteSelectionDraft(selected: original, catalog: catalog)

        XCTAssertEqual(draft.toggle(id: "h3"), .removed)
        XCTAssertEqual(draft.toggle(id: "h10"), .added)
        XCTAssertEqual(draft.ids, original.filter { $0 != "h3" } + ["h10"])

        draft.cancel()

        XCTAssertEqual(draft.ids, original)
        XCTAssertEqual(store.ids, original)
        XCTAssertEqual(defaults.stringArray(forKey: SharedKeys.happeningPaletteSelection), original)
    }

    func testChooserDraftPreservesSurvivingSlotOrderAndAppendsInCheckOrder() {
        let catalog = makeCatalog(counts: Array(repeating: 0, count: 13))
        let original = Array(catalog.prefix(10).map(\.id))
        var draft = HappeningPaletteSelectionDraft(selected: original, catalog: catalog)

        XCTAssertEqual(draft.toggle(id: "h1"), .removed)
        XCTAssertEqual(draft.toggle(id: "h6"), .removed)
        XCTAssertEqual(draft.toggle(id: "h12"), .added)
        XCTAssertEqual(draft.toggle(id: "h10"), .added)

        XCTAssertEqual(
            draft.ids,
            ["h0", "h2", "h3", "h4", "h5", "h7", "h8", "h9", "h12", "h10"]
        )
        XCTAssertTrue(draft.canSave)
    }

    func testChooserDraftPreventsAnEleventhUniqueSelectionAndRequiresTenLiveIdsToSave() {
        let catalog = makeCatalog(counts: Array(repeating: 0, count: 11))
        let original = Array(catalog.prefix(10).map(\.id))
        var fullDraft = HappeningPaletteSelectionDraft(selected: original, catalog: catalog)
        var incompleteDraft = HappeningPaletteSelectionDraft(
            selected: Array(original.dropLast()),
            catalog: catalog
        )

        XCTAssertEqual(fullDraft.toggle(id: "h10"), .limitReached)
        XCTAssertFalse(incompleteDraft.canSave)
        XCTAssertEqual(incompleteDraft.toggle(id: "unknown"), .unavailable)
    }

    func testPanelAccessibilityOrderPlacesChooserSearchBeforeRowsAndCreatorInputBeforeActions() {
        XCTAssertEqual(
            HappeningPanelAccessibilityOrder.chooser,
            [.heading, .status, .search, .rows, .actions]
        )
        XCTAssertEqual(
            HappeningPanelAccessibilityOrder.creator,
            [.heading, .input, .actions]
        )
    }

    func testCustomHappeningReplacesLeastUsedSlot() throws {
        let catalog = makeCatalog(counts: [5, 4, 3, 2, 1, 0, 8, 7, 6, 9])
            + [Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)]
        let store = HappeningPaletteSelectionStore(defaults: defaults)
        try store.save(Array(catalog.prefix(10).map(\.id)), catalog: catalog)

        let removed = try store.insertReplacingLeastUsed("user_sauna", catalog: catalog)

        XCTAssertEqual(removed, catalog[5].id)
        XCTAssertEqual(store.ids[5], "user_sauna")
        XCTAssertEqual(store.ids.count, 10)
    }

    func testCatalogOnlyCreationReplacesLeastUsedSlotWithoutRecordingUse() throws {
        let catalog = makeCatalog(counts: [5, 4, 3, 2, 1, 0, 8, 7, 6, 9])
            + [Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)]
        let store = HappeningPaletteSelectionStore(defaults: defaults)
        try store.save(Array(catalog.prefix(10).map(\.id)), catalog: catalog)

        _ = try store.insertReplacingLeastUsed("user_sauna", catalog: catalog)

        let created = try XCTUnwrap(catalog.first { $0.id == "user_sauna" })
        XCTAssertEqual(created.useCount, 0)
        XCTAssertNil(created.lastUsedAt)
        XCTAssertFalse(store.ids.contains("h5"))
    }

    func testReplacementTiesUseOldestLastUse() {
        let catalog = [
            Happening(id: "newer", title: "Newer", isBuiltIn: true, useCount: 0,
                      lastUsedAt: Date(timeIntervalSince1970: 200)),
            Happening(id: "older-later-slot", title: "Older later", isBuiltIn: true, useCount: 0,
                      lastUsedAt: Date(timeIntervalSince1970: 100)),
            Happening(id: "older-earlier-slot", title: "Older earlier", isBuiltIn: true, useCount: 0,
                      lastUsedAt: Date(timeIntervalSince1970: 100))
        ]

        XCTAssertEqual(
            HappeningPaletteSelection.replacementIndex(
                in: ["newer", "older-earlier-slot", "older-later-slot"],
                catalog: catalog
            ),
            1
        )
    }

    func testReplacementTiesUseCurrentSlotOrderWhenUsageAndLastUseMatch() {
        let lastUsedAt = Date(timeIntervalSince1970: 100)
        let catalog = [
            Happening(id: "later-slot", title: "Later", isBuiltIn: true, useCount: 0,
                      lastUsedAt: lastUsedAt),
            Happening(id: "earlier-slot", title: "Earlier", isBuiltIn: true, useCount: 0,
                      lastUsedAt: lastUsedAt)
        ]

        XCTAssertEqual(
            HappeningPaletteSelection.replacementIndex(
                in: ["earlier-slot", "later-slot"],
                catalog: catalog
            ),
            0
        )
    }

    func testReplacementDoesNotDeleteTheReplacedCatalogItem() throws {
        let catalog = makeCatalog(counts: [5, 4, 3, 2, 1, 0, 8, 7, 6, 9])
            + [Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)]
        let originalIDs = catalog.map(\.id)
        let store = HappeningPaletteSelectionStore(defaults: defaults)
        try store.save(Array(catalog.prefix(10).map(\.id)), catalog: catalog)

        let removed = try store.insertReplacingLeastUsed("user_sauna", catalog: catalog)

        XCTAssertEqual(catalog.map(\.id), originalIDs)
        XCTAssertTrue(catalog.contains { $0.id == removed })
    }

    func testMigratesV1FrozenOrderOnceWhenItContainsTenLiveIds() {
        let catalog = HappeningDefaults.builtIns
        let migratedIDs = catalog.map(\.id).reversed()
        defaults.set(Array(migratedIDs), forKey: "paletteOrderIds_v1")
        let first = HappeningPaletteSelectionStore(defaults: defaults)

        first.load(catalog: catalog)
        defaults.set(catalog.map(\.id), forKey: "paletteOrderIds_v1")
        let second = HappeningPaletteSelectionStore(defaults: defaults)
        second.load(catalog: catalog)

        XCTAssertEqual(first.ids, Array(migratedIDs))
        XCTAssertEqual(second.ids, Array(migratedIDs))
    }

    func testDoesNotMigrateV1FrozenOrderUnlessItContainsTenLiveIds() {
        let catalog = HappeningDefaults.builtIns
        defaults.set(Array(catalog.map(\.id).dropLast()) + ["unknown"], forKey: "paletteOrderIds_v1")
        let store = HappeningPaletteSelectionStore(defaults: defaults)

        store.load(catalog: catalog)

        XCTAssertEqual(store.ids, catalog.map(\.id))
    }
}
