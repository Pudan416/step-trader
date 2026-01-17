import DeviceActivity
import Foundation
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

}
