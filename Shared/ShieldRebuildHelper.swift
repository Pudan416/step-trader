import Foundation
import Darwin
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

/// A paid wall-clock access pass. DeviceActivity only signals its end; usage
/// thresholds never change the deadline.
struct UsageBudgetSession: Codable, Equatable {
    let generation: String
    let initialMinutes: Int
    var monitoringFailed: Bool = false
    let startedAt: Date
    var expiresAt: Date

    init(minutes: Int, startedAt: Date, expiresAt: Date) {
        generation = UUID().uuidString
        initialMinutes = max(0, minutes)
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    var remainingMinutes: Int {
        max(0, Int(ceil(expiresAt.timeIntervalSinceNow / 60)))
    }

    func activityName(groupId: String) -> String { "timedAccess_\(groupId)_\(generation)" }
    func legacyActivityName(groupId: String) -> String { "usageBudget_\(groupId)" }

    static let keyPrefix = "timedAccessPass_v1_"
    static func key(_ groupId: String) -> String { "\(keyPrefix)\(groupId)" }
    static func load(from defaults: UserDefaults, groupId: String) -> Self? {
        guard let data = defaults.data(forKey: key(groupId)),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.initialMinutes > 0,
              value.expiresAt > value.startedAt else { return nil }
        return value
    }

    func save(to defaults: UserDefaults, groupId: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(groupId))
        // Compatibility projections used by app and widget snapshots.
        defaults.set(remainingMinutes, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(initialMinutes, forKey: SharedKeys.usageBudgetInitialKey(groupId))
        defaults.set(startedAt, forKey: SharedKeys.usageBudgetStartedKey(groupId))
        defaults.set(expiresAt, forKey: SharedKeys.usageBudgetExpiryKey(groupId))
    }
}

/// Device-level fence around account-specific Screen Time state.
enum UsageBudgetAccountBoundary {
    static let epochKey = "accountHistoryBudgetEpoch_v1"
    static let suspendedKey = "accountHistoryBudgetSuspended_v1"

    static func epoch(in defaults: UserDefaults) -> String {
        defaults.string(forKey: epochKey) ?? ""
    }

    static func accepts(_ epoch: String, in defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: suspendedKey) && self.epoch(in: defaults) == epoch
    }

    static func require(_ epoch: String, in defaults: UserDefaults) throws {
        guard accepts(epoch, in: defaults) else {
            throw NSError(domain: "Nowhere.AccountHistory", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Your account changed. Try again after it finishes loading."])
        }
    }

    /// Keep a valid pass's deadline but stop its old daemon identity before account data rotates.
    static func suspend(defaults: UserDefaults) -> [String] {
        defaults.set(true, forKey: suspendedKey)
        defaults.set(UUID().uuidString, forKey: epochKey)
        var names: [String] = []
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(UsageBudgetSession.keyPrefix) {
            let groupId = String(key.dropFirst(UsageBudgetSession.keyPrefix.count))
            guard var session = UsageBudgetSession.load(from: defaults, groupId: groupId) else { continue }
            names += [session.activityName(groupId: groupId), session.legacyActivityName(groupId: groupId)]
            session.monitoringFailed = true
            session.save(to: defaults, groupId: groupId)
        }
        defaults.synchronize()
        return names
    }

    static func resume(defaults: UserDefaults) {
        defaults.set(false, forKey: suspendedKey)
        defaults.synchronize()
    }
}

/// A small `flock` wrapper shared by the app and Screen Time extension.
/// Each operation opens its own descriptor so independent processes contend
/// on the same kernel lock rather than relying on in-process synchronization.
struct UsageBudgetFileLock: Sendable {
    let fileURL: URL

    func withLock<T>(_ body: () throws -> T) throws -> T {
        let descriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

/// Serializes monitor replacements without holding the state lock across the
/// Screen Time daemon call. DeviceActivity callbacks need the state lock and
/// can run synchronously while `startMonitoring` is waiting to return.
enum UsageBudgetRegistrationCoordinator {
    /// Exclude a registration waiting on the daemon and callbacks committing state.
    static func withAccountHistoryTransition<T>(
        stateLock: UsageBudgetFileLock,
        registrationLock: UsageBudgetFileLock,
        body: () throws -> T
    ) throws -> T {
        try registrationLock.withLock { try stateLock.withLock(body) }
    }

    static func perform<Prepared>(
        stateLock: UsageBudgetFileLock,
        registrationLock: UsageBudgetFileLock,
        prepare: () throws -> Prepared,
        register: (Prepared) throws -> Void,
        commit: (Prepared) throws -> Void,
        rollback: (Prepared) throws -> Void
    ) throws {
        try registrationLock.withLock {
            let prepared = try stateLock.withLock(prepare)
            do {
                try register(prepared)
                try stateLock.withLock { try commit(prepared) }
            } catch {
                try? stateLock.withLock { try rollback(prepared) }
                throw error
            }
        }
    }
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

    // MARK: - Timed access state

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

    /// The paid wall-clock deadline is the only source of remaining access.
    static func usageBudgetDeadline(defaults: UserDefaults, groupId: String) -> Date? {
        UsageBudgetSession.load(from: defaults, groupId: groupId)?.expiresAt
    }

    /// Returns the pass deadline while it is still in the future.
    static func usageBudgetDisplayExpiry(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Date? {
        guard let expiry = usageBudgetDeadline(defaults: defaults, groupId: groupId), expiry > now else { return nil }
        return expiry
    }

    static func remainingUsageBudget(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Int {
        guard let expiry = usageBudgetDeadline(defaults: defaults, groupId: groupId), expiry > now else { return 0 }
        return Int(ceil(expiry.timeIntervalSince(now) / 60))
    }

    /// The pass deadline is predictable and can be included in widget timelines.
    static func budgetObservationDates(from now: Date, through horizon: Date, expiries: [Date]) -> [Date] {
        guard horizon > now else { return [] }
        return Array(Set(expiries.filter { $0 > now && $0 <= horizon })).sorted()
    }

    /// Resolve only current timed-pass activities. Old usage-budget callbacks
    /// cannot match the new activity identity.
    static func groupIdForUsageActivity(defaults: UserDefaults, activityName: String) -> String? {
        guard UsageBudgetAccountBoundary.accepts(UsageBudgetAccountBoundary.epoch(in: defaults), in: defaults) else {
            return nil
        }
        for group in loadGroups(defaults: defaults) {
            guard let session = UsageBudgetSession.load(from: defaults, groupId: group.id) else { continue }
            if activityName == session.activityName(groupId: group.id) {
                return group.id
            }
        }
        return nil
    }

    static func hasRecoverableUsageBudget(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Bool {
        guard UsageBudgetAccountBoundary.accepts(UsageBudgetAccountBoundary.epoch(in: defaults), in: defaults) else {
            return false
        }
        guard let session = UsageBudgetSession.load(from: defaults, groupId: groupId),
              session.expiresAt > now else { return false }
        if session.monitoringFailed { return true }
        #if canImport(DeviceActivity)
        let name = DeviceActivityName(session.activityName(groupId: groupId))
        return DeviceActivityCenter().schedule(for: name) == nil
            || !DeviceActivityCenter().events(for: name).isEmpty
        #else
        return false
        #endif
    }

    private static func shouldSkipShieldingDueToActiveUsageBudget(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Bool {
        guard UsageBudgetAccountBoundary.accepts(UsageBudgetAccountBoundary.epoch(in: defaults), in: defaults) else {
            return false
        }
        guard let session = UsageBudgetSession.load(from: defaults, groupId: groupId) else { return false }
        return session.expiresAt > now && !session.monitoringFailed
    }

    static func isUsageBudgetActive(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Bool {
        shouldSkipShieldingDueToActiveUsageBudget(defaults: defaults, groupId: groupId, at: now)
    }

    // MARK: - Public

    /// Rebuild the shield from any process that links ManagedSettings.
    static func rebuild(startPendingBudgets: Bool = true) {
        #if canImport(ManagedSettings) && canImport(FamilyControls)
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupId) else {
            Logger(subsystem: "com.personalproject.StepsTrader", category: "ShieldRebuild").error("App group unavailable — skipping rebuild to preserve existing shields")
            return
        }
        clearLegacyUsageBudgets(defaults: defaults)

        // The app and monitor callbacks share the purchase state lock from
        // their first budget read through the actual settings assignment. An
        // obsolete snapshot can therefore never land after a newer purchase.
        let groups: [GroupTuple]
        do {
            groups = try withUsageBudgetLock {
                defaults.synchronize()
                var allApps = Set<ApplicationToken>()
                var allCategories = Set<ActivityCategoryToken>()
                var activeBudgetApps = Set<ApplicationToken>()
                var activeBudgetCategories = Set<ActivityCategoryToken>()

                let groups = loadGroups(defaults: defaults)

                for group in groups where group.active {
                    if shouldSkipShieldingDueToActiveUsageBudget(defaults: defaults, groupId: group.id) {
                        if let selectionData = group.selectionData,
                           let selection = cachedSelection(for: group.id, data: selectionData) {
                            activeBudgetApps.formUnion(selection.applicationTokens)
                            activeBudgetCategories.formUnion(selection.categoryTokens)
                        }
                        continue
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

                // An active purchase grants access even when another group or
                // legacy selection contains the same token. Keep unrelated
                // blockers, and exempt paid apps from remaining category shields.
                allApps.subtract(activeBudgetApps)
                allCategories.subtract(activeBudgetCategories)
                let store = ManagedSettingsStore(named: .init("shield"))
                store.shield.applications = allApps.isEmpty ? nil : allApps
                store.shield.applicationCategories = allCategories.isEmpty
                    ? nil
                    : .specific(allCategories, except: activeBudgetApps)

                // Readback describes our configured store. Effective enforcement still
                // requires a device check; iOS can enforce settings from other stores.
                let storedApps = store.shield.applications ?? []
                let activeBudgetAppsStillShielded = activeBudgetApps.intersection(storedApps).count

                defaults.set(0, forKey: SharedKeys.shieldState)

                logDiagnostic(
                    defaults: defaults,
                    apps: allApps.count,
                    categories: allCategories.count,
                    budgetApps: activeBudgetApps.count,
                    budgetAppsStillShielded: activeBudgetAppsStillShielded
                )
                defaults.synchronize()
                return groups
            }
        } catch {
            Logger(subsystem: "com.personalproject.StepsTrader", category: "ShieldRebuild")
                .error("Shield state lock unavailable — preserving existing shields: \(error.localizedDescription)")
            return
        }

        // Registration can synchronously deliver callbacks that need the state
        // lock. Always release it before contacting the Screen Time daemon.
        if startPendingBudgets {
            startPendingWidgetBudgets(defaults: defaults, groups: groups)
        }
        #endif
    }

    // MARK: - Usage Budget Schedule

    #if canImport(DeviceActivity)
    /// Shortest interval DeviceActivity accepts before throwing `MonitoringError.intervalTooShort`.
    static let minimumScheduleMinutes = 15

    /// Monitor through the paid pass deadline. Short passes pad only the start
    /// to satisfy DeviceActivity's minimum interval; the end stays exact.
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

    private static func usageBudgetLock(named filename: String) throws -> UsageBudgetFileLock {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId) else {
            throw NSError(domain: "Nowhere.UsageBudget", code: 2)
        }
        return UsageBudgetFileLock(fileURL: container.appendingPathComponent(filename))
    }

    /// Serialize persisted budget state across the app and monitor extension.
    static func withUsageBudgetLock<T>(_ body: () throws -> T) throws -> T {
        try usageBudgetLock(named: "usage-budget.lock").withLock(body)
    }

    static func withAccountHistoryTransitionLock<T>(_ body: () throws -> T) throws -> T {
        try UsageBudgetRegistrationCoordinator.withAccountHistoryTransition(
            stateLock: usageBudgetLock(named: "usage-budget.lock"),
            registrationLock: usageBudgetLock(named: "usage-budget-registration.lock"),
            body: body
        )
    }

    /// The new pass key intentionally does not decode old usage balances. Remove
    /// those balances and their monitors once so no old purchase survives rollout.
    static func clearLegacyUsageBudgets(defaults: UserDefaults) {
        guard defaults.integer(forKey: SharedKeys.timedAccessMigrationVersion) < 1 else { return }
        let shouldStopLegacyActivities: Bool
        do {
            shouldStopLegacyActivities = try withUsageBudgetLock {
                defaults.synchronize()
                guard defaults.integer(forKey: SharedKeys.timedAccessMigrationVersion) < 1 else { return false }
                let legacyPrefixes = [
                    "usageBudgetSession_v2_", "usageBudget_", "usageBudgetStarted_",
                    "usageBudgetInitial_", "usageBudgetExpiry_", "pendingBudgetMonitoring_",
                    "pendingBudgetMinutes_"
                ]
                for key in defaults.dictionaryRepresentation().keys
                    where legacyPrefixes.contains(where: { key.hasPrefix($0) }) {
                    defaults.removeObject(forKey: key)
                }
                defaults.set(1, forKey: SharedKeys.timedAccessMigrationVersion)
                defaults.synchronize()
                return true
            }
        } catch {
            Logger(subsystem: "com.personalproject.StepsTrader", category: "TimedAccess")
                .error("Could not clear legacy usage balances: \(error.localizedDescription)")
            return
        }
        guard shouldStopLegacyActivities else { return }
        let oldActivities = DeviceActivityCenter().activities.filter { $0.rawValue.hasPrefix("usageBudget_") }
        if !oldActivities.isEmpty { DeviceActivityCenter().stopMonitoring(oldActivities) }
    }

    private struct PreparedUsageBudgetRegistration {
        let session: UsageBudgetSession
        let previousValues: [(key: String, value: Any?)]
        let schedule: DeviceActivitySchedule
    }

    /// Build the replacement from current state only after both locks are held.
    /// A recovery may return nil when a newer generation already won.
    private static func register(
        defaults: UserDefaults,
        groupId: String,
        now: Date,
        accountEpoch: String,
        makeSession: () throws -> UsageBudgetSession?
    ) throws {
        let stateLock = try usageBudgetLock(named: "usage-budget.lock")
        let registrationLock = try usageBudgetLock(named: "usage-budget-registration.lock")
        var obsoleteActivityNames = Set<String>()
        var attemptedSession: UsageBudgetSession?
        do {
            try UsageBudgetRegistrationCoordinator.perform(
                stateLock: stateLock,
                registrationLock: registrationLock,
                prepare: { () throws -> PreparedUsageBudgetRegistration? in
                    defaults.synchronize()
                    try UsageBudgetAccountBoundary.require(accountEpoch, in: defaults)
                    guard let session = try makeSession() else { return nil }
                    guard let schedule = usageBudgetSchedule(endingAt: session.expiresAt, anchoredAt: now) else {
                        throw NSError(domain: "Nowhere.UsageBudget", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "The access pass has expired"])
                    }
                    var provisional = session
                    // Keep the group shielded until the deadline monitor is live.
                    provisional.monitoringFailed = true
                    let previous = defaults.data(forKey: UsageBudgetSession.key(groupId))
                    let previousValues = [
                        UsageBudgetSession.key(groupId),
                        SharedKeys.usageBudgetKey(groupId),
                        SharedKeys.usageBudgetInitialKey(groupId),
                        SharedKeys.usageBudgetStartedKey(groupId),
                        SharedKeys.usageBudgetExpiryKey(groupId)
                    ].map { (key: $0, value: defaults.object(forKey: $0)) }
                    obsoleteActivityNames.insert(session.legacyActivityName(groupId: groupId))
                    if let previous,
                       let previousSession = try? JSONDecoder().decode(UsageBudgetSession.self, from: previous) {
                        obsoleteActivityNames.insert(previousSession.activityName(groupId: groupId))
                    }
                    defaults.set(try JSONEncoder().encode(provisional), forKey: UsageBudgetSession.key(groupId))
                    defaults.synchronize()
                    attemptedSession = provisional
                    return PreparedUsageBudgetRegistration(
                        session: provisional,
                        previousValues: previousValues,
                        schedule: schedule
                    )
                },
                register: { prepared in
                    guard let prepared else { return }
                    // Never call the daemon under the state lock: it can deliver
                    // a callback before startMonitoring returns.
                    // Replace any prior deadline monitor before registering this pass.
                    let center = DeviceActivityCenter()
                    let previousActivities = obsoleteActivityNames
                        .filter { $0 != prepared.session.activityName(groupId: groupId) }
                        .map { DeviceActivityName($0) }
                    if !previousActivities.isEmpty { center.stopMonitoring(previousActivities) }
                    try center.startMonitoring(
                        DeviceActivityName(prepared.session.activityName(groupId: groupId)),
                        during: prepared.schedule,
                        events: [:]
                    )
                },
                commit: { prepared in
                    guard let prepared else { return }
                    defaults.synchronize()
                    try UsageBudgetAccountBoundary.require(accountEpoch, in: defaults)
                    guard var current = UsageBudgetSession.load(from: defaults, groupId: groupId),
                          current.generation == prepared.session.generation,
                          current.expiresAt > now else {
                        throw NSError(domain: "Nowhere.UsageBudget", code: 4,
                                      userInfo: [NSLocalizedDescriptionKey: "Screen Time monitoring could not be verified. The pass remains saved until its original expiry."])
                    }
                    current.monitoringFailed = false
                    current.save(to: defaults, groupId: groupId)
                    defaults.synchronize()
                },
                rollback: { prepared in
                    guard let prepared else { return }
                    defaults.synchronize()
                    guard UsageBudgetAccountBoundary.accepts(accountEpoch, in: defaults) else { return }
                    guard UsageBudgetSession.load(from: defaults, groupId: groupId)?.generation
                            == prepared.session.generation else { return }
                    // Restore both the session and widget/legacy projections,
                    // including absent keys on a failed first purchase.
                    for (key, value) in prepared.previousValues {
                        defaults.set(value, forKey: key)
                    }
                    // If replacement fails, keep the pass recoverable and shielded
                    // until a deadline monitor is live.
                    if var previous = UsageBudgetSession.load(from: defaults, groupId: groupId),
                       previous.remainingMinutes > 0 {
                        previous.monitoringFailed = true
                        previous.save(to: defaults, groupId: groupId)
                    }
                    defaults.synchronize()
                }
            )
        } catch {
            // A failed/invalidated new identity must not remain as an orphan.
            // The previous monitor is stopped only after a successful commit.
            if let attemptedSession {
                DeviceActivityCenter().stopMonitoring([
                    DeviceActivityName(attemptedSession.activityName(groupId: groupId))
                ])
            }
            rebuild(startPendingBudgets: false)
            throw error
        }

    }

    static func purchaseUsageBudget(defaults: UserDefaults, groupId: String, minutes: Int, now: Date = Date()) throws {
        guard minutes > 0 else { throw NSError(domain: "Nowhere.UsageBudget", code: 3) }
        let accountEpoch = try withUsageBudgetLock {
            defaults.synchronize()
            let epoch = UsageBudgetAccountBoundary.epoch(in: defaults)
            try UsageBudgetAccountBoundary.require(epoch, in: defaults)
            return epoch
        }
        try register(defaults: defaults, groupId: groupId, now: now, accountEpoch: accountEpoch) {
            defaults.synchronize()
            if let current = UsageBudgetSession.load(from: defaults, groupId: groupId), current.expiresAt > now {
                throw NSError(domain: "Nowhere.TimedAccess", code: 5,
                              userInfo: [NSLocalizedDescriptionKey: "This group already has an active access pass"])
            }
            let deadline = now.addingTimeInterval(TimeInterval(minutes * 60))
            return UsageBudgetSession(minutes: minutes, startedAt: now, expiresAt: deadline)
        }
    }

    /// Recovery restores only the deadline monitor. The paid deadline never moves.
    static func startUsageBudgetMonitoring(defaults: UserDefaults, groupId: String, now: Date = Date()) throws {
        let snapshot = try withUsageBudgetLock { () -> (session: UsageBudgetSession, accountEpoch: String) in
            defaults.synchronize()
            let accountEpoch = UsageBudgetAccountBoundary.epoch(in: defaults)
            try UsageBudgetAccountBoundary.require(accountEpoch, in: defaults)
            guard let session = UsageBudgetSession.load(from: defaults, groupId: groupId),
                  session.expiresAt > now else {
                throw NSError(domain: "Nowhere.UsageBudget", code: 1)
            }
            return (session, accountEpoch)
        }

        let center = DeviceActivityCenter()
        let name = DeviceActivityName(snapshot.session.activityName(groupId: groupId))
        if !snapshot.session.monitoringFailed,
           let desired = usageBudgetSchedule(endingAt: snapshot.session.expiresAt, anchoredAt: now),
           center.schedule(for: name)?.intervalEnd == desired.intervalEnd,
           center.events(for: name).isEmpty {
            return
        }

        do {
            try register(defaults: defaults, groupId: groupId, now: now, accountEpoch: snapshot.accountEpoch) {
                let current = UsageBudgetSession.load(from: defaults, groupId: groupId)
                guard current?.generation == snapshot.session.generation,
                      (current?.expiresAt ?? .distantPast) > now else { return nil }
                return current
            }
        } catch {
            try withUsageBudgetLock {
                defaults.synchronize()
                guard UsageBudgetAccountBoundary.accepts(snapshot.accountEpoch, in: defaults) else { return }
                let current = UsageBudgetSession.load(from: defaults, groupId: groupId)
                if var paused = current, paused.generation == snapshot.session.generation, paused.expiresAt > now {
                    paused.monitoringFailed = true
                    paused.save(to: defaults, groupId: groupId)
                }
                defaults.synchronize()
            }
            throw error
        }
    }

    #endif

    // MARK: - Pending Widget Pass Monitoring

    /// Starts DeviceActivity monitoring for widget-initiated passes. Called from rebuild()
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
            guard isUsageBudgetActive(defaults: defaults, groupId: group.id) else {
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
                // Keep the pending handoff for recovery; widget purchases register
                // synchronously before charging or removing shields.
            }
        }
        #endif
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private static func logDiagnostic(
        defaults: UserDefaults,
        apps: Int,
        categories: Int,
        budgetApps: Int,
        budgetAppsStillShielded: Int
    ) {
        let ts = isoFormatter.string(from: Date())
        let entry = "[\(ts)] [helper] apps=\(apps) cats=\(categories) budgetApps=\(budgetApps) budgetAppsStillShielded=\(budgetAppsStillShielded)"

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
