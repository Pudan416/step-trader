import Foundation
import Combine

struct FixtureLogger {
    func error(_ message: String) {}
    func debug(_ message: String) {}
}
enum AppLogger { static let energy = FixtureLogger(); static let app = FixtureLogger() }
enum AppError: Error { case persistenceError(Error) }
actor ErrorManager {
    static let shared = ErrorManager()
    private(set) var reported = 0
    func handle(_ error: AppError) { reported += 1 }
}
protocol BudgetEngineProtocol {}
struct FixtureBudget: BudgetEngineProtocol {}
struct CancelDuringEncoding: Encodable {
    func encode(to encoder: Encoder) throws {
        withUnsafeCurrentTask { $0?.cancel() }
        var value = encoder.singleValueContainer()
        try value.encode("old account payload")
    }
}
enum Tariff {
    case medium
    var entryCostSteps: Int { 10 }
}
struct PayGateSession {}
enum AppModel { static func dayKey(for date: Date) -> String { "fixture-day" } }
enum DayBoundary {
    static func currentDayStart(for date: Date, dayEndHour: Int, dayEndMinute: Int) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
enum SharedKeys {
    static let appStepsSpentByDay = "by-day"
    static let appStepsSpentLifetime = "lifetime"
    static let spentStepsToday = "spent"
    static let stepsBalance = "balance"
    static let appDayPassGrants = "day-passes"
    static let dayEndHour = "hour"
    static let dayEndMinute = "minute"
}
enum FixtureDefaults {
    static let name = "EconomyWriteBarrier-" + UUID().uuidString
    static let value = UserDefaults(suiteName: name)!
}
extension UserDefaults { static func nowhere() -> UserDefaults { FixtureDefaults.value } }

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct EconomyWriteBarrierHarness {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        PersistenceManager.storageDirectoryOverride = root
        defer {
            FixtureDefaults.value.removePersistentDomain(forName: FixtureDefaults.name)
            try? FileManager.default.removeItem(at: root)
            PersistenceManager.storageDirectoryOverride = nil
        }
        let manager = PersistenceManager.shared
        if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "flushFailure" {
            let store = UserEconomyStore(budgetEngine: FixtureBudget())
            store.appStepsSpentByDay = ["A": ["app": 12]]
            let blocked = root.appendingPathComponent("blocked")
            try Data("not a directory".utf8).write(to: blocked)
            PersistenceManager.storageDirectoryOverride = blocked
            var didFail = false
            do { try await store.suspendPersistence() } catch { didFail = true }
            expect(didFail, "failed outgoing flush must abort account rotation")
            expect(store.appStepsSpentByDay == ["A": ["app": 12]], "failed flush must preserve outgoing history in memory")
            PersistenceManager.storageDirectoryOverride = root
            store.resumePersistence()
            try await store.suspendPersistence()
            let preserved = try await manager.load([String: [String: Int]].self, from: "appStepsSpentByDay.json")
            expect(preserved == ["A": ["app": 12]], "retry must durably preserve the outgoing account")
            print("PASS flushFailure")
            return
        }
        if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "encodingCancellation" {
            let worker = Task {
                do { try await manager.save(CancelDuringEncoding(), to: "encoding.json"); return false }
                catch is CancellationError { return true }
                catch { return false }
            }
            let cancelled = await worker.value
            expect(cancelled, "cancellation after encoding must stop the imminent disk write")
            expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("encoding.json").path), "encoded foreign payload must not reach disk")
            let reported = await ErrorManager.shared.reported
            expect(reported == 0, "post-encoding cancellation must stay silent")
            print("PASS encodingCancellation")
            return
        }
        if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "barrier" {
            let store = UserEconomyStore(budgetEngine: FixtureBudget())
            store.stepsBalance = 111
            store.spentSteps = 12
            store.appStepsSpentByDay = ["A": ["app": 12]]
            store.appStepsSpentLifetime = ["app": 12]
            store.persistAppStepsSpentByDay()
            store.persistAppStepsSpentLifetime()
            try await store.suspendPersistence()
            let outgoing = try await manager.load([String: [String: Int]].self, from: "appStepsSpentByDay.json")
            expect(outgoing == ["A": ["app": 12]], "quiescence must preserve the latest outgoing history before archiving")
            expect(FixtureDefaults.value.integer(forKey: SharedKeys.stepsBalance) == 111, "quiescence must preserve the outgoing scalar balance")
            FixtureDefaults.value.removeObject(forKey: SharedKeys.appDayPassGrants)
            FixtureDefaults.value.set(222, forKey: SharedKeys.stepsBalance)
            FixtureDefaults.value.set(0, forKey: SharedKeys.spentStepsToday)
            try? FileManager.default.removeItem(at: root.appendingPathComponent("appStepsSpentByDay.json"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("appStepsSpentLifetime.json"))
            // Attempts from an old callback while incoming state is loading.
            store.stepsBalance = 999
            store.spentSteps = 888
            store.persistAppStepsSpentByDay()
            store.persistAppStepsSpentLifetime()
            store.dayPassGrants = ["A": .now]
            store.persistDayPassGrants()
            await Task.yield()
            expect(FixtureDefaults.value.integer(forKey: SharedKeys.stepsBalance) == 222, "old scalar callback must not replace B's balance")
            expect(FixtureDefaults.value.integer(forKey: SharedKeys.spentStepsToday) == 0, "old scalar callback must not replace B's spending")
            expect(FixtureDefaults.value.data(forKey: SharedKeys.appDayPassGrants) == nil, "old pass grant callback must not reach incoming defaults")
            expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("appStepsSpentByDay.json").path), "suspended daily history writer must stay silent")
            expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("appStepsSpentLifetime.json").path), "suspended lifetime writer must stay silent")
            store.stepsBalance = 222
            store.spentSteps = 0
            store.appStepsSpentByDay = ["B": ["app": 7]]
            store.resumePersistence()
            store.stepsBalance = 223
            store.persistAppStepsSpentByDay()
            let deadline = ContinuousClock.now + .seconds(3)
            while ContinuousClock.now < deadline {
                if FixtureDefaults.value.integer(forKey: SharedKeys.stepsBalance) == 223,
                   FileManager.default.fileExists(atPath: root.appendingPathComponent("appStepsSpentByDay.json").path) { break }
                await Task.yield()
            }
            let restored = try await manager.load([String: [String: Int]].self, from: "appStepsSpentByDay.json")
            expect(restored == ["B": ["app": 7]], "resuming must persist B's history, with A absent")
            expect(FixtureDefaults.value.integer(forKey: SharedKeys.stepsBalance) == 223, "resuming must permit fresh scalar writes")
            try await store.suspendPersistence()
            print("PASS barrier")
            return
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await manager.save(["foreign": 41], to: "cancelled.json")
                return false
            } catch is CancellationError {
                return true
            } catch { return false }
        }
        let cancelled = await task.value
        expect(cancelled, "cancelled persistence must stop before writing account history")
        expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled.json").path), "cancelled account bytes must not reach disk")
        let reported = await ErrorManager.shared.reported
        expect(reported == 0, "normal cancellation must not become a user-visible persistence error")
        print("PASS cancellation")
    }
}
