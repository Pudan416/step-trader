import DeviceActivity
import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

fileprivate func stepsTraderDefaults() -> UserDefaults {
    let groupId = "group.personal-project.StepsTrader"
    return UserDefaults(suiteName: groupId) ?? .standard
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
        // Enable custom shield for minute mode
        if activity == DeviceActivityName("minuteMode") {
            setupShieldForMinuteMode()
        }
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
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
        handleMinuteEvent(event)
    }
    
    #if canImport(ManagedSettings)
    private func setupShieldForMinuteMode() {
        let defaults = stepsTraderDefaults()
        var allApps: Set<ApplicationToken> = []
        var allCategories: Set<ActivityCategoryToken> = []
        var unlockSettingsByBundle: [String: StoredUnlockSettings] = [:]
        
        // Каждый раз, когда мы включаем щит, сбрасываем его состояние
        // (первый экран "App Blocked" → потом уже по действиям ShieldActionExtension).
        defaults.set(0, forKey: "doomShieldState_v1")
        
        // Сначала собираем приложения из групп щитов
        if let groupsData = defaults.data(forKey: "shieldGroups_v1"),
           let groups = try? JSONDecoder().decode([ShieldGroupDataForMonitor].self, from: groupsData) {
            print("🛡️ DeviceActivityMonitor: Found \(groups.count) shield groups")
            for group in groups {
                if let selectionData = group.selectionData,
                   let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
                    // Проверяем настройки группы (нужно декодировать settings)
                    if group.hasActiveSettings {
                        allApps.formUnion(sel.applicationTokens)
                        allCategories.formUnion(sel.categoryTokens)
                        print("🛡️ Added \(sel.applicationTokens.count) apps from group: \(group.name)")
                    }
                }
            }
        }
        
        // Also collect apps from per-app selections (for backward compatibility)
        if let data = defaults.data(forKey: "appUnlockSettings_v1"),
           let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data) {
            unlockSettingsByBundle = decoded
            for (bundleId, settings) in decoded {
                if settings.minuteTariffEnabled == true || settings.familyControlsModeEnabled == true {
                    let key = "timeAccessSelection_v1_\(bundleId)"
                    if let selectionData = defaults.data(forKey: key),
                       let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
                        allApps.formUnion(selection.applicationTokens)
                        allCategories.formUnion(selection.categoryTokens)
                    }
                }
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
            
            // 1) Сначала проверяем группы щитов
            if let groupsData = defaults.data(forKey: "shieldGroups_v1"),
               let groups = try? JSONDecoder().decode([ShieldGroupDataForMonitor].self, from: groupsData) {
                for group in groups {
                    if let selectionData = group.selectionData,
                       let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
                       sel.applicationTokens.contains(firstApp) {
                        // Получаем имя приложения из токена
                        if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstApp, requiringSecureCoding: true) {
                            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                            if let appName = defaults.string(forKey: tokenKey) {
                                foundBundleId = appName
                                print("💾 Found app in shield group: \(appName)")
                                break
                            }
                        }
                    }
                }
            }
            
            // 2) Если не нашли в группах, проверяем старые настройки
            if foundBundleId == nil {
                if let globalSelectionData = defaults.data(forKey: "appSelection_v1"),
                   let globalSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: globalSelectionData) {
                    if globalSelection.applicationTokens.contains(firstApp) {
                        if let data = defaults.data(forKey: "appUnlockSettings_v1"),
                           let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data) {
                            for (bundleId, _) in decoded {
                                let key = "timeAccessSelection_v1_\(bundleId)"
                                if let selectionData = defaults.data(forKey: key),
                                   let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
                                   selection.applicationTokens.contains(firstApp) {
                                    foundBundleId = bundleId
                                    print("💾 Found app in old settings: \(bundleId)")
                                    break
                                }
                            }
                        }
                    }
                }
            }
            
            // Save for unlock action
            if let bundleId = foundBundleId {
                defaults.set(bundleId, forKey: "lastBlockedAppBundleId")
                print("💾 Saved last blocked app: \(bundleId)")
            } else {
                print("⚠️ Could not find bundleId for blocked app token")
            }
        }
        
        print("🛡️ Shield applied: \(allApps.count) apps, \(allCategories.count) categories")
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
    private func setupShieldForMinuteMode() {}
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
        } catch {
            // Best-effort: will be retried on next app foreground / next toggle.
        }
        #endif
    }
    
    private func buildAllMinuteEvents(defaults: UserDefaults) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        #if canImport(FamilyControls) && canImport(DeviceActivity)
        guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
        else { return [:] }
        
        let today = dayKey(for: Date())
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        
        for (bundleId, _) in decoded {
            let key = "timeAccessSelection_v1_\(bundleId)"
            guard let selectionData = defaults.data(forKey: key),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
            else { continue }
            
            if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
                continue
            }
            
            // DeviceActivity tracks CUMULATIVE usage since schedule start.
            // After threshold fires for minute N, next threshold must be N+1.
            let countKey = "minuteCount_\(today)_\(bundleId)"
            let currentMinutes = defaults.integer(forKey: countKey)
            let nextThreshold = currentMinutes + 1
            
            let eventName = DeviceActivityEvent.Name("minute_\(bundleId)")
            let event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                threshold: DateComponents(minute: nextThreshold)
            )
            events[eventName] = event
        }
        
        return events
        #else
        return [:]
        #endif
    }
    
    private func logMinuteCharge(bundleId: String, cost: Int, balanceAfter: Int, defaults: UserDefaults) {
        var logs: [MinuteChargeLog] = []
        if let data = defaults.data(forKey: "minuteChargeLogs_v1"),
           let decoded = try? JSONDecoder().decode([MinuteChargeLog].self, from: data) {
            logs = decoded
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
        
        if let data = try? JSONEncoder().encode(logs) {
            defaults.set(data, forKey: "minuteChargeLogs_v1")
        }
        
        // Also update cumulative time per app per day
        updateMinuteTimeLog(bundleId: bundleId, defaults: defaults)
    }
    
    private func updateMinuteTimeLog(bundleId: String, defaults: UserDefaults) {
        let dayKey = dayKey(for: Date())
        var perDay: [String: [String: Int]] = [:]
        if let data = defaults.data(forKey: "minuteTimeByDay_v1"),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            perDay = decoded
        }
        
        var dayMap = perDay[dayKey] ?? [:]
        dayMap[bundleId, default: 0] += 1 // +1 minute
        perDay[dayKey] = dayMap
        
        // Clean up old days (keep last 7)
        let sortedKeys = perDay.keys.sorted().suffix(7)
        perDay = perDay.filter { sortedKeys.contains($0.key) }
        
        if let data = try? JSONEncoder().encode(perDay) {
            defaults.set(data, forKey: "minuteTimeByDay_v1")
        }
    }

    private func entryCost(for bundleId: String, defaults: UserDefaults) -> Int {
        guard let settings = unlockSettings(for: bundleId, defaults: defaults) else { return 0 }
        return settings.entryCostSteps ?? 0
    }

    private func unlockSettings(for bundleId: String, defaults: UserDefaults) -> StoredUnlockSettings? {
        guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
        else { return nil }
        return decoded[bundleId]
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
        var perAppToday: [String: Int] = [:]
        if let data = defaults.data(forKey: "appStepsSpentToday_v1"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            perAppToday = decoded
        }
        perAppToday[bundleId, default: 0] += cost
        if let data = try? JSONEncoder().encode(perAppToday) {
            defaults.set(data, forKey: "appStepsSpentToday_v1")
        }

        var lifetime: [String: Int] = [:]
        if let data = defaults.data(forKey: "appStepsSpentLifetime_v1"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            lifetime = decoded
        }
        lifetime[bundleId, default: 0] += cost
        if let data = try? JSONEncoder().encode(lifetime) {
            defaults.set(data, forKey: "appStepsSpentLifetime_v1")
        }

        var perDay: [String: [String: Int]] = [:]
        if let data = defaults.data(forKey: "appStepsSpentByDay_v1"),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            perDay = decoded
        }
        let dayKey = dayKey(for: Date())
        var dayMap = perDay[dayKey] ?? [:]
        dayMap[bundleId, default: 0] += cost
        perDay[dayKey] = dayMap
        if let data = try? JSONEncoder().encode(perDay) {
            defaults.set(data, forKey: "appStepsSpentByDay_v1")
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
    
    // Минимальная структура для декодирования групп щитов
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

}
