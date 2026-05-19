import XCTest
@testable import Steps4

@MainActor
final class AuthSessionRestoreTests: XCTestCase {

    func testSessionExpiredIsInvalidating() {
        XCTAssertTrue(AuthenticationService.shared.isSessionInvalidatingError(AuthError.sessionExpired))
    }

    func testNetworkErrorIsTransient() {
        let error = NetworkClient.NetworkError.transport(URLError(.notConnectedToInternet))
        XCTAssertFalse(AuthenticationService.shared.isSessionInvalidatingError(error))
    }

    func testSupabaseServerErrorIsTransient() {
        XCTAssertFalse(
            AuthenticationService.shared.isSessionInvalidatingError(
                AuthError.supabaseError("upstream timeout")
            )
        )
    }

    func testInvalidGrantIsInvalidating() {
        XCTAssertTrue(
            AuthenticationService.shared.isSessionInvalidatingError(
                AuthError.supabaseError("invalid_grant: refresh token revoked")
            )
        )
    }

    func testCachedProfileRoundTrip() throws {
        let service = AuthenticationService.shared
        let userId = "test-user-\(UUID().uuidString)"
        defer { service.clearCachedProfile(for: userId) }

        let user = AppUser(
            id: userId,
            email: "a@b.com",
            nickname: "Tester",
            country: "US",
            avatarData: nil,
            createdAt: .now,
            appleDisplayName: "Apple Name",
            hasSetCustomNickname: true
        )
        service.persistCachedProfile(user)

        let loaded = service.loadCachedProfile(for: userId)
        XCTAssertEqual(loaded?.id, userId)
        XCTAssertEqual(loaded?.nickname, "Tester")
        XCTAssertEqual(loaded?.country, "US")
        XCTAssertEqual(loaded?.displayName, "Tester")
    }
}
