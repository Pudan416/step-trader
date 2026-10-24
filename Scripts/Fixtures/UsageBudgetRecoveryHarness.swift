import Foundation
import Darwin
import os.log

struct DeviceActivityName: Hashable {
    let rawValue: String
    init(_ value: String) { rawValue = value }
}
struct DeviceActivitySchedule { let intervalEnd: Date }
struct FamilyActivitySelection {
    var applicationTokens = Set(["selected-app"])
    var categoryTokens = Set<String>()
}
struct DeviceActivityEvent {
    struct Name: Hashable {
        let rawValue: String
        init(_ value: String) { rawValue = value }
    }
}
struct DeviceActivityCenter {
    static var registrations: [DeviceActivityName: [DeviceActivityEvent.Name: DeviceActivityEvent]] = [:]
    static var schedules: [DeviceActivityName: DeviceActivitySchedule] = [:]
    static var startCalls = 0
    static var failStart = false
    func startMonitoring(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule,
                         events: [DeviceActivityEvent.Name: DeviceActivityEvent]) throws {
        Self.startCalls += 1
        if Self.failStart { throw NSError(domain: "TestDaemon", code: 1) }
        Self.registrations[name] = events
        Self.schedules[name] = schedule
    }
    func stopMonitoring(_ names: [DeviceActivityName]) {
        for name in names {
            Self.registrations.removeValue(forKey: name)
            Self.schedules.removeValue(forKey: name)
        }
    }
    func events(for name: DeviceActivityName) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        Self.registrations[name] ?? [:]
    }
    func schedule(for name: DeviceActivityName) -> DeviceActivitySchedule? { Self.schedules[name] }
}
enum SharedKeys {
    static let appGroupId = "test.group"
    static let timedAccessMigrationVersion = "migration"
    static func usageBudgetKey(_ id: String) -> String { "budget_" + id }
    static func usageBudgetInitialKey(_ id: String) -> String { "initial_" + id }
    static func usageBudgetStartedKey(_ id: String) -> String { "started_" + id }
    static func usageBudgetExpiryKey(_ id: String) -> String { "expiry_" + id }
}
// INSERT_MODEL

enum ShieldRebuildHelper {
    struct Group {
        let id = "G"
        let active = true
        let selectionData: Data? = Data([1])
    }
    static var rebuildCalls = 0
    static func rebuild(startPendingBudgets: Bool = true) { rebuildCalls += 1 }
    static let locks = FileManager.default.temporaryDirectory
        .appendingPathComponent("timed-access-locks-" + UUID().uuidString)
    static func usageBudgetLock(named name: String) throws -> UsageBudgetFileLock {
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
        return UsageBudgetFileLock(fileURL: locks.appendingPathComponent(name))
    }
    static func withUsageBudgetLock<T>(_ body: () throws -> T) throws -> T {
        try usageBudgetLock(named: "usage-budget.lock").withLock(body)
    }
    static func loadGroups(defaults: UserDefaults) -> [Group] { [Group()] }
    static func cachedSelection(for id: String, data: Data) -> FamilyActivitySelection? {
        FamilyActivitySelection()
    }
    static func usageBudgetSchedule(endingAt expiry: Date, anchoredAt now: Date) -> DeviceActivitySchedule? {
        expiry > now ? DeviceActivitySchedule(intervalEnd: expiry) : nil
    }
// INSERT_PREDICATES
// INSERT_TRANSACTIONS
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: " + message); exit(1) }
}
let t = Date.now.addingTimeInterval(1_000)
let suite = "TimedAccessPass." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: ShieldRebuildHelper.locks)
}
let center = DeviceActivityCenter()
func current() -> UsageBudgetSession? { UsageBudgetSession.load(from: defaults, groupId: "G") }

switch CommandLine.arguments[1] {
case "purchase_starts_deadline":
    try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10, now: t)
    let pass = current()!
    expect(pass.expiresAt == t.addingTimeInterval(10 * 60), "Pass deadline must be purchase time plus its duration")
    expect(!pass.monitoringFailed, "A successfully monitored pass must be active")
    expect(center.events(for: DeviceActivityName(pass.activityName(groupId: "G"))).isEmpty,
           "A time pass must not register usage thresholds")
case "active_purchase_rejected":
    try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10, now: t)
    let originalDeadline = current()!.expiresAt
    do {
        try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 30,
                                                     now: t.addingTimeInterval(60))
        expect(false, "Second purchase must be rejected while a pass is active")
    } catch {}
    expect(current()?.expiresAt == originalDeadline, "A rejected purchase must not extend the timer")
    expect(DeviceActivityCenter.startCalls == 1, "A rejected purchase must not register another monitor")
case "recovery_keeps_deadline":
    try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 30, now: t)
    let pass = current()!
    let name = DeviceActivityName(pass.activityName(groupId: "G"))
    center.stopMonitoring([name])
    try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: "G", now: t.addingTimeInterval(5 * 60))
    expect(current()?.expiresAt == pass.expiresAt, "Restoring the monitor must keep the original deadline")
    expect(center.schedule(for: name)?.intervalEnd == pass.expiresAt, "Restored monitor must end at the original deadline")
case "failed_purchase_rolls_back":
    DeviceActivityCenter.failStart = true
    do {
        try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10, now: t)
        expect(false, "A monitor registration failure must fail the purchase")
    } catch {}
    expect(current() == nil, "Failed first purchase must remove provisional pass state")
    expect(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: "G", at: t) == 0,
           "Failed purchase must not leave access enabled")
case "expired_purchase_can_restart":
    try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10, now: t)
    let first = current()!
    let secondStart = first.expiresAt.addingTimeInterval(1)
    try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 30, now: secondStart)
    expect(current()?.startedAt == secondStart, "A new pass may start after the previous one expires")
    expect(current()?.expiresAt == secondStart.addingTimeInterval(30 * 60), "The new pass gets its own deadline")
default: fatalError("Unknown scenario")
}
print("PASS: " + CommandLine.arguments[1])
