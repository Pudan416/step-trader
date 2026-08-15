import XCTest
@testable import Steps4

/// Guards the `isLoading` lifecycle of the Apple sign-in flow.
///
/// `AuthenticationService` is a process-lifetime singleton, so a leaked
/// `isLoading == true` is permanent: `LoginView` keeps the Sign in with Apple
/// button `.disabled(...)` and the ProgressView spinning until the app is
/// killed. Every exit path out of the sign-in task therefore has to clear it.
@MainActor
final class AuthSignInLoadingStateTests: XCTestCase {

    func testTokenExchangeTimeoutStopsLoadingAndSurfacesConnectivityError() async {
        let service = AuthenticationService.shared
        defer {
            service.isLoading = false
            service.error = nil
        }

        await service.runSignIn(
            idToken: "apple-id-token",
            nonce: "nonce",
            appleFullName: nil,
            exchangeTimeout: .milliseconds(10)
        ) { _, _ in
            try await Task.sleep(for: .milliseconds(100))
            throw URLError(.cannotConnectToHost)
        }

        XCTAssertFalse(service.isLoading)
        XCTAssertEqual(
            service.error,
            "Couldn't reach the server. Please check your connection and try again."
        )
    }

    /// `signOut()` and `deleteAccount()` both call `signInTask?.cancel()`. When
    /// that cancellation lands *after* the Supabase token exchange has already
    /// returned a session, the flow bails out at `guard !Task.isCancelled`
    /// instead of reaching the optimistic-success or `catch` reset — that exit
    /// has to clear the spinner too.
    func testSignInCancelledAfterTokenExchangeLeavesIsLoadingFalse() async throws {
        let service = AuthenticationService.shared
        defer {
            service.isLoading = false
            service.error = nil
        }

        let session = try Self.makeSession()

        let signIn = Task { @MainActor in
            await service.runSignIn(idToken: "apple-id-token", nonce: "nonce", appleFullName: nil) { _, _ in
                // Cancel the enclosing sign-in task mid-exchange, then hand back
                // a valid session: the flow resumes, sees `Task.isCancelled` and
                // takes the discard-the-session early return.
                withUnsafeCurrentTask { $0?.cancel() }
                return session
            }
        }
        await signIn.value

        XCTAssertFalse(
            service.isLoading,
            "Sign-in cancelled after the token exchange must clear isLoading — a leaked true permanently disables the Sign in with Apple button"
        )
    }

    // MARK: - Helpers

    /// A syntactically valid GoTrue session. Decoded rather than constructed:
    /// `SupabaseSessionResponse` has no memberwise init.
    private static func makeSession() throws -> SupabaseSessionResponse {
        let json = """
        {
          "access_token": "test-access-token",
          "token_type": "bearer",
          "expires_in": 3600,
          "refresh_token": "test-refresh-token",
          "expires_at": "2099-01-01T00:00:00Z",
          "user": {
            "id": "00000000-0000-0000-0000-000000000000",
            "email": "tester@example.com",
            "created_at": "2024-01-01T00:00:00Z",
            "is_anonymous": false
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SupabaseSessionResponse.self, from: Data(json.utf8))
    }
}
