import XCTest
import HealthKit
@testable import Steps4

final class HappeningPaletteSelectionTests: XCTestCase {
    // These tests cover the user's ten preferred starting choices, independent
    // of the larger catalog available by scrolling.
    private var originalBuiltIns: [Happening] { Array(HappeningDefaults.builtIns.prefix(10)) }


    func testAlternativesOfferOneWalkAcrossBuiltInHistoryAndHealthKit() {
        let catalog = [
            Happening(id: "body_walking", title: "Walking", isBuiltIn: false),
            Happening(id: "health_workout_\(HKWorkoutActivityType.walking.rawValue)", title: "Walking", isBuiltIn: false),
            Happening(id: "happening_walk", title: "Walk", isBuiltIn: true),
            Happening(id: "happening_outside", title: "Time outside", isBuiltIn: true),
            Happening(id: "user_walk", title: "Walk", isBuiltIn: false)
        ]

        XCTAssertEqual(
            HappeningPaletteSelection.alternatives(catalog: catalog, selected: []).map(\.id),
            ["happening_walk", "happening_outside", "user_walk"]
        )
        for selected in ["happening_walk", "body_walking", "health_workout_52"] {
            XCTAssertEqual(
                HappeningPaletteSelection.alternatives(catalog: catalog, selected: [selected]).map(\.id),
                ["happening_outside", "user_walk"],
                "A selected walk must not be offered again under an imported ID"
            )
        }
    }

    func testAlternativeSearchFindsTheCanonicalWalkUsingItsImportedTitle() {
        let catalog = [
            Happening(id: "body_walking", title: "Walking", isBuiltIn: false),
            Happening(id: "happening_walk", title: "Walk", isBuiltIn: true)
        ]
        XCTAssertEqual(
            HappeningPaletteSelection.alternatives(catalog: catalog, selected: [], query: "  WALKING  ").map(\.id),
            ["happening_walk"]
        )
        XCTAssertTrue(HappeningPaletteSelection.alternatives(catalog: catalog, selected: [], query: "absent").isEmpty)
    }

    func testAlternativesKeepCustomDuplicatesAndDifferentWorkoutTypes() {
        let catalog = [
            Happening(id: "user_a", title: "Walk", isBuiltIn: false),
            Happening(id: "user_b", title: "Walk", isBuiltIn: false),
            Happening(id: "health_workout_20", title: "Strength Training", isBuiltIn: false),
            Happening(id: "health_workout_50", title: "Strength Training", isBuiltIn: false)
        ]
        XCTAssertEqual(HappeningPaletteSelection.alternatives(catalog: catalog, selected: []), catalog)
    }

    func testSavedAndLegacyWalkingDuplicatesBecomeOneWalkAndStayRepairedAfterReload() {
        let catalog = originalBuiltIns + [
            Happening(id: "body_walking", title: "Walking", isBuiltIn: false, useCount: 7),
            Happening(id: "health_workout_52", title: "Walking", isBuiltIn: false, useCount: 3)
        ]
        let selected = ["body_walking", "health_workout_52"] + Array(originalBuiltIns.dropFirst(2)).map(\.id)
        for key in [SharedKeys.happeningPaletteSelection, SharedKeys.legacyHappeningPaletteOrderIds] {
            defaults.removeObject(forKey: SharedKeys.happeningPaletteSelection)
            defaults.set(selected, forKey: key)
            let store = HappeningPaletteSelectionStore(defaults: defaults)
            store.load(catalog: catalog)
            XCTAssertEqual(store.ids.first, "happening_walk")
            XCTAssertEqual(store.ids.count, 10)
            XCTAssertFalse(store.ids.contains("body_walking"))
            XCTAssertFalse(store.ids.contains("health_workout_52"))
            XCTAssertEqual(store.ids.last, "happening_workout")
            let reloaded = HappeningPaletteSelectionStore(defaults: defaults)
            reloaded.load(catalog: catalog)
            XCTAssertEqual(reloaded.ids, store.ids)
            XCTAssertEqual(defaults.stringArray(forKey: SharedKeys.happeningPaletteSelection), store.ids)
        }
    }

    func testSaveCannotReintroduceWalkingAliasBesideWalk() throws {
        let catalog = originalBuiltIns + [
            Happening(id: "health_workout_52", title: "Walking", isBuiltIn: false)
        ]
        let store = HappeningPaletteSelectionStore(defaults: defaults)
        store.load(catalog: catalog)
        let original = store.ids
        XCTAssertThrowsError(try store.save(Array(original.dropLast()) + ["health_workout_52"], catalog: catalog))
        XCTAssertEqual(store.ids, original)
    }

    func testRepairKeepsCustomWalkAndAnImportedWalkWhenBuiltInIsMissing() {
        let catalog = [
            Happening(id: "body_walking", title: "Walking", isBuiltIn: false),
            Happening(id: "health_workout_52", title: "Walking", isBuiltIn: false),
            Happening(id: "user_walk", title: "Walk", isBuiltIn: false)
        ]
        XCTAssertEqual(
            HappeningPaletteSelection.repaired(ids: catalog.map(\.id), catalog: catalog, defaults: []),
            ["body_walking", "user_walk"]
        )
    }

    func testAlternativeStillExistsWhenItsBuiltInIsMissing() {
        let legacy = Happening(id: "body_walking", title: "Walking", isBuiltIn: false)
        let health = Happening(id: "health_workout_52", title: "Walking", isBuiltIn: false)
        XCTAssertEqual(
            HappeningPaletteSelection.alternatives(catalog: [legacy, health], selected: []),
            [legacy]
        )
    }

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

    func testExplicitReplacementKeepsTenSlotsAndCancellationRestoresOrder() {
        let catalog = makeCatalog(counts: Array(repeating: 0, count: 12))
        let selected = Array(catalog.prefix(10)).map(\.id)
        var draft = HappeningPaletteSelectionDraft(selected: selected, catalog: catalog, protectedIDs: ["h0"])
        XCTAssertTrue(draft.replace(id: "h4", with: "h10"))
        XCTAssertEqual(draft.ids[4], "h10")
        XCTAssertEqual(draft.ids.count, 10)
        XCTAssertTrue(draft.canSave)
        XCTAssertTrue(draft.hasChanges)
        XCTAssertFalse(draft.replace(id: "h0", with: "h11"))
        XCTAssertFalse(draft.replace(id: "h1", with: "h2"))
        XCTAssertFalse(draft.replace(id: "h1", with: "missing"))
        XCTAssertFalse(draft.replace(id: "missing", with: "h11"))
        draft.cancel()
        XCTAssertEqual(draft.ids, selected)
        XCTAssertFalse(draft.hasChanges)
    }

    func testFirstLoadSeedsBuiltInsInSourceOrder() {
        let store = HappeningPaletteSelectionStore(defaults: defaults)

        store.load(catalog: originalBuiltIns)

        XCTAssertEqual(store.ids, originalBuiltIns.map(\.id))
        XCTAssertEqual(defaults.stringArray(forKey: SharedKeys.happeningPaletteSelection), store.ids)
    }

    func testLoadRemovesUnknownIdsAndRefillsInDefaultOrder() {
        let catalog = originalBuiltIns + [
            Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)
        ]
        defaults.set(
            ["unknown", originalBuiltIns[2].id],
            forKey: SharedKeys.happeningPaletteSelection
        )
        let store = HappeningPaletteSelectionStore(defaults: defaults)

        store.load(catalog: catalog)

        XCTAssertEqual(
            store.ids,
            [originalBuiltIns[2].id]
                + originalBuiltIns.map(\.id).filter { $0 != originalBuiltIns[2].id }
        )
    }

    func testLoadRemovesDuplicatesBeforeRefilling() {
        let catalog = originalBuiltIns
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
        let catalog = originalBuiltIns
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

    func testChooserDraftKeepsHappeningSelectedWhenItIsOnCanvas() {
        let catalog = makeCatalog(counts: Array(repeating: 0, count: 10))
        let selected = catalog.map(\.id)
        var draft = HappeningPaletteSelectionDraft(
            selected: selected,
            catalog: catalog,
            protectedIDs: [selected[0]]
        )

        XCTAssertEqual(draft.toggle(id: selected[0]), .protected)
        XCTAssertEqual(draft.ids, selected)
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

    func testPaletteCreationOutcomesKeepCreatorOpenForActionableFeedback() {
        XCTAssertTrue(HappeningPaletteCreationOutcome.created.closesCreator)
        XCTAssertNil(HappeningPaletteCreationOutcome.created.feedback)

        XCTAssertFalse(HappeningPaletteCreationOutcome.invalidTitle.closesCreator)
        XCTAssertEqual(
            HappeningPaletteCreationOutcome.invalidTitle.feedback?.message,
            "Enter a happening before adding it."
        )

        XCTAssertFalse(HappeningPaletteCreationOutcome.noReplaceableSlot.closesCreator)
        XCTAssertEqual(
            HappeningPaletteCreationOutcome.noReplaceableSlot.feedback?.message,
            "Remove a happening from Canvas before adding another."
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

    func testReplacementSkipsProtectedHappeningEvenWhenItIsLeastUsed() {
        let catalog = makeCatalog(counts: [0, 1])

        XCTAssertEqual(
            HappeningPaletteSelection.replacementIndex(
                in: ["h0", "h1"],
                catalog: catalog,
                excluding: ["h0"]
            ),
            1
        )
    }

    func testReplacementReturnsNilWhenEverySelectedHappeningIsProtected() {
        let catalog = makeCatalog(counts: [0, 1])

        XCTAssertNil(
            HappeningPaletteSelection.replacementIndex(
                in: ["h0", "h1"],
                catalog: catalog,
                excluding: ["h0", "h1"]
            )
        )
    }

    func testStoreReportsNoReplaceableSlotWhenEverySelectedHappeningIsProtected() throws {
        let catalog = makeCatalog(counts: Array(repeating: 0, count: 10))
            + [Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)]
        let store = HappeningPaletteSelectionStore(defaults: defaults)
        let selected = Array(catalog.prefix(10).map(\.id))
        try store.save(selected, catalog: catalog)

        XCTAssertThrowsError(
            try store.insertReplacingLeastUsed(
                "user_sauna",
                catalog: catalog,
                excluding: Set(selected)
            )
        ) {
            XCTAssertEqual($0 as? HappeningPaletteSelectionError, .noReplaceableSlot)
        }
        XCTAssertEqual(store.ids, selected)
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
        let catalog = originalBuiltIns
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
        let catalog = originalBuiltIns
        defaults.set(Array(catalog.map(\.id).dropLast()) + ["unknown"], forKey: "paletteOrderIds_v1")
        let store = HappeningPaletteSelectionStore(defaults: defaults)

        store.load(catalog: catalog)

        XCTAssertEqual(store.ids, catalog.map(\.id))
    }
}
