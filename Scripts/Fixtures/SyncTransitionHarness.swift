import Foundation
/*STATE*/
struct EnergyRoutine { let id: String; let name: String; let happeningIds: [String]; var lastUsed: Date? = nil }
struct Owner { let id: String }
actor AuthenticationService {
    static let shared = AuthenticationService()
    var currentUser: Owner? = Owner(id: "A")
    func waitForInitialization() async {}
    func setOwner(_ owner: String) { currentUser = Owner(id: owner) }
}
struct SupabaseConfig {
    let baseURL = URL(string: "https://fixture.invalid")!
    let anonKey = "fixture"
    static func load() throws -> Self { Self() }
}
struct Log { func debug(_ message: String) {}; func error(_ message: String) {} }
enum AppLogger { static let network = Log() }
actor NetworkFixture {
    var requests: [URLRequest] = []
    var blocked = false
    var continuation: CheckedContinuation<Void, Never>?
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if blocked { await withCheckedContinuation { continuation = $0 } }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
    }
    func block() { blocked = true }
    func release() { blocked = false; continuation?.resume(); continuation = nil }
    func count() -> Int { requests.count }
}
actor SupabaseSyncService {
    @TaskLocal nonisolated static var historySyncEpoch: SupabaseSyncEpoch?
    nonisolated let transitionState = SupabaseSyncTransitionState()
    nonisolated func captureSyncEpoch() -> SupabaseSyncEpoch { transitionState.capture() }
    var routinesSyncTask: Task<Void, Never>?
    let network = NetworkFixture()
    var retryCount = 0
    func enqueueForRetry(_ request: URLRequest) { retryCount += 1 }
    func iso8601String(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    struct AuthContext { let token: String; let userId: String }
    func authenticatedContext() async -> AuthContext? {
        guard let owner = await AuthenticationService.shared.currentUser else { return nil }
        return AuthContext(token: owner.id, userId: owner.id)
    }
    func worker() -> Task<Void, Never>? { routinesSyncTask }
    /*METHODS*/
}
actor Flag { var value = false; func set() { value = true } }
func require(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
@main struct Tests {
    static func main() async {
        let gate = SupabaseSyncTransitionState()
        let old = gate.capture()
        let active = gate.begin(old, owner: "A", writing: true)!
        gate.suspend()
        require(!active.isCurrent, "pause must invalidate in-flight ACK/apply")
        let drained = Flag()
        let waiting = Task { await gate.waitUntilIdle(); await drained.set() }
        try? await Task.sleep(for: .milliseconds(20))
        require(await drained.value == false, "pause must await active network operation")
        active.finish()
        await waiting.value
        gate.resumeReads()
        let incoming = gate.capture()
        require(gate.begin(old, owner: "B", writing: true) == nil, "old epoch cannot enter after resume")
        require(gate.begin(incoming, owner: "B", writing: false) != nil, "incoming cloud reads must work before restore")
        require(gate.begin(incoming, owner: "B", writing: true) == nil, "uploads must wait for owner history")
        require(gate.allowUploads(for: "B", epoch: incoming), "open restored owner")
        require(gate.begin(incoming, owner: "A", writing: true) == nil, "wrong owner cannot upload")
        require(gate.begin(incoming, owner: "B", writing: true) != nil, "restored owner may upload")
        print("PASS drain, generation, read/restore readiness, owner isolation")

        let service = SupabaseSyncService()
        let epochA = service.captureSyncEpoch()
        service.transitionState.suspend()
        await AuthenticationService.shared.setOwner("B")
        service.transitionState.resumeReads()
        require(service.transitionState.allowUploads(for: "B", epoch: service.captureSyncEpoch()), "B ready")
        await SupabaseSyncService.$historySyncEpoch.withValue(epochA) {
            await service.syncSavedRoutines([EnergyRoutine(id: "A-old", name: "A", happeningIds: [])])
        }
        require(await service.worker() == nil, "old producer entering after B must not schedule")
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await service.syncSavedRoutines([])
        }
        await canceled.value
        require(await service.worker() == nil, "canceled old callback cannot capture incoming epoch")
        print("PASS actual routines scheduler rejects delayed/canceled A producer")

        await service.network.block()
        let upload = Task { await service.performSavedRoutinesSync([EnergyRoutine(id: "B", name: "B", happeningIds: [])]) }
        while await service.network.count() == 0 { await Task.yield() }
        service.transitionState.suspend()
        await service.network.release()
        await upload.value
        await service.transitionState.waitUntilIdle()
        require(await service.network.count() == 1, "late upsert response cannot issue follow-up stale DELETE")
        require(await service.retryCount == 0, "late response cannot mutate retry queue")
        print("PASS actual routines writer stops after in-flight response on pause")
    }
}
