import Foundation
import os.log

enum AppLogger { static let auth = Logger(subsystem: "Synthetic", category: "Auth") }
struct Session {
    struct User { let id = "B"; let isAnonymous = false }
    let user = User()
    let accessToken = "synthetic-token"
    let expiresAt: Double = 100
}
@MainActor final class AuthFixture {
    var sessionGeneration = UUID()
    var currentUser: String?
    var isAuthenticated = false
    var isAnonymous = false
    var error: String?
    var credential = Data("original-valid-session-B".utf8)
    var prepareCalls = 0
    var anonymousCalls = 0
    var profileCalls = 0
    var publishCalls = 0
    var clears = 0
    var failStorage = true
    func loadStoredSession() -> Session? { Session() }
    func signInAnonymously() async throws { anonymousCalls += 1 }
    func checkSessionGeneration(_ generation: UUID) throws {
        guard generation == sessionGeneration else { throw CancellationError() }
    }
    func advanceSessionGeneration() { sessionGeneration = UUID() }
    func ensureValidSession(_ session: Session) async throws -> Session { session }
    func storeSession(_ session: Session) { credential = Data("rewritten-session".utf8) }
    func clearStoredSession() { clears += 1; credential = Data() }
    func clearCachedProfile(for owner: String) {}
    func queueSignedOutHistoryTransition() {}
    func reapplyCachedState(for session: Session) { publishCalls += 1; currentUser = session.user.id; isAuthenticated = true }
    func loadCurrentUserFromSupabase(session: Session) async throws { profileCalls += 1 }
    func isSessionInvalidatingError(_ error: Error) -> Bool { false }
    func commitAccountSession(_ session: Session, generation: UUID) async throws {
        prepareCalls += 1
        if failStorage { throw CocoaError(.fileReadNoPermission) }
        reapplyCachedState(for: session)
    }
    func run() async { await loadStoredSessionAndRefreshUser() }
    // INSERT_RESTORE
}

@main @MainActor struct AuthHistoryRestoreHarness {
    static func main() async {
        let auth = AuthFixture()
        let originalCredential = auth.credential
        await auth.run()
        precondition(auth.prepareCalls == 1, "Incoming history must be prepared before publishing cached auth")
        precondition(auth.credential == originalCredential && auth.clears == 0, "Storage failure must retain original credential bytes")
        precondition(auth.currentUser == nil && !auth.isAuthenticated && auth.publishCalls == 0, "Storage failure must not publish B over A working history")
        precondition(auth.anonymousCalls == 0 && auth.profileCalls == 0, "Storage failure must not trigger signup or auth fallback")
        precondition(auth.error != nil, "Storage failure must surface a retryable error")
        auth.failStorage = false
        await auth.run()
        precondition(auth.prepareCalls == 2 && auth.currentUser == "B" && auth.isAuthenticated)
        precondition(auth.credential == originalCredential && auth.anonymousCalls == 0)
        print("PASS existing valid session survives history storage failure and retry")
    }
}
