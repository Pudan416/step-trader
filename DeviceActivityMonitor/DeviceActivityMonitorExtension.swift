import DeviceActivity
import Foundation
import ManagedSettings
#if canImport(FamilyControls)
import FamilyControls
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
    private let store = ManagedSettingsStore()

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        handleMinuteEvent(event)
    }

    private func handleMinuteEvent(_ event: DeviceActivityEvent.Name) {
        let raw = event.rawValue
        let prefix = "minute_"
        guard raw.hasPrefix(prefix) else { return }
        let bundleId = String(raw.dropFirst(prefix.count))

        let g = stepsTraderDefaults()
        let cost = entryCost(for: bundleId, defaults: g)
        guard cost > 0 else { return }

        // Track cumulative minutes for this bundleId today
        let minuteCount = incrementMinuteCount(for: bundleId, defaults: g)

        applyMinuteCharge(cost: cost, for: bundleId, defaults: g)
        updateSpentSteps(cost: cost, for: bundleId, defaults: g)
        
        // Log the charge for debugging
        let balanceAfter = g.integer(forKey: "stepsBalance") + g.integer(forKey: "debugStepsBonus_v1")
        logMinuteCharge(bundleId: bundleId, cost: cost, balanceAfter: balanceAfter, defaults: g)

        let remaining = remainingMinutes(cost: cost, defaults: g)
        if remaining <= 0 {
            reenableShield(defaults: g)
        } else {
            // Reschedule with new threshold for next minute
            rescheduleMinuteEvent(for: bundleId, nextMinute: minuteCount + 1, defaults: g)
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
    
    private func rescheduleMinuteEvent(for bundleId: String, nextMinute: Int, defaults: UserDefaults) {
        #if canImport(FamilyControls) && canImport(DeviceActivity)
        let key = "timeAccessSelection_v1_\(bundleId)"
        guard let selectionData = defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
              !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        else { return }
        
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName("minuteMode")
        
        // Build event with next minute threshold
        let eventName = DeviceActivityEvent.Name("minute_\(bundleId)")
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: nextMinute)
        )
        
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        
        // Stop and restart with updated event
        center.stopMonitoring([activityName])
        
        // Rebuild all events with updated thresholds
        var events = buildAllMinuteEvents(defaults: defaults)
        events[eventName] = event
        
        do {
            try center.startMonitoring(activityName, during: schedule, events: events)
        } catch {
            // Silently fail - will be retried on next app foreground
        }
        #endif
    }
    
    private func buildAllMinuteEvents(defaults: UserDefaults) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        #if canImport(FamilyControls) && canImport(DeviceActivity)
        guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
        else { return [:] }
        
        let dayKey = dayKey(for: Date())
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        
        for (bundleId, settings) in decoded {
            let enabled = (settings.familyControlsModeEnabled ?? false)
                || (settings.minuteTariffEnabled ?? false)
            guard enabled else { continue }
            
            let key = "timeAccessSelection_v1_\(bundleId)"
            guard let selectionData = defaults.data(forKey: key),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData)
            else { continue }
            
            if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
                continue
            }
            
            // Get current minute count for this app today
            let countKey = "minuteCount_\(dayKey)_\(bundleId)"
            let currentMinutes = defaults.integer(forKey: countKey)
            let nextThreshold = currentMinutes + 1
            
            let eventName = DeviceActivityEvent.Name("minute_\(bundleId)")
            let event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
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
        guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data),
              let settings = decoded[bundleId]
        else { return 0 }
        return settings.entryCostSteps ?? 0
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

    private func reenableShield(defaults: UserDefaults) {
        #if canImport(FamilyControls)
        guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
        else { return }

        var combined = FamilyActivitySelection()
        for (bundleId, settings) in decoded {
            let enabled = (settings.familyControlsModeEnabled ?? false)
                || (settings.minuteTariffEnabled ?? false)
            guard enabled else { continue }
            let key = "timeAccessSelection_v1_\(bundleId)"
            if let selectionData = defaults.data(forKey: key),
               let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
                combined.applicationTokens.formUnion(selection.applicationTokens)
                combined.categoryTokens.formUnion(selection.categoryTokens)
            }
        }

        if combined.applicationTokens.isEmpty && combined.categoryTokens.isEmpty {
            store.clearAllSettings()
            return
        }

        store.shield.applications = combined.applicationTokens
        store.shield.applicationCategories = combined.categoryTokens.isEmpty
            ? nil
            : .specific(combined.categoryTokens)
        #endif
    }
}
