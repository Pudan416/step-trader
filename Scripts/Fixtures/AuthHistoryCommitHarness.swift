import Foundation

struct SupabaseSessionResponse: Codable {
    struct User: Codable { let id: String; let isAnonymous: Bool }
    let user: User
    let accessToken: String
    init(_ owner: String) { user = User(id: owner, isAnonymous: false); accessToken = "token-" + owner }
}
@MainActor enum Events { static var values: [String] = [] }
@MainActor enum SessionKeychain {
    static var saved: Data?
    @discardableResult static func saveSession(_ data: Data) -> Bool {
        Events.values.append("credentials"); saved = data; return true
    }
    static func deleteSession() { saved = nil }
}
@MainActor final class AppModel {}
@MainActor final class DIContainer {
    static let shared = DIContainer()
    var creations = 0
    lazy var applicationModel = makeAppModel()
    func makeAppModel() -> AppModel { creations += 1; return AppModel() }
}
@MainActor final class SupabaseSyncService {
    static let shared = SupabaseSyncService()
    var closed = false
    func beginAccountSwitch() { closed = true; Events.values.append("sync-closed") }
}
@MainActor final class AccountHistoryCoordinator {
    static let shared = AccountHistoryCoordinator()
    static let signedOutOwner = "local-signed-out"
    var fail = false
    var hold = false
    var waiter: CheckedContinuation<Void, Never>?
    var owners: [String] = []
    func transition(to owner: String, model: AppModel,
        currentOwner: @escaping @MainActor () -> String?,
        validateIdentity: @escaping @MainActor () throws -> Void,
        publishIdentity: @escaping @MainActor () -> Void) async throws {
        owners.append(owner)
        Events.values.append("prepare")
        if hold { hold = false; await withCheckedContinuation { waiter = $0 } }
        if fail { throw CocoaError(.fileReadNoPermission) }
        try validateIdentity()
        Events.values.append("vault-commit")
        publishIdentity()
    }
}
@MainActor final class AuthenticationService {
    struct User { let id: String }
    private struct PendingTeardown { let bearer: String }
    static let shared = AuthenticationService()
    let bypassAccountHistoryForTesting = false
    var postLoginSyncModel: AppModel?
    var sessionGeneration = UUID()
    var currentUser: User? = User(id: "A")
    var isLoading = false
    var isAuthenticated = true
    var isAnonymous = false
    var error: String?
    var signInTask: Task<Void, Never>?
    var postLoginSyncTask: Task<Void, Never>?
    var historyTransitionTask: Task<Void, Never>?
    var teardownBearers: [String] = []
    let supabaseEncoder = JSONEncoder()
    let userDefaultsKey = "Synthetic.AuthHistory." + UUID().uuidString
    func runCommit(_ session: SupabaseSessionResponse) async throws {
        try await commitAccountSession(session, generation: sessionGeneration)
    }
    func awaitHistory() async { await historyTransitionTask?.value }
    func loadStoredSession() -> SupabaseSessionResponse? {
        SessionKeychain.saved.flatMap { try? JSONDecoder().decode(SupabaseSessionResponse.self, from: $0) }
    }
    func clearCachedProfile(for owner: String) {}
    private func capturePendingTeardown() -> PendingTeardown? {
        loadStoredSession().map { PendingTeardown(bearer: $0.accessToken) }
    }
    private static func performTeardown(_ pending: PendingTeardown?) async {
        if let pending { shared.teardownBearers.append(pending.bearer) }
    }
    func reapplyCachedState(for session: SupabaseSessionResponse) {
        Events.values.append("profile-published")
        currentUser = User(id: session.user.id); isAuthenticated = true
    }
    // INSERT_METHODS
}
@main @MainActor struct AuthHistoryCommitHarness {
    static func main() async throws {
        let auth = AuthenticationService.shared
        let a = SupabaseSessionResponse("A")
        let bytes = try JSONEncoder().encode(a)
        SessionKeychain.saved = bytes
        let mode = CommandLine.arguments[1]
        switch mode {
        case "before-model":
            precondition(auth.postLoginSyncModel == nil)
            try await auth.runCommit(SupabaseSessionResponse("B"))
            precondition(DIContainer.shared.creations == 1 && auth.postLoginSyncModel === DIContainer.shared.applicationModel,
                "Auth before Root must use the same canonical lazy model")
            precondition(AccountHistoryCoordinator.shared.owners == ["B"], "Missing model must not bypass vault")
            precondition(Events.values == ["prepare", "vault-commit", "credentials", "profile-published"])
            precondition(auth.loadStoredSession()?.user.id == "B" && auth.currentUser?.id == "B")
        case "prepare-failure":
            AccountHistoryCoordinator.shared.fail = true
            do { try await auth.runCommit(SupabaseSessionResponse("B")); fatalError("prepare must fail") } catch {}
            precondition(SessionKeychain.saved == bytes && auth.currentUser?.id == "A")
            precondition(!Events.values.contains("credentials") && !Events.values.contains("profile-published"))
            AccountHistoryCoordinator.shared.fail = false
            try await auth.runCommit(SupabaseSessionResponse("B"))
            precondition(auth.loadStoredSession()?.user.id == "B")
        case "signout-before-model":
            auth.signOut()
            precondition(SupabaseSyncService.shared.closed, "Sign out closes sync before its async history drain")
            await auth.awaitHistory()
            precondition(SessionKeychain.saved == nil && auth.currentUser == nil && !auth.isAuthenticated)
            precondition(DIContainer.shared.creations == 1 && AccountHistoryCoordinator.shared.owners == [AccountHistoryCoordinator.signedOutOwner])
        case "signout-during-prepare":
            AccountHistoryCoordinator.shared.hold = true
            let incoming = Task { try await auth.runCommit(SupabaseSessionResponse("B")) }
            while AccountHistoryCoordinator.shared.waiter == nil { await Task.yield() }
            let signIn = Task<Void, Never> { try? await Task.sleep(for: .seconds(10)) }
            let postLogin = Task<Void, Never> { try? await Task.sleep(for: .seconds(10)) }
            auth.signInTask = signIn; auth.postLoginSyncTask = postLogin
            auth.signOut()
            precondition(signIn.isCancelled && postLogin.isCancelled)
            await auth.awaitHistory()
            AccountHistoryCoordinator.shared.waiter?.resume(); AccountHistoryCoordinator.shared.waiter = nil
            do { try await incoming.value; fatalError("Old B prepare must not commit after sign out") } catch {}
            precondition(SessionKeychain.saved == nil && auth.currentUser == nil)
            precondition(!Events.values.contains("credentials") && !Events.values.contains("profile-published"))
            while auth.teardownBearers.isEmpty { await Task.yield() }
            precondition(auth.teardownBearers == ["token-A"])
        default: fatalError("Unknown scenario")
        }
        print("PASS " + mode)
    }
}
