import Foundation

@MainActor
final class SupabaseSyncService {
    static let shared = SupabaseSyncService()
    @TaskLocal static var historySyncEpoch: UUID?
    var currentEpoch = UUID()
    func captureSyncEpoch() -> UUID { currentEpoch }
}

@MainActor
final class ModelHarness {
    var historyWorkTasks: [UUID: Task<Void, Never>] = [:]
    var isHistoryWorkSuspended = false
    var historyWorkGeneration = UUID()
    var historyWorkWaiters: [CheckedContinuation<Void, Never>] = []
    var dayBoundaryTimer: Timer?
    var recalcTask: Task<Void, Never>?
    var sleepRefetchTask: Task<Void, Never>?
    var dayEndCommitTask: Task<Void, Never>?
    var localPurchaseStateTask: Task<Void, Never>?
    /*__SCHEDULE__*/
    /*__SUSPEND__*/
    /*__RESUME__*/
    /*__CURRENT__*/
    /*__WAIT__*/
    func waitUntilResumed() async { await waitForHistoryWorkResumption() }
}

enum SharedKeys {
    static let appSelection = "selection"
    static let appSelectionSavedDate = "selection-date"
}
enum FixtureDefaults {
    static let suite = "BlockingAccountTransition-" + UUID().uuidString
    static let value = UserDefaults(suiteName: suite)!
}
extension UserDefaults { static func nowhere() -> UserDefaults { FixtureDefaults.value } }
struct Selection: Codable, Equatable { var applications: [Int] }
@MainActor
final class BlockingHarness {
    var persistenceSuspended = false
    var appSelection = Selection(applications: [1])
    var rebuildBlockTask: Task<Void, Never>?
    var persistAndRebuildTask: Task<Void, Never>?
    var saveAppSelectionTask: Task<Void, Never>?
    /*__BLOCKING_SUSPEND__*/
    /*__BLOCKING_RESUME__*/
    /*__BLOCKING_SAVE__*/
}

@MainActor
final class Gate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation {
            release = $0
            entered = true
            entryWaiter?.resume()
            entryWaiter = nil
        }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func open() { release?.resume(); release = nil }
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct AccountModelWorkHarness {
    @MainActor
    static func main() async {
        defer { FixtureDefaults.value.removePersistentDomain(forName: FixtureDefaults.suite) }
        let model = ModelHarness()
        let oldGeneration = model.historyWorkGeneration
        let producerEpoch = SupabaseSyncService.shared.currentEpoch
        let gate = Gate()
        var writes: [String] = []
        model.scheduleHistoryWork {
            // Deliberately ignore cancellation after entering: suspension must
            // still await this old producer before allowing a storage swap.
            await gate.wait()
            expect(SupabaseSyncService.historySyncEpoch == producerEpoch, "producer must retain its original sync epoch across suspension")
            writes.append("A finished")
        }
        await gate.waitForEntry()
        let pause = Task {
            await model.suspendHistoryWork()
            writes.append("paused")
        }
        while !model.isHistoryWorkSuspended { await Task.yield() }
        expect(writes.isEmpty, "a suspended operation must not pretend that its old writer drained")
        expect(!model.isHistoryWorkCurrent(oldGeneration), "an outgoing authorization token must expire immediately")
        SupabaseSyncService.shared.currentEpoch = UUID()
        gate.open()
        await pause.value
        expect(writes == ["A finished", "paused"], "outgoing producer must finish before storage is declared safe to replace")
        model.scheduleHistoryWork { writes.append("stale callback") }
        await Task.yield()
        expect(writes == ["A finished", "paused"], "new work while paused must not be admitted")
        let bootstrap = Task {
            await model.waitUntilResumed()
            writes.append("bootstrap resumed")
        }
        model.resumeHistoryWork()
        await bootstrap.value
        expect(!model.isHistoryWorkCurrent(oldGeneration), "a delayed A authorization must remain stale after B resumes")
        await withCheckedContinuation { continuation in
            model.scheduleHistoryWork { writes.append("B finished"); continuation.resume() }
        }
        expect(writes == ["A finished", "paused", "bootstrap resumed", "B finished"], "incoming producer and bootstrap must resume without old A callbacks")
        let loader = Gate()
        model.localPurchaseStateTask = Task { await loader.wait(); writes.append("loader finished") }
        await loader.waitForEntry()
        let loadPause = Task { await model.suspendHistoryWork(); writes.append("loader drained") }
        while !model.isHistoryWorkSuspended { await Task.yield() }
        loader.open()
        await loadPause.value
        expect(writes.suffix(2) == ["loader finished", "loader drained"], "local purchase loaders must complete before rotation")
        let blocking = BlockingHarness()
        let selectionGate = Gate()
        blocking.saveAppSelectionTask = Task { await selectionGate.wait(); FixtureDefaults.value.set(Data("old selection".utf8), forKey: SharedKeys.appSelection) }
        await selectionGate.waitForEntry()
        let blockingPause = Task { try await blocking.suspendPersistence() }
        while !blocking.persistenceSuspended { await Task.yield() }
        selectionGate.open()
        try! await blockingPause.value
        let savedSelection = try! JSONDecoder().decode(Selection.self, from: FixtureDefaults.value.data(forKey: SharedKeys.appSelection)!)
        expect(savedSelection.applications == [1], "selection barrier must persist latest outgoing selection after old writer drains")
        FixtureDefaults.value.set(Data("B selection".utf8), forKey: SharedKeys.appSelection)
        blocking.appSelection = Selection(applications: [9])
        blocking.saveAppSelection()
        expect(FixtureDefaults.value.data(forKey: SharedKeys.appSelection) == Data("B selection".utf8), "paused selection callback must not replace incoming account")
        blocking.resumePersistence()
        blocking.saveAppSelection()
        let incomingSelection = try! JSONDecoder().decode(Selection.self, from: FixtureDefaults.value.data(forKey: SharedKeys.appSelection)!)
        expect(incomingSelection.applications == [9], "incoming selection writer must work after resume")
        print("PASS model producers, delayed authorization generation, bootstrap wait, loader and selection drains")
    }
}
