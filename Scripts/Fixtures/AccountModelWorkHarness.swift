import Foundation

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
        let model = ModelHarness()
        let oldGeneration = model.historyWorkGeneration
        let gate = Gate()
        var writes: [String] = []
        model.scheduleHistoryWork {
            // Deliberately ignore cancellation after entering: suspension must
            // still await this old producer before allowing a storage swap.
            await gate.wait()
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
        print("PASS model producers, delayed authorization generation, bootstrap wait and loader drain")
    }
}
