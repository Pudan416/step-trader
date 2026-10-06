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
    static var onStart: (() throws -> Void)?
    func startMonitoring(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule,
                         events: [DeviceActivityEvent.Name: DeviceActivityEvent]) throws {
        Self.startCalls += 1
        if Self.failStart { throw NSError(domain: "TestDaemon", code: 1) }
        Self.registrations[name] = events
        Self.schedules[name] = schedule
        if let hook = Self.onStart { Self.onStart = nil; try hook() }
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
    static let dayEndHour = "hour"
    static let dayEndMinute = "minute"
    static func usageBudgetKey(_ id: String) -> String { "budget_" + id }
    static func usageBudgetInitialKey(_ id: String) -> String { "initial_" + id }
    static func usageBudgetStartedKey(_ id: String) -> String { "started_" + id }
    static func usageBudgetExpiryKey(_ id: String) -> String { "expiry_" + id }
}
enum DayBoundary {
    static func purchaseExpiry(minutes: Int, dayEndHour: Int, dayEndMinute: Int, now: Date) -> Date {
        now.addingTimeInterval(43200)
    }
}
// INSERT_MODEL

enum ShieldRebuildHelper {
    struct Group {
        let id = "G"
        let active = true
        let selectionData: Data? = Data([1])
    }
    static var afterUnlock: (() -> Void)?
    static var rebuildCalls = 0
    static func rebuild(startPendingBudgets: Bool = true) { rebuildCalls += 1 }
    static let locks = FileManager.default.temporaryDirectory
        .appendingPathComponent("recovery-locks-" + UUID().uuidString)
    static func usageBudgetLock(named name: String) throws -> UsageBudgetFileLock {
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
        return UsageBudgetFileLock(fileURL: locks.appendingPathComponent(name))
    }
    static func withUsageBudgetLock<T>(_ body: () throws -> T) throws -> T {
        let result = try usageBudgetLock(named: "usage-budget.lock").withLock(body)
        // Schedule a competing operation at a real lock-release boundary.
        if let hook = afterUnlock { afterUnlock = nil; hook() }
        return result
    }
    static func loadGroups(defaults: UserDefaults) -> [Group] { [Group()] }
    static func usageBudgetSchedule(endingAt: Date, anchoredAt: Date) -> DeviceActivitySchedule? {
        endingAt > anchoredAt ? DeviceActivitySchedule(intervalEnd: endingAt) : nil
    }
    static func cachedSelection(for id: String, data: Data) -> FamilyActivitySelection? {
        FamilyActivitySelection()
    }
    static var selectionMatches = true
    static func usageSelectionMatches(defaults: UserDefaults, groupId: String,
                                      session: UsageBudgetSession) -> Bool { selectionMatches }
    static func usageEvents(selection: FamilyActivitySelection,
                            session: UsageBudgetSession) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        Dictionary(uniqueKeysWithValues: (1...session.initialMinutes).map {
            (DeviceActivityEvent.Name(session.eventName(minute: $0)), DeviceActivityEvent())
        })
    }
// INSERT_PREDICATES
// INSERT_TRANSACTIONS
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: " + message); exit(1) }
}
let t = Date(timeIntervalSince1970: 1_789_200_000)
let suite = "UsageBudgetRecovery." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer {
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: ShieldRebuildHelper.locks)
}
var original = UsageBudgetSession(minutes: 10, startedAt: t, expiresAt: t.addingTimeInterval(43200))
original.monitoredSelectionData = Data([1])
original.save(to: defaults, groupId: "G")
let center = DeviceActivityCenter()
let originalName = DeviceActivityName(original.activityName(groupId: "G"))
try center.startMonitoring(originalName, during: DeviceActivitySchedule(intervalEnd: original.expiresAt),
    events: ShieldRebuildHelper.usageEvents(selection: FamilyActivitySelection(), session: original))
DeviceActivityCenter.startCalls = 0
func current() -> UsageBudgetSession { UsageBudgetSession.load(from: defaults, groupId: "G")! }
func earlyThreshold() throws {
    _ = try ShieldRebuildHelper.recordUsageThreshold(defaults: defaults, groupId: "G",
        event: original.eventName(minute: 10), now: t.addingTimeInterval(13))
}

switch CommandLine.arguments[1] {
case "implausible_pause":
    try earlyThreshold()
    expect(current().remainingMinutes == 10, "Impossible threshold must preserve paid minutes")
    expect(current().monitoringFailed, "Invalid measurement must close access until recovery")
    expect(DeviceActivityCenter.startCalls == 0, "A callback must not synchronously re-arm an invalid monitor")
case "topup_during_callback":
    ShieldRebuildHelper.afterUnlock = {
        try! ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G",
                                                     minutes: 10, now: t.addingTimeInterval(13))
        expect(current().remainingMinutes == 20, "Top-up must succeed before recovery finishes")
    }
    try earlyThreshold()
    expect(current().remainingMinutes == 20, "Recovery discarded a concurrent paid top-up")
case "purchase_during_recovery":
    center.stopMonitoring([originalName])
    ShieldRebuildHelper.afterUnlock = {
        try! ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G",
                                                     minutes: 10, now: t.addingTimeInterval(13))
    }
    try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: "G", now: t.addingTimeInterval(13))
    expect(current().remainingMinutes == 20, "Stale foreground recovery overwrote a newer purchase")
    expect(DeviceActivityCenter.startCalls == 1, "A newer healthy monitor must survive stale recovery")
case "failure_preserves_paid":
    center.stopMonitoring([originalName])
    DeviceActivityCenter.failStart = true
    do {
        try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: "G", now: t.addingTimeInterval(13))
        expect(false, "Daemon failure must propagate")
    } catch {}
    expect(current().remainingMinutes == 10 && current().monitoringFailed, "Failed recovery must retain a paused paid balance")
    DeviceActivityCenter.failStart = false
    try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: "G", now: t.addingTimeInterval(14))
    expect(current().remainingMinutes == 10 && !current().monitoringFailed, "Retry must resume without another purchase")
case "old_events_after_pause":
    try earlyThreshold()
    let rejectedGeneration = current()
    _ = try ShieldRebuildHelper.recordUsageThreshold(defaults: defaults, groupId: "G",
        event: rejectedGeneration.eventName(minute: 10), now: t.addingTimeInterval(3600))
    expect(current().remainingMinutes == 10, "A rejected generation must never consume paid minutes later")
case "recovery_without_overlapping_monitor":
    try earlyThreshold()
    DeviceActivityCenter.onStart = {
        expect(DeviceActivityCenter.registrations[originalName] == nil,
               "A new usage monitor must not start while the rejected monitor is still registered")
    }
    try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: "G", now: t.addingTimeInterval(14))
    expect(current().remainingMinutes == 10 && !current().monitoringFailed,
           "Replacing the rejected monitor must reopen the paid balance")
case "failed_replacement_pauses_old_balance":
    ShieldRebuildHelper.selectionMatches = false
    DeviceActivityCenter.failStart = true
    do {
        try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10,
                                                    now: t.addingTimeInterval(14))
        expect(false, "Replacement failure must propagate")
    } catch {}
    expect(DeviceActivityCenter.registrations[originalName] == nil,
           "The rejected baseline must not remain registered after replacement fails")
    expect(current().remainingMinutes == 10 && current().monitoringFailed,
           "Paid minutes without a live monitor must be shielded and recoverable")
    expect(ShieldRebuildHelper.rebuildCalls == 1,
           "Failed replacement must reapply the shield after stopping the old monitor")
case "callback_during_registration":
    center.stopMonitoring([originalName])
    DeviceActivityCenter.onStart = {
        let provisional = current()
        _ = try ShieldRebuildHelper.recordUsageThreshold(defaults: defaults, groupId: "G",
            event: provisional.eventName(minute: 10), now: t.addingTimeInterval(14))
    }
    do {
        try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: "G", now: t.addingTimeInterval(13))
        expect(false, "Registration must not silently clear a rejected baseline")
    } catch {}
    expect(current().remainingMinutes == 10 && current().monitoringFailed, "Synchronous bad callback must preserve a paused balance")
    expect(DeviceActivityCenter.startCalls == 1, "Bad callbacks must not recursively register")
case "rollback_projection":
    original.consumedMinutes = 2
    original.save(to: defaults, groupId: "G")
    center.stopMonitoring([originalName])
    DeviceActivityCenter.onStart = {
        let provisional = current()
        _ = try ShieldRebuildHelper.recordUsageThreshold(defaults: defaults, groupId: "G",
            event: provisional.eventName(minute: 1), now: t.addingTimeInterval(73))
        throw NSError(domain: "TestDaemon", code: 2)
    }
    do {
        try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10, now: t.addingTimeInterval(13))
        expect(false, "Failed registration must fail the purchase")
    } catch {}
    expect(current().remainingMinutes == 8, "Failure must restore the original paid balance")
    expect(defaults.integer(forKey: SharedKeys.usageBudgetKey("G")) == 8,
           "Widget projection must roll back with the authoritative session")
case "first_purchase_failure":
    for key in [UsageBudgetSession.key("G"), SharedKeys.usageBudgetKey("G"),
                SharedKeys.usageBudgetInitialKey("G"), SharedKeys.usageBudgetStartedKey("G"),
                SharedKeys.usageBudgetExpiryKey("G")] { defaults.removeObject(forKey: key) }
    center.stopMonitoring([originalName])
    DeviceActivityCenter.onStart = {
        let provisional = current()
        _ = try ShieldRebuildHelper.recordUsageThreshold(defaults: defaults, groupId: "G",
            event: provisional.eventName(minute: 1), now: t.addingTimeInterval(73))
        throw NSError(domain: "TestDaemon", code: 2)
    }
    do {
        try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10, now: t.addingTimeInterval(13))
        expect(false, "Failed first registration must fail the purchase")
    } catch {}
    expect(UsageBudgetSession.load(from: defaults, groupId: "G") == nil, "Failed first purchase must remove provisional state")
    expect(ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: "G", at: t.addingTimeInterval(74)) == 0,
           "Failed first purchase must not leave unpaid legacy minutes")
case "legacy_recovery_failure":
    defaults.removeObject(forKey: UsageBudgetSession.key("G"))
    center.stopMonitoring([originalName])
    DeviceActivityCenter.failStart = true
    do {
        try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: "G", now: t.addingTimeInterval(13))
        expect(false, "Legacy recovery failure must propagate")
    } catch {}
    let paused = UsageBudgetSession.load(from: defaults, groupId: "G")
    expect(paused?.remainingMinutes == 10 && paused?.monitoringFailed == true,
           "Legacy paid minutes must become a paused session after failed recovery")
case "healthy_topup":
    try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: "G", minutes: 10, now: t.addingTimeInterval(13))
    expect(current().generation == original.generation && current().remainingMinutes == 20,
           "Healthy top-ups must retain Apple's partial usage and add paid minutes")
    expect(DeviceActivityCenter.startCalls == 0, "Healthy top-up must not replace its monitor")
case "continuation":
    original.queuedMinutes = 10
    original.save(to: defaults, groupId: "G")
    _ = try ShieldRebuildHelper.recordUsageThreshold(defaults: defaults, groupId: "G",
        event: original.eventName(minute: 10), now: t.addingTimeInterval(600))
    expect(current().remainingMinutes == 10 && !current().monitoringFailed, "Next segment must retain the paid queue")
    expect(current().generation != original.generation, "Next segment needs a fresh measurement")
    _ = try ShieldRebuildHelper.recordUsageThreshold(defaults: defaults, groupId: "G",
        event: original.eventName(minute: 10), now: t.addingTimeInterval(1200))
    expect(current().remainingMinutes == 10, "Replayed old final threshold must not spend the next segment")
default: fatalError("Unknown scenario")
}
print("PASS: " + CommandLine.arguments[1])
