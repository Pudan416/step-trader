import Foundation
/*STATE*/
struct EnergyRoutine { let id: String; let name: String; let happeningIds: [String]; var lastUsed: Date? = nil }
struct Owner { let id: String }
actor AuthenticationService {
    static let shared = AuthenticationService()
    var isInitialized = true
    func setInitialized(_ value: Bool) { isInitialized = value }
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
enum SharedKeys { static let analyticsEventsQueue = "analytics-fixture" }
extension UserDefaults {
    static let fixture = UserDefaults(suiteName: "nowhere-sync-fixture-\(UUID().uuidString)")!
    static func nowhere() -> UserDefaults { fixture }
}
actor Suspension {
    var waiting = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { waiting = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
struct DailySpentPayload: Equatable { let dayKey: String; let totalSpent: Int; let spentByApp: [String: Int] }
struct DailySpentRow: Encodable { let userId: String; let dayKey: String; let totalSpent: Int; let spentByApp: [String: Int]; let updatedAt: String }
struct CanvasUploadOrdering {}
@MainActor final class AppModel {
    var happenings: [String] = []
    func mergeRestoredHappenings(_ values: [String]) { happenings += values }
}
actor SupabaseSyncService {
    @TaskLocal nonisolated static var historySyncEpoch: SupabaseSyncEpoch?
    nonisolated let transitionState = SupabaseSyncTransitionState()
    nonisolated func captureSyncEpoch() -> SupabaseSyncEpoch { transitionState.capture() }
    var routinesSyncTask: Task<Void, Never>?
    var dailySelectionsSyncTask: Task<Void, Never>?
    var dailyStatsSyncTask: Task<Void, Never>?
    var dailySpentSyncTask: Task<Void, Never>?
    var ticketGroupsSyncTask: Task<Void, Never>?
    var analyticsFlushTask: Task<Void, Never>?
    var dayCanvasSyncTask: Task<Void, Never>?
    var preferencesSyncTask: Task<Void, Never>?
    var daySnapshotSyncTask: Task<Void, Never>?
    var entriesSyncTask: Task<Void, Never>?
    var canvasRecoveryTasks: [UUID: Task<Void, Never>] = [:]
    var pendingDailySelections: String?, pendingDailyStats: String?, pendingDayCanvas: String?, pendingPreferences: String?
    var pendingDailySpent: DailySpentPayload?
    var lastSentDailySpent: DailySpentPayload?
    var lastSentDailySelections: String?, lastSentDailyStats: String?, lastSentDayCanvas: String?, lastSentPreferences: String?
    var pendingTicketGroupsPayload: [String] = [], lastSentTicketGroupsPayload: [String] = []
    var cachedTodaySelections: String?, cachedTodayStats: String?, cachedTodaySpent: String?
    var lastSyncedCustomActivitiesHash = 42
    var lastSyncedDayKey = "A"
    var analyticsDedupeKeys: Set<String> = ["A"]
    var canvasUploadOrdering = CanvasUploadOrdering()
    var pendingAnalyticsEvents: [String] = ["A"]
    static func loadAnalyticsQueueFromDefaults() -> [String] { ["B"] }
    func loadCustomHappeningsFromServer() async -> [String]? {
        _ = try? await network.data(for: URLRequest(url: URL(string: "https://fixture.invalid/read")!))
        return ["A-history"]
    }
    /*ADOPTION*/
    /*PERSIST*/
    func queueDelayedAnalytics(_ suspension: Suspension) async {
        guard let syncOperation = await beginSyncOperation(writing: true) else { return }
        defer { syncOperation.finish() }
        pendingAnalyticsEvents.append("A-new")
        await suspension.wait()
        await persistAnalyticsQueueToDefaults(syncOperation: syncOperation)
    }
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
enum FixtureUploadOrdering { /*UPLOAD_ORDERING*/ }
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
        let duringPause = gate.capture()
        gate.resumeReads()
        let incoming = gate.capture()
        require(gate.begin(duringPause, owner: "B", writing: false) == nil, "paused producer must stay invalid after resume")
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
        await AuthenticationService.shared.setInitialized(false)
        let startupService = SupabaseSyncService()
        let startup = Task { await startupService.performSavedRoutinesSync([]) }
        try? await Task.sleep(for: .milliseconds(30))
        startup.cancel()
        await startup.value
        await startupService.transitionState.waitUntilIdle()
        require(await startupService.network.count() == 0, "canceled startup admission must not submit")
        print("PASS pending auth initialization cancels and drains without auth completion")
        let parentService = SupabaseSyncService()
        let producer = Task {
            await FixtureUploadOrdering.runUpload {
                await parentService.performSavedRoutinesSync([])
            }
        }
        try? await Task.sleep(for: .milliseconds(30))
        parentService.beginAccountSwitch()
        producer.cancel()
        await producer.value
        await parentService.transitionState.waitUntilIdle()
        print("PASS first invalidation lets canceled producer drain uncanceled upload child before auth finishes")
        let uncanceled = Task { await startupService.performSavedRoutinesSync([]) }
        try? await Task.sleep(for: .milliseconds(30))
        startupService.transitionState.suspend()
        await uncanceled.value
        print("PASS pause also drains an uncanceled Canvas-style child waiting for auth")
        await AuthenticationService.shared.setInitialized(true)
        await AuthenticationService.shared.setOwner("A")
        let writer = SupabaseSyncService()
        await writer.network.block()
        let payload = DailySpentPayload(dayKey: "2099-01-01", totalSpent: 13, spentByApp: ["fixture": 13])
        let sent = Task { await writer.performDailySpentSync(payload: payload) }
        while await writer.network.count() == 0 { await Task.yield() }
        let paused = Flag()
        let pausing = Task { await writer.pauseForAccountSwitch(); await paused.set() }
        while writer.transitionState.allows(writer.captureSyncEpoch(), writing: true) { await Task.yield() }
        require(await paused.value == false, "actual pause must await direct writer lease")
        require(await writer.lastSyncedCustomActivitiesHash == 42, "cache reset must follow drain")
        await writer.network.release()
        await sent.value
        await pausing.value
        require(await writer.lastSentDailySpent == nil, "late daily-spent response cannot ACK cache")
        require(await writer.lastSyncedCustomActivitiesHash == 0, "cache reset after drain")
        require(await writer.pendingAnalyticsEvents == ["A"], "pause cannot drop persisted queue payload")
        await AuthenticationService.shared.setOwner("B")
        await writer.resumeAfterAccountSwitch()
        require(await writer.pendingAnalyticsEvents == ["B"], "incoming account queue must reload")
        require(await writer.allowUploadsAfterRestore(for: "A") == false, "owner ready must verify current auth")
        require(await writer.allowUploadsAfterRestore(for: "B"), "incoming owner can become ready")
        print("PASS actual pause drains daily-spent writer before cache reset, rejects late ACK, preserves queue")
        let reader = SupabaseSyncService()
        await reader.network.block()
        let model = await AppModel()
        let restoring = Task { await reader.restoreCustomHappeningsFromServer(model: model) }
        while await reader.network.count() == 0 { await Task.yield() }
        let pauseRead = Task { await reader.pauseForAccountSwitch() }
        while reader.transitionState.allows(reader.captureSyncEpoch(), writing: false) { await Task.yield() }
        await reader.network.release()
        await restoring.value
        await pauseRead.value
        require(await model.happenings.isEmpty, "old read response cannot apply history at MainActor commit")
        print("PASS production restore apply rejects stale response at MainActor commit")
        let analytics = SupabaseSyncService()
        let delayedPersistence = Suspension()
        let event = Task { await analytics.queueDelayedAnalytics(delayedPersistence) }
        while !(await delayedPersistence.waiting) { await Task.yield() }
        let pausingAnalytics = Task { await analytics.pauseForAccountSwitch() }
        while analytics.transitionState.allows(analytics.captureSyncEpoch(), writing: true) { await Task.yield() }
        await delayedPersistence.release()
        await event.value
        await pausingAnalytics.value
        let outgoing = UserDefaults.nowhere().data(forKey: SharedKeys.analyticsEventsQueue)!
        require(try! JSONDecoder().decode([String].self, from: outgoing) == ["A", "A-new"],
                "pause must persist appended outgoing event when ordinary delayed persistence is invalidated")
        print("PASS outgoing analytics append survives pause invalidating pending normal persistence")
    }
}
