import Foundation
import os.log
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - Shared Codable Types
// Canonical definitions used by DeviceActivityMonitor, ShieldAction, and
// ShieldRebuildHelper to decode ticket-group / unlock-settings payloads
// from App Group UserDefaults.  Keep these at file scope so every target
// that includes Shared/ can reference them without qualification.

/// Minimal decoded view of per-app unlock settings stored under `appUnlockSettings_v1`.
struct StoredUnlockSettings: Codable {
    let entryCostSteps: Int?
    let familyControlsModeEnabled: Bool?
}

/// Lite ticket config written by the main app (`liteTicketConfig_v1` / `liteShieldConfig_v1`).
struct LiteConfig: Decodable {
    let groups: [LiteGroup]
}

/// A single group inside `LiteConfig`.
struct LiteGroup: Decodable {
    let id: String
    let name: String
    let selectionDataBase64: String
    let active: Bool
}

/// Full ticket-group payload decoded from `ticketGroups_v1` / `shieldGroups_v1`.
struct ShieldGroupData: Decodable {
    let id: String
    let name: String
    let selectionData: Data?
    let settings: SettingsBlock?

    var hasActiveSettings: Bool {
        settings?.familyControlsModeEnabled == true
    }

    struct SettingsBlock: Decodable {
        let familyControlsModeEnabled: Bool?
    }
}

/// Resolved group tuple returned by `ShieldRebuildHelper.loadGroups`.
struct GroupTuple {
    let id: String
    let name: String
    let selectionData: Data?
    let active: Bool
}

// MARK: - Shield Rebuild

/// Shared shield rebuild logic used by the main app, widget extension, and
/// DeviceActivityMonitor extension.  Reads ticket groups from the App Group
/// UserDefaults, skips unlocked groups, unions the remaining selections, and
/// applies the result to `ManagedSettingsStore(named: "shield")`.
enum ShieldRebuildHelper {

    // MARK: - Decoded Selection Cache
    #if canImport(FamilyControls)
    private static let cacheLock = NSLock()
    private static var decodedSelectionCache: [String: FamilyActivitySelection] = [:]
    private static var cacheDataBytes: [String: Data] = [:]

    static func cachedSelection(for groupId: String, data: Data) -> FamilyActivitySelection? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cacheDataBytes[groupId], cached == data {
            return decodedSelectionCache[groupId]
        }
        guard let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return nil
        }
        decodedSelectionCache[groupId] = sel
        cacheDataBytes[groupId] = data
        return sel
    }

    static func invalidateSelectionCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        decodedSelectionCache.removeAll()
        cacheDataBytes.removeAll()
    }
    #endif

    // MARK: - Usage budget (wall clock)

    /// Interprets plist values from App Group UserDefaults (any process).
    private static func coercedDate(from object: Any?) -> Date? {
        switch object {
        case let d as Date:
            return d
        case let d as NSDate:
            return d as Date
        case let n as NSNumber:
            return Date(timeIntervalSince1970: n.doubleValue)
        default:
            return nil
        }
    }

    /// True while a positive usage budget should keep the group unshielded (wall-clock purchase window).
    /// - Important: If `usageBudgetExpiry` is missing (CFPreferences lag after widget unlock, or legacy data),
    ///   we infer the window from `usageBudgetStarted` + `usageBudgetInitial` instead of wiping the budget.
    ///   Previously, nil expiry was treated as expired and keys were removed — main app then showed 0 min.
    private static func shouldSkipShieldingDueToActiveUsageBudget(defaults: UserDefaults, groupId: String) -> Bool {
        let budgetKey = SharedKeys.usageBudgetKey(groupId)
        guard defaults.integer(forKey: budgetKey) > 0 else { return false }

        let expiryObj = defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
        if let expiry = coercedDate(from: expiryObj) {
            return Date() < expiry
        }

        let started = coercedDate(from: defaults.object(forKey: SharedKeys.usageBudgetStartedKey(groupId)))
        let initial = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(groupId))
        if let started, initial > 0 {
            return Date() < started.addingTimeInterval(TimeInterval(initial * 60))
        }

        // Budget > 0 but no usable timing metadata — default to shielded to prevent bypass.
        return false
    }

    /// Whether prefs show an active usage budget whose wall-clock window has not passed (Screen Time budget may still apply separately).
    static func isUsageBudgetWallClockActive(defaults: UserDefaults, groupId: String) -> Bool {
        guard defaults.integer(forKey: SharedKeys.usageBudgetKey(groupId)) > 0 else { return false }
        return shouldSkipShieldingDueToActiveUsageBudget(defaults: defaults, groupId: groupId)
    }

    // MARK: - Public

    /// Rebuild the shield from any process that links ManagedSettings.
    static func rebuild() {
        #if canImport(ManagedSettings) && canImport(FamilyControls)
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupId) else {
            Logger(subsystem: "com.personalproject.StepsTrader", category: "ShieldRebuild").error("App group unavailable — skipping rebuild to preserve existing shields")
            return
        }

        var allApps = Set<ApplicationToken>()
        var allCategories = Set<ActivityCategoryToken>()

        let groups = loadGroups(defaults: defaults)

        for group in groups where group.active {
            let budgetKey = SharedKeys.usageBudgetKey(group.id)
            if defaults.integer(forKey: budgetKey) > 0 {
                if shouldSkipShieldingDueToActiveUsageBudget(defaults: defaults, groupId: group.id) {
                    continue
                }
                defaults.removeObject(forKey: budgetKey)
                defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(group.id))
            }

            guard let selectionData = group.selectionData else { continue }
            guard let sel = cachedSelection(for: group.id, data: selectionData) else { continue }

            allApps.formUnion(sel.applicationTokens)
            allCategories.formUnion(sel.categoryTokens)
        }

        // Legacy per-app selections
        if let data = defaults.data(forKey: SharedKeys.appUnlockSettings),
           let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data) {
            for (bundleId, settings) in decoded where settings.familyControlsModeEnabled == true {
                let key = SharedKeys.timeAccessSelectionKey(bundleId)
                if let selData = defaults.data(forKey: key),
                   let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selData) {
                    allApps.formUnion(sel.applicationTokens)
                    allCategories.formUnion(sel.categoryTokens)
                }
            }
        }

        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = allApps.isEmpty ? nil : allApps
        store.shield.applicationCategories = allCategories.isEmpty
            ? nil
            : .specific(allCategories)

        defaults.set(0, forKey: SharedKeys.shieldState)

        startPendingWidgetBudgets(defaults: defaults, groups: groups)

        logDiagnostic(defaults: defaults, apps: allApps.count, categories: allCategories.count)
        #endif
    }

    // MARK: - Pending Widget Budget Monitoring

    /// Starts DeviceActivity monitoring for widget-initiated budgets. Called from rebuild()
    /// so monitoring begins immediately when the widget removes the shield, rather than
    /// waiting for the main app to foreground (which may be minutes/hours later).
    private static func startPendingWidgetBudgets(defaults: UserDefaults, groups: [GroupTuple]) {
        #if canImport(DeviceActivity) && canImport(FamilyControls)
        let center = DeviceActivityCenter()

        for group in groups where group.active {
            let pendingKey = SharedKeys.pendingBudgetMonitoringPrefix + group.id
            let minutesKey = SharedKeys.pendingBudgetMinutesPrefix + group.id
            guard defaults.bool(forKey: pendingKey) else { continue }

            let minutes = defaults.integer(forKey: minutesKey)
            guard minutes > 0 else {
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                continue
            }

            guard defaults.integer(forKey: SharedKeys.usageBudgetKey(group.id)) > 0 else {
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                continue
            }

            guard let selectionData = group.selectionData,
                  let sel = cachedSelection(for: group.id, data: selectionData)
            else { continue }

            let activityName = DeviceActivityName("usageBudget_\(group.id)")
            guard !center.activities.contains(activityName) else {
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                continue
            }

            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for m in 1..<minutes {
                events[DeviceActivityEvent.Name("usageBudgetTick_\(group.id)_\(m)")] = DeviceActivityEvent(
                    applications: sel.applicationTokens,
                    categories: sel.categoryTokens,
                    threshold: DateComponents(minute: m)
                )
            }

            let widgetMilestones: [Double] = [0.25, 0.50, 0.75, 0.90]
            var seenWidgetMinutes = Set<Int>()
            for frac in widgetMilestones {
                let m = Int(Double(minutes) * frac)
                guard m >= 1, m < minutes, !seenWidgetMinutes.contains(m) else { continue }
                seenWidgetMinutes.insert(m)
                events[DeviceActivityEvent.Name("usageBudgetWidgetTick_\(group.id)_\(m)")] = DeviceActivityEvent(
                    applications: sel.applicationTokens,
                    categories: sel.categoryTokens,
                    threshold: DateComponents(minute: m)
                )
            }

            events[DeviceActivityEvent.Name("usageBudgetDone_\(group.id)")] = DeviceActivityEvent(
                applications: sel.applicationTokens,
                categories: sel.categoryTokens,
                threshold: DateComponents(minute: minutes)
            )

            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
                repeats: true
            )

            do {
                try center.startMonitoring(activityName, during: schedule, events: events)
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)

                let ts = isoFormatter.string(from: Date())
                let msg = "[\(ts)] OK usageBudget_\(group.id) \(minutes)m events=\(events.count) apps=\(sel.applicationTokens.count) sched=[start=0:0:0 end=23:59:59] activities=\(center.activities.map(\.rawValue))"
                defaults.set(msg, forKey: SharedKeys.lastStartMonitoringLog)
            } catch {
                // Don't clear pending keys on failure — the extension or main app will retry
            }
        }
        #endif
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private static func logDiagnostic(defaults: UserDefaults, apps: Int, categories: Int) {
        let ts = isoFormatter.string(from: Date())
        let entry = "[\(ts)] [helper] apps=\(apps) cats=\(categories)"

        var history = defaults.stringArray(forKey: SharedKeys.shieldDiagHistory) ?? []
        history.append(entry)
        if history.count > 20 { history = Array(history.suffix(20)) }
        defaults.set(history, forKey: SharedKeys.shieldDiagHistory)
        defaults.set(entry, forKey: SharedKeys.shieldDiagLastRebuild)
    }

    // MARK: - Group Loading

    /// Load ticket groups from UserDefaults, preferring lite config over full payload.
    /// Shared across DeviceActivityMonitor, ShieldAction, and the rebuild logic.
    static func loadGroups(defaults: UserDefaults) -> [GroupTuple] {
        if let liteData = defaults.data(forKey: SharedKeys.liteTicketConfig),
           let lite = try? JSONDecoder().decode(LiteConfig.self, from: liteData) {
            return lite.groups.map {
                GroupTuple(id: $0.id, name: $0.name,
                           selectionData: Data(base64Encoded: $0.selectionDataBase64),
                           active: $0.active)
            }
        }
        if let liteData = defaults.data(forKey: SharedKeys.liteShieldConfig),
           let lite = try? JSONDecoder().decode(LiteConfig.self, from: liteData) {
            return lite.groups.map {
                GroupTuple(id: $0.id, name: $0.name,
                           selectionData: Data(base64Encoded: $0.selectionDataBase64),
                           active: $0.active)
            }
        }
        let groupsData = defaults.data(forKey: SharedKeys.ticketGroups)
            ?? defaults.data(forKey: SharedKeys.legacyShieldGroups)
        guard let data = groupsData,
              let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: data)
        else { return [] }
        return groups.map {
            GroupTuple(id: $0.id, name: $0.name,
                       selectionData: $0.selectionData,
                       active: $0.hasActiveSettings)
        }
    }
}
