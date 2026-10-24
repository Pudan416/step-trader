import Foundation
import Combine
import Darwin

@MainActor enum Fixture {
    static let suite = "AccountCoordinator." + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suite)!
    static var credential = Data("valid-session-A".utf8)
    static var publishes = 0
    static var anonymousSignups = 0
    static var holdReload = false
    static var reloadWaiter: CheckedContinuation<Void, Never>?
    static var holdHealth = false
    static var healthWaiter: CheckedContinuation<Void, Never>?
    static var widgetWrites = 0
    static var widgetReloads = 0
    static var shieldRebuilds = 0
    static var monitorRecoveries = 0
}
extension UserDefaults { @MainActor static func nowhere() -> UserDefaults { Fixture.defaults } }
enum SharedKeys {
    static let hasCompletedInitialRestore = "restored"
    static func usageBudgetKey(_ id: String) -> String { "budget_" + id }
    static func usageBudgetInitialKey(_ id: String) -> String { "initial_" + id }
    static func usageBudgetStartedKey(_ id: String) -> String { "started_" + id }
    static func usageBudgetExpiryKey(_ id: String) -> String { "expiry_" + id }
}
// INSERT_BUDGET_MODELS
@MainActor struct WidgetCenter { static let shared = WidgetCenter(); func reloadAllTimelines() { Fixture.widgetReloads += 1 } }
struct DeviceActivityName { let rawValue: String; init(_ raw: String) { rawValue = raw } }
struct DeviceActivityCenter { func stopMonitoring(_ names: [DeviceActivityName]) {} }
@MainActor enum ShieldRebuildHelper {
    static func rebuild(startPendingBudgets: Bool = true) { Fixture.shieldRebuilds += 1 }
    static func withAccountHistoryTransitionLock<T>(_ body: () throws -> T) rethrows -> T { try body() }
}
@MainActor enum AccountHistoryStorage {
    static func makeVault() throws -> AccountHistoryVault {
        throw CocoaError(.fileReadNoPermission)
    }
}
@MainActor final class AuthenticationService {
    struct User { let id: String }
    static let shared = AuthenticationService()
    var currentUser: User?
}
@MainActor final class SupabaseSyncService {
    static let shared = SupabaseSyncService()
    @TaskLocal static var historySyncEpoch: UUID?
    var epoch = UUID()
    var closed = false
    var uploadsOpen = false
    var restoreSucceeds = true
    var fullSyncs = 0
    func beginAccountSwitch() { closed = true; uploadsOpen = false; epoch = UUID() }
    func captureSyncEpoch() -> UUID { epoch }
    func pauseForAccountSwitch() async { beginAccountSwitch() }
    func resumeAfterAccountSwitch() { closed = false }
    func allowUploadsAfterRestore(for owner: String) async -> Bool {
        guard !closed, AuthenticationService.shared.currentUser?.id == owner else { return false }
        uploadsOpen = true
        return true
    }
    func restoreFromServer(model: AppModel) async -> Bool {
        precondition(!uploadsOpen, "Hydration must run with uploads closed")
        return restoreSucceeds
    }
    func performFullSync(model: AppModel) async { precondition(uploadsOpen); fullSyncs += 1 }
}
@MainActor class PauseStore {
    var paused = false
    func suspendPersistence() async throws { paused = true }
    func resumePersistence() { paused = false }
}
@MainActor class HealthStore { func stopObservingSteps() {} }
@MainActor final class AppModel {
    let blockingStore = PauseStore()
    let userEconomyStore = PauseStore()
    let healthStore = HealthStore()
    var historyWorkGeneration = UUID()
    var paused = false
    var history: Data?
    var pauseCount = 0
    func suspendHistoryWork() async {
        precondition(SupabaseSyncService.shared.closed, "Sync must close again at each serialized transition start")
        pauseCount += 1
        paused = true
        historyWorkGeneration = UUID()
    }
    func reloadAccountHistory() async {
        precondition(paused)
        if Fixture.holdReload {
            Fixture.holdReload = false
            await withCheckedContinuation { Fixture.reloadWaiter = $0 }
        }
        history = Fixture.defaults.data(forKey: "history")
    }
    func resumeHistoryWork() { paused = false }
    func scheduleDayBoundaryTimer() {}
    func writeWidgetSnapshot() { Fixture.widgetWrites += 1 }
    func ensureUsageBudgetMonitoringForActiveGroups() { Fixture.monitorRecoveries += 1 }
    func scheduleHistoryWork(_ body: @escaping @MainActor () async -> Void) { Task { await body() } }
    func refreshStepsIfAuthorized() async {
        if Fixture.holdHealth { await withCheckedContinuation { Fixture.healthWaiter = $0 } }
    }
    func refreshSleepIfAuthorized() async {}
    // INSERT_RESTART
    func isHistoryWorkCurrent(_ generation: UUID) -> Bool { !paused && historyWorkGeneration == generation }
}
@MainActor final class CanvasStorageService {
    static let shared = CanvasStorageService()
    func invalidatePendingWritesForAccountSwitch() async {}
    func resumeWritesAfterAccountSwitch() {}
}
@MainActor final class MePosterCanvasLoadCoordinator {
    static let shared = MePosterCanvasLoadCoordinator()
    func suspendForAccountSwitch() async {}
    func resumeAfterAccountSwitch() {}
}
@MainActor final class MePosterSnapshotCache {
    static let shared = MePosterSnapshotCache()
    var failPurge = false
    func suspendForAccountSwitch() async throws {
        if failPurge { throw CocoaError(.fileWriteNoPermission) }
    }
    func resumeAfterAccountSwitch() {}
}
@MainActor final class HistoryThumbnailCache {
    static let shared = HistoryThumbnailCache()
    func suspendForAccountSwitch() async throws {}
    func resumeAfterAccountSwitch() {}
}
// INSERT_COORDINATOR

func expect(_ condition: @autoclosure () throws -> Bool) rethrows {
    let result = try condition()
    precondition(result)
}

@main @MainActor struct AccountHistoryCoordinatorHarness {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Fixture.defaults.removePersistentDomain(forName: Fixture.suite)
            try? FileManager.default.removeItem(at: root)
        }
        let working = root.appendingPathComponent("working")
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        let file = working.appendingPathComponent("history.json")
        let legacy = Data("legacy UUID 0D046E58-15CE-4C98-9B6D-AEF26D7DD1F1".utf8)
        Fixture.defaults.set(legacy, forKey: "history")
        try legacy.write(to: file)
        let mode = CommandLine.arguments[1]
        var manifestWrites = 0
        let vault = try AccountHistoryVault(root: root.appendingPathComponent("vault"),
            domains: [.init(defaults: Fixture.defaults, keys: ["history", "restored", "queue"])],
            locations: [.init(name: "history", url: file)],
            manifestWriter: { data, url in
                manifestWrites += 1
                if mode == "commit-failure" && manifestWrites == 3 { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            })
        let coordinator = AccountHistoryCoordinator(vault: mode == "constructor-failure" ? nil : vault)
        let model = AppModel()
        func transition(_ owner: String, reject: Bool = false) async throws {
            try await coordinator.transition(to: owner, model: model,
                currentOwner: { AuthenticationService.shared.currentUser?.id },
                validateIdentity: { if reject { throw CancellationError() } },
                publishIdentity: {
                    Fixture.publishes += 1
                    Fixture.credential = Data(owner.utf8)
                    AuthenticationService.shared.currentUser = .init(id: owner)
                })
        }
        switch mode {
        case "widget-refresh":
            Fixture.holdHealth = true
            try await transition("B")
            while Fixture.healthWaiter == nil { await Task.yield() }
            try expect(Fixture.widgetWrites > 0 && Fixture.widgetReloads > 0)
            try expect(Fixture.shieldRebuilds > 0 && Fixture.monitorRecoveries > 0)
            Fixture.holdHealth = false
            Fixture.healthWaiter?.resume(); Fixture.healthWaiter = nil
        case "roundtrip":
            try await transition("A")
            try expect(model.history == nil)
            let a = Data("A UUID 709662A7-2F59-412A-A5B4-E2AB60CBB75E".utf8)
            Fixture.defaults.set(a, forKey: "history"); try a.write(to: file)
            Fixture.defaults.set(Data("A queued write".utf8), forKey: "queue")
            try await transition(AccountHistoryCoordinator.signedOutOwner)
            try await transition("B")
            try expect(model.history == nil && Fixture.defaults.data(forKey: "queue") == nil)
            Fixture.defaults.set(Data("B".utf8), forKey: "history")
            try await transition("A")
            try expect(model.history == a && (try Data(contentsOf: file)) == a)
            try expect(Fixture.defaults.data(forKey: "queue") == Data("A queued write".utf8))
            try expect(try vault.legacyArchive()?.fileData(at: "history") == legacy)
        case "generation-reject", "commit-failure", "constructor-failure":
            let credential = Fixture.credential
            do { try await transition("B", reject: mode == "generation-reject"); fatalError("Transition must fail") } catch {}
            try expect(Fixture.publishes == 0 && Fixture.credential == credential)
            try expect(AuthenticationService.shared.currentUser == nil && Fixture.anonymousSignups == 0)
            try expect(!SupabaseSyncService.shared.uploadsOpen && coordinator.error != nil)
            try expect(try vault.activeOwner == AccountHistoryVault.legacyOwner)
            try expect(Fixture.defaults.data(forKey: "history") == legacy && (try Data(contentsOf: file)) == legacy)
            if mode != "constructor-failure" {
                try await transition("B")
                try expect(model.history == nil && Fixture.publishes == 1)
            }
        case "cache-failure":
            try await transition("A")
            let a = Data("A".utf8)
            Fixture.defaults.set(a, forKey: "history")
            MePosterSnapshotCache.shared.failPurge = true
            do { try await transition("B"); fatalError("Purge failure must abort before publishing B") } catch {}
            try expect(AuthenticationService.shared.currentUser?.id == "A" && !model.paused)
            try expect(try vault.activeOwner == "A")
            try expect(Fixture.defaults.data(forKey: "history") == a)
        case "restore-failure":
            try await transition("B")
            SupabaseSyncService.shared.restoreSucceeds = false
            let failed = await coordinator.hydrate(owner: "B", model: model)
            try expect(!failed && !SupabaseSyncService.shared.uploadsOpen)
            try expect(!Fixture.defaults.bool(forKey: "restored"))
            SupabaseSyncService.shared.restoreSucceeds = true
            let retried = await coordinator.hydrate(owner: "B", model: model)
            try expect(retried && SupabaseSyncService.shared.uploadsOpen)
            try expect(Fixture.defaults.bool(forKey: "restored"))
        case "queued":
            Fixture.holdReload = true
            let first = Task { try await transition("A") }
            while Fixture.reloadWaiter == nil { await Task.yield() }
            let second = Task { try await transition("B") }
            await Task.yield()
            Fixture.reloadWaiter?.resume(); Fixture.reloadWaiter = nil
            try await first.value
            try await second.value
            try expect(model.pauseCount == 2 && AuthenticationService.shared.currentUser?.id == "B")
        default: fatalError("Unknown scenario")
        }
        print("PASS " + mode)
    }
}
