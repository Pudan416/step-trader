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
                optionId: "happening_walk", label: "Walk",
                existingElements: [], dayKey: today,
                composition: DayComposition.forDay(dayKey: today, happeningCount: 0)
            )
        ]
        _ = CanvasStorageService.shared.saveCanvas(canvas)
        defer { CanvasStorageService.shared.deleteCanvas(for: today) }

        let model = makeModel()
        model.loadDailyEnergyState()

        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk"])
    }

    func testCanvasReconciliationCreatesMissingEntryWithoutRecordingAnotherUse() throws {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        let elementID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        var canvas = DayCanvas(dayKey: dayKey)
        canvas.elements = [
            CanvasElement.spawn(
                id: elementID,
                optionId: "happening_walk",
                label: "Walk",
                existingElements: [],
                dayKey: dayKey,
                composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 0)
            )
        ]

        let reconciliation = CanvasHappeningReconciler.reconcile(
            canvas: canvas,
            entries: [],
            dayKey: dayKey,
            now: now
        )

        XCTAssertEqual(reconciliation.entriesToAdd, [
            OptionEntry(
                id: elementID.uuidString,
                dayKey: dayKey,
                optionId: "happening_walk",
                colorHex: canvas.elements[0].hexColor,
                timestamp: now,
                assetVariant: canvas.elements[0].assetVariant
            ),
        ])
        XCTAssertTrue(reconciliation.entryIDsToRemove.isEmpty)

        let model = makeModel()
        model.loadDailyEnergyState()
        let useCountBefore = try XCTUnwrap(
            model.happeningStore.happening(id: "happening_walk")?.useCount
        )
        CanvasHappeningReconciliationTransaction.commit(
            reconciliation,
            model: model
        )
        XCTAssertEqual(
            model.happeningStore.happening(id: "happening_walk")?.useCount,
            useCountBefore
        )
        XCTAssertEqual(
            CanvasHappeningReconciler.reconcile(
                canvas: canvas,
                entries: model.todayAdditions,
                dayKey: dayKey,
                now: now.addingTimeInterval(1)
            ),
            CanvasHappeningReconciliation(entriesToAdd: [], entryIDsToRemove: [])
        )
    }

    func testCanvasReconciliationWaitsForDailyAdditionsHydrationThenUsesHydratedEntries() {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        let canvas = DayCanvas(dayKey: dayKey)
        let restoredEntry = OptionEntry(
            id: "server-restored-entry",
            dayKey: dayKey,
            optionId: "happening_walk",
            colorHex: "#AABBCC",
            timestamp: now,
            assetVariant: 2
        )

        XCTAssertNil(
            CanvasHappeningReconciliationPolicy.reconcileIfReady(
                canvasLoaded: true,
                appModelIsBootstrapping: true,
                canvas: canvas,
                entries: [],
                dayKey: dayKey,
                now: now
            ),
            "an empty pre-bootstrap projection must not be treated as hydrated truth"
        )

        XCTAssertEqual(
            CanvasHappeningReconciliationPolicy.reconcileIfReady(
                canvasLoaded: true,
                appModelIsBootstrapping: false,
                canvas: canvas,
                entries: [restoredEntry],
                dayKey: dayKey,
                now: now
            )?.entryIDsToRemove,
            [restoredEntry.id],
            "the hydration transition must reconcile the restored additions snapshot"
        )
    }

    func testCanvasFetchResultDistinguishesConfirmedAbsenceFromFailure() {
        switch DayCanvasFetchResult.decode(statusCode: 200, data: Data("[]".utf8)) {
        case .confirmedAbsent:
            break
        case .found, .failed:
            XCTFail("a successful empty response is the only confirmed-absence case")
        }

        for failure in [
            DayCanvasFetchResult.decode(statusCode: 304, data: Data("[]".utf8)),
            DayCanvasFetchResult.decode(statusCode: 503, data: Data("[]".utf8)),
            DayCanvasFetchResult.decode(statusCode: 200, data: Data("not-json".utf8)),
        ] {
            guard case .failed = failure else {
                XCTFail("HTTP and decoding failures must never masquerade as absence")
                continue
            }
        }
    }

    func testFailedCanvasFetchCannotHydrateEmptyOrDeleteRestoredAddition() {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        let restored = OptionEntry(
            id: "restored-entry",
            dayKey: dayKey,
            optionId: "happening_walk",
            colorHex: "#A1B2C3",
            timestamp: now,
            assetVariant: 2
        )
        let model = makeModel()
        model.loadDailyEnergyState()
        model.todayAdditions = [restored]
        var cloudPlans = [[CanvasHappeningReconciliationSyncOperation]]()

        let didHydrate = CanvasRemoteHydrationCoordinator.apply(
            .failed,
            onFound: { canvas in
                let reconciliation = CanvasHappeningReconciler.reconcile(
                    canvas: canvas,
                    entries: model.todayAdditions,
                    dayKey: dayKey,
                    now: now
                )
                CanvasHappeningReconciliationTransaction.commit(
                    reconciliation,
                    model: model,
                    syncOperations: { cloudPlans.append($0) }
                )
            },
            onConfirmedAbsent: {
                let reconciliation = CanvasHappeningReconciler.reconcile(
                    canvas: DayCanvas(dayKey: dayKey),
                    entries: model.todayAdditions,
                    dayKey: dayKey,
                    now: now
                )
                CanvasHappeningReconciliationTransaction.commit(
                    reconciliation,
                    model: model,
                    syncOperations: { cloudPlans.append($0) }
                )
            }
        )

        XCTAssertFalse(didHydrate)
        XCTAssertEqual(model.todayAdditions, [restored])
        XCTAssertTrue(cloudPlans.isEmpty)
    }

    func testCanvasReconciliationRemovesOrphanEntryAndIsIdempotent() {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        let orphan = OptionEntry(
            id: "orphan-entry",
            dayKey: dayKey,
            optionId: "happening_walk",
            colorHex: "#AABBCC",
            timestamp: now,
            assetVariant: 2
        )
        let canvas = DayCanvas(dayKey: dayKey)

        let reconciliation = CanvasHappeningReconciler.reconcile(
            canvas: canvas,
            entries: [orphan],
            dayKey: dayKey,
            now: now
        )

        XCTAssertTrue(reconciliation.entriesToAdd.isEmpty)
        XCTAssertEqual(reconciliation.entryIDsToRemove, ["orphan-entry"])
        let remaining = [orphan].filter { !reconciliation.entryIDsToRemove.contains($0.id) }
        XCTAssertEqual(
            CanvasHappeningReconciler.reconcile(
                canvas: canvas,
                entries: remaining,
                dayKey: dayKey,
                now: now.addingTimeInterval(1)
            ),
            CanvasHappeningReconciliation(entriesToAdd: [], entryIDsToRemove: [])
        )
    }

    func testCanvasReconciliationPreservesExistingEntryIDWhenOptionMatches() {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        var canvas = DayCanvas(dayKey: dayKey)
        canvas.elements = [
            CanvasElement.spawn(
                id: UUID(),
                optionId: "happening_walk",
                label: "Walk",
                existingElements: [],
                dayKey: dayKey,
                composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 0)
            ),
        ]
        let existing = OptionEntry(
            id: "legacy-stable-entry-id",
            dayKey: dayKey,
            optionId: "happening_walk",
            colorHex: "#AABBCC",
            timestamp: now.addingTimeInterval(-100),
            assetVariant: 1
        )

        XCTAssertEqual(
            CanvasHappeningReconciler.reconcile(
                canvas: canvas,
                entries: [existing],
                dayKey: dayKey,
                now: now
            ),
            CanvasHappeningReconciliation(entriesToAdd: [], entryIDsToRemove: [])
        )
    }

    func testCanvasReconciliationRepairsConflictingStableIdentityBeforeLegacyOptionMatching() throws {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        let walkID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let readID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        var canvas = DayCanvas(dayKey: dayKey)
        canvas.elements = [
            CanvasElement.spawn(
                id: walkID, optionId: "happening_walk", label: "Walk",
                existingElements: [], dayKey: dayKey,
                composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 0)
            ),
            CanvasElement.spawn(
                id: readID, optionId: "happening_read", label: "Read",
                existingElements: [], dayKey: dayKey,
                composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 1)
            ),
        ]
        let stale = OptionEntry(
            id: walkID.uuidString,
            dayKey: dayKey,
            optionId: "happening_read",
            colorHex: "#AABBCC",
            timestamp: now.addingTimeInterval(-100),
            assetVariant: nil
        )

        let reconciliation = CanvasHappeningReconciler.reconcile(
            canvas: canvas,
            entries: [stale],
            dayKey: dayKey,
            now: now
        )

        XCTAssertEqual(reconciliation.entryIDsToRemove, [walkID.uuidString])
        XCTAssertEqual(reconciliation.entriesToAdd.map(\.id), [
            walkID.uuidString,
            readID.uuidString,
        ])
        XCTAssertEqual(reconciliation.entriesToAdd.map(\.optionId), [
            "happening_walk",
            "happening_read",
        ])
    }

    func testReconciliationSameIDReplacementCannotQueueDeleteAfterCanonicalUpsert() throws {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        let stableID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let stale = OptionEntry(
            id: stableID.uuidString,
            dayKey: dayKey,
            optionId: "happening_read",
            colorHex: "#000000",
            timestamp: now.addingTimeInterval(-100),
            assetVariant: nil
        )
        let canonical = OptionEntry(
            id: stableID.uuidString,
            dayKey: dayKey,
            optionId: "happening_walk",
            colorHex: "#A1B2C3",
            timestamp: now,
            assetVariant: 7
        )
        let model = makeModel()
        model.loadDailyEnergyState()
        model.todayAdditions = [stale]
        var cloudPlans = [[CanvasHappeningReconciliationSyncOperation]]()

        CanvasHappeningReconciliationTransaction.commit(
            CanvasHappeningReconciliation(
                entriesToAdd: [canonical],
                entryIDsToRemove: [stale.id]
            ),
            model: model,
            syncOperations: { cloudPlans.append($0) }
        )

        XCTAssertEqual(model.todayAdditions, [canonical])
        XCTAssertEqual(cloudPlans, [[.upsert(canonical)]])
    }

    func testOptionEntryUpsertPayloadExplicitlyClearsNilAssetVariant() throws {
        let entry = OptionEntry(
            id: "entry-id",
            dayKey: "2026-09-06",
            optionId: "happening_walk",
            colorHex: "#A1B2C3",
            timestamp: Date(timeIntervalSince1970: 1_786_176_000),
            assetVariant: nil
        )
        let rows = [
            OptionEntryUpsertRow(
                entry: entry,
                userID: "user-id",
                createdAt: "2026-09-06T10:00:00Z"
            ),
        ]

        let data = try JSONEncoder().encode(rows)
        let payload = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first
        )

        XCTAssertEqual(payload["id"] as? String, entry.id)
        XCTAssertEqual(payload["user_id"] as? String, "user-id")
        XCTAssertEqual(payload["day_key"] as? String, entry.dayKey)
        XCTAssertEqual(payload["option_id"] as? String, entry.optionId)
        XCTAssertEqual(payload["color_hex"] as? String, entry.colorHex)
        XCTAssertEqual(payload["created_at"] as? String, "2026-09-06T10:00:00Z")
        XCTAssertTrue(payload.keys.contains("asset_variant"))
        XCTAssertTrue(payload["asset_variant"] is NSNull)
    }

    func testReconciliationCanonicalizesDuplicateCanvasOptionsAndBecomesIdempotent() throws {
        let now = Date(timeIntervalSince1970: 1_786_176_000)
        let dayKey = AppModel.dayKey(for: now)
        let firstID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let duplicateID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        var canvas = DayCanvas(dayKey: dayKey)
        canvas.elements = [
            CanvasElement.spawn(
                id: firstID, optionId: "happening_walk", label: "Walk",
                existingElements: [], dayKey: dayKey,
                composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 0)
            ),
            CanvasElement.spawn(
                id: duplicateID, optionId: "happening_walk", label: "Walk",
                existingElements: [], dayKey: dayKey,
                composition: DayComposition.forDay(dayKey: dayKey, happeningCount: 1)
            ),
        ]

        let first = CanvasHappeningReconciler.reconcile(
            canvas: canvas,
            entries: [],
            dayKey: dayKey,
            now: now
        )

        XCTAssertEqual(first.entriesToAdd.map(\.id), [firstID.uuidString])
        XCTAssertEqual(first.duplicateElementIDsToRemove, [duplicateID])

        canvas.elements.removeAll { first.duplicateElementIDsToRemove.contains($0.id) }
        let model = makeModel()
        model.loadDailyEnergyState()
        CanvasHappeningReconciliationTransaction.commit(
            first,
            model: model,
            syncOperations: { _ in }
        )

        XCTAssertEqual(
            CanvasHappeningReconciler.reconcile(
                canvas: canvas,
                entries: model.todayAdditions,
                dayKey: dayKey,
                now: now.addingTimeInterval(1)
            ),
            CanvasHappeningReconciliation(entriesToAdd: [], entryIDsToRemove: [])
        )
    }

    func testDayEndReanchorMovesAdditionAndCanvasWithoutReopeningHappening() async throws {
        let now = Date.now
        guard let pair = dayEndPairWithDifferentKeys(at: now) else {
            throw XCTSkip(
                """
                No two day ends give different keys at \(now). Only true in the \
                final minute before midnight, when every boundary of the day has \
                already passed and there is none left to move across.
                """
            )
        }
        defaults.set(pair.old.hour, forKey: SharedKeys.dayEndHour)
        defaults.set(pair.old.minute, forKey: SharedKeys.dayEndMinute)
        UserDefaults.standard.set(pair.old.hour, forKey: SharedKeys.dayEndHour)
        UserDefaults.standard.set(pair.old.minute, forKey: SharedKeys.dayEndMinute)

        let oldKey = DayBoundary.dayKey(
            for: now,
            dayEndHour: pair.old.hour,
            dayEndMinute: pair.old.minute
        )
        let newKey = DayBoundary.dayKey(
            for: now,
            dayEndHour: pair.new.hour,
            dayEndMinute: pair.new.minute
        )
        // `CanvasStorageService` writes into the app's real container, which the
        // test host shares — so running the app by hand on this simulator leaves
        // a canvas for the ambient day that this test then reads as its own.
        // Clear that one too, not just the two keys under test.
        let ambientKey = AppModel.dayKey(for: now)
        let ambientBackup = CanvasStorageService.shared.loadCanvas(for: ambientKey)
        let oldBackup = CanvasStorageService.shared.loadCanvas(for: oldKey)
        let newBackup = CanvasStorageService.shared.loadCanvas(for: newKey)
        CanvasStorageService.shared.deleteCanvas(for: ambientKey)
        CanvasStorageService.shared.deleteCanvas(for: oldKey)
        CanvasStorageService.shared.deleteCanvas(for: newKey)
        defer {
            CanvasStorageService.shared.deleteCanvas(for: oldKey)
            CanvasStorageService.shared.deleteCanvas(for: newKey)
            CanvasStorageService.shared.deleteCanvas(for: ambientKey)
            if let ambientBackup { _ = CanvasStorageService.shared.saveCanvas(ambientBackup) }
            if let oldBackup { _ = CanvasStorageService.shared.saveCanvas(oldBackup) }
            if let newBackup { _ = CanvasStorageService.shared.saveCanvas(newBackup) }
            UserDefaults.standard.removeObject(forKey: SharedKeys.dayEndHour)
            UserDefaults.standard.removeObject(forKey: SharedKeys.dayEndMinute)
        }

        defaults.set(try JSONEncoder().encode([OptionEntry]()), forKey: SharedKeys.todayAdditions)
        defaults.set(
            DayBoundary.currentDayStart(
                for: now,
                dayEndHour: pair.old.hour,
                dayEndMinute: pair.old.minute
            ),
            forKey: SharedKeys.dailyEnergyAnchor
        )
        let standardSuite = try XCTUnwrap(UserDefaults(suiteName: "day-end-reanchor-\(UUID())"))
        let budgetEngine = BudgetEngine(
            sharedDefaults: defaults,
            standardDefaults: standardSuite
        )
        let model = AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: budgetEngine,
            subscriptionStore: SubscriptionStore()
        )
        model.isBootstrapping = true
        model.loadDailyEnergyState()
        XCTAssertEqual(model.dayEndHour, pair.old.hour)
        XCTAssertEqual(model.dayEndMinute, pair.old.minute)

        let entry = try XCTUnwrap(
            model.addHappening(
                id: "happening_walk",
                colorHex: "#AABBCC",
                at: now
            )
        )
        var canvas = DayCanvas(dayKey: oldKey)
        canvas.elements = [
            CanvasElement.spawn(
                id: try XCTUnwrap(UUID(uuidString: entry.id)),
                optionId: entry.optionId,
                label: "Walk",
                existingElements: [],
                dayKey: oldKey,
                composition: DayComposition.forDay(dayKey: oldKey, happeningCount: 0)
            )
        ]
        XCTAssertTrue(CanvasStorageService.shared.saveCanvas(canvas))
        XCTAssertEqual(
            CanvasStorageService.shared.loadCanvas(for: oldKey)?.elements.map(\.id),
            canvas.elements.map(\.id)
        )

        model.updateDayEnd(hour: pair.new.hour, minute: pair.new.minute)
        // Wait for the production debounce task itself. A fixed delay races
        // simulator scheduling and can inspect storage before the commit ran.
        await model.dayEndCommitTask?.value
        XCTAssertEqual(model.dayEndHour, pair.new.hour)
        XCTAssertEqual(model.dayEndMinute, pair.new.minute)

        XCTAssertEqual(model.todayAdditions.map(\.dayKey), [newKey])
        XCTAssertNil(
            model.addHappening(
                id: "happening_walk",
                colorHex: "#DDEEFF",
                at: now
            ),
            "re-anchoring must preserve once-per-custom-day identity"
        )
        XCTAssertNil(CanvasStorageService.shared.loadCanvas(for: oldKey))
        let movedCanvas = try XCTUnwrap(
            CanvasStorageService.shared.loadCanvas(for: newKey),
            "Expected moved canvas at \(newKey); available: \(CanvasStorageService.shared.availableDayKeys())"
        )
        XCTAssertEqual(movedCanvas.dayKey, newKey)
        XCTAssertEqual(movedCanvas.elements.map(\.id), canvas.elements.map(\.id))
    }

    private func clearEnergyDefaults() {
        let keys = [
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.dailySleepHours,
            SharedKeys.baseEnergyToday,
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            SharedKeys.dayEndHour,
            SharedKeys.dayEndMinute,
            "dailyEnergySelections_v1_body",
            "dailyEnergySelections_v1_mind",
            "dailyEnergySelections_v1_heart",
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    private struct DayEnd {
        let hour: Int
        let minute: Int
    }

    /// Two day ends that put `date` in different days — the reanchor this test
    /// exercises needs a boundary it can actually move across.
    ///
    /// Minutes are part of the search, not just hours. `dayKey` names the
    /// calendar date the day *started* on, so two day ends differ only when one
    /// of their boundaries has already passed today and the other has not. Once
    /// 23:00 is behind us every whole hour has passed and an hours-only search
    /// comes back empty — which is what failed this test at 23:44, on the
    /// unwrap rather than on anything it was asserting.
    ///
    /// Single pass: hold the first candidate, return the first one that keys
    /// differently. Deterministic, and 1440 boundary computations rather than
    /// the square of that.
    private func dayEndPairWithDifferentKeys(
        at date: Date
    ) -> (old: DayEnd, new: DayEnd)? {
        var first: (end: DayEnd, key: String)?
        for hour in 0..<24 {
            for minute in 0..<60 {
                let end = DayEnd(hour: hour, minute: minute)
                let key = DayBoundary.dayKey(
                    for: date,
                    dayEndHour: hour,
                    dayEndMinute: minute
                )
                guard let anchor = first else {
                    first = (end, key)
                    continue
                }
                if key != anchor.key { return (anchor.end, end) }
            }
        }
        return nil
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
