import BackgroundTasks
import Foundation
import os.log
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Manages a BGAppRefreshTask that checks for expired group unlocks and
/// reapplies the ManagedSettings shield while the app is in the background.
///
/// This closes the gap where DeviceActivity non-repeating schedule callbacks
/// fail to fire (Apple "best-effort" limitation), leaving apps unblocked
/// after the purchased access window expires.
final class UnlockExpiryTaskManager {
    static let shared = UnlockExpiryTaskManager()

    static let taskIdentifier = "com.personalproject.StepsTrader.unlockExpiryRefresh"

    private let log = OSLog(subsystem: "com.personalproject.StepsTrader", category: "UnlockExpiry")

    private init() {}

    // MARK: - Registration (call once at app launch, before end of didFinishLaunching)

    func registerTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            self?.handleRefresh(task: task)
        }
        os_log(.info, log: log, "BGAppRefreshTask registered")
    }

    // MARK: - Scheduling

    /// Schedule a background refresh. Safe to call multiple times; the system
    /// coalesces requests for the same identifier.
    func scheduleIfNeeded() {
        let defaults = SharedKeys.appGroupDefaults()
        let now = Date()

        let earliestExpiry = findEarliestExpiry(defaults: defaults, now: now)
        guard let earliest = earliestExpiry else {
            os_log(.info, log: log, "No active unlocks — skipping BGTask schedule")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        // Ask to run shortly after the earliest expiry, with a 30s buffer
        // so the system has scheduling room.
        request.earliestBeginDate = earliest.addingTimeInterval(30)

        do {
            try BGTaskScheduler.shared.submit(request)
            os_log(.info, log: log, "BGAppRefreshTask scheduled for %{public}@",
                   earliest.addingTimeInterval(30).description)
        } catch {
            os_log(.error, log: log, "Failed to submit BGAppRefreshTask: %{public}@",
                   error.localizedDescription)
        }
    }

    func cancelPendingTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        os_log(.info, log: log, "Cancelled pending BGAppRefreshTask")
    }

    // MARK: - Task Handler

    private func handleRefresh(task: BGAppRefreshTask) {
        os_log(.info, log: log, "BGAppRefreshTask fired")

        let defaults = SharedKeys.appGroupDefaults()
        let now = Date()

        // 1. Clear expired unlock keys
        var didExpire = false
        let allKeys = defaults.dictionaryRepresentation().keys

        for key in allKeys where key.hasPrefix("groupUnlock_") {
            if let until = defaults.object(forKey: key) as? Date, now >= until {
                defaults.removeObject(forKey: key)
                let groupId = String(key.dropFirst("groupUnlock_".count))
                os_log(.info, log: log, "Cleared expired group unlock: %{public}@", groupId)
                didExpire = true
            }
        }

        for key in allKeys where key.hasPrefix("blockUntil_") {
            if let until = defaults.object(forKey: key) as? Date, now >= until {
                defaults.removeObject(forKey: key)
                let bundleId = String(key.dropFirst("blockUntil_".count))
                os_log(.info, log: log, "Cleared expired access window: %{public}@", bundleId)
                didExpire = true
            }
        }

        // 2. Rebuild shield if anything expired
        if didExpire {
            rebuildShield(defaults: defaults, now: now)
        }

        // 3. Reschedule if more unlocks are still pending
        if findEarliestExpiry(defaults: defaults, now: now) != nil {
            scheduleIfNeeded()
        }

        // 4. Also nudge the main app to rebuild on next foreground
        // (in case the BGTask's ManagedSettingsStore write and the main
        //  app's next rebuild race — the foreground handler always wins)

        task.setTaskCompleted(success: true)
    }

    // MARK: - Shield Rebuild (standalone, mirrors DeviceActivityMonitorExtension)

    private func rebuildShield(defaults: UserDefaults, now: Date) {
        #if canImport(ManagedSettings) && canImport(FamilyControls)
        var allApps: Set<ApplicationToken> = []
        var allCategories: Set<ActivityCategoryToken> = []

        let groups = loadGroups(defaults: defaults)
        for group in groups {
            let unlockKey = "groupUnlock_\(group.id)"
            if let until = defaults.object(forKey: unlockKey) as? Date, now < until {
                continue
            }
            guard group.active, let selectionData = group.selectionData else { continue }
            do {
                let sel = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                allApps.formUnion(sel.applicationTokens)
                allCategories.formUnion(sel.categoryTokens)
            } catch {
                os_log(.error, log: log, "Failed to decode selection for group %{public}@: %{public}@",
                       group.name, error.localizedDescription)
            }
        }

        // Per-app legacy selections
        if let data = defaults.data(forKey: "appUnlockSettings_v1"),
           let decoded = try? JSONDecoder().decode([String: StoredSettings].self, from: data) {
            for (bundleId, settings) in decoded {
                guard settings.minuteTariffEnabled == true || settings.familyControlsModeEnabled == true else { continue }
                let blockKey = "blockUntil_\(bundleId)"
                if let until = defaults.object(forKey: blockKey) as? Date {
                    if now < until { continue }
                    else { defaults.removeObject(forKey: blockKey) }
                }
                let selKey = "timeAccessSelection_v1_\(bundleId)"
                if let selData = defaults.data(forKey: selKey),
                   let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selData) {
                    allApps.formUnion(sel.applicationTokens)
                    allCategories.formUnion(sel.categoryTokens)
                }
            }
        }

        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = allApps.isEmpty ? nil : allApps
        store.shield.applicationCategories = allCategories.isEmpty ? nil : .specific(allCategories)
        os_log(.info, log: log, "Shield rebuilt from BGTask: %d apps, %d categories",
               allApps.count, allCategories.count)
        #endif
    }

    // MARK: - Helpers

    private func findEarliestExpiry(defaults: UserDefaults, now: Date) -> Date? {
        var earliest: Date?
        let allKeys = defaults.dictionaryRepresentation().keys

        for key in allKeys where key.hasPrefix("groupUnlock_") || key.hasPrefix("blockUntil_") {
            guard let until = defaults.object(forKey: key) as? Date, until > now else { continue }
            if earliest == nil || until < earliest! {
                earliest = until
            }
        }
        return earliest
    }

    // Minimal decodable structures (mirrors extension)

    private struct StoredSettings: Codable {
        let entryCostSteps: Int?
        let minuteTariffEnabled: Bool?
        let familyControlsModeEnabled: Bool?
    }

    private struct LiteConfig: Decodable {
        let groups: [LiteGroup]
    }

    private struct LiteGroup: Decodable {
        let id: String
        let name: String
        let selectionDataBase64: String
        let active: Bool
    }

    private struct LegacyGroup: Decodable {
        let id: String
        let name: String
        let selectionData: Data?
        let settings: Data?

        enum CodingKeys: String, CodingKey {
            case id, name, selectionData, settings
        }

        var active: Bool {
            guard let settings,
                  let s = try? JSONDecoder().decode(StoredSettings.self, from: settings)
            else { return false }
            return (s.minuteTariffEnabled ?? false) || (s.familyControlsModeEnabled ?? false)
        }
    }

    func loadGroupsPublic(defaults: UserDefaults) -> [(id: String, name: String, selectionData: Data?, active: Bool)] {
        loadGroups(defaults: defaults)
    }

    private func loadGroups(defaults: UserDefaults) -> [(id: String, name: String, selectionData: Data?, active: Bool)] {
        if let data = defaults.data(forKey: "liteTicketConfig_v1"),
           let lite = try? JSONDecoder().decode(LiteConfig.self, from: data) {
            return lite.groups.map { g in
                (g.id, g.name, Data(base64Encoded: g.selectionDataBase64), g.active)
            }
        }
        if let data = defaults.data(forKey: "liteShieldConfig_v1"),
           let lite = try? JSONDecoder().decode(LiteConfig.self, from: data) {
            return lite.groups.map { g in
                (g.id, g.name, Data(base64Encoded: g.selectionDataBase64), g.active)
            }
        }
        let groupsData = defaults.data(forKey: "ticketGroups_v1") ?? defaults.data(forKey: "shieldGroups_v1")
        guard let raw = groupsData,
              let groups = try? JSONDecoder().decode([LegacyGroup].self, from: raw)
        else { return [] }
        return groups.map { ($0.id, $0.name, $0.selectionData, $0.active) }
    }
}
