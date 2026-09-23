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

enum UsageBudgetThresholdResult: Equatable {
    case ignored
    case recorded
    case implausible
}

/// One immutable Screen Time measurement interval. Extra purchases queue behind
/// it, so topping up cannot reset Apple's fractional usage already accumulated.
struct UsageBudgetSession: Codable, Equatable {
    let generation: String
    let initialMinutes: Int
    var consumedMinutes: Int = 0
    var queuedMinutes: Int = 0
    var monitoringFailed: Bool = false
    var monitoredSelectionData: Data? = nil
    var lastRecordedAt: Date? = nil
    /// Once a generation reports impossible usage, no later event from it is trusted.
    var invalidatedAt: Date? = nil
    let startedAt: Date
    var expiresAt: Date

    init(minutes: Int, startedAt: Date, expiresAt: Date) {
        generation = UUID().uuidString
        initialMinutes = min(60, minutes)
        queuedMinutes = max(0, minutes - initialMinutes)
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    var remainingMinutes: Int { max(0, initialMinutes - consumedMinutes) + queuedMinutes }
    var needsNextSegment: Bool { consumedMinutes >= initialMinutes && queuedMinutes > 0 }
    func eventName(minute: Int) -> String { "usageV2_\(generation)_\(minute)" }
    func activityName(groupId: String) -> String { "usageBudget_\(groupId)_\(generation)" }
    func legacyActivityName(groupId: String) -> String { "usageBudget_\(groupId)" }

    /// Cumulative thresholds can arrive twice or out of order. A generation
    /// belongs to exactly one registration, never to a later purchase.
    mutating func record(event: String, at now: Date) -> UsageBudgetThresholdResult {
        let prefix = "usageV2_\(generation)_"
        guard invalidatedAt == nil,
              event.hasPrefix(prefix), let minute = Int(event.dropFirst(prefix.count)),
              minute > consumedMinutes, minute <= initialMinutes else { return .ignored }

        // Callback delivery can be delayed or batched. Its arrival time is not
        // the time the user reached the threshold, so validate only against the
        // entire measurement interval. Elapsed time is a plausibility ceiling,
        // never evidence that idle time should spend a paid minute.
        let earlyTolerance: TimeInterval = 10
        guard now.timeIntervalSince(startedAt) + earlyTolerance
                >= TimeInterval(minute * 60) else {
            return .implausible
        }
        consumedMinutes = minute
        lastRecordedAt = now
        return .recorded
    }

    static func key(_ groupId: String) -> String { "usageBudgetSession_v2_\(groupId)" }
    static func load(from defaults: UserDefaults, groupId: String) -> Self? {
        guard let data = defaults.data(forKey: key(groupId)),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.initialMinutes > 0, value.consumedMinutes >= 0,
              value.consumedMinutes <= value.initialMinutes, value.queuedMinutes >= 0 else { return nil }
        return value
    }

    func save(to defaults: UserDefaults, groupId: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key(groupId))
        // Compatibility projection for existing widget progress and diagnostics.
        defaults.set(remainingMinutes, forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.set(initialMinutes + queuedMinutes, forKey: SharedKeys.usageBudgetInitialKey(groupId))
        defaults.set(startedAt, forKey: SharedKeys.usageBudgetStartedKey(groupId))
        defaults.set(expiresAt, forKey: SharedKeys.usageBudgetExpiryKey(groupId))
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

    // MARK: - Usage budget

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
        if let session = UsageBudgetSession.load(from: defaults, groupId: groupId) { return session.expiresAt }
        if let expiry = coercedDate(from: defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(groupId))) {
            return expiry
        }
        guard let started = coercedDate(from: defaults.object(forKey: SharedKeys.usageBudgetStartedKey(groupId))) else { return nil }
        let initial = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(groupId))
        return initial > 0 ? started.addingTimeInterval(TimeInterval(initial) * 60) : nil
    }

    /// Calendar validity only for usage sessions. It must never be displayed
    /// as a countdown; remaining minutes come from recorded usage thresholds.
    /// Pre-v2 records retain their original deadline until replaced/expired.
    static func usageBudgetDisplayExpiry(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Date? {
        if let session = UsageBudgetSession.load(from: defaults, groupId: groupId) {
            return session.remainingMinutes > 0 && session.expiresAt > now ? session.expiresAt : nil
        }
        let stored = defaults.integer(forKey: SharedKeys.usageBudgetKey(groupId))
        guard stored > 0, let expiry = usageBudgetDeadline(defaults: defaults, groupId: groupId), expiry > now else { return nil }
        return min(expiry, now.addingTimeInterval(TimeInterval(stored) * 60))
    }

    static func remainingUsageBudget(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Int {
        if let session = UsageBudgetSession.load(from: defaults, groupId: groupId) {
            return session.expiresAt > now ? session.remainingMinutes : 0
        }
        guard let expiry = usageBudgetDisplayExpiry(defaults: defaults, groupId: groupId, at: now) else { return 0 }
        return Int(ceil(expiry.timeIntervalSince(now) / 60))
    }

    /// Only the custom-day expiry is predictable. Usage changes trigger widget
    /// reloads from DeviceActivity; idle time cannot generate minute transitions.
    static func budgetObservationDates(from now: Date, through horizon: Date, expiries: [Date]) -> [Date] {
        guard horizon > now else { return [] }
        return Array(Set(expiries.filter { $0 > now && $0 <= horizon })).sorted()
    }

    static func usageSelectionMatches(defaults: UserDefaults, groupId: String, session: UsageBudgetSession) -> Bool {
        #if canImport(FamilyControls)
        guard let originalData = session.monitoredSelectionData,
              let currentData = loadGroups(defaults: defaults).first(where: { $0.id == groupId && $0.active })?.selectionData,
              let original = try? JSONDecoder().decode(FamilyActivitySelection.self, from: originalData),
              let current = cachedSelection(for: groupId, data: currentData) else { return false }
        return original.applicationTokens == current.applicationTokens
            && original.categoryTokens == current.categoryTokens
            && original.webDomainTokens == current.webDomainTokens
        #else
        return false
        #endif
    }

    /// Resolve callbacks by the persisted session instead of parsing group IDs
    /// out of the activity string. Old activity generations then become harmless.
    static func groupIdForUsageActivity(defaults: UserDefaults, activityName: String) -> String? {
        for group in loadGroups(defaults: defaults) {
            guard let session = UsageBudgetSession.load(from: defaults, groupId: group.id) else { continue }
            if activityName == session.activityName(groupId: group.id)
                || activityName == session.legacyActivityName(groupId: group.id) {
                return group.id
            }
        }
        return nil
    }

    static func hasRecoverableUsageBudget(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Bool {
        guard let session = UsageBudgetSession.load(from: defaults, groupId: groupId),
              session.expiresAt > now, session.remainingMinutes > 0 else { return false }
        return session.needsNextSegment || session.monitoringFailed
            || !usageSelectionMatches(defaults: defaults, groupId: groupId, session: session)
    }

    private static func shouldSkipShieldingDueToActiveUsageBudget(defaults: UserDefaults, groupId: String, at now: Date = Date()) -> Bool {
        guard remainingUsageBudget(defaults: defaults, groupId: groupId, at: now) > 0 else { return false }
        guard let session = UsageBudgetSession.load(from: defaults, groupId: groupId) else { return true }
        return !session.needsNextSegment && !session.monitoringFailed
            && usageSelectionMatches(defaults: defaults, groupId: groupId, session: session)
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

        var allApps = Set<ApplicationToken>()
        var allCategories = Set<ActivityCategoryToken>()

        let groups = loadGroups(defaults: defaults)

        for group in groups where group.active {
            if shouldSkipShieldingDueToActiveUsageBudget(defaults: defaults, groupId: group.id) {
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

        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = allApps.isEmpty ? nil : allApps
        store.shield.applicationCategories = allCategories.isEmpty
            ? nil
            : .specific(allCategories)

        defaults.set(0, forKey: SharedKeys.shieldState)

        // DeviceActivity callbacks must return before another monitor replacement.
        // The app can opt in (the default); the extension explicitly opts out.
        if startPendingBudgets {
            startPendingWidgetBudgets(defaults: defaults, groups: groups)
        }

        logDiagnostic(defaults: defaults, apps: allApps.count, categories: allCategories.count)
        #endif
    }

    // MARK: - Usage Budget Schedule

    #if canImport(DeviceActivity)
    /// Shortest interval DeviceActivity accepts before throwing `MonitoringError.intervalTooShort`.
    static let minimumScheduleMinutes = 15

    /// Monitor through the custom day end, independently of purchased minutes.
    /// If less than 15 calendar minutes remain, pad only the start; each event
    /// excludes past activity so the padding cannot spend the new purchase.
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

    static func usageEvents(selection: FamilyActivitySelection, session: UsageBudgetSession) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        // Each event fires once at its cumulative threshold. No repeating tick
        // assumption and no stop/start chain while this segment is in use.
        Dictionary(uniqueKeysWithValues: (1...session.initialMinutes).map { minute in
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                event = DeviceActivityEvent(applications: selection.applicationTokens,
                    categories: selection.categoryTokens, webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: minute), includesPastActivity: false)
            } else {
                event = DeviceActivityEvent(applications: selection.applicationTokens,
                    categories: selection.categoryTokens, webDomains: selection.webDomainTokens,
                    threshold: DateComponents(minute: minute))
            }
            return (DeviceActivityEvent.Name(session.eventName(minute: minute)), event)
        })
    }

    private struct PreparedUsageBudgetRegistration {
        let session: UsageBudgetSession
        let previousValues: [(key: String, value: Any?)]
        let schedule: DeviceActivitySchedule
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent]
    }

    /// Build the replacement from current state only after both locks are held.
    /// A queued recovery may return nil when a newer generation already won.
    private static func register(
        defaults: UserDefaults,
        groupId: String,
        now: Date,
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
                    guard let session = try makeSession() else { return nil }
                    guard let schedule = usageBudgetSchedule(endingAt: session.expiresAt, anchoredAt: now),
                          let data = loadGroups(defaults: defaults).first(where: { $0.id == groupId && $0.active })?.selectionData,
                          let selection = cachedSelection(for: groupId, data: data),
                          !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
                        throw NSError(domain: "Nowhere.UsageBudget", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "No applications selected or today's usage budget has expired"])
                    }
                    var provisional = session
                    provisional.monitoredSelectionData = data
                    // A provisional monitor must not open access. Its callbacks
                    // can still record valid usage or invalidate this generation.
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
                        schedule: schedule,
                        events: usageEvents(selection: selection, session: provisional)
                    )
                },
                register: { prepared in
                    guard let prepared else { return }
                    // Never call the daemon under the state lock: it can deliver
                    // a callback before startMonitoring returns.
                    // End the previous measurement before starting the next one.
                    // Overlapping monitors for the same selection let Screen Time
                    // carry the old usage baseline into the replacement on device.
                    let center = DeviceActivityCenter()
                    let previousActivities = obsoleteActivityNames
                        .filter { $0 != prepared.session.activityName(groupId: groupId) }
                        .map { DeviceActivityName($0) }
                    if !previousActivities.isEmpty { center.stopMonitoring(previousActivities) }
                    try center.startMonitoring(
                        DeviceActivityName(prepared.session.activityName(groupId: groupId)),
                        during: prepared.schedule,
                        events: prepared.events
                    )
                },
                commit: { prepared in
                    guard let prepared else { return }
                    defaults.synchronize()
                    guard var current = UsageBudgetSession.load(from: defaults, groupId: groupId),
                          current.generation == prepared.session.generation,
                          current.invalidatedAt == nil else {
                        throw NSError(domain: "Nowhere.UsageBudget", code: 4,
                                      userInfo: [NSLocalizedDescriptionKey: "Screen Time monitoring could not be verified. Your unused minutes are saved."])
                    }
                    current.monitoringFailed = false
                    current.monitoredSelectionData = prepared.session.monitoredSelectionData
                    current.save(to: defaults, groupId: groupId)
                    defaults.synchronize()
                },
                rollback: { prepared in
                    guard let prepared else { return }
                    defaults.synchronize()
                    guard UsageBudgetSession.load(from: defaults, groupId: groupId)?.generation
                            == prepared.session.generation else { return }
                    // Restore both the session and widget/legacy projections,
                    // including absent keys on a failed first purchase.
                    for (key, value) in prepared.previousValues {
                        defaults.set(value, forKey: key)
                    }
                    // The former monitor was stopped before registration. If
                    // replacement fails, keep its paid balance recoverable but
                    // shielded until another monitor is live.
                    if var previous = UsageBudgetSession.load(from: defaults, groupId: groupId),
                       previous.remainingMinutes > 0 {
                        previous.monitoringFailed = true
                        previous.invalidatedAt = previous.invalidatedAt ?? now
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

        let candidate = try withUsageBudgetLock {
            defaults.synchronize()
            return UsageBudgetSession.load(from: defaults, groupId: groupId)
        }
        let hasRegisteredFinalEvent: Bool
        if let candidate {
            hasRegisteredFinalEvent = DeviceActivityCenter()
                .events(for: DeviceActivityName(candidate.activityName(groupId: groupId)))[
                    DeviceActivityEvent.Name(candidate.eventName(minute: candidate.initialMinutes))
                ] != nil
        } else {
            hasRegisteredFinalEvent = false
        }

        let didTopUp = try withUsageBudgetLock {
            defaults.synchronize()
            defer { defaults.synchronize() }
            if var session = UsageBudgetSession.load(from: defaults, groupId: groupId),
               session.generation == candidate?.generation,
               session.expiresAt > now, session.remainingMinutes > 0,
               !session.needsNextSegment, !session.monitoringFailed,
               usageSelectionMatches(defaults: defaults, groupId: groupId, session: session),
               hasRegisteredFinalEvent {
                session.queuedMinutes += minutes
                session.save(to: defaults, groupId: groupId)
                return true
            }
            return false
        }
        guard !didTopUp else { return }

        try register(defaults: defaults, groupId: groupId, now: now) {
            let deadline = DayBoundary.purchaseExpiry(minutes: minutes,
                dayEndHour: defaults.integer(forKey: SharedKeys.dayEndHour),
                dayEndMinute: defaults.integer(forKey: SharedKeys.dayEndMinute), now: now)
            let existing = remainingUsageBudget(defaults: defaults, groupId: groupId, at: now)
            return UsageBudgetSession(minutes: existing + minutes, startedAt: now, expiresAt: deadline)
        }
    }

    /// Recovery runs only when the registered interval/events are missing. It
    /// retains confirmed unspent minutes, never subtracts elapsed clock time.
    static func startUsageBudgetMonitoring(defaults: UserDefaults, groupId: String, now: Date = Date()) throws {
        let snapshot = try withUsageBudgetLock { () -> (deadline: Date, session: UsageBudgetSession?) in
            defaults.synchronize()
            let remaining = remainingUsageBudget(defaults: defaults, groupId: groupId, at: now)
            guard remaining > 0, let deadline = usageBudgetDeadline(defaults: defaults, groupId: groupId) else {
                throw NSError(domain: "Nowhere.UsageBudget", code: 1)
            }
            return (deadline, UsageBudgetSession.load(from: defaults, groupId: groupId))
        }

        let center = DeviceActivityCenter()
        let name = snapshot.session.map { DeviceActivityName($0.activityName(groupId: groupId)) }
        if let session = snapshot.session,
           !session.needsNextSegment, !session.monitoringFailed,
           usageSelectionMatches(defaults: defaults, groupId: groupId, session: session),
           let desired = usageBudgetSchedule(endingAt: snapshot.deadline, anchoredAt: now),
           let name,
           center.schedule(for: name)?.intervalEnd == desired.intervalEnd,
           center.events(for: name)[DeviceActivityEvent.Name(session.eventName(minute: session.initialMinutes))] != nil {
            return
        }

        do {
            try register(defaults: defaults, groupId: groupId, now: now) {
                // Another purchase/recovery may have completed while this caller
                // waited for registration. Never replace its newer generation.
                let current = UsageBudgetSession.load(from: defaults, groupId: groupId)
                guard current?.generation == snapshot.session?.generation else { return nil }
                let remaining = remainingUsageBudget(defaults: defaults, groupId: groupId, at: now)
                guard remaining > 0,
                      let deadline = usageBudgetDeadline(defaults: defaults, groupId: groupId) else {
                    throw NSError(domain: "Nowhere.UsageBudget", code: 1)
                }
                return UsageBudgetSession(minutes: remaining, startedAt: now, expiresAt: deadline)
            }
        } catch {
            try withUsageBudgetLock {
                defaults.synchronize()
                let current = UsageBudgetSession.load(from: defaults, groupId: groupId)
                let remaining = remainingUsageBudget(defaults: defaults, groupId: groupId, at: now)
                if current?.generation == snapshot.session?.generation, remaining > 0,
                   let deadline = usageBudgetDeadline(defaults: defaults, groupId: groupId) {
                    // Legacy paid windows also need a paused v2 session; leaving
                    // only legacy keys would allow access without a monitor.
                    var paused = current ?? UsageBudgetSession(minutes: remaining, startedAt: now, expiresAt: deadline)
                    paused.monitoringFailed = true
                    paused.invalidatedAt = paused.invalidatedAt ?? now
                    paused.save(to: defaults, groupId: groupId)
                }
                defaults.synchronize()
            }
            throw error
        }
    }

    @discardableResult
    static func recordUsageThreshold(defaults: UserDefaults, groupId: String, event: String, now: Date = Date()) throws -> Bool {
        let result = try withUsageBudgetLock { () -> (changed: Bool, needsContinuation: Bool) in
            defaults.synchronize()
            defer { defaults.synchronize() }
            guard var session = UsageBudgetSession.load(from: defaults, groupId: groupId),
                  session.expiresAt > now else { return (false, false) }
            switch session.record(event: event, at: now) {
            case .ignored:
                return (false, false)
            case .implausible:
                // Fail closed without re-entering the daemon from its callback.
                // The app/widget can recover this paid balance with a fresh
                // generation. Do not retry an untrusted baseline in a loop.
                Logger(
                    subsystem: "com.personalproject.StepsTrader",
                    category: "UsageBudget"
                ).error("Rejected implausible Screen Time threshold \(event, privacy: .public) after \(now.timeIntervalSince(session.startedAt), privacy: .public)s")
                session.invalidatedAt = now
                session.monitoringFailed = true
                session.save(to: defaults, groupId: groupId)
                return (true, false)
            case .recorded:
                session.save(to: defaults, groupId: groupId)
            }
            // During registration the coordinator owns the registration lock.
            // Do not re-enter it from a synchronous daemon callback. The saved
            // queue remains recoverable if a very slow registration finishes it.
            return (true, session.needsNextSegment && !session.monitoringFailed)
        }
        if result.needsContinuation {
            try startUsageBudgetMonitoring(defaults: defaults, groupId: groupId, now: now)
        }
        return result.changed
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
