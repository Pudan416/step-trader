import XCTest
@testable import Steps4

/// Guards the offline sync retry-queue drain policy: transient failures are
/// retried, permanent 4xx are dropped. Regression guard for the bug where
/// `drainRetryQueue` re-queued *any* status >= 400, so a permanent 400/409
/// replayed on every launch for the full 3-day TTL.
final class RetryQueueClassificationTests: XCTestCase {

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
}
