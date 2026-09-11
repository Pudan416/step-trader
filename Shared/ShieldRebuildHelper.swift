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
///
/// ## Threading contract (§3.8)
///
/// `ShieldRebuildHelper` is intentionally a stateless enum (no instances),
/// safe to call from ANY actor context including non-`@MainActor`:
///
/// - **Main app**: called from `@MainActor` after ticket-group / settings changes.
/// - **DeviceActivityMonitor extension**: called from `intervalDidStart` /
///   `eventDidReachThreshold` on a system-chosen background thread.
/// - **UnlockWidget extension**: called from widget timeline provider on
///   a `Sendable` background actor.
///
/// All inputs are `Sendable` (`Data`, `String`, `[String: Any]` via UserDefaults).
/// All outputs are value types (`GroupTuple`, etc.). The decoded-selection
/// cache below is the only mutable state — it is guarded by `NSLock` and is
/// safe to read/write from any thread.
///
/// `ManagedSettingsStore(named:)` is thread-safe per Apple's documentation;
/// the synchronous `rebuild()` call below is safe to invoke from extension
/// callbacks without hopping to MainActor.
enum ShieldRebuildHelper {

    // MARK: - Decoded Selection Cache
    //
    // §3.8: mutable state — accessed from multiple processes (main app +
    // extensions) via shared static memory. Guarded by `cacheLock`. Cache
    // hit avoids ~10ms NSKeyedUnarchiver work per call site.
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

    /// The stored deadline is authoritative; legacy records can recover it from start + initial.
    static func usageBudgetDeadline(defaults: UserDefaults, groupId: String) -> Date? {
        if let expiry = coercedDate(from: defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(groupId))) {
            return expiry
        }
        guard let started = coercedDate(from: defaults.object(forKey: SharedKeys.usageBudgetStartedKey(groupId))) else { return nil }
        let initial = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(groupId))
        return initial > 0 ? started.addingTimeInterval(TimeInterval(initial) * 60) : nil
    }

    /// A single observation shared by the app and widgets. Legacy usage counters may
    /// shorten a window, but can never advertise access beyond its wall-clock deadline.
    static func usageBudgetDisplayExpiry(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Date? {
        let stored = defaults.integer(forKey: SharedKeys.usageBudgetKey(groupId))
        guard stored > 0, let expiry = usageBudgetDeadline(defaults: defaults, groupId: groupId), expiry > now else { return nil }
        return min(expiry, now.addingTimeInterval(TimeInterval(stored) * 60))
    }

    static func remainingUsageBudget(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Int {
        guard let expiry = usageBudgetDisplayExpiry(defaults: defaults, groupId: groupId, at: now) else { return 0 }
        return Int(ceil(expiry.timeIntervalSince(now) / 60))
    }

    /// Precompute the labels' minute transitions and closed state inside a widget
    /// timeline. These entries need no additional WidgetKit reload budget.
    static func budgetObservationDates(from now: Date, through horizon: Date, expiries: [Date]) -> [Date] {
        guard horizon > now else { return [] }
        var dates = Set<Date>()
        for expiry in expiries where expiry > now {
            let wholeMinutes = floor(expiry.timeIntervalSince(now) / 60)
            var tick = expiry.addingTimeInterval(-wholeMinutes * 60)
            if tick <= now { tick = tick.addingTimeInterval(60) }
            while tick <= min(expiry, horizon) {
                dates.insert(tick)
                tick = tick.addingTimeInterval(60)
            }
        }
        return dates.sorted()
    }

    private static func shouldSkipShieldingDueToActiveUsageBudget(defaults: UserDefaults, groupId: String) -> Bool {
        usageBudgetDisplayExpiry(defaults: defaults, groupId: groupId) != nil
    }

    static func isUsageBudgetWallClockActive(defaults: UserDefaults, groupId: String) -> Bool {
        shouldSkipShieldingDueToActiveUsageBudget(defaults: defaults, groupId: groupId)
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

    // MARK: - Usage Budget Schedule

    #if canImport(DeviceActivity)
    /// Shortest interval DeviceActivity accepts before throwing `MonitoringError.intervalTooShort`.
    static let minimumScheduleMinutes = 15

    /// The nonrepeating interval ends at the purchased deadline. For short windows,
    /// only its start is padded into the past to satisfy DeviceActivity's 15-minute
    /// minimum. Full date components preserve windows that cross midnight.
    ///
    /// No usage events are attached: historical activity during that padding must
    /// not spend the new window. The contract is elapsed time, not foreground usage.
    /// Apple delivers interval callbacks when the device is used, not while asleep.
    static func usageBudgetSchedule(
        endingAt expiry: Date,
        anchoredAt now: Date = Date(),
        calendar: Calendar = .current
    ) -> DeviceActivitySchedule? {
        guard expiry > now else { return nil }
        // Never round the end down: an early callback would see a still-valid expiry
        // and there would be no later interval-end callback to clear the shield.
        let end = Date(timeIntervalSince1970: ceil(expiry.timeIntervalSince1970))
        let start = Date(timeIntervalSince1970: floor(min(
            now.timeIntervalSince1970,
            end.timeIntervalSince1970 - TimeInterval(minimumScheduleMinutes * 60)
        )))
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        var startComponents = calendar.dateComponents(components, from: start)
        var endComponents = calendar.dateComponents(components, from: end)
        startComponents.calendar = calendar
        startComponents.timeZone = calendar.timeZone
        endComponents.calendar = calendar
        endComponents.timeZone = calendar.timeZone
        return DeviceActivitySchedule(intervalStart: startComponents, intervalEnd: endComponents, repeats: false)
    }

    /// Registration succeeds before a purchase removes the shield. Replacing the
    /// same activity avoids the extra slot and stale callback race of stop-then-start.
    static func startUsageBudgetMonitoring(defaults: UserDefaults, groupId: String, now: Date = Date()) throws {
        guard let expiry = usageBudgetDeadline(defaults: defaults, groupId: groupId),
              let schedule = usageBudgetSchedule(endingAt: expiry, anchoredAt: now) else {
            throw NSError(domain: "Nowhere.UsageBudget", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Access window has expired"])
        }
        try DeviceActivityCenter().startMonitoring(
            DeviceActivityName("usageBudget_\(groupId)"), during: schedule, events: [:])
    }
    #endif

    // MARK: - Pending Widget Budget Monitoring

    /// Starts DeviceActivity monitoring for widget-initiated budgets. Called from rebuild()
    /// so monitoring begins immediately when the widget removes the shield, rather than
    /// waiting for the main app to foreground (which may be minutes/hours later).
    static func startPendingWidgetBudgets() {
        let defaults = SharedKeys.appGroupDefaults()
        startPendingWidgetBudgets(defaults: defaults, groups: loadGroups(defaults: defaults))
    }

    private static func startPendingWidgetBudgets(defaults: UserDefaults, groups: [GroupTuple]) {
        #if canImport(DeviceActivity) && canImport(FamilyControls)
        for group in groups where group.active {
            let pendingKey = SharedKeys.pendingBudgetMonitoringPrefix + group.id
            let minutesKey = SharedKeys.pendingBudgetMinutesPrefix + group.id
            guard defaults.bool(forKey: pendingKey) else { continue }
            guard isUsageBudgetWallClockActive(defaults: defaults, groupId: group.id) else {
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                continue
            }
            do {
                // Always replace: an older monitor may still target an earlier purchase.
                try startUsageBudgetMonitoring(defaults: defaults, groupId: group.id)
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
            } catch {
                // Keep the pending handoff for recovery; new widget purchases register
                // synchronously before charging or removing shields.
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
