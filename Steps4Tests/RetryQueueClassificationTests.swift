import XCTest
@testable import Steps4

/// Guards the offline sync retry-queue drain policy: transient failures are
/// retried, permanent 4xx are dropped. Regression guard for the bug where
/// `drainRetryQueue` re-queued *any* status >= 400, so a permanent 400/409
/// replayed on every launch for the full 3-day TTL.
final class RetryQueueClassificationTests: XCTestCase {

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "RetryQueueClassificationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    func testTransientStatusesAreRetried() {
        for status in [408, 429, 500, 502, 503, 504] {
            XCTAssertTrue(
                SupabaseSyncService.retryQueueShouldKeep(afterStatus: status),
                "HTTP \(status) is transient and should stay queued for retry"
            )
        }
    }

    func testPermanentClientErrorsAreDropped() {
        for status in [400, 401, 403, 404, 409, 410, 422] {
            XCTAssertFalse(
                SupabaseSyncService.retryQueueShouldKeep(afterStatus: status),
                "HTTP \(status) is permanent and should be dropped, not retried for 3 days"
            )
        }
    }

    func testSuccessIsNotRetried() {
        for status in [200, 201, 204] {
            XCTAssertFalse(
                SupabaseSyncService.retryQueueShouldKeep(afterStatus: status),
                "HTTP \(status) succeeded and must never be re-queued"
            )
        }
    }

    func testFailedDeleteThenSameIdentityReAddIsSupersededBeforeDrain() {
        let entryID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let failedDeletes = [entryID]
        let readded = OptionEntry(
            id: entryID.lowercased(),
            dayKey: "2026-09-06",
            optionId: "happening_walk",
            colorHex: "#A1B2C3",
            timestamp: Date(timeIntervalSince1970: 1_786_176_000),
            assetVariant: 2
        )

        XCTAssertEqual(
            OptionEntryRetrySupersession.deleteIDsToReplay(
                failedDeleteIDs: failedDeletes,
                desiredEntries: [readded]
            ),
            []
        )
        XCTAssertEqual(
            OptionEntryRetrySupersession.deleteIDsToReplay(
                failedDeleteIDs: failedDeletes,
                desiredEntries: []
            ),
            failedDeletes
        )
        XCTAssertEqual(
            OptionEntryRetrySupersession.recoveryEntry(
                afterReplayingDeleteID: entryID,
                latestDesiredEntries: [readded]
            ),
            readded
        )
        XCTAssertNil(
            OptionEntryRetrySupersession.recoveryEntry(
                afterReplayingDeleteID: entryID,
                latestDesiredEntries: []
            )
        )
    }

    func testCanonicalOptionEntryIdentityNormalizesUUIDCaseButPreservesLegacyCase() {
        let uppercase = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let lowercase = uppercase.lowercased()

        XCTAssertEqual(
            OptionEntryCanonicalIdentity.key(for: uppercase),
            OptionEntryCanonicalIdentity.key(for: lowercase)
        )
        XCTAssertNotEqual(
            OptionEntryCanonicalIdentity.key(for: "legacy-Walk"),
            OptionEntryCanonicalIdentity.key(for: "legacy-walk")
        )

        let tagged = SupabasePendingSyncRequest(
            urlString: "https://example.supabase.co/rest/v1/user_happening_additions?id=eq.ignored",
            method: "DELETE",
            body: nil,
            preferHeader: nil,
            createdAt: Date(timeIntervalSince1970: 1_786_176_000),
            optionEntryDeleteID: uppercase
        )
        let legacyURL = SupabasePendingSyncRequest(
            urlString: "https://example.supabase.co/rest/v1/user_happening_additions?id=eq.\(lowercase)&user_id=eq.user",
            method: "DELETE",
            body: nil,
            preferHeader: nil,
            createdAt: Date(timeIntervalSince1970: 1_786_176_000),
            optionEntryDeleteID: nil
        )

        XCTAssertEqual(tagged.canonicalOptionEntryIdentity, legacyURL.canonicalOptionEntryIdentity)
    }

    func testLegacyRawOptionUpsertCanBeConvertedToDurableIdentityIntent() throws {
        let id = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let body = try JSONSerialization.data(withJSONObject: [[
            "id": id.lowercased(),
            "user_id": "user",
            "day_key": "2026-09-07",
            "option_id": "happening_walk",
            "color_hex": "#A1B2C3",
            "asset_variant": NSNull(),
            "created_at": "2026-09-07T08:00:00Z"
        ]])
        let request = SupabasePendingSyncRequest(
            urlString: "https://example.supabase.co/rest/v1/user_happening_additions?on_conflict=id",
            method: "POST",
            body: body,
            preferHeader: "resolution=merge-duplicates",
            createdAt: .now,
            optionEntryDeleteID: nil
        )

        XCTAssertEqual(request.optionEntryMutations?.first?.ownerUserID, "user")
        if case .upsert(let restored) = request.optionEntryMutations?.first?.operation {
            XCTAssertEqual(restored.dayKey, "2026-09-07")
            XCTAssertEqual(restored.optionId, "happening_walk")
        } else { XCTFail("Legacy POST must remain an upsert after rollover") }
        XCTAssertTrue(request.isOptionEntryMutation)
        XCTAssertEqual(request.resolvedOptionEntryMutationIDs, [id.lowercased()])
        XCTAssertEqual(
            request.resolvedOptionEntryMutationIDs.map(OptionEntryCanonicalIdentity.key(for:)),
            [id]
        )
    }

    func testRetryDrainSnapshotRemainsDurableUntilAcknowledgedAndPreservesConcurrentEnqueue() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SupabaseRetryQueuePersistence(
            defaults: defaults,
            key: "retry-queue",
            maximumCount: 50
        )
        let first = SupabasePendingSyncRequest(
            queueID: "first",
            urlString: "https://example.supabase.co/rest/v1/a",
            method: "POST",
            body: Data("one".utf8),
            preferHeader: nil,
            createdAt: Date.now,
            optionEntryDeleteID: nil
        )
        let second = SupabasePendingSyncRequest(
            queueID: "second",
            urlString: "https://example.supabase.co/rest/v1/b",
            method: "POST",
            body: Data("two".utf8),
            preferHeader: nil,
            createdAt: Date.now,
            optionEntryDeleteID: nil
        )
        let concurrent = SupabasePendingSyncRequest(
            queueID: "concurrent",
            urlString: "https://example.supabase.co/rest/v1/c",
            method: "POST",
            body: Data("three".utf8),
            preferHeader: nil,
            createdAt: Date.now,
            optionEntryDeleteID: nil
        )

        store.save([first, second])
        let snapshot = store.loadUnexpired(now: .now)
        XCTAssertEqual(store.load().map(\.queueID), ["first", "second"], "Taking a drain snapshot must not clear unacknowledged work")

        store.append(concurrent)
        store.removeAcknowledged(queueIDs: [first.queueID])

        XCTAssertEqual(Set(store.load().map(\.queueID)), ["second", "concurrent"])
        XCTAssertEqual(snapshot.map(\.queueID), ["first", "second"])
    }

    func testLatestIntentPersistenceConvergesAcrossRemoveReaddRemove() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "entry-intents")
        let uppercase = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let lowercase = uppercase.lowercased()
        let entry = OptionEntry(
            id: lowercase,
            dayKey: "2026-09-07",
            optionId: "happening_walk",
            colorHex: "#A1B2C3",
            timestamp: Date(timeIntervalSince1970: 1_786_262_400),
            assetVariant: 2
        )

        let remove = store.mark(.delete(id: uppercase))
        XCTAssertEqual(store.operation(for: remove, desiredEntries: []), .delete(id: uppercase))
        let readd = store.mark(.upsert(entry))
        XCTAssertEqual(store.operation(for: readd, desiredEntries: [entry]), .upsert(entry))
        let finalRemove = store.mark(.delete(id: uppercase))
        XCTAssertEqual(store.operation(for: finalRemove, desiredEntries: []), .delete(id: uppercase))

        XCTAssertFalse(store.finishAttempt(remove, operation: .delete(id: uppercase), succeeded: true, latestDesiredEntries: []))
        XCTAssertFalse(store.finishAttempt(readd, operation: .upsert(entry), succeeded: true, latestDesiredEntries: []))
        XCTAssertNotNil(store.pending(canonicalID: finalRemove.canonicalID))
        XCTAssertTrue(store.finishAttempt(finalRemove, operation: .delete(id: uppercase), succeeded: true, latestDesiredEntries: []))
        XCTAssertNil(store.pending(canonicalID: finalRemove.canonicalID))
    }

    func testFailedRecoveryUpsertStaysPendingAndFollowsFinalDesiredRemoval() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "entry-intents")
        let id = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let entry = OptionEntry(
            id: id.lowercased(),
            dayKey: "2026-09-07",
            optionId: "happening_walk",
            colorHex: "#A1B2C3",
            timestamp: Date(timeIntervalSince1970: 1_786_262_400),
            assetVariant: nil
        )

        let readd = store.mark(.upsert(entry))
        let failedUpsert = OptionEntryIntentOperation.upsert(entry)
        XCTAssertFalse(store.finishAttempt(readd, operation: failedUpsert, succeeded: false, latestDesiredEntries: [entry]))
        XCTAssertEqual(store.operation(for: readd, desiredEntries: [entry]), failedUpsert)

        let finalRemove = store.mark(.delete(id: id.lowercased()))
        XCTAssertEqual(store.operation(for: finalRemove, desiredEntries: []), .delete(id: id.lowercased()))
        XCTAssertNotNil(store.pending(canonicalID: finalRemove.canonicalID))
    }

    func testPendingUpsertSurvivesRolloverAndStoreReload() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "entry-intents")
        let entry = OptionEntry(id: UUID().uuidString, dayKey: "2026-09-11", optionId: "walk",
            colorHex: "#A1B2C3", timestamp: .now, assetVariant: 2)
        let saved = store.mark(.upsert(entry), ownerUserID: "owner-a")
        let reloaded = try XCTUnwrap(OptionEntryIntentPersistence(defaults: defaults, key: "entry-intents")
            .pending(canonicalID: saved.canonicalID))
        XCTAssertEqual(reloaded.ownerUserID, "owner-a")
        XCTAssertEqual(store.operation(for: reloaded, desiredEntries: []), .upsert(entry))
        XCTAssertTrue(store.finishAttempt(reloaded, operation: .upsert(entry), succeeded: true, latestDesiredEntries: []))
    }

    func testLegacyIdentityOnlyMarkerCannotDeleteMissingHistoricalEntry() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: [id: ["canonicalID": id, "requestedID": id, "version": 1]])
        defaults.set(data, forKey: "entry-intents")
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "entry-intents")
        let legacy = try XCTUnwrap(store.pending(canonicalID: id))
        XCTAssertNil(store.operation(for: legacy, desiredEntries: []))
    }

    func testRawHistoricalPostUpgradesCoexistingIdentityOnlyMarker() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID().uuidString
        defaults.set(try JSONSerialization.data(withJSONObject: [id: ["canonicalID": id, "requestedID": id, "version": 1]]), forKey: "intents")
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "intents")
        let row: [String: Any] = ["id": id, "user_id": "owner-a", "day_key": "2026-09-11",
            "option_id": "walk", "color_hex": "#FFFFFF", "created_at": "2026-09-11T08:00:00Z"]
        let request = SupabasePendingSyncRequest(urlString: "https://example.supabase.co/rest/v1/user_happening_additions",
            method: "POST", body: try JSONSerialization.data(withJSONObject: [row]), preferHeader: nil,
            createdAt: .now, optionEntryDeleteID: nil)
        XCTAssertEqual(store.migrateLegacyRequests([request]), [request.queueID])
        let upgraded = try XCTUnwrap(store.pending(canonicalID: id))
        XCTAssertEqual(upgraded.ownerUserID, "owner-a")
        guard case .upsert(let entry) = store.operation(for: upgraded, desiredEntries: []) else {
            return XCTFail("Historical payload was discarded behind identity-only marker")
        }
        XCTAssertEqual(entry.dayKey, "2026-09-11")
        XCTAssertEqual(entry.optionId, "walk")
        // A newer explicit removal must still supersede a stale raw upsert.
        let deletion = store.mark(.delete(id: id), ownerUserID: "owner-a")
        _ = store.migrateLegacyRequests([request])
        XCTAssertEqual(store.pending(canonicalID: id), deletion)
    }

    func testStaleBatchSnapshotAfterRolloverCannotSupersedeLaterDeletion() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "intents")
        let entry = OptionEntry(id: UUID().uuidString, dayKey: "2026-09-11", optionId: "walk",
            colorHex: "#FFFFFF", timestamp: .now, assetVariant: nil)
        _ = store.recordUpsert(entry, desiredEntries: [entry], currentDayKey: "2026-09-11", ownerUserID: "owner")
        let deletion = store.mark(.delete(id: entry.id), ownerUserID: "owner")
        let replay = store.recordUpsert(entry, desiredEntries: [], currentDayKey: "2026-09-12", ownerUserID: "owner")
        XCTAssertEqual(replay, deletion)
        // A real re-add, present in local state, can still supersede removal.
        let readded = store.recordUpsert(entry, desiredEntries: [entry], currentDayKey: "2026-09-12", ownerUserID: "owner")
        XCTAssertEqual(readded.savedOperation, .upsert(entry))
    }

    func testPendingIntentCannotBeReassignedToAnotherAccountOrSignedOutSession() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "intents")
        let entry = OptionEntry(id: UUID().uuidString, dayKey: "2026-09-11", optionId: "walk",
            colorHex: "#FFFFFF", timestamp: .now, assetVariant: nil)
        let original = store.mark(.upsert(entry), ownerUserID: "owner-a")
        let otherAccount = store.recordUpsert(entry, desiredEntries: [entry], currentDayKey: entry.dayKey, ownerUserID: "owner-b")
        XCTAssertEqual(otherAccount, original)
        XCTAssertEqual(store.mark(.delete(id: entry.id), ownerUserID: "owner-b"), original)
        XCTAssertEqual(store.mark(.delete(id: entry.id), ownerUserID: nil), original)
        XCTAssertEqual(store.pending(canonicalID: original.canonicalID), original)
        // The original account can still edit its own pending entry.
        let removal = store.mark(.delete(id: entry.id), ownerUserID: "owner-a")
        XCTAssertEqual(removal.savedOperation, .delete(id: entry.id))
        XCTAssertGreaterThan(removal.version, original.version)
    }

    func testMigratedRawOwnerSurvivesNextAccountsFullSyncRegistration() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OptionEntryIntentPersistence(defaults: defaults, key: "intents")
        let entry = OptionEntry(id: UUID().uuidString, dayKey: "2026-09-11", optionId: "walk",
            colorHex: "#FFFFFF", timestamp: Date(timeIntervalSince1970: 1_789_113_600), assetVariant: nil)
        let row: [String: Any] = ["id": entry.id, "user_id": "owner-a", "day_key": entry.dayKey,
            "option_id": entry.optionId, "color_hex": entry.colorHex, "created_at": "2026-09-11T08:00:00Z"]
        let request = SupabasePendingSyncRequest(urlString: "https://example.supabase.co/rest/v1/user_happening_additions",
            method: "POST", body: try JSONSerialization.data(withJSONObject: [row]), preferHeader: nil,
            createdAt: .now, optionEntryDeleteID: nil)
        _ = store.migrateLegacyRequests([request])
        let migrated = try XCTUnwrap(store.pending(canonicalID: entry.id))
        let nextLogin = store.recordUpsert(entry, desiredEntries: [entry], currentDayKey: entry.dayKey, ownerUserID: "owner-b")
        XCTAssertEqual(nextLogin, migrated)
        XCTAssertEqual(nextLogin.ownerUserID, "owner-a")
        XCTAssertEqual(store.pending(canonicalID: entry.id), migrated)
    }

    func testDelayedUpsertPreservesYesterdayButRespectsTodaysRemoval() {
        let entry = OptionEntry(id: UUID().uuidString, dayKey: "2026-09-11", optionId: "walk",
            colorHex: "#A1B2C3", timestamp: .now, assetVariant: nil)
        XCTAssertEqual(OptionEntryIntentOperation.upsertIntent(entry, desiredEntries: [], currentDayKey: "2026-09-12"), .upsert(entry))
        XCTAssertEqual(OptionEntryIntentOperation.upsertIntent(entry, desiredEntries: [], currentDayKey: "2026-09-11"), .delete(id: entry.id))
    }

    func testAttemptCoordinatorDoesNotAcknowledgeFinalIntentWhileOlderRequestsAreInFlight() async {
        let coordinator = OptionEntryIntentAttemptCoordinator()
        let identity = OptionEntryCanonicalIdentity.key(for: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let firstDelete = await coordinator.begin(canonicalID: identity, version: 1)
        let readd = await coordinator.begin(canonicalID: identity, version: 2)
        let finalDelete = await coordinator.begin(canonicalID: identity, version: 3)

        let finalDeleteResult = await coordinator.finish(
            finalDelete,
            succeeded: true,
            currentVersion: 3,
            operationStillCurrent: true
        )
        XCTAssertEqual(finalDeleteResult, .retryLatest)
        let readdResult = await coordinator.finish(
            readd,
            succeeded: true,
            currentVersion: 3,
            operationStillCurrent: false
        )
        XCTAssertEqual(readdResult, .retryLatest)
        let firstDeleteResult = await coordinator.finish(
            firstDelete,
            succeeded: true,
            currentVersion: 3,
            operationStillCurrent: false
        )
        XCTAssertEqual(firstDeleteResult, .retryLatest)

        let settlingDelete = await coordinator.begin(canonicalID: identity, version: 3)
        let settlingResult = await coordinator.finish(
            settlingDelete,
            succeeded: true,
            currentVersion: 3,
            operationStillCurrent: true
        )
        XCTAssertEqual(settlingResult, .acknowledge)
    }
}
