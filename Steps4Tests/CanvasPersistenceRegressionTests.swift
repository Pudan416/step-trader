import XCTest
import HealthKit
import Metal
import UIKit
import SwiftUI
@testable import Steps4

@MainActor
final class CanvasPersistenceRegressionTests: XCTestCase {
    func testCloudCanvasRoundTripPreservesFullWidthRemixAndShapeSeeds() throws {
        var canvas = CanvasUnifiedRemix.next(canvas: DayCanvas(dayKey: "2026-08-18")).canvas
        canvas.remixSeed = UInt64.max
        var element = CanvasElement.spawn(
            optionId: "walk", label: "Walk", existingElements: [],
            dayKey: canvas.dayKey,
            composition: .forDay(dayKey: canvas.dayKey, happeningCount: 1)
        )
        element.shapeSeed = 0xD4A0_B1EC_75ED_0001
        canvas.elements = [element]
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(canvas))
        let envelope = try JSONSerialization.data(withJSONObject: ["canvas_json": json])
        let row = try JSONDecoder().decode(DayCanvasReadRow.self, from: envelope)
        let restored = try JSONDecoder().decode(
            DayCanvas.self, from: JSONSerialization.data(withJSONObject: row.canvasJson)
        )
        XCTAssertEqual(restored.remixSeed, UInt64.max)
        XCTAssertEqual(restored.elements[0].shapeSeed, 0xD4A0_B1EC_75ED_0001)
        XCTAssertEqual(restored.resolvedMusicSelection, canvas.resolvedMusicSelection)
    }
    func testLegacyCanvasDecodesWithoutRemixFieldsAndResolvesStableDayIdentity() throws {
        let canvas = DayCanvas(dayKey: "2026-08-18")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(canvas)) as? [String: Any])
        ["remixSeed", "soundWorldRaw", "soundMoodRaw", "guestSoundWorldRaw"].forEach { json.removeValue(forKey: $0) }
        let decoded = try JSONDecoder().decode(DayCanvas.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.remixSeed)
        XCTAssertEqual(decoded.resolvedRemixSeed, CanvasElement.makeSeed(optionId: "dayObjects:primary-canvas", dayKey: "2026-08-18", index: 0))
        XCTAssertEqual(decoded.resolvedMusicSelection, DayObjectsWorldSelector.makeSelection(remixSeed: decoded.resolvedRemixSeed))
    }

    func testRemixIdentityAndBackgroundSurviveStorageAndLaterHealthSync() throws {
        let key = "2098-12-27"
        let prior = CanvasStorageService.shared.loadCanvas(for: key)
        defer {
            CanvasStorageService.shared.deleteCanvas(for: key)
            if let prior { _ = CanvasStorageService.shared.saveCanvas(prior) }
        }
        var canvas = CanvasUnifiedRemix.next(canvas: DayCanvas(dayKey: key)).canvas
        canvas.remixSeed = UInt64.max
        canvas.soundWorldRaw = "metalAndCurrent"
        canvas.soundMoodRaw = "strange"
        canvas.guestSoundWorldRaw = "electricDream"
        let palette = canvas.gradientPalette
        let texture = canvas.textureRaw
        XCTAssertFalse(canvas.applyVisualPreferences(gradientStyle: "radial", gradientPalette: "ocean", overlayStyle: "smudge", textureRaw: "grainSmall"))
        canvas.stepsPoints = 20
        XCTAssertTrue(CanvasStorageService.shared.saveCanvas(canvas))
        let restored = try XCTUnwrap(CanvasStorageService.shared.loadCanvas(for: key))
        XCTAssertEqual(restored.remixSeed, UInt64.max)
        XCTAssertEqual(restored.soundWorldRaw, "metalAndCurrent")
        XCTAssertEqual(restored.soundMoodRaw, "strange")
        XCTAssertEqual(restored.guestSoundWorldRaw, "electricDream")
        XCTAssertEqual(restored.gradientPalette, palette)
        XCTAssertEqual(restored.textureRaw, texture)
        XCTAssertEqual(restored.stepsPoints, 20)
    }

    func testLegacyCanvasStillAdoptsVisualPreferences() {
        var canvas = DayCanvas(dayKey: "2026-08-18")
        XCTAssertTrue(canvas.applyVisualPreferences(gradientStyle: "radial", gradientPalette: "ocean", overlayStyle: "smudge", textureRaw: "grainSmall"))
        XCTAssertEqual(canvas.gradientPalette, "ocean")
        XCTAssertEqual(canvas.textureRaw, "grainSmall")
    }
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
final class NativeAtlasRecipeTests: XCTestCase {
    func testNewNativeCanvasCapturesChosenPalette() throws {
        let pastel = DayCanvas.newDailyCanvas(dayKey: "2026-09-10", paletteCategories: [.pastel])
        let neon = DayCanvas.newDailyCanvas(dayKey: "2026-09-10", paletteCategories: [.neon])
        let pastelStyle = try XCTUnwrap(pastel.artworkRecipe?.backgroundStyle)
        let neonStyle = try XCTUnwrap(neon.artworkRecipe?.backgroundStyle)
        XCTAssertNotEqual(pastelStyle.colors, neonStyle.colors)
        let decoded = try JSONDecoder().decode(DayCanvas.self, from: JSONEncoder().encode(pastel))
        let input = EditorialCanvasInputFactory.make(
            canvas: decoded,
            metrics: .init(stepsProgress: 0.5, sleepProgress: 0.8, spentProgress: 0),
            paletteCategories: [.neon]
        )
        XCTAssertEqual(DayObjectScene.make(input: input.sceneInput).meshGradientStyle, pastelStyle)
    }

    func testAppearanceApplyPersistsTodaysNativeBackgroundWithoutGallery() throws {
        let suite = "NativeAppearanceApply.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let today = "appearance-today-\(UUID().uuidString)"
        let archive = "appearance-archive-\(UUID().uuidString)"
        let storage = CanvasStorageService.shared
        defer {
            defaults.removePersistentDomain(forName: suite)
            storage.deleteCanvas(for: today)
            storage.deleteCanvas(for: archive)
        }
        let original = DayCanvas.newDailyCanvas(dayKey: today, paletteCategories: [.pastel])
        let archived = DayCanvas.newDailyCanvas(dayKey: archive, paletteCategories: [.pastel])
        XCTAssertTrue(storage.saveCanvas(original))
        XCTAssertTrue(storage.saveCanvas(archived))
        var draft = SettingsAppearanceDraft.load(from: defaults)
        draft.categories = ModernPaletteSelection.encode([.neon])
        // This path runs with no Gallery view, and must update the saved recipe.
        draft.apply(to: defaults, shared: nil, dayKey: today)
        var updated = try XCTUnwrap(storage.loadCanvas(for: today))
        let recipe = try XCTUnwrap(updated.artworkRecipe)
        XCTAssertEqual(recipe.backgroundStyle, NativeAtlasRecipe.makeBackgroundStyle(
            dayKey: today, recipeSeed: UInt64(recipe.seedHex, radix: 16) ?? 0, paletteCategories: [.neon]))
        XCTAssertNotEqual(recipe.backgroundStyle, original.artworkRecipe?.backgroundStyle)
        let unchangedArchive = try XCTUnwrap(storage.loadCanvas(for: archive))
        XCTAssertEqual(unchangedArchive.artworkRecipe, archived.artworkRecipe)
        XCTAssertEqual(unchangedArchive.lastModified, archived.lastModified)

        updated.artworkRecipe?.locks.insert("artwork")
        XCTAssertTrue(storage.saveCanvas(updated))
        draft.categories = ModernPaletteSelection.encode([.winter])
        draft.apply(to: defaults, shared: nil, dayKey: today)
        let locked = try XCTUnwrap(storage.loadCanvas(for: today))
        XCTAssertEqual(locked.artworkRecipe, updated.artworkRecipe)
        XCTAssertEqual(locked.lastModified, updated.lastModified)
    }

    func testNativeBackgroundMigrationPreservesDefaultAppearanceAndTimestamps() throws {
        var canvas = DayCanvas.newDailyCanvas(dayKey: "2026-09-10")
        let style = try XCTUnwrap(canvas.artworkRecipe?.backgroundStyle)
        let modified = canvas.lastModified
        canvas.artworkRecipe?.backgroundStyle = nil
        XCTAssertTrue(canvas.freezeNativeBackgroundIfNeeded())
        XCTAssertEqual(canvas.artworkRecipe?.backgroundStyle, style)
        XCTAssertEqual(canvas.lastModified, modified)
        XCTAssertFalse(canvas.freezeNativeBackgroundIfNeeded())

        canvas.artworkRecipe?.schemaVersion = 99
        canvas.artworkRecipe?.backgroundStyle = nil
        XCTAssertFalse(canvas.freezeNativeBackgroundIfNeeded())
        XCTAssertNil(canvas.artworkRecipe?.backgroundStyle)
        var legacy = DayCanvas(dayKey: canvas.dayKey)
        XCTAssertFalse(legacy.freezeNativeBackgroundIfNeeded())
        XCTAssertNil(legacy.artworkRecipe)
    }

    func testUnifiedNativeRemixAndUndoPreserveBackgroundOwnership() throws {
        var canvas = DayCanvas.newDailyCanvas(dayKey: "2026-09-10", paletteCategories: [.pastel])
        let original = try XCTUnwrap(canvas.artworkRecipe?.backgroundStyle)
        var history = CanvasRemixHistory()
        let remix = history.remix(canvas: canvas, paletteCategories: [.neon])
        XCTAssertNotEqual(remix.canvas.artworkRecipe?.backgroundStyle?.colors, original.colors)
        let restored = try XCTUnwrap(history.undo(into: remix.canvas))
        XCTAssertEqual(restored.artworkRecipe?.backgroundStyle, original)

        canvas.artworkRecipe?.locks.insert("artwork")
        let locked = history.remix(canvas: canvas, paletteCategories: [.neon])
        XCTAssertEqual(locked.canvas.artworkRecipe?.backgroundStyle, original)
    }

    func testArchivedNativeBackgroundIgnoresLaterPalettePreferences() throws {
        let original = DayCanvas.newDailyCanvas(dayKey: "2026-09-10")
        let decoded = try JSONDecoder().decode(DayCanvas.self, from: JSONEncoder().encode(original))
        func style(_ categories: Set<ModernPaletteCategory>) -> DayObjectMeshGradientStyle {
            let input = EditorialCanvasInputFactory.make(
                canvas: decoded,
                metrics: .init(stepsProgress: 0.5, sleepProgress: 0.8, spentProgress: 0),
                paletteCategories: categories
            )
            return DayObjectScene.make(input: input.sceneInput).meshGradientStyle
        }
        XCTAssertEqual(style(ModernPaletteSelection.all), style([.neon]),
                       "Changing today's preferences must not recolor an archived native canvas")
    }

    func testRecipeWithoutFrozenBackgroundDecodesAndUsesStableFallback() throws {
        let original = DayCanvas.newDailyCanvas(dayKey: "2026-09-10")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var recipe = try XCTUnwrap(json["artworkRecipe"] as? [String: Any])
        recipe.removeValue(forKey: "backgroundStyle")
        json["artworkRecipe"] = recipe
        let decoded = try JSONDecoder().decode(DayCanvas.self, from: JSONSerialization.data(withJSONObject: json))
        func style(_ categories: Set<ModernPaletteCategory>) -> DayObjectMeshGradientStyle {
            let input = EditorialCanvasInputFactory.make(
                canvas: decoded,
                metrics: .init(stepsProgress: 0.5, sleepProgress: 0.8, spentProgress: 0),
                paletteCategories: categories
            )
            return DayObjectScene.make(input: input.sceneInput).meshGradientStyle
        }
        XCTAssertNotNil(decoded.artworkRecipe)
        XCTAssertEqual(style(ModernPaletteSelection.all), style([.pastel]),
                       "Old recipes have no saved palette, so their fallback must not follow current settings")
    }

    func testInterfaceThemeHonorsDayNightAndSystemWithoutChangingCanvas() {
        XCTAssertTrue(AppTheme.normalized(rawValue: "daylight").isLight(in: .dark))
        XCTAssertFalse(AppTheme.normalized(rawValue: "night").isLight(in: .light))
        XCTAssertTrue(AppTheme.normalized(rawValue: "system").isLight(in: .light))
        XCTAssertFalse(AppTheme.normalized(rawValue: "system").isLight(in: .dark))
    }

    @MainActor
    func testCanvasActionsUseReadableDailyPalette() throws {
        let palette = CanvasChromePalette.resolve(backgroundColors: [DayObjectRGB(hex: "#78966B")])
        let content = CanvasBottomActionRow(isDataPanelOpen: false, isHappeningPalettePresented: false, soundAppearance: .readyToPlay, onSound: {}, onOpenHappeningList: {}, onToggleHappeningPalette: {})
            .environment(\.canvasChromePalette, palette)
            .frame(width: 320, height: 60).background(Color.white)
        let renderer = ImageRenderer(content: content); renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage), p = try pixels(image)
        func matches(_ pixel: Int, _ color: DayObjectRGB) -> Bool {
            (0..<3).allSatisfy { abs(p[pixel + $0] - Double(color.sRGB[$0])) < 0.05 }
        }
        XCTAssertTrue(matches((30 * 320 + 14) * 4, palette.surface), "Play uses the daily dark surface")
        XCTAssertTrue(matches((30 * 320 + 278) * 4, palette.accent), "Add uses the daily light accent")
        let playAccentPixels = (8..<49).flatMap { x in (10..<50).map { y in (y * 320 + x) * 4 } }
            .filter { matches($0, palette.accent) }
        XCTAssertGreaterThan(playAccentPixels.count, 20, "Play remains visible against its tonal surface")
    }

    @MainActor
    func testLightCircleSupportsBlackInkOnLightAndDarkGradients() async throws {
        for (name, colors) in [
            ("light-gradient", [SIMD3<Float>(0.65, 0.82, 0.46), SIMD3(0.90, 0.95, 0.74), SIMD3(0.72, 0.86, 0.56)]),
            ("dark-gradient", [SIMD3<Float>(0.005, 0.015, 0.025), SIMD3(0.025, 0.065, 0.035), SIMD3(0.01, 0.02, 0.055)])
        ] {
            let circle = try await pickerImage(presetID: "legacy.soft-square", state: .available, backgroundColors: colors)
            let p = try pixels(circle)
            var minimumContrast = Double.greatestFiniteMagnitude
            for y in 80..<120 {
                for x in 70..<130 {
                    let i = (y * 200 + x) * 4
                    let linear = p[i..<i + 3].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                    let luminance = linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
                    minimumContrast = min(minimumContrast, (luminance + 0.05) / 0.05)
                }
            }
            XCTAssertGreaterThan(minimumContrast, 7, "Black text must remain readable over \(name)")
            let label = Happening(id: "h0", title: "Called someone", isBuiltIn: false)
            let input = DayObjectSceneInput(dayKey: "2026-09-10", identity: "native-picker-regression", eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true)
            let assignments = HappeningEditorialAssignmentResolver.assignments(happenings: [label], baseInput: input, colorNonce: 7)
            let screenshot = ImageRenderer(content: ZStack {
                Image(uiImage: circle).resizable().frame(width: 200, height: 200)
                HappeningShapeField(
                    happenings: [label], assignments: assignments,
                    layout: .init(sources: [.init(index: 0, center: CGPoint(x: 100, y: 100), radius: 60)], labelFrames: [], contourBounds: .zero, dockAnchor: .zero, completionBounds: nil),
                    interaction: .init(), addedIDs: [], onActivate: { _ in }
                )
            }.frame(width: 200, height: 200))
            screenshot.scale = 3
            let image = try XCTUnwrap(screenshot.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "light-circle-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testNativeBackgroundKeepsDistinctPaletteColors() {
        let input = DayObjectSceneInput(dayKey: "2026-09-10", identity: "primary-canvas", eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: .make(dayKey: "2026-09-10"))
        let scene = DayObjectScene.make(input: input)
        let colors = scene.meshGradientStyle.colors
        let palette = scene.paletteSet.background.hexes.map { DayObjectRGB(hex: $0).linearRGB }
        XCTAssertTrue(colors.allSatisfy { palette.contains($0) }, "Use the chosen palette, not neutral replacement colors")
        let differences: [Float] = colors.flatMap { a in colors.map { b in
            max(abs(a.x - b.x), max(abs(a.y - b.y), abs(a.z - b.z)))
        } }
        XCTAssertGreaterThan(differences.max() ?? 0, 0.3)
    }

    func testNativeBackgroundShowsBothPaletteEndpointsInPixels() async throws {
        let input = DayObjectSceneInput(dayKey: "2026-09-10", identity: "primary-canvas", eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: .make(dayKey: "2026-09-10"))
        let scene = DayObjectScene.make(input: input)
        let result = await DayObjectsImageRenderer.image(input: .init(sceneInput: input, digitalImpact: .none), size: CGSize(width: 300, height: 400), scale: 1, elapsedTime: 4)
        let image = try XCTUnwrap(result), p = try pixels(image)
        for color in scene.meshGradientStyle.colors.prefix(2) {
            let swatch = try XCTUnwrap(scene.palette.colors.first { $0.linearRGB == color }).sRGB
            var nearest = Double.infinity
            for y in stride(from: 12, to: 388, by: 6) {
                for x in stride(from: 12, to: 288, by: 6) {
                    let i = (y * 300 + x) * 4
                    let error = max(abs(p[i] - Double(swatch.z)), max(abs(p[i + 1] - Double(swatch.y)), abs(p[i + 2] - Double(swatch.x))))
                    nearest = min(nearest, error)
                }
            }
            XCTAssertLessThan(nearest, 0.12, "Each dominant swatch must remain visible, not disappear into an average")
        }
    }

    @MainActor
    func testEnergyPanelStaysDarkOnWhiteCanvas() throws {
        let content = CanvasEnergyStatusPill(status: .init(stepsBalance: 58, baseEnergyToday: 72, maximum: 100))
            .frame(width: 208, height: 58)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let p = try pixels(image)
        let i = (29 * 208 + 7) * 4
        XCTAssertLessThan((p[i] + p[i + 1] + p[i + 2]) / 3, 0.45, "The energy surface needs its own dark backing even on white")
        let attachment = XCTAttachment(image: image); attachment.name = "energy-on-white"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testPrimaryGeneratorNeverSelectsDenseInteriorContours() {
        for seed in 0..<100 {
            let recipe = NativeAtlasRecipe.make(dayKey: "safe-fill-\(seed)").reconciled(eventIDs: (0..<10).map(String.init))
            XCTAssertFalse(recipe.actors.contains { $0.materialID == .proceduralContour })
        }
    }

    func testNativeGrainIsSharperThanHistoricalPaperTexture() async throws {
        func render(native: Bool) async -> UIImage? {
            let input = DayObjectSceneInput(dayKey: "2026-09-10", identity: "primary-canvas", eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: native ? .make(dayKey: "2026-09-10") : nil)
            let base = DayObjectScene.make(input: input)
            // Compare the two finish pipelines with the SAME new background.
            // Historical background selection itself must remain unchanged.
            let style = DayObjectMeshGradientStyle.primaryCanvas(seed: UInt64(NativeAtlasRecipe.make(dayKey: input.dayKey).seedHex, radix: 16)!, palette: base.palette)
            let scene = DayObjectScene(input: input, rootSeed: base.rootSeed, composition: base.composition, compositionPlan: base.compositionPlan, paletteSet: base.paletteSet, choreographyConfiguration: base.choreographyConfiguration, visualLanguage: base.visualLanguage, motionPlan: base.motionPlan, palette: base.palette, meshGradientStyle: style, score: base.score, actors: base.actors, sceneRecipeV1: base.sceneRecipeV1)
            DayObjectsRenderer.prepareResources()
            guard let renderer = DayObjectsRenderer.create(scene: scene, environment: .init(motionEnergy: 0.5, visualClarity: 1)) else { return nil }
            return await withCheckedContinuation { continuation in
                renderer.renderOffscreen(size: CGSize(width: 300, height: 400), pointScale: 1, elapsedTime: 4) { texture, _ in
                    continuation.resume(returning: texture.flatMap { DayObjectsImageRenderer.makeImage(texture: $0, scale: 1) })
                }
            }
        }
        let referenceResult = await render(native: false)
        let nativeResult = await render(native: true)
        let reference = try XCTUnwrap(referenceResult)
        let native = try XCTUnwrap(nativeResult)
        let a = try pixels(reference), b = try pixels(native)
        func detail(_ values: [Double]) -> [Double] {
            var result: [Double] = []
            for y in stride(from: 8, to: 392, by: 3) {
                for x in stride(from: 8, to: 292, by: 3) {
                    func l(_ xx: Int, _ yy: Int) -> Double {
                        let i = (yy * 300 + xx) * 4
                        return (values[i] + values[i + 1] + values[i + 2]) / 3
                    }
                    result.append(l(x, y) - (l(x - 1, y) + l(x + 1, y) + l(x, y - 1) + l(x, y + 1)) / 4)
                }
            }
            return result
        }
        let da = detail(a), db = detail(b)
        let originalDetail = da.map { abs($0) }.reduce(0, +) / Double(da.count)
        let newDetail = db.map { abs($0) }.reduce(0, +) / Double(db.count)
        XCTAssertGreaterThan(newDetail, originalDetail * 2, "Photographic grain needs visible fine detail, not only smooth paper fields")
        XCTAssertGreaterThan(newDetail, 0.006)
        XCTAssertLessThan(newDetail, 0.08, "Grain must not overwhelm the artwork")
        for (name, image) in [("restored-native-background", native), ("reference-background", reference)] {
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    private func pixels(_ image: UIImage) throws -> [Double] {
        let data = try XCTUnwrap(image.cgImage?.dataProvider?.data)
        return Array(data as Data).map { Double($0) / 255 }
    }

    @MainActor
    func testNativePickerStartsAsCirclesThenRevealsAndDesaturatesShape() async throws {
        let square = try await pickerImage(presetID: "legacy.soft-square", state: .available)
        let flower = try await pickerImage(presetID: "genome.windflower", state: .available)
        XCTAssertEqual(square.pngData(), flower.pngData(), "Before selection, every item is a circle, not its final silhouette")
        let selected = try await pickerImage(presetID: "legacy.soft-square", state: .additionPreview)
        XCTAssertNotEqual(square.pngData(), selected.pngData(), "First tap must reveal the actual figure")
        let added = try await pickerImage(presetID: "legacy.soft-square", state: .added)
        // Sample the center of the opaque figure, independently of the background.
        let p = try pixels(added), index = (100 * 200 + 100) * 4
        XCTAssertLessThan((p[index..<index + 3].max() ?? 1) - (p[index..<index + 3].min() ?? 0), 0.04)
        for (name, image) in [("picker-1-circle", square), ("picker-2-selected", selected), ("picker-3-added", added)] {
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    @MainActor
    func testAvailableCircleDoesNotInheritItsFutureMaterial() async throws {
        let reference = try await pickerImage(presetID: "legacy.soft-square", state: .available)
        for material in MetalShapeMaterial.allCases {
            let image = try await pickerImage(presetID: "legacy.soft-square", state: .available, material: material)
            XCTAssertEqual(image.pngData(), reference.pngData(), "Available circle changed for \(material)")
        }
    }

    @MainActor
    func testPreviouslySavedDenseFillRendersAsSimpleContour() async throws {
        let dense = try await pickerImage(presetID: "legacy.soft-square", state: .additionPreview, material: .proceduralContour)
        let outline = try await pickerImage(presetID: "legacy.soft-square", state: .additionPreview, material: .contour)
        XCTAssertEqual(dense.pngData(), outline.pngData(), "Already saved bad fills must also stop rendering nested lines")
    }

    @MainActor
    private func pickerImage(presetID: String, state: HappeningPaletteSlotVisualState, material: MetalShapeMaterial = .solid, includesSlot: Bool = true, backgroundColors: [SIMD3<Float>]? = nil) async throws -> UIImage {
        let base = DayObjectSceneInput(dayKey: "2026-09-10", identity: "native-picker-regression", eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true)
        let assignment = try XCTUnwrap(HappeningEditorialAssignmentResolver.assignments(happenings: [.init(id: "h0", title: "Test", isBuiltIn: true)], baseInput: base, colorNonce: 7)["h0"])
        let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == presetID })
        let generated = MetalShapeGenomeFrame.make(preset: preset, material: material, seed: 71)
        let referencePreset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == "legacy.soft-square" })
        let sharedMaterial = MetalShapeGenomeFrame.make(preset: referencePreset, material: material, seed: 71).material
        var recipe = NativeAtlasRecipe.make(dayKey: base.dayKey)
        recipe.actors = [.init(eventID: assignment.elementID.uuidString.lowercased(), presetID: presetID, materialID: material, seedHex: "47", geometry: generated.geometry, material: sharedMaterial, position: SIMD2(0.5, 0.5), size: 0.5, rotation: 0, slot: 0)]
        let input = DayObjectSceneInput(dayKey: base.dayKey, identity: base.identity, eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: recipe)
        let presentation = HappeningPaletteRenderPresentation(slots: includesSlot ? [.init(happeningID: "h0", assignment: assignment, visualState: state, source: .init(index: 0, center: CGPoint(x: 100, y: 100), radius: 60))] : [], viewportSize: CGSize(width: 200, height: 200), reduceMotion: true, isTransitionActive: false, backgroundRevision: 1)
        DayObjectsRenderer.prepareResources()
        var scene = DayObjectScene.make(input: input)
        if let colors = backgroundColors {
            let style = scene.meshGradientStyle
            scene = DayObjectScene(
                input: scene.input, rootSeed: scene.rootSeed, composition: scene.composition,
                compositionPlan: scene.compositionPlan, paletteSet: scene.paletteSet,
                choreographyConfiguration: scene.choreographyConfiguration, visualLanguage: scene.visualLanguage,
                motionPlan: scene.motionPlan, palette: scene.palette,
                meshGradientStyle: .init(colors: colors, archetype: style.archetype, offset: style.offset, distortion: style.distortion, swirl: style.swirl, speed: style.speed, scale: style.scale, phase: style.phase, motionDirection: style.motionDirection, preservesColorFields: true),
                score: scene.score, actors: scene.actors, sceneRecipeV1: scene.sceneRecipeV1
            )
        }
        let renderer = try XCTUnwrap(DayObjectsRenderer.create(scene: scene, environment: .init(motionEnergy: 0.5, visualClarity: 1), presentationMode: .happeningPalette(presentation)))
        let image: UIImage? = await withCheckedContinuation { continuation in
            renderer.renderOffscreen(size: CGSize(width: 200, height: 200), pointScale: 1, elapsedTime: 4) { texture, _ in
                continuation.resume(returning: texture.flatMap { DayObjectsImageRenderer.makeImage(texture: $0, scale: 1) })
            }
        }
        return try XCTUnwrap(image)
    }
    @MainActor
    func testNativePaletteUsesAtlasInsteadOfObsoleteAssignedSilhouette() async throws {
        let input = DayObjectSceneInput(dayKey: "2026-09-10", identity: "native-palette", eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: .make(dayKey: "2026-09-10"))
        let assignment = try XCTUnwrap(HappeningEditorialAssignmentResolver.assignments(happenings: [.init(id: "h0", title: "Test", isBuiltIn: true)], baseInput: input, colorNonce: 7)["h0"])
        DayObjectsRenderer.prepareResources()
        func render(_ rootKey: String) async throws -> Data? {
            let changed = assignment
            var recipe = NativeAtlasRecipe.make(dayKey: input.dayKey)
            recipe.actors = NativeAtlasRecipe.make(dayKey: rootKey).reconciled(eventIDs: [assignment.elementID.uuidString.lowercased()]).actors
            let nativeInput = DayObjectSceneInput(dayKey: input.dayKey, identity: input.identity, eventIDs: [], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: recipe)
            let mode = DayObjectsPresentationMode.happeningPalette(.init(slots: [.init(happeningID: "h0", assignment: changed, visualState: .additionPreview, source: .init(index: 0, center: CGPoint(x: 64, y: 80), radius: 32))], viewportSize: CGSize(width: 128, height: 160), reduceMotion: true, isTransitionActive: false, backgroundRevision: 1))
            let renderer = try XCTUnwrap(DayObjectsRenderer.create(scene: .make(input: nativeInput), environment: .init(motionEnergy: 0.5, visualClarity: 1), presentationMode: mode))
            return await withCheckedContinuation { continuation in
                renderer.renderOffscreen(size: CGSize(width: 128, height: 160), pointScale: 1, elapsedTime: 4) { texture, _ in
                    continuation.resume(returning: texture.flatMap { DayObjectsImageRenderer.makeImage(texture: $0, scale: 1)?.pngData() })
                }
            }
        }
        let sphere = try await render("2026-09-10")
        let lens = try await render("2026-09-11")
        XCTAssertNotNil(sphere)
        XCTAssertNotEqual(sphere, lens)
    }

    func testArtworkLockRetainsBackgroundAndFutureGenerationSeed() {
        var recipe = NativeAtlasRecipe.make(dayKey: "locked").reconciled(eventIDs: ["a"])
        recipe.locks.insert("artwork")
        let changed = recipe.remixed(seedKey: "other")
        XCTAssertEqual(changed.background, recipe.background)
        XCTAssertEqual(changed.seedHex, recipe.seedHex)
        XCTAssertEqual(changed.actors, recipe.actors)
    }

    func testNativeAdapterPreservesEventIdentityAndSoundPulse() throws {
        let recipe = NativeAtlasRecipe.make(dayKey: "sound").reconciled(eventIDs: ["a", "b"])
        let scene = DayObjectScene.make(input: .init(dayKey: "sound", identity: "native", eventIDs: ["a", "b"], motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: recipe))
        let frame = DayObjectRenderFrame.make(scene: scene, environment: .init(motionEnergy: 0.5, visualClarity: 1), elapsed: 3.05, insertions: [:])
        let renderer = try XCTUnwrap(NativeAtlasMetalRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice())))
        let original = renderer.adapt(frame, recipe: recipe, aspect: 0.8, elapsed: 3.05)
        let pulsed = renderer.adapt(frame, recipe: recipe, aspect: 0.8, elapsed: 3.05, soundPulses: ["a": 3])
        XCTAssertEqual(Set(pulsed.actors.map(\.eventID)), ["a", "b"])
        for actor in pulsed.actors {
            let before = try XCTUnwrap(original.actors.first { $0.eventID == actor.eventID })
            XCTAssertEqual(actor.gpuActor.position, before.gpuActor.position)
            XCTAssertEqual(actor.gpuActor.opacity, before.gpuActor.opacity)
            if actor.eventID == "a" { XCTAssertGreaterThan(actor.halfSize.x, before.halfSize.x) }
            else { XCTAssertEqual(actor.halfSize, before.halfSize) }
        }
    }

    func testAllNativeTraceTypesAreNoOpAtZeroAndChangeTheImageAtFullStrength() async throws {
        var recipe = NativeAtlasRecipe.make(dayKey: "trace-probe").reconciled(eventIDs: (0..<10).map(String.init))
        var pristine: Data?
        for type in 0..<5 {
            recipe.glitchType = type
            func render(_ strength: Float) async -> Data? {
                var configured = recipe
                configured.glitchStrength = strength
                let input = EditorialCanvasRenderInput(sceneInput: .init(dayKey: "trace-probe", identity: "native", eventIDs: (0..<10).map(String.init), motionEnergy: 0.5, visualClarity: 1, usesEditorialField: true, nativeAtlasRecipe: configured), digitalImpact: .none)
                return await DayObjectsImageRenderer.image(input: input, size: CGSize(width: 300, height: 400), scale: 1, elapsedTime: 4)?.pngData()
            }
            let zero = await render(0)
            let full = await render(1)
            XCTAssertNotNil(zero)
            if let pristine { XCTAssertEqual(zero, pristine) } else { pristine = zero }
            XCTAssertNotEqual(zero, full, "Trace \(type) must affect visible pixels")
        }
    }
    func testNewStoredCanvasUsesAtlasWithoutMigratingExistingCanvas() {
        let key = "native-atlas-test-\(UUID().uuidString)"
        let storage = CanvasStorageService.shared
        defer { storage.deleteCanvas(for: key) }
        let fresh = storage.loadOrCreateCanvas(for: key)
        XCTAssertTrue(fresh.artworkRecipe?.isSupported == true)
        XCTAssertEqual(fresh.resolvedVisualStyle, .editorial)
        storage.saveCanvas(DayCanvas(dayKey: key))
        XCTAssertNil(storage.loadOrCreateCanvas(for: key).artworkRecipe)
    }

    func testNativeCanvasRespondsToClarityAndColorSelection() async throws {
        let recipe = NativeAtlasRecipe.make(dayKey: "2026-09-10").reconciled(eventIDs: ["a", "b", "c"])
        func input(clarity: Double, variant: Int?) -> EditorialCanvasRenderInput {
            .init(sceneInput: .init(dayKey: "2026-09-10", identity: "native-test", eventIDs: ["a", "b", "c"], motionEnergy: 0.5, visualClarity: clarity, usesEditorialField: true, actorColorVariants: variant.map { ["a": $0, "b": $0, "c": $0] } ?? [:], nativeAtlasRecipe: recipe), digitalImpact: .none)
        }
        let original = await DayObjectsImageRenderer.image(input: input(clarity: 1, variant: nil), size: CGSize(width: 240, height: 300), scale: 1, elapsedTime: 4)
        let sleepy = await DayObjectsImageRenderer.image(input: input(clarity: 0, variant: nil), size: CGSize(width: 240, height: 300), scale: 1, elapsedTime: 4)
        let recolored = await DayObjectsImageRenderer.image(input: input(clarity: 1, variant: 3), size: CGSize(width: 240, height: 300), scale: 1, elapsedTime: 4)
        XCTAssertNotNil(original)
        XCTAssertNotEqual(original?.pngData(), sleepy?.pngData())
        XCTAssertNotEqual(original?.pngData(), recolored?.pngData())
        if let original {
            let attachment = XCTAttachment(image: original)
            attachment.name = "native-atlas-preview"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    func testNativeMetalRendersDeterministicallyAndGlitchChangesPixels() async throws {
        let recipe = NativeAtlasRecipe.make(dayKey: "2026-09-10").reconciled(eventIDs: ["a", "b", "c"])
        let scene = DayObjectSceneInput(dayKey: "2026-09-10", identity: "native-test", eventIDs: ["a", "b", "c"], motionEnergy: 0.5, visualClarity: 0.8, usesEditorialField: true, nativeAtlasRecipe: recipe)
        let input = EditorialCanvasRenderInput(sceneInput: scene, digitalImpact: .none)
        let first = await DayObjectsImageRenderer.image(input: input, size: CGSize(width: 160, height: 200), scale: 1, elapsedTime: 4)
        let second = await DayObjectsImageRenderer.image(input: input, size: CGSize(width: 160, height: 200), scale: 1, elapsedTime: 4)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.pngData(), second?.pngData())
        let damaged = await DayObjectsImageRenderer.image(input: .init(sceneInput: scene, digitalImpact: .init(spentColors: 100)), size: CGSize(width: 160, height: 200), scale: 1, elapsedTime: 4)
        XCTAssertNotNil(damaged)
        XCTAssertNotEqual(first?.pngData(), damaged?.pngData())
    }
    func testHistoricalCanvasDoesNotAcquireRecipeWhenDecoded() throws {
        let canvas = DayCanvas(dayKey: "2026-08-01")
        let data = try JSONEncoder().encode(canvas)
        let decoded = try JSONDecoder().decode(DayCanvas.self, from: data)
        XCTAssertNil(decoded.artworkRecipe)
    }

    func testRecipeRoundTripAndEventReconciliationAreStable() throws {
        let recipe = NativeAtlasRecipe.make(dayKey: "2026-09-10")
            .reconciled(eventIDs: ["a", "b", "a"])
        XCTAssertEqual(recipe.actors.map(\.eventID), ["a", "b"])
        XCTAssertEqual(recipe, NativeAtlasRecipe.make(dayKey: "2026-09-10").reconciled(eventIDs: ["a", "b"]))
        XCTAssertEqual(recipe, try JSONDecoder().decode(NativeAtlasRecipe.self, from: JSONEncoder().encode(recipe)))
        let expanded = recipe.reconciled(eventIDs: ["a", "b", "c"])
        XCTAssertEqual(Array(expanded.actors.prefix(2)), recipe.actors)
        XCTAssertEqual(expanded.reconciled(eventIDs: ["b"]).actors, [recipe.actors[1]])
        XCTAssertEqual(recipe.reconciled(eventIDs: []).actors.count, 0)
        XCTAssertEqual(recipe.reconciled(eventIDs: (0..<20).map(String.init)).actors.count, 10)
    }

    func testSelectedMaterialsAreCompatibleAndUnknownVersionsAreNotRegenerated() {
        for day in 1...50 {
            let recipe = NativeAtlasRecipe.make(dayKey: "test-\(day)").reconciled(eventIDs: (0..<10).map(String.init))
            for actor in recipe.actors {
                let preset = MetalShapeGenomeCatalog.presets.first { $0.id == actor.presetID }!
                XCTAssertTrue(preset.compatibility.allowed.contains(actor.materialID))
                if actor.materialID == .sunset { XCTAssertEqual(actor.presetID, "legacy.circle") }
            }
        }
        var future = NativeAtlasRecipe.make(dayKey: "future")
        future.schemaVersion = 99
        XCTAssertEqual(future.reconciled(eventIDs: ["new"]), future)
    }
}
