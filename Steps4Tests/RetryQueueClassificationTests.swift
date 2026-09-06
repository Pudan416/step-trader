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

        let remove = store.mark(id: uppercase)
        XCTAssertEqual(store.operation(for: remove, desiredEntries: []), .delete(id: uppercase))
        let readd = store.mark(id: lowercase)
        XCTAssertEqual(store.operation(for: readd, desiredEntries: [entry]), .upsert(entry))
        let finalRemove = store.mark(id: uppercase)
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

        let readd = store.mark(id: id)
        let failedUpsert = OptionEntryIntentOperation.upsert(entry)
        XCTAssertFalse(store.finishAttempt(readd, operation: failedUpsert, succeeded: false, latestDesiredEntries: [entry]))
        XCTAssertEqual(store.operation(for: readd, desiredEntries: [entry]), failedUpsert)

        let finalRemove = store.mark(id: id.lowercased())
        XCTAssertEqual(store.operation(for: finalRemove, desiredEntries: []), .delete(id: id.lowercased()))
        XCTAssertNotNil(store.pending(canonicalID: finalRemove.canonicalID))
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
