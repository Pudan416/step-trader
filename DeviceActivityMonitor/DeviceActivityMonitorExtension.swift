import DeviceActivity
import Foundation
import os.log
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Logging Infrastructure

private let monitorLog = OSLog(subsystem: "com.personalproject.StepsTrader.DeviceActivityMonitor", category: "Monitor")

/// Structured error log entry for debugging
private struct MonitorErrorLog: Codable {
    let timestamp: Date
    let function: String
    let message: String
    let context: [String: String]?
    
    init(function: String, message: String, context: [String: String]? = nil) {
        self.timestamp = Date()
        self.function = function
        self.message = message
        self.context = context
    }
}

/// Centralized logging for DeviceActivityMonitor extension
private enum MonitorLogger {
    static func info(_ message: String, function: String = #function) {
        os_log(.info, log: monitorLog, "[%{public}@] %{public}@", function, message)
        #if DEBUG
        print("🔵 [\(function)] \(message)")
        #endif
    }
    
    static func error(_ message: String, function: String = #function, context: [String: String]? = nil) {
        os_log(.error, log: monitorLog, "[%{public}@] ERROR: %{public}@", function, message)
        #if DEBUG
        print("🔴 [\(function)] ERROR: \(message)")
        #endif
        
        // Store error in UserDefaults for main app to read and potentially send to Supabase
        storeErrorLog(function: function, message: message, context: context)
    }
    
    static func warning(_ message: String, function: String = #function) {
        os_log(.default, log: monitorLog, "[%{public}@] WARNING: %{public}@", function, message)
        #if DEBUG
        print("🟡 [\(function)] WARNING: \(message)")
        #endif
    }
    
    private static func storeErrorLog(function: String, message: String, context: [String: String]?) {
        let defaults = stepsTraderDefaults()
        var logs: [MonitorErrorLog] = []
        
        if let data = defaults.data(forKey: "monitorErrorLogs_v1"),
           let decoded = try? JSONDecoder().decode([MonitorErrorLog].self, from: data) {
            logs = decoded
        }
        
        let entry = MonitorErrorLog(function: function, message: message, context: context)
        logs.append(entry)
        
        // Keep only last 50 errors to avoid bloat
        if logs.count > 50 {
            logs = Array(logs.suffix(50))
        }
        
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: "monitorErrorLogs_v1")
        }
        
        // Also increment error counter for quick health check
        let errorCount = defaults.integer(forKey: "monitorErrorCount_v1") + 1
        defaults.set(errorCount, forKey: "monitorErrorCount_v1")
        defaults.set(Date(), forKey: "monitorLastErrorAt_v1")
    }
}

fileprivate func stepsTraderDefaults() -> UserDefaults {
    let groupId = "group.personal-project.StepsTrader"
    guard let defaults = UserDefaults(suiteName: groupId) else {
        MonitorLogger.error("Failed to create UserDefaults with suite: \(groupId)", context: ["groupId": groupId])
        return .standard
    }
    return defaults
}

private func appendMonitorLog(_ message: String) {
    let defaults = stepsTraderDefaults()
    let now = ISO8601DateFormatter().string(from: Date())
    var logs = defaults.stringArray(forKey: "monitorLogs_v1") ?? []
    logs.append("[\(now)] \(message)")
    if logs.count > 200 {
        logs = Array(logs.suffix(200))
    }
    defaults.set(logs, forKey: "monitorLogs_v1")
}

private struct StoredUnlockSettings: Codable {
    let entryCostSteps: Int?
    let minuteTariffEnabled: Bool?
    let familyControlsModeEnabled: Bool?
}

private struct MinuteChargeLog: Codable {
    let bundleId: String
    let timestamp: Date
    let cost: Int
    let balanceAfter: Int
}

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        MonitorLogger.info("intervalDidStart: \(activity.rawValue)")
        appendMonitorLog("intervalDidStart: \(activity.rawValue)")
        
        // Check for expired unlocks on any activity
        checkAndClearExpiredUnlocks()
        
        // Enable custom shield for minute mode
        if activity == DeviceActivityName("minuteMode") {
            setupBlockForMinuteMode()
        }
    }
    
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        let activityRaw = activity.rawValue
        MonitorLogger.info("intervalWillEndWarning: \(activityRaw)")
        appendMonitorLog("intervalWillEndWarning: \(activityRaw)")
        // Short unlocks (< 15 min) use a 15-min interval with warningTime; treat warning as actual expiry
        if activityRaw.hasPrefix("unlockExpiry_") {
            let groupId = String(activityRaw.dropFirst("unlockExpiry_".count))
            MonitorLogger.info("Unlock expiry warning for group \(groupId) - clearing and rebuilding shield")
            let defaults = stepsTraderDefaults()
            let unlockKey = "groupUnlock_\(groupId)"
            defaults.removeObject(forKey: unlockKey)
            rebuildBlockFromExtension()
            DeviceActivityCenter().stopMonitoring([activity])
        }
        if activityRaw.hasPrefix("accessWindowExpiry_") {
            let bundleId = String(activityRaw.dropFirst("accessWindowExpiry_".count))
            MonitorLogger.info("Access window expiry warning for bundleId \(bundleId) - clearing and rebuilding shield")
            let defaults = stepsTraderDefaults()
            let blockKey = "blockUntil_\(bundleId)"
            defaults.removeObject(forKey: blockKey)
            rebuildBlockFromExtension()
            DeviceActivityCenter().stopMonitoring([activity])
        }
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        let activityRaw = activity.rawValue
        MonitorLogger.info("intervalDidEnd: \(activityRaw)")
        appendMonitorLog("intervalDidEnd: \(activityRaw)")
        
        // Handle unlock expiry activities
        if activityRaw.hasPrefix("unlockExpiry_") {
            let groupId = String(activityRaw.dropFirst("unlockExpiry_".count))
            MonitorLogger.info("Unlock expiry interval ended for group \(groupId)")
            
            // Clear the unlock and rebuild shield
            let defaults = stepsTraderDefaults()
            let unlockKey = "groupUnlock_\(groupId)"
            defaults.removeObject(forKey: unlockKey)
            
            rebuildBlockFromExtension()
            return
        }
        if activityRaw.hasPrefix("accessWindowExpiry_") {
            let bundleId = String(activityRaw.dropFirst("accessWindowExpiry_".count))
            MonitorLogger.info("Access window expiry interval ended for bundleId \(bundleId)")
            
            let defaults = stepsTraderDefaults()
            let blockKey = "blockUntil_\(bundleId)"
            defaults.removeObject(forKey: blockKey)
            
            rebuildBlockFromExtension()
            return
        }
        
        // Check for expired unlocks
        checkAndClearExpiredUnlocks()
        
        // Clear shield when interval ends (but don't clear if monitoring is still active)
        // Shield will be re-enabled on next interval start
        if activity == DeviceActivityName("minuteMode") {
            // Don't clear immediately - let it persist until next day
            // clearShield()
        }
    }
    
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        MonitorLogger.info("eventDidReachThreshold: \(event.rawValue) for activity \(activity.rawValue)")
        appendMonitorLog("eventDidReachThreshold: \(event.rawValue) for activity \(activity.rawValue)")
        
        // Check for expired unlocks on any threshold event
        checkAndClearExpiredUnlocks()
        
        handleMinuteEvent(event)
    }
    
    // MARK: - Expired Unlocks Check
    /// Called from extension to check and clear any expired group unlocks, then rebuild shield
    private func checkAndClearExpiredUnlocks() {
        let defaults = stepsTraderDefaults()
        let now = Date()
        var hasExpired = false
        
        // Find all groupUnlock_* keys and check if they've expired
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("groupUnlock_") {
            if let unlockUntil = defaults.object(forKey: key) as? Date {
                if now >= unlockUntil {
                    // Unlock has expired, remove it
                    defaults.removeObject(forKey: key)
                    let groupId = String(key.dropFirst("groupUnlock_".count))
                    print("⏰ DeviceActivityMonitor: Unlock expired for group \(groupId)")
                    hasExpired = true
                    appendMonitorLog("Expired group unlock: \(groupId)")
                }
            }
        }
        
        // Find all blockUntil_* keys and check if they've expired
        for key in allKeys where key.hasPrefix("blockUntil_") {
            if let until = defaults.object(forKey: key) as? Date {
                if now >= until {
                    defaults.removeObject(forKey: key)
                    let bundleId = String(key.dropFirst("blockUntil_".count))
                    print("⏰ DeviceActivityMonitor: Access window expired for bundleId \(bundleId)")
                    hasExpired = true
                    appendMonitorLog("Expired access window: \(bundleId)")
                }
            }
        }
        
        // If any unlocks expired, rebuild the shield to restore blocking
        if hasExpired {
            print("🛡️ DeviceActivityMonitor: Rebuilding block after unlock expiry")
            rebuildBlockFromExtension()
        }
    }
    
    /// Rebuild block from extension - similar to setupBlockForMinuteMode but for all active groups
    private func rebuildBlockFromExtension() {
        #if canImport(ManagedSettings)
        let defaults = stepsTraderDefaults()
        var allApps: Set<ApplicationToken> = []
        var allCategories: Set<ActivityCategoryToken> = []
        let now = Date()
        
        let groups = loadTicketGroupsForExtension(defaults: defaults)
        if groups.isEmpty {
            MonitorLogger.warning("No ticket groups (lite or legacy) found in UserDefaults")
            appendMonitorLog("rebuildBlockFromExtension: no groups")
        }
        MonitorLogger.info("Processing \(groups.count) ticket groups")
        
        for group in groups {
            let unlockKey = "groupUnlock_\(group.id)"
            if let unlockUntil = defaults.object(forKey: unlockKey) as? Date, now < unlockUntil {
                MonitorLogger.info("Group \(group.name) still unlocked until \(unlockUntil)")
                continue
            }
            guard let selectionData = group.selectionData else {
                MonitorLogger.warning("Group \(group.name) has no selectionData")
                continue
            }
            do {
                let sel = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                allApps.formUnion(sel.applicationTokens)
                allCategories.formUnion(sel.categoryTokens)
                MonitorLogger.info("Adding \(sel.applicationTokens.count) apps from locked group: \(group.name)")
            } catch {
                MonitorLogger.error("Failed to decode FamilyActivitySelection for group \(group.name): \(error.localizedDescription)", context: [
                    "groupId": group.id,
                    "groupName": group.name,
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Also collect apps from per-app selections (for backward compatibility / single-app mode)
        if let data = defaults.data(forKey: "appUnlockSettings_v1") {
            do {
                let decoded = try JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
                
                for (bundleId, settings) in decoded {
                    if settings.minuteTariffEnabled == true || settings.familyControlsModeEnabled == true {
                        let blockKey = "blockUntil_\(bundleId)"
                        if let until = defaults.object(forKey: blockKey) as? Date {
                            if now < until {
                                // Access window active — skip shielding this app
                                continue
                            } else {
                                defaults.removeObject(forKey: blockKey)
                            }
                        }
                        let key = "timeAccessSelection_v1_\(bundleId)"
                        if let selectionData = defaults.data(forKey: key) {
                            do {
                                let selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                                allApps.formUnion(selection.applicationTokens)
                                allCategories.formUnion(selection.categoryTokens)
                            } catch {
                                MonitorLogger.error("Failed to decode selection for \(bundleId): \(error.localizedDescription)", context: [
                                    "bundleId": bundleId,
                                    "error": error.localizedDescription
                                ])
                            }
                        }
                    }
                }
            } catch {
                MonitorLogger.error("Failed to decode appUnlockSettings_v1: \(error.localizedDescription)", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Apply shield
        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = allApps.isEmpty ? nil : allApps
        store.shield.applicationCategories = allCategories.isEmpty ? nil : .specific(allCategories)
        
        MonitorLogger.info("Shield rebuilt: \(allApps.count) apps, \(allCategories.count) categories")
        appendMonitorLog("Shield rebuilt: \(allApps.count) apps, \(allCategories.count) categories")
        #endif
    }
    
    #if canImport(ManagedSettings)
    private func setupBlockForMinuteMode() {
        let defaults = stepsTraderDefaults()
        var allApps: Set<ApplicationToken> = []
        var allCategories: Set<ActivityCategoryToken> = []
        
        MonitorLogger.info("Setting up shield for minute mode")
        
        // Каждый раз, когда мы включаем щит, сбрасываем его состояние
        // (первый экран "App Blocked" → потом уже по действиям ShieldActionExtension).
        defaults.set(0, forKey: "doomShieldState_v1")
        
        let groups = loadTicketGroupsForExtension(defaults: defaults)
        MonitorLogger.info("Found \(groups.count) ticket groups")
        for group in groups where group.active {
            guard let selectionData = group.selectionData else {
                MonitorLogger.warning("Group \(group.name) has no selectionData")
                continue
            }
            do {
                let sel = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                allApps.formUnion(sel.applicationTokens)
                allCategories.formUnion(sel.categoryTokens)
                MonitorLogger.info("Added \(sel.applicationTokens.count) apps from group: \(group.name)")
            } catch {
                MonitorLogger.error("Failed to decode selection for group \(group.name): \(error.localizedDescription)", context: [
                    "groupId": group.id,
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Also collect apps from per-app selections (for backward compatibility)
        if let data = defaults.data(forKey: "appUnlockSettings_v1") {
            do {
                let decoded = try JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
                
                for (bundleId, settings) in decoded {
                    if settings.minuteTariffEnabled == true || settings.familyControlsModeEnabled == true {
                        let key = "timeAccessSelection_v1_\(bundleId)"
                        if let selectionData = defaults.data(forKey: key) {
                            do {
                                let selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                                allApps.formUnion(selection.applicationTokens)
                                allCategories.formUnion(selection.categoryTokens)
                            } catch {
                                MonitorLogger.error("Failed to decode selection for \(bundleId): \(error.localizedDescription)", context: [
                                    "bundleId": bundleId,
                                    "error": error.localizedDescription
                                ])
                            }
                        }
                    }
                }
            } catch {
                MonitorLogger.error("Failed to decode appUnlockSettings_v1: \(error.localizedDescription)", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Setup shield to show custom shield instead of system blocking
        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = allApps.isEmpty ? nil : allApps
        store.shield.applicationCategories = allCategories.isEmpty ? nil : .specific(allCategories)
        
        // Save blocked apps info for ShieldActionExtension to use
        // We'll save the first app's bundleId as the "last blocked app"
        if let firstApp = allApps.first {
            var foundBundleId: String? = nil
            
            let groups = loadTicketGroupsForExtension(defaults: defaults)
            for group in groups {
                guard let selectionData = group.selectionData else { continue }
                do {
                    let sel = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                    if sel.applicationTokens.contains(firstApp) {
                        do {
                            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: firstApp, requiringSecureCoding: true)
                            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                            if let appName = defaults.string(forKey: tokenKey) {
                                foundBundleId = appName
                                MonitorLogger.info("Found app in shield group: \(appName)")
                                break
                            }
                        } catch {
                            MonitorLogger.warning("Failed to archive app token: \(error.localizedDescription)")
                        }
                    }
                } catch {
                    // Silent continue
                }
            }
            
            // 2) Если не нашли в группах, проверяем старые настройки
            if foundBundleId == nil {
                if let globalSelectionData = defaults.data(forKey: "appSelection_v1") {
                    do {
                        let globalSelection = try JSONDecoder().decode(FamilyActivitySelection.self, from: globalSelectionData)
                        if globalSelection.applicationTokens.contains(firstApp) {
                            if let data = defaults.data(forKey: "appUnlockSettings_v1") {
                                do {
                                    let decoded = try JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
                                    for (bundleId, _) in decoded {
                                        let key = "timeAccessSelection_v1_\(bundleId)"
                                        if let selectionData = defaults.data(forKey: key) {
                                            do {
                                                let selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                                                if selection.applicationTokens.contains(firstApp) {
                                                    foundBundleId = bundleId
                                                    MonitorLogger.info("Found app in old settings: \(bundleId)")
                                                    break
                                                }
                                            } catch {
                                                MonitorLogger.error("Failed to decode selection for \(bundleId)", context: ["error": error.localizedDescription])
                                            }
                                        }
                                    }
                                } catch {
                                    MonitorLogger.error("Failed to decode appUnlockSettings_v1 for bundleId lookup", context: ["error": error.localizedDescription])
                                }
                            }
                        }
                    } catch {
                        MonitorLogger.error("Failed to decode appSelection_v1", context: ["error": error.localizedDescription])
                    }
                }
            }
            
            // Save for unlock action
            if let bundleId = foundBundleId {
                defaults.set(bundleId, forKey: "lastBlockedAppBundleId")
                MonitorLogger.info("Saved last blocked app: \(bundleId)")
            } else {
                MonitorLogger.warning("Could not find bundleId for blocked app token")
            }
        }
        
        MonitorLogger.info("Shield applied: \(allApps.count) apps, \(allCategories.count) categories")
    }
    
    #if canImport(UserNotifications)
    private func sendBlockedAppPushNotifications(for settings: [String: StoredUnlockSettings], defaults: UserDefaults) {
        let center = UNUserNotificationCenter.current()
        
        for (bundleId, settings) in settings {
            if settings.minuteTariffEnabled == true || settings.familyControlsModeEnabled == true {
                // Get app name
                let appName = defaults.string(forKey: "appName_\(bundleId)") ?? bundleId
                
                // Create notification
                let content = UNMutableNotificationContent()
                content.title = "App Blocked"
                content.body = "\(appName) is blocked. Tap to unlock."
                content.sound = .default
                content.categoryIdentifier = "UNLOCK_APP"
                content.userInfo = [
                    "bundleId": bundleId,
                    "appName": appName,
                    "action": "unlock"
                ]
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "blocked_\(bundleId)_\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                
                center.add(request) { error in
                    if let error = error {
                        print("❌ Failed to send blocked app push: \(error)")
                    } else {
                        print("✅ Sent blocked app push for \(bundleId)")
                    }
                }
            }
        }
    }
    #endif
    
    private func clearShield() {
        let store = ManagedSettingsStore(named: .init("minuteModeShield"))
        store.clearAllSettings()
    }
    #else
    private func setupBlockForMinuteMode() {}
    private func clearShield() {}
    #endif

    private func handleMinuteEvent(_ event: DeviceActivityEvent.Name) {
        let raw = event.rawValue
        let prefix = "minute_"
        guard raw.hasPrefix(prefix) else { return }
        let bundleId = String(raw.dropFirst(prefix.count))

        let g = stepsTraderDefaults()
        let settings = unlockSettings(for: bundleId, defaults: g)
        let shouldCharge = (settings?.familyControlsModeEnabled ?? false)
            || (settings?.minuteTariffEnabled ?? false)
        // If the app charged upfront on entry, skip the first 1-minute threshold to avoid double-charging.
        // We still restart monitoring so the next minute can be tracked.
        let skipKey = "minuteModeSkipNextCharge_v1_\(bundleId)"
        if g.bool(forKey: skipKey) {
            g.removeObject(forKey: skipKey)
            _ = incrementMinuteCount(for: bundleId, defaults: g)
            updateMinuteTimeLog(bundleId: bundleId, defaults: g)
            restartMinuteModeMonitoring(defaults: g)
            return
        }

        let cost = entryCost(for: bundleId, defaults: g)

        // Track cumulative minutes for this bundleId today
        _ = incrementMinuteCount(for: bundleId, defaults: g)

        if !shouldCharge {
            updateMinuteTimeLog(bundleId: bundleId, defaults: g)
            restartMinuteModeMonitoring(defaults: g)
            return
        }

        guard cost > 0 else {
            updateMinuteTimeLog(bundleId: bundleId, defaults: g)
            restartMinuteModeMonitoring(defaults: g)
            return
        }

        applyMinuteCharge(cost: cost, for: bundleId, defaults: g)
        updateSpentSteps(cost: cost, for: bundleId, defaults: g)
        
        // Log the charge for debugging
        let balanceAfter = g.integer(forKey: "stepsBalance") + g.integer(forKey: "debugStepsBonus_v1")
        logMinuteCharge(bundleId: bundleId, cost: cost, balanceAfter: balanceAfter, defaults: g)

        let remaining = remainingMinutes(cost: cost, defaults: g)
        if remaining <= 0 {
            // No shielding: mark that minute-mode is depleted so the app can react (e.g. show pay gate).
            g.set(true, forKey: "minuteModeDepleted_v1")
            g.set(bundleId, forKey: "minuteModeDepletedBundleId_v1")
            // Stop monitoring to avoid further charges while depleted.
            DeviceActivityCenter().stopMonitoring([DeviceActivityName("minuteMode")])
        } else {
            // Restart monitoring so the next 1-minute threshold can fire again.
            restartMinuteModeMonitoring(defaults: g)
        }
    }
    
    private func incrementMinuteCount(for bundleId: String, defaults: UserDefaults) -> Int {
        let dayKey = dayKey(for: Date())
        let key = "minuteCount_\(dayKey)_\(bundleId)"
        let current = defaults.integer(forKey: key)
        let next = current + 1
        defaults.set(next, forKey: key)
        return next
    }
    
    private func restartMinuteModeMonitoring(defaults: UserDefaults) {
        #if canImport(FamilyControls) && canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName("minuteMode")
        let events = buildAllMinuteEvents(defaults: defaults)
        if events.isEmpty {
            MonitorLogger.info("No events to monitor, stopping minuteMode")
            center.stopMonitoring([activityName])
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        center.stopMonitoring([activityName])
        do {
            try center.startMonitoring(activityName, during: schedule, events: events)
            MonitorLogger.info("Restarted minuteMode monitoring with \(events.count) events")
        } catch {
            MonitorLogger.error("Failed to restart minuteMode monitoring: \(error.localizedDescription)", context: [
                "eventsCount": "\(events.count)",
                "error": error.localizedDescription
            ])
        }
        #endif
    }
    
    private func buildAllMinuteEvents(defaults: UserDefaults) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        #if canImport(FamilyControls) && canImport(DeviceActivity)
        guard let data = defaults.data(forKey: "appUnlockSettings_v1") else {
            MonitorLogger.warning("No appUnlockSettings_v1 data for buildAllMinuteEvents")
            return [:]
        }
        
        let decoded: [String: StoredUnlockSettings]
        do {
            decoded = try JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
        } catch {
            MonitorLogger.error("Failed to decode appUnlockSettings_v1 in buildAllMinuteEvents: \(error.localizedDescription)", context: [
                "error": error.localizedDescription
            ])
            return [:]
        }
        
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        
        for (bundleId, _) in decoded {
            let key = "timeAccessSelection_v1_\(bundleId)"
            guard let selectionData = defaults.data(forKey: key) else {
                continue
            }
            
            let selection: FamilyActivitySelection
            do {
                selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
            } catch {
                MonitorLogger.error("Failed to decode selection for \(bundleId) in buildAllMinuteEvents: \(error.localizedDescription)", context: [
                    "bundleId": bundleId,
                    "error": error.localizedDescription
                ])
                continue
            }
            
            if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
                continue
            }
            
            // DeviceActivity tracks usage since schedule start.
            // Since we restart monitoring after every event, the counter resets to 0.
            // We always want to be notified after the *next* 1 minute of usage.
            let eventName = DeviceActivityEvent.Name("minute_\(bundleId)")
            let event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                threshold: DateComponents(minute: 1)
            )
            events[eventName] = event
        }
        
        MonitorLogger.info("Built \(events.count) minute events")
        return events
        #else
        return [:]
        #endif
    }
    
    private func logMinuteCharge(bundleId: String, cost: Int, balanceAfter: Int, defaults: UserDefaults) {
        var logs: [MinuteChargeLog] = []
        if let data = defaults.data(forKey: "minuteChargeLogs_v1") {
            do {
                logs = try JSONDecoder().decode([MinuteChargeLog].self, from: data)
            } catch {
                MonitorLogger.warning("Failed to decode minuteChargeLogs_v1, starting fresh: \(error.localizedDescription)")
            }
        }
        
        let entry = MinuteChargeLog(
            bundleId: bundleId,
            timestamp: Date(),
            cost: cost,
            balanceAfter: balanceAfter
        )
        logs.append(entry)
        
        // Keep only last 100 entries to avoid bloat
        if logs.count > 100 {
            logs = Array(logs.suffix(100))
        }
        
        do {
            let data = try JSONEncoder().encode(logs)
            defaults.set(data, forKey: "minuteChargeLogs_v1")
        } catch {
            MonitorLogger.error("Failed to encode minuteChargeLogs_v1: \(error.localizedDescription)", context: [
                "bundleId": bundleId,
                "error": error.localizedDescription
            ])
        }
        
        // Also update cumulative time per app per day
        updateMinuteTimeLog(bundleId: bundleId, defaults: defaults)
    }
    
    private func updateMinuteTimeLog(bundleId: String, defaults: UserDefaults) {
        let dayKey = dayKey(for: Date())
        var perDay: [String: [String: Int]] = [:]
        if let data = defaults.data(forKey: "minuteTimeByDay_v1") {
            do {
                perDay = try JSONDecoder().decode([String: [String: Int]].self, from: data)
            } catch {
                MonitorLogger.warning("Failed to decode minuteTimeByDay_v1, starting fresh: \(error.localizedDescription)")
            }
        }
        
        var dayMap = perDay[dayKey] ?? [:]
        dayMap[bundleId, default: 0] += 1 // +1 minute
        perDay[dayKey] = dayMap
        
        // Clean up old days (keep last 7)
        let sortedKeys = perDay.keys.sorted().suffix(7)
        perDay = perDay.filter { sortedKeys.contains($0.key) }
        
        do {
            let data = try JSONEncoder().encode(perDay)
            defaults.set(data, forKey: "minuteTimeByDay_v1")
        } catch {
            MonitorLogger.error("Failed to encode minuteTimeByDay_v1: \(error.localizedDescription)", context: [
                "bundleId": bundleId,
                "error": error.localizedDescription
            ])
        }
    }

    private func entryCost(for bundleId: String, defaults: UserDefaults) -> Int {
        guard let settings = unlockSettings(for: bundleId, defaults: defaults) else { return 0 }
        return settings.entryCostSteps ?? 0
    }

    private func unlockSettings(for bundleId: String, defaults: UserDefaults) -> StoredUnlockSettings? {
        guard let data = defaults.data(forKey: "appUnlockSettings_v1") else {
            return nil
        }
        
        do {
            let decoded = try JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
            return decoded[bundleId]
        } catch {
            MonitorLogger.error("Failed to decode appUnlockSettings_v1 for bundleId \(bundleId): \(error.localizedDescription)", context: [
                "bundleId": bundleId,
                "error": error.localizedDescription
            ])
            return nil
        }
    }

    private func applyMinuteCharge(cost: Int, for bundleId: String, defaults: UserDefaults) {
        var stepsBalance = defaults.integer(forKey: "stepsBalance")
        var bonusSteps = defaults.integer(forKey: "debugStepsBonus_v1")
        var spentStepsToday = defaults.integer(forKey: "spentStepsToday")

        let consumeFromBase = min(cost, stepsBalance)
        spentStepsToday += consumeFromBase
        stepsBalance = max(0, stepsBalance - consumeFromBase)

        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            bonusSteps = max(0, bonusSteps - remainingCost)
        }

        defaults.set(spentStepsToday, forKey: "spentStepsToday")
        defaults.set(stepsBalance, forKey: "stepsBalance")
        defaults.set(bonusSteps, forKey: "debugStepsBonus_v1")
        defaults.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
    }

    private func updateSpentSteps(cost: Int, for bundleId: String, defaults: UserDefaults) {
        // Update today's spent steps per app
        var perAppToday: [String: Int] = [:]
        if let data = defaults.data(forKey: "appStepsSpentToday_v1") {
            do {
                perAppToday = try JSONDecoder().decode([String: Int].self, from: data)
            } catch {
                MonitorLogger.warning("Failed to decode appStepsSpentToday_v1: \(error.localizedDescription)")
            }
        }
        perAppToday[bundleId, default: 0] += cost
        do {
            let data = try JSONEncoder().encode(perAppToday)
            defaults.set(data, forKey: "appStepsSpentToday_v1")
        } catch {
            MonitorLogger.error("Failed to encode appStepsSpentToday_v1", context: ["error": error.localizedDescription])
        }

        // Update lifetime spent steps per app
        var lifetime: [String: Int] = [:]
        if let data = defaults.data(forKey: "appStepsSpentLifetime_v1") {
            do {
                lifetime = try JSONDecoder().decode([String: Int].self, from: data)
            } catch {
                MonitorLogger.warning("Failed to decode appStepsSpentLifetime_v1: \(error.localizedDescription)")
            }
        }
        lifetime[bundleId, default: 0] += cost
        do {
            let data = try JSONEncoder().encode(lifetime)
            defaults.set(data, forKey: "appStepsSpentLifetime_v1")
        } catch {
            MonitorLogger.error("Failed to encode appStepsSpentLifetime_v1", context: ["error": error.localizedDescription])
        }

        // Update daily breakdown
        var perDay: [String: [String: Int]] = [:]
        if let data = defaults.data(forKey: "appStepsSpentByDay_v1") {
            do {
                perDay = try JSONDecoder().decode([String: [String: Int]].self, from: data)
            } catch {
                MonitorLogger.warning("Failed to decode appStepsSpentByDay_v1: \(error.localizedDescription)")
            }
        }
        let dayKey = dayKey(for: Date())
        var dayMap = perDay[dayKey] ?? [:]
        dayMap[bundleId, default: 0] += cost
        perDay[dayKey] = dayMap
        do {
            let data = try JSONEncoder().encode(perDay)
            defaults.set(data, forKey: "appStepsSpentByDay_v1")
        } catch {
            MonitorLogger.error("Failed to encode appStepsSpentByDay_v1", context: ["error": error.localizedDescription])
        }
    }

    private func remainingMinutes(cost: Int, defaults: UserDefaults) -> Int {
        guard cost > 0 else { return 0 }
        let balance = defaults.integer(forKey: "stepsBalance")
        let bonusSteps = defaults.integer(forKey: "debugStepsBonus_v1")
        return max(0, (balance + bonusSteps) / cost)
    }

    private func dayKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    // Минимальная структура для декодирования групп щитов (legacy full payload)
    private struct ShieldGroupDataForMonitor: Decodable {
        let id: String
        let name: String
        let selectionData: Data?
        let settingsData: Data?
        
        enum CodingKeys: String, CodingKey {
            case id, name, selectionData, settings
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            selectionData = try? container.decode(Data.self, forKey: .selectionData)
            settingsData = try? container.decode(Data.self, forKey: .settings)
        }
        
        var hasActiveSettings: Bool {
            guard let settingsData = settingsData,
                  let settings = try? JSONDecoder().decode(StoredUnlockSettings.self, from: settingsData)
            else { return false }
            return (settings.minuteTariffEnabled ?? false) || (settings.familyControlsModeEnabled ?? false)
        }
    }

    // Lite config from main app: minimal payload for extension (id, name, selection base64, active)
    private struct LiteShieldConfigDecoded: Decodable {
        let groups: [LiteShieldGroupDecoded]
    }
    private struct LiteShieldGroupDecoded: Decodable {
        let id: String
        let name: String
        let selectionDataBase64: String
        let active: Bool
    }

    /// Load ticket groups for extension: prefers liteTicketConfig_v1, then liteShieldConfig_v1, then ticketGroups_v1, then shieldGroups_v1.
    private func loadTicketGroupsForExtension(defaults: UserDefaults) -> [(id: String, name: String, selectionData: Data?, active: Bool)] {
        if let liteData = defaults.data(forKey: "liteTicketConfig_v1"),
           let lite = try? JSONDecoder().decode(LiteShieldConfigDecoded.self, from: liteData) {
            return lite.groups.map { g in
                let data = Data(base64Encoded: g.selectionDataBase64)
                return (g.id, g.name, data, g.active)
            }
        }
        if let liteData = defaults.data(forKey: "liteShieldConfig_v1"),
           let lite = try? JSONDecoder().decode(LiteShieldConfigDecoded.self, from: liteData) {
            return lite.groups.map { g in
                let data = Data(base64Encoded: g.selectionDataBase64)
                return (g.id, g.name, data, g.active)
            }
        }
        let groupsData = defaults.data(forKey: "ticketGroups_v1") ?? defaults.data(forKey: "shieldGroups_v1")
        guard let data = groupsData,
              let groups = try? JSONDecoder().decode([ShieldGroupDataForMonitor].self, from: data) else {
            return []
        }
        return groups.map { g in (g.id, g.name, g.selectionData, g.hasActiveSettings) }
    }

}
