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
    
    private static func storeErrorLog(function: String, message: String, context: [String: String]?) {
        let defaults = SharedKeys.appGroupDefaults()
        var logs: [MonitorErrorLog] = []
        
        if let data = defaults.data(forKey: SharedKeys.monitorErrorLogs),
           let decoded = try? JSONDecoder().decode([MonitorErrorLog].self, from: data) {
            logs = decoded
        }
        
        let entry = MonitorErrorLog(function: function, message: message, context: context)
        logs.append(entry)
        
        // Keep only last 30 errors to avoid bloat (extension memory ~6MB)
        if logs.count > 30 {
            logs = Array(logs.suffix(30))
        }
        
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: SharedKeys.monitorErrorLogs)
        }
        
        // Also increment error counter for quick health check
        let errorCount = defaults.integer(forKey: SharedKeys.monitorErrorCount) + 1
        defaults.set(errorCount, forKey: SharedKeys.monitorErrorCount)
        defaults.set(Date(), forKey: SharedKeys.monitorLastErrorAt)
    }
}

private func makeISO8601Formatter() -> ISO8601DateFormatter {
    ISO8601DateFormatter()
}

private func appendMonitorLog(_ message: String) {
    let defaults = SharedKeys.appGroupDefaults()
    let now = makeISO8601Formatter().string(from: Date())
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
            let defaults = SharedKeys.appGroupDefaults()
            defaults.removeObject(forKey: SharedKeys.usageBudgetKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
            MonitorLogger.info("usageBudget interval ended for \(groupId) — cleared budget, re-shielding")
            appendMonitorLog("usageBudget intervalEnd cleared: \(groupId)")
            rebuildBlockFromExtension()
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
        for group in groups where group.active {
            let budgetKey = SharedKeys.usageBudgetKey(group.id)
            if defaults.integer(forKey: budgetKey) > 0 {
                MonitorLogger.info("Skipping group \(group.name) - usage budget active")
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
                MonitorLogger.info("Added \(sel.applicationTokens.count) apps from group: \(group.name)")
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
        // We'll save the first app's bundleId as the "last blocked app"
        if let firstApp = allApps.first {
            var foundBundleId: String? = nil
            
            let groups = ShieldRebuildHelper.loadGroups(defaults: defaults)
            for group in groups {
                guard let selectionData = group.selectionData else { continue }
                do {
                    let sel = try JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
                    if sel.applicationTokens.contains(firstApp) {
                        do {
                            let tokenData = try NSKeyedArchiver.archivedData(withRootObject: firstApp, requiringSecureCoding: true)
                            let tokenKey = SharedKeys.fcAppNameKey(tokenData.base64EncodedString())
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
                    MonitorLogger.error("Failed to decode selection during bundleId resolution: \(error.localizedDescription)", context: ["error": error.localizedDescription])
                }
            }
            
            // 2) If not found in groups, check legacy settings
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

        if raw.hasPrefix("usageBudgetTick_") {
            let parts = raw.dropFirst("usageBudgetTick_".count)
            if let lastUnderscore = parts.lastIndex(of: "_") {
                let groupId = String(parts[parts.startIndex..<lastUnderscore])
                let minuteReached = Int(parts[parts.index(after: lastUnderscore)...]) ?? 0
                let defaults = SharedKeys.appGroupDefaults()
                let initialBudget = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(groupId))
                let remaining = max(0, initialBudget - minuteReached)
                defaults.set(remaining, forKey: SharedKeys.usageBudgetKey(groupId))
                MonitorLogger.info("Usage tick for \(groupId): minute \(minuteReached), remaining \(remaining)m")
                appendMonitorLog("usageBudgetTick \(groupId): \(remaining)m left")
            }
        }

        if raw.hasPrefix("usageBudgetDone_") {
            let groupId = String(raw.dropFirst("usageBudgetDone_".count))
            let defaults = SharedKeys.appGroupDefaults()
            defaults.removeObject(forKey: SharedKeys.usageBudgetKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(groupId))
            defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
            MonitorLogger.info("Usage budget exhausted for group \(groupId) — re-shielding")
            appendMonitorLog("usageBudget exhausted: \(groupId)")
            rebuildBlockFromExtension()
            DeviceActivityCenter().stopMonitoring([DeviceActivityName("usageBudget_\(groupId)")])
            reloadWidgets()
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    

}
