
import Foundation
import Darwin
typealias ApplicationToken = Int
typealias ActivityCategoryToken = Int
struct FamilyActivitySelection: Codable {
    var applicationTokens: Set<Int> = [7]
    var categoryTokens: Set<Int> = []
}
struct GroupTuple { let id: String; var active = true; let selectionData: Data? }
struct StoredUnlockSettings: Codable { let familyControlsModeEnabled: Bool }
enum SharedKeys {
    static let appGroupId = "ShieldRace." + UUID().uuidString
    static let appUnlockSettings = "settings"
    static let shieldState = "shieldState"
    static let defaults = UserDefaults(suiteName: appGroupId)!
    static func usageBudgetKey(_ s: String) -> String { "budget_" + s }
    static func usageBudgetExpiryKey(_ s: String) -> String { "expiry_" + s }
    static func usageBudgetStartedKey(_ s: String) -> String { "started_" + s }
    static func usageBudgetInitialKey(_ s: String) -> String { "initial_" + s }
    static func timeAccessSelectionKey(_ s: String) -> String { "selection_" + s }
}
struct Logger {
    init(subsystem: String, category: String) {}
    func error(_ message: String) { print(message) }
}
struct DeviceActivityName { let rawValue: String; init(_ rawValue: String) { self.rawValue = rawValue } }
struct DeviceActivitySchedule { let intervalEnd: Date }
struct DeviceActivityCenter {
    func schedule(for name: DeviceActivityName) -> DeviceActivitySchedule? { nil }
    func events(for name: DeviceActivityName) -> [String: Int] { [:] }
}
final class ShieldStub {
    private let lock = NSLock()
    private var storedApplications: Set<Int>?
    var beforeWrite: ((Set<Int>?) -> Void)?
    var applications: Set<Int>? {
        get { lock.lock(); defer { lock.unlock() }; return storedApplications }
        set {
            beforeWrite?(newValue)
            lock.lock(); defer { lock.unlock() }; storedApplications = newValue
        }
    }
    enum Categories: Equatable { case specific(Set<Int>, except: Set<Int> = []) }
    var applicationCategories: Categories?
}
struct ManagedSettingsStore {
    struct Name { init(_ s: String) {} }
    static let state = ShieldStub()
    init(named: Name) {}
    var shield: ShieldStub { Self.state }
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let stateLock = UsageBudgetFileLock(fileURL: directory.appendingPathComponent("state.lock"))
let registrationLock = UsageBudgetFileLock(fileURL: directory.appendingPathComponent("registration.lock"))
/*__MODELS__*/
enum ShieldRebuildHelper {
    static func withUsageBudgetLock<T>(_ body: () throws -> T) throws -> T {
        try stateLock.withLock(body)
    }
/*__LEGACY_CLEAR__*/
    static func loadGroups(defaults: UserDefaults) -> [GroupTuple] {
        configuredGroups
    }
    static func cachedSelection(for id: String, data: Data) -> FamilyActivitySelection? {
        try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }
    static func startPendingWidgetBudgets(defaults: UserDefaults, groups: [GroupTuple]) {
        // A daemon registration may need this lock. Pending work must run after
        // rebuild releases it, otherwise the app deadlocks itself.
        try! withUsageBudgetLock { defaults.synchronize() }
    }
    static func logDiagnostic(defaults: UserDefaults, apps: Int, categories: Int,
                              budgetApps: Int, budgetAppsStillShielded: Int) {}
/*__PREDICATES__*//*__REBUILD__*/
}

var configuredGroups = [GroupTuple(id: "G", selectionData: try! JSONEncoder().encode(FamilyActivitySelection()))]
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: " + message); exit(1) }
}
let mode = CommandLine.arguments[2]
if mode == "transition-lock" {
    enum Expected: Error { case interrupted }
    func probe(_ lock: UsageBudgetFileLock) -> Bool {
        let descriptor = open(lock.fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        expect(descriptor >= 0, "lock descriptor must open")
        defer { close(descriptor) }
        let acquired = flock(descriptor, LOCK_EX | LOCK_NB) == 0
        if acquired { flock(descriptor, LOCK_UN) }
        return acquired
    }
    var visited = false
    do {
        try UsageBudgetRegistrationCoordinator.withAccountHistoryTransition(
            stateLock: stateLock, registrationLock: registrationLock
        ) {
            visited = true
            expect(!probe(stateLock), "extension state writers must stay excluded during history replacement")
            expect(!probe(registrationLock), "in-flight daemon registrations must stay excluded during history replacement")
            throw Expected.interrupted
        }
        fatalError("transition error must propagate")
    } catch Expected.interrupted {} catch { fatalError("unexpected transition error") }
    expect(visited, "transition body must run")
    expect(probe(stateLock) && probe(registrationLock), "failed transition must release both locks for retry")
    let result = try! UsageBudgetRegistrationCoordinator.withAccountHistoryTransition(
        stateLock: stateLock, registrationLock: registrationLock
    ) { 42 }
    expect(result == 42, "successful transition must preserve its return value")
    print("PASS: transition-lock")
    exit(0)
}
if mode == "race" {
let defaults = SharedKeys.defaults
defer { defaults.removePersistentDomain(forName: SharedKeys.appGroupId) }
var initial = UsageBudgetSession(minutes: 10, startedAt: Date(), expiresAt: Date().addingTimeInterval(3600))
initial.monitoringFailed = true
initial.save(to: defaults, groupId: "G")
defaults.synchronize()
let writerPaused = DispatchSemaphore(value: 0)
let resumeWriter = DispatchSemaphore(value: 0)
let staleWriterDone = DispatchSemaphore(value: 0)
let purchaseDone = DispatchSemaphore(value: 0)
ManagedSettingsStore.state.beforeWrite = { applications in
    if applications == [7] {
        writerPaused.signal()
        assert(resumeWriter.wait(timeout: .now() + 5) == .success)
    }
}
DispatchQueue.global().async {
    ShieldRebuildHelper.rebuild(startPendingBudgets: false)
    staleWriterDone.signal()
}
assert(writerPaused.wait(timeout: .now() + 5) == .success)
// Probe lock ownership at the exact framework assignment boundary. No timing
// assumption is needed to distinguish the old unlocked writer from the fix.
let descriptor = open(stateLock.fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
assert(descriptor >= 0)
let unprotected = flock(descriptor, LOCK_EX | LOCK_NB) == 0
if unprotected { flock(descriptor, LOCK_UN) }
close(descriptor)
func commitPurchaseAndRebuild() {
    try! stateLock.withLock {
        defaults.synchronize()
        var committed = UsageBudgetSession.load(from: defaults, groupId: "G")!
        committed.monitoringFailed = false
        committed.save(to: defaults, groupId: "G")
        defaults.synchronize()
    }
    ShieldRebuildHelper.rebuild()
}
if unprotected {
    // Old writer permits the whole purchase to complete before its stale set
    // lands. This reproduces the reported purchased-but-still-shielded state.
    commitPurchaseAndRebuild()
    resumeWriter.signal()
    assert(staleWriterDone.wait(timeout: .now() + 5) == .success)
} else {
    // The new writer holds the commit lock until assignment completes. A later
    // purchase therefore computes and applies the final authoritative set.
    DispatchQueue.global().async {
        commitPurchaseAndRebuild()
        purchaseDone.signal()
    }
    resumeWriter.signal()
    assert(staleWriterDone.wait(timeout: .now() + 5) == .success)
    assert(purchaseDone.wait(timeout: .now() + 5) == .success)
}
assert(ManagedSettingsStore.state.applications == nil,
       "Obsolete extension shield landed after purchase commit")
assert(!unprotected, "Shield snapshot and assignment must hold the purchase state lock")
ManagedSettingsStore.state.beforeWrite = nil
// startMonitoring can deliver a synchronous callback. The coordinator must
// release the state lock before that callback rebuilds the shield.
try! UsageBudgetRegistrationCoordinator.perform(
    stateLock: stateLock, registrationLock: registrationLock,
    prepare: { 1 },
    register: { _ in ShieldRebuildHelper.rebuild(startPendingBudgets: false) },
    commit: { _ in }, rollback: { _ in })
print("PASS: obsolete shield cannot overwrite purchase; callbacks and pending registration do not deadlock")

} else {
    let defaults = SharedKeys.defaults
    defer { defaults.removePersistentDomain(forName: SharedKeys.appGroupId) }
    func group(_ id: String, apps: Set<Int>, categories: Set<Int> = []) -> GroupTuple {
        GroupTuple(id: id, selectionData: try! JSONEncoder().encode(FamilyActivitySelection(applicationTokens: apps, categoryTokens: categories)))
    }
    configuredGroups = [group("G", apps: [7]), group("H", apps: [7, 8])]
    var paid = UsageBudgetSession(minutes: 10, startedAt: Date(), expiresAt: Date().addingTimeInterval(3600))
    if mode == "category-exception" {
        configuredGroups = [group("G", apps: [7]), group("H", apps: [8], categories: [3])]
    } else if mode == "paid-category" {
        configuredGroups = [group("G", apps: [], categories: [3]), group("H", apps: [], categories: [3, 4])]
    } else if mode == "paused" {
        paid.monitoringFailed = true
    } else if mode == "expired" {
        paid.expiresAt = Date().addingTimeInterval(-1)
    }
    paid.save(to: defaults, groupId: "G")
    defaults.synchronize()
    ShieldRebuildHelper.rebuild(startPendingBudgets: false)
    switch mode {
    case "overlap":
        expect(ManagedSettingsStore.state.applications == [8], "paid app 7 must be excluded, unrelated app 8 must remain blocked")
        paid.monitoringFailed = true
        paid.save(to: defaults, groupId: "G")
        ShieldRebuildHelper.rebuild(startPendingBudgets: false)
        expect(ManagedSettingsStore.state.applications == [7, 8], "pausing paid budget must shield app 7 again")
    case "category-exception":
        expect(ManagedSettingsStore.state.applications == [8], "unrelated app remains blocked")
        expect(ManagedSettingsStore.state.applicationCategories == .specific([3], except: [7]), "paid app must be an exception to blocked categories")
    case "paid-category":
        expect(ManagedSettingsStore.state.applicationCategories == .specific([4]), "paid category 3 must be excluded, unrelated category 4 remains blocked")
    case "paused", "expired":
        expect(ManagedSettingsStore.state.applications == [7, 8], "unhealthy or expired budget must not exempt apps")
    default: fatalError("unknown mode")
    }
    print("PASS: " + mode)
}
