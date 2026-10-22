import XCTest
@testable import Nowhere

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

/// Completes real REST requests in a controlled order; no Supabase traffic.
@MainActor
final class AuthSessionGenerationTests: XCTestCase {
    private var service: AuthenticationService!
    private var urlSession: URLSession!
    private var savedKeychain: Data?
    private var savedLegacy: Data?
    private let legacyKey = "supabaseSession_v1"
    private let userA = "auth-race-a"
    private let userB = "auth-race-b"
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    override func setUp() async throws {
        try await super.setUp()
        await AuthenticationService.shared.waitForInitialization()
        savedKeychain = SessionKeychain.loadSession()
        savedLegacy = UserDefaults.standard.data(forKey: legacyKey)
        SessionKeychain.deleteSession()
        UserDefaults.standard.removeObject(forKey: legacyKey)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthRaceResponseProtocol.self]
        urlSession = URLSession(configuration: configuration)
        service = AuthenticationService(network: NetworkClient(session: urlSession), restoreSession: false)
    }

    override func tearDown() async throws {
        AuthRaceResponseProtocol.onRequest = nil
        urlSession.invalidateAndCancel()
        service.clearCachedProfile(for: userA)
        service.clearCachedProfile(for: userB)
        SessionKeychain.deleteSession()
        if let savedKeychain { _ = SessionKeychain.saveSession(savedKeychain) }
        UserDefaults.standard.set(savedLegacy, forKey: legacyKey)
        service = nil
        try await super.tearDown()
    }

    func testRestoreSuccessAndErrorsCannotUndoSignOut() async throws {
        for status in [200, 401, 418] {
            seed(try session(userA))
            let started = expectation(description: "profile request \(status)")
            var pending: AuthRaceResponseProtocol?
            AuthRaceResponseProtocol.onRequest = { request in
                pending = request
                started.fulfill()
            }
            let restore = Task { await service.checkAuthenticationState() }
            await fulfillment(of: [started], timeout: 2)
            XCTAssertEqual(service.currentUser?.id, userA)
            service.signOut()
            try XCTUnwrap(pending).respond(status: status, data: Data("[]".utf8))
            await restore.value
            assertSignedOut()
        }
    }

    func testRefreshCannotStoreTokenAfterSignOut() async throws {
        seed(try session(userA, expired: true))
        let started = expectation(description: "refresh request")
        var pending: AuthRaceResponseProtocol?
        AuthRaceResponseProtocol.onRequest = { request in
            pending = request
            started.fulfill()
        }
        let refresh = Task { await service.freshAccessToken() }
        await fulfillment(of: [started], timeout: 2)
        service.signOut()
        try XCTUnwrap(pending).respond(data: try encoder.encode(session(userA)))
        let token = await refresh.value
        XCTAssertNil(token)
        assertSignedOut()
    }

    func testOldProfileSuccessAndErrorsCannotReplaceNewSignIn() async throws {
        for status in [200, 401, 418] {
            seed(try session(userA))
            let started = expectation(description: "old profile request \(status)")
            var oldRequest: AuthRaceResponseProtocol?
            AuthRaceResponseProtocol.onRequest = { request in
                if request.request.value(forHTTPHeaderField: "authorization") == "Bearer token-auth-race-a" {
                    oldRequest = request
                    started.fulfill()
                } else {
                    request.respond(data: Data("[]".utf8))
                }
            }
            let restore = Task { await service.checkAuthenticationState() }
            await fulfillment(of: [started], timeout: 2)
            let newSession = try session(userB)
            await service.runSignIn(idToken: "test", nonce: "test", appleFullName: nil) { _, _ in newSession }
            XCTAssertEqual(service.currentUser?.id, userB)
            let newToken = SessionKeychain.loadSession()
            try XCTUnwrap(oldRequest).respond(status: status, data: Data("[]".utf8))
            await restore.value
            XCTAssertEqual(service.currentUser?.id, userB)
            XCTAssertTrue(service.isAuthenticated)
            XCTAssertEqual(SessionKeychain.loadSession(), newToken)
            XCTAssertNil(service.error)
        }
    }

    func testAnonymousSignupCannotUndoSignOut() async throws {
        let started = expectation(description: "anonymous signup")
        var pending: AuthRaceResponseProtocol?
        AuthRaceResponseProtocol.onRequest = { request in
            pending = request
            started.fulfill()
        }
        let restore = Task { await service.checkAuthenticationState() }
        await fulfillment(of: [started], timeout: 2)
        service.signOut()
        try XCTUnwrap(pending).respond(data: try encoder.encode(session(userA)))
        await restore.value
        assertSignedOut()
    }

    func testRefreshStartedDuringAppleExchangeCannotReplaceNewAccount() async throws {
        seed(try session(userA, expired: true))
        let exchangeStarted = expectation(description: "Apple exchange started")
        var exchangeResult: CheckedContinuation<SupabaseSessionResponse, Never>?
        let signIn = Task {
            await service.runSignIn(idToken: "test", nonce: "test", appleFullName: nil) { _, _ in
                await withCheckedContinuation { continuation in
                    exchangeResult = continuation
                    exchangeStarted.fulfill()
                }
            }
        }
        await fulfillment(of: [exchangeStarted], timeout: 2)
        let refreshStarted = expectation(description: "old token refresh started during exchange")
        var oldRefresh: AuthRaceResponseProtocol?
        AuthRaceResponseProtocol.onRequest = { request in
            if request.request.url?.path == "/auth/v1/token" {
                oldRefresh = request
                refreshStarted.fulfill()
            } else {
                request.respond(data: Data("[]".utf8))
            }
        }
        let refresh = Task { await service.freshAccessToken() }
        await fulfillment(of: [refreshStarted], timeout: 2)
        try XCTUnwrap(exchangeResult).resume(returning: session(userB))
        await signIn.value
        let newToken = SessionKeychain.loadSession()
        try XCTUnwrap(oldRefresh).respond(data: try encoder.encode(session(userA)))
        let staleToken = await refresh.value
        XCTAssertNil(staleToken)
        XCTAssertEqual(service.currentUser?.id, userB)
        XCTAssertEqual(SessionKeychain.loadSession(), newToken)
    }

    func testProfileUpdateCannotReloadUserAfterSignOut() async throws {
        seed(try session(userA))
        service.applyCachedSessionState(userId: userA, email: nil, createdAt: .now)
        let started = expectation(description: "profile patch")
        var pending: AuthRaceResponseProtocol?
        AuthRaceResponseProtocol.onRequest = { request in
            XCTAssertEqual(request.request.httpMethod, "PATCH", "No profile GET may follow logout")
            pending = request
            started.fulfill()
        }
        let update = Task { try await service.updateProfileAsync(nickname: nil, country: nil, avatarData: Data()) }
        await fulfillment(of: [started], timeout: 2)
        service.signOut()
        try XCTUnwrap(pending).respond(data: Data("{}".utf8))
        do {
            try await update.value
            XCTFail("Superseded update must be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        assertSignedOut()
    }

    func testUnchangedSessionStillRestoresProfile() async throws {
        seed(try session(userA))
        AuthRaceResponseProtocol.onRequest = { $0.respond(data: Data("[]".utf8)) }
        await service.checkAuthenticationState()
        XCTAssertEqual(service.currentUser?.id, userA)
        XCTAssertTrue(service.isAuthenticated)
        XCTAssertNotNil(service.loadCachedProfile(for: userA))
    }

    func testLogoutBeforeStartupTaskDoesNotStartSignup() async {
        AuthRaceResponseProtocol.onRequest = { request in
            XCTFail("Invalidated initialization must not start a new signup")
            request.respond(status: 418, data: Data())
        }
        service = AuthenticationService(network: NetworkClient(session: urlSession))
        service.signOut()
        await service.waitForInitialization()
        assertSignedOut()
    }

    private func assertSignedOut(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(service.currentUser, file: file, line: line)
        XCTAssertFalse(service.isAuthenticated, file: file, line: line)
        XCTAssertFalse(service.isAnonymous, file: file, line: line)
        XCTAssertNil(SessionKeychain.loadSession(), file: file, line: line)
        XCTAssertNil(UserDefaults.standard.data(forKey: legacyKey), file: file, line: line)
        XCTAssertNil(service.loadCachedProfile(for: userA), file: file, line: line)
        XCTAssertNil(service.error, file: file, line: line)
    }

    private func seed(_ session: SupabaseSessionResponse) {
        SessionKeychain.deleteSession()
        UserDefaults.standard.set(try! encoder.encode(session), forKey: legacyKey)
    }

    private func session(_ id: String, expired: Bool = false) throws -> SupabaseSessionResponse {
        let json = """
        {"access_token":"token-\(id)","refresh_token":"refresh-\(id)","token_type":"bearer",
        "expires_in":3600,"expires_at":"\(expired ? "2000" : "2099")-01-01T00:00:00Z",
        "user":{"id":"\(id)","email":"test@example.com","created_at":"2024-01-01T00:00:00Z","is_anonymous":false}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SupabaseSessionResponse.self, from: Data(json.utf8))
    }
}

private final class AuthRaceResponseProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var onRequest: ((AuthRaceResponseProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in Self.onRequest?(self) }
    }
    override func stopLoading() {}

    func respond(status: Int = 200, data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
