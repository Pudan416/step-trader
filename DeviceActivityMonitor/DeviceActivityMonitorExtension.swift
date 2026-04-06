import DeviceActivity
import Foundation
import os.log
import WidgetKit
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
    
    private static var lastErrorLogWrite: Date = .distantPast

    private static func storeErrorLog(function: String, message: String, context: [String: String]?) {
        let now = Date()
        guard now.timeIntervalSince(lastErrorLogWrite) >= 5 else { return }
        lastErrorLogWrite = now

        let defaults = SharedKeys.appGroupDefaults()
        var logs: [MonitorErrorLog] = []
        
        if let data = defaults.data(forKey: SharedKeys.monitorErrorLogs),
           let decoded = try? JSONDecoder().decode([MonitorErrorLog].self, from: data) {
            logs = decoded
        }
        
        let entry = MonitorErrorLog(function: function, message: message, context: context)
        logs.append(entry)
        
        if logs.count > 30 {
            logs = Array(logs.suffix(30))
        }
        
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: SharedKeys.monitorErrorLogs)
        }
        
        let errorCount = defaults.integer(forKey: SharedKeys.monitorErrorCount) + 1
        defaults.set(errorCount, forKey: SharedKeys.monitorErrorCount)
        defaults.set(Date(), forKey: SharedKeys.monitorLastErrorAt)
    }
}

private let sharedISO8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

private func appendMonitorLog(_ message: String) {
    let defaults = SharedKeys.appGroupDefaults()
    let now = sharedISO8601Formatter.string(from: Date())
    var logs = defaults.stringArray(forKey: SharedKeys.monitorLogs) ?? []
    logs.append("[\(now)] \(message)")
    if logs.count > 30 {
        logs = Array(logs.suffix(30))
    }
    defaults.set(logs, forKey: SharedKeys.monitorLogs)
}

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        MonitorLogger.info("intervalDidStart: \(activity.rawValue)")
        appendMonitorLog("intervalDidStart: \(activity.rawValue)")
        
        if activity == DeviceActivityName("minuteMode") {
            setupBlockForMinuteMode()
        }
    }
    
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        let activityRaw = activity.rawValue
        MonitorLogger.info("intervalWillEndWarning: \(activityRaw)")
        appendMonitorLog("intervalWillEndWarning: \(activityRaw)")
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        let activityRaw = activity.rawValue
        MonitorLogger.info("intervalDidEnd: \(activityRaw)")
        appendMonitorLog("intervalDidEnd: \(activityRaw)")
        
        if activityRaw.hasPrefix("usageBudget_") {
            let groupId = String(activityRaw.dropFirst("usageBudget_".count))
            // Do NOT stopMonitoring or rebuild here. intervalDidEnd fires for two reasons:
            // 1. Race condition: stopMonitoring() before startMonitoring() in the main app
            //    generates a deferred intervalDidEnd that kills the newly registered monitor.
            // 2. Daily schedule boundary (23:59:59). The repeating schedule handles this;
            //    the monitor stays alive for the next day automatically.
            // Budget expiration is handled solely by usageBudgetDone events. Day boundary
            // cleanup is handled by clearAllUsageBudgets in the main app.
            MonitorLogger.info("usageBudget daily interval ended for \(groupId) — no action (repeating schedule)")
            appendMonitorLog("usageBudget intervalEnd (no-op): \(groupId)")
            return
        }
    }
    
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        MonitorLogger.info("eventDidReachThreshold: \(event.rawValue) for activity \(activity.rawValue)")
        appendMonitorLog("eventDidReachThreshold: \(event.rawValue) for activity \(activity.rawValue)")
        
        handleMinuteEvent(event)
    }
    
    
    private func rebuildBlockFromExtension() {
        ShieldRebuildHelper.rebuild()
    }
    
    #if canImport(ManagedSettings)
    private func setupBlockForMinuteMode() {
        let defaults = SharedKeys.appGroupDefaults()
        var allApps: Set<ApplicationToken> = []
        var allCategories: Set<ActivityCategoryToken> = []
        
        MonitorLogger.info("Setting up shield for minute mode")
        
        // Every time we enable the shield, reset its state
        // (first screen "App Blocked" → then driven by ShieldActionExtension actions).
        defaults.set(0, forKey: SharedKeys.shieldState)
        
        let groups = ShieldRebuildHelper.loadGroups(defaults: defaults)
        MonitorLogger.info("Found \(groups.count) ticket groups")

        // Single pass: collect shielded apps/categories AND build firstApp→bundleId mapping
        var firstAppBundleId: String? = nil
        var firstAppResolved = false

        for group in groups where group.active {
            let budgetKey = SharedKeys.usageBudgetKey(group.id)
            if defaults.integer(forKey: budgetKey) > 0 {
                if ShieldRebuildHelper.isUsageBudgetWallClockActive(defaults: defaults, groupId: group.id) {
                    MonitorLogger.info("Skipping group \(group.name) - usage budget active (wall clock valid)")
                    continue
                }
                MonitorLogger.info("Budget expired for group \(group.name) — clearing stale keys")
                defaults.removeObject(forKey: budgetKey)
                defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(group.id))
            }
            guard let selectionData = group.selectionData else {
                MonitorLogger.warning("Group \(group.name) has no selectionData")
                continue
            }
            do {
                let sel = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                allApps.formUnion(sel.applicationTokens)
                allCategories.formUnion(sel.categoryTokens)
                MonitorLogger.info("Added \(sel.applicationTokens.count) apps from group: \(group.name)")

                // Resolve firstApp bundleId during this same pass (avoids second iteration)
                if !firstAppResolved, let firstApp = allApps.first, sel.applicationTokens.contains(firstApp) {
                    if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstApp, requiringSecureCoding: true) {
                        let tokenKey = SharedKeys.fcAppNameKey(tokenData.base64EncodedString())
                        if let appName = defaults.string(forKey: tokenKey) {
                            firstAppBundleId = appName
                            firstAppResolved = true
                            MonitorLogger.info("Found app in shield group: \(appName)")
                        }
                    }
                }
            } catch {
                MonitorLogger.error("Failed to decode selection for group \(group.name): \(error.localizedDescription)", context: [
                    "groupId": group.id,
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Also collect apps from per-app selections (for backward compatibility)
        if let data = defaults.data(forKey: SharedKeys.appUnlockSettings) {
            do {
                let decoded = try JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
                
                for (bundleId, settings) in decoded {
                    if settings.familyControlsModeEnabled == true {
                        let key = SharedKeys.timeAccessSelectionKey(bundleId)
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
                MonitorLogger.error("Failed to decode appUnlockSettings: \(error.localizedDescription)", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Setup shield to show custom shield instead of system blocking
        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = allApps.isEmpty ? nil : allApps
        store.shield.applicationCategories = allCategories.isEmpty ? nil : .specific(allCategories)
        
        // Save blocked apps info for ShieldActionExtension to use
        if let firstApp = allApps.first {
            var foundBundleId = firstAppBundleId
            
            // If not found in groups during the single pass, check legacy settings
            if foundBundleId == nil {
                if let globalSelectionData = defaults.data(forKey: SharedKeys.appSelection) {
                    do {
                        let globalSelection = try JSONDecoder().decode(FamilyActivitySelection.self, from: globalSelectionData)
                        if globalSelection.applicationTokens.contains(firstApp) {
                            if let data = defaults.data(forKey: SharedKeys.appUnlockSettings) {
                                do {
                                    let decoded = try JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
                                    for (bundleId, _) in decoded {
                                        let key = SharedKeys.timeAccessSelectionKey(bundleId)
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
                                    MonitorLogger.error("Failed to decode appUnlockSettings for bundleId lookup", context: ["error": error.localizedDescription])
                                }
                            }
                        }
                    } catch {
                        MonitorLogger.error("Failed to decode appSelection", context: ["error": error.localizedDescription])
                    }
                }
            }
            
            // Save for unlock action
            if let bundleId = foundBundleId {
                defaults.set(bundleId, forKey: SharedKeys.lastBlockedAppBundleId)
                MonitorLogger.info("Saved last blocked app: \(bundleId)")
            } else {
                MonitorLogger.warning("Could not find bundleId for blocked app token")
            }
        }
        
        MonitorLogger.info("Shield applied: \(allApps.count) apps, \(allCategories.count) categories")
    }
    #else
    private func setupBlockForMinuteMode() {}
    #endif

    private func handleMinuteEvent(_ event: DeviceActivityEvent.Name) {
        let raw = event.rawValue

        if raw.hasPrefix("ticketGroup_") {
            checkAndClearExpiredBudgets()
            return
        }

        if raw.hasPrefix("usageBudgetWidgetTick_") {
            let parts = raw.dropFirst("usageBudgetWidgetTick_".count)
            if let lastUnderscore = parts.lastIndex(of: "_") {
                let groupId = String(parts[parts.startIndex..<lastUnderscore])
                let minuteReached = Int(parts[parts.index(after: lastUnderscore)...]) ?? 0
                let defaults = SharedKeys.appGroupDefaults()
                let initialBudget = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(groupId))
                let remaining = max(0, initialBudget - minuteReached)
                defaults.set(remaining, forKey: SharedKeys.usageBudgetKey(groupId))
                defaults.synchronize()
                MonitorLogger.info("Widget milestone for \(groupId): minute \(minuteReached), remaining \(remaining)m")
                appendMonitorLog("usageBudgetWidgetTick \(groupId): \(remaining)m left")
                reloadWidgets()
            }
            return
        }

        if raw.hasPrefix("usageBudgetTick_") {
            let parts = raw.dropFirst("usageBudgetTick_".count)
            if let lastUnderscore = parts.lastIndex(of: "_") {
                let groupId = String(parts[parts.startIndex..<lastUnderscore])
                let minuteReached = Int(parts[parts.index(after: lastUnderscore)...]) ?? 0
                let defaults = SharedKeys.appGroupDefaults()
                let initialBudget = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(groupId))
                let remaining = max(0, initialBudget - minuteReached)
                defaults.set(remaining, forKey: SharedKeys.usageBudgetKey(groupId))
                defaults.synchronize()
                MonitorLogger.info("Usage tick for \(groupId): minute \(minuteReached), remaining \(remaining)m")
                appendMonitorLog("usageBudgetTick \(groupId): \(remaining)m left")
            }
            return
        }

        if raw.hasPrefix("usageBudgetDone_") {
            let groupId = String(raw.dropFirst("usageBudgetDone_".count))
            let defaults = SharedKeys.appGroupDefaults()
            defaults.removeObject(forKey: SharedKeys.usageBudgetKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
            defaults.synchronize()
            MonitorLogger.info("Usage budget exhausted for group \(groupId) — re-shielding")
            appendMonitorLog("usageBudget exhausted: \(groupId)")
            rebuildBlockFromExtension()
            DeviceActivityCenter().stopMonitoring([DeviceActivityName("usageBudget_\(groupId)")])
            reloadWidgets()
        }
    }

    private func checkAndClearExpiredBudgets() {
        let defaults = SharedKeys.appGroupDefaults()
        let groups = ShieldRebuildHelper.loadGroups(defaults: defaults)
        var didClear = false

        for group in groups where group.active {
            let budgetKey = SharedKeys.usageBudgetKey(group.id)
            guard defaults.integer(forKey: budgetKey) > 0 else { continue }

            if !ShieldRebuildHelper.isUsageBudgetWallClockActive(defaults: defaults, groupId: group.id) {
                defaults.removeObject(forKey: budgetKey)
                defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(group.id))
                DeviceActivityCenter().stopMonitoring([DeviceActivityName("usageBudget_\(group.id)")])
                MonitorLogger.info("Budget wall-clock expired for \(group.name) — re-shielding")
                appendMonitorLog("budget wallclock expired: \(group.id)")
                didClear = true
            }
        }

        if didClear {
            rebuildBlockFromExtension()
            reloadWidgets()
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    

}
