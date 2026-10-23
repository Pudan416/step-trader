import Foundation

/*__DTO__*/
struct SupabaseConfig {
    let baseURL = URL(string: "https://fixture.invalid")!
    let anonKey = "fixture-public-key"
    static func load() throws -> Self { Self() }
}
enum AppLogger {
    static let auth = Logger()
    struct Logger { func error(_ message: String) {}; func debug(_ message: String) {} }
}
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { print("FAIL: " + message); exit(1) }
}
func session(_ uid: String, token: String = "new-token", anonymous: Bool = false) throws -> SupabaseSessionResponse {
    let json: [String: Any] = ["access_token": token, "token_type": "bearer", "expires_in": 3600,
                              "refresh_token": "fixture-refresh", "user": ["id": uid, "is_anonymous": anonymous]]
    return try JSONDecoder().decode(SupabaseSessionResponse.self, from: JSONSerialization.data(withJSONObject: json))
}
@MainActor final class NetworkClient {
    var mode = "new"
    var requests: [URLRequest] = []
    var afterRequest: (() -> Void)?
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        check(body["provider"] as? String == "apple", "provider changed")
        check(body["id_token"] as? String == "fixture-apple-token", "Apple token changed")
        check(body["nonce"] as? String == "fixture-nonce", "nonce changed")
        check(request.httpMethod == "POST", "exchange method changed")
        check(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "id_token", "wrong grant")
        let link = body["link_identity"] as? Bool == true
        var status = 200
        let data: Data
        if link {
            check(request.value(forHTTPHeaderField: "authorization") == "Bearer refreshed-anon-token", "link used an unrefreshed bearer")
            if mode == "transport" { throw URLError(.networkConnectionLost) }
            if mode == "existing" || mode == "other-422" {
                status = 422
                data = Data((mode == "existing" ? "{\"code\":\"identity_already_exists\"}" : "{\"code\":\"validation_failed\"}").utf8)
            } else {
                data = try JSONEncoder().encode(session(mode == "fork" ? "forked-user" : "anonymous-owner"))
            }
        } else {
            check(body["link_identity"] == nil, "ordinary sign-in included link flag")
            data = try JSONEncoder().encode(session("existing-apple-owner"))
        }
        afterRequest?()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
@MainActor final class AuthenticationService {
    var isAnonymous = true
    var isInitialized = true
    var currentUser: SupabaseAuthUser? = try! session("anonymous-owner", anonymous: true).user
    var sessionGeneration = UUID()
    let network = NetworkClient()
    let supabaseDecoder = JSONDecoder()
    var storedSession: SupabaseSessionResponse? = try! session("anonymous-owner", token: "expired-anon-token", anonymous: true)
    var refreshes = 0
    var storedTokens: [String] = []
    var accessToken: String? { storedSession?.accessToken }
    func loadStoredSession() -> SupabaseSessionResponse? { storedSession }
    func storeSession(_ value: SupabaseSessionResponse) { storedTokens.append(value.accessToken); storedSession = value }
    func checkSessionGeneration(_ generation: UUID) throws {
        try Task.checkCancellation()
        if generation != sessionGeneration { throw CancellationError() }
    }
    func ensureValidSession(_ value: SupabaseSessionResponse) async throws -> SupabaseSessionResponse {
        refreshes += 1
        if network.mode == "refresh-failure" { throw URLError(.notConnectedToInternet) }
        if network.mode == "switch" { sessionGeneration = UUID() }
        return try session(network.mode == "refresh-owner" ? "wrong-owner" : "anonymous-owner", token: "refreshed-anon-token", anonymous: true)
    }
    /*__CONTEXT__*/
    /*__REQUEST__*/
    /*__EXCHANGE__*/

    func test(_ mode: String) async throws {
        network.mode = mode
        if mode == "registered" {
            isAnonymous = false
            storedSession = try session("registered-owner")
            currentUser = storedSession?.user
        }
        if mode == "signed-out" { isAnonymous = false; currentUser = nil; storedSession = nil }
        if mode == "missing" { storedSession = nil }
        if mode == "initializing" || mode == "unpublished" {
            isAnonymous = false
            currentUser = nil
            isInitialized = mode != "initializing"
        }
        if mode == "conflicting-owner" { currentUser = try session("other-owner").user }
        if mode == "link-switch" { network.afterRequest = { [weak self] in self?.sessionGeneration = UUID() } }
        let expectFailure = ["missing", "refresh-failure", "refresh-owner", "fork", "other-422", "transport", "switch", "link-switch", "initializing", "conflicting-owner"].contains(mode)
        do {
            let result = try await supabaseSignInWithApple(idToken: "fixture-apple-token", nonce: "fixture-nonce")
            check(!expectFailure, "unsafe exchange succeeded")
            check(result.user.id == (["new", "unpublished"].contains(mode) ? "anonymous-owner" : "existing-apple-owner"), "wrong resulting UID")
            check(network.requests.count == (mode == "existing" ? 2 : 1), "wrong exchange count")
            check(refreshes == (["registered", "signed-out"].contains(mode) ? 0 : 1), "wrong refresh count")
        } catch {
            check(expectFailure, "valid exchange failed")
            let expectedRequests = ["fork", "other-422", "transport", "link-switch"].contains(mode) ? 1 : 0
            check(network.requests.count == expectedRequests, "failure attempted unsafe normal sign-in")
        }
        if let storedSession {
            check(storedSession.user.id == (mode == "registered" ? "registered-owner" : "anonymous-owner"), "exchange overwrote the original stored owner")
        }
    }
}
@main struct Runner {
    static func main() async throws { try await AuthenticationService().test(CommandLine.arguments[1]) }
}
