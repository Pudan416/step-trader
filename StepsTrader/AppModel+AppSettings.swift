import Foundation

// MARK: - App Unlock Settings Management
extension AppModel {
    // MARK: - Per-app unlock settings
    func unlockSettings(for bundleId: String?) -> AppUnlockSettings {
        let fallback = AppUnlockSettings(
            entryCostSteps: entryCostSteps,
            dayPassCostSteps: defaultDayPassCost(forEntryCost: entryCostSteps),
            allowedWindows: [.minutes10, .minutes30, .hour1]
        )
        guard let bundleId else { return fallback }

        if let group = findTicketGroup(for: bundleId) {
            var settings = group.settings
            if settings.allowedWindows.isEmpty {
                settings.allowedWindows = [.minutes10, .minutes30, .hour1]
            }
            return settings
        }

        var settings = appUnlockSettings[bundleId] ?? fallback
        if settings.allowedWindows.isEmpty {
            settings.allowedWindows = [.minutes10, .minutes30, .hour1]
        }
        return settings
    }
    
    func allowedAccessWindows(for bundleId: String?) -> Set<AccessWindow> {
        // Check groups first
        if let group = findTicketGroup(for: bundleId) {
            return group.enabledIntervals
        }
        return unlockSettings(for: bundleId).allowedWindows
    }

    func updateAccessWindow(_ window: AccessWindow, enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        if enabled {
            settings.allowedWindows.insert(window)
        } else {
            settings.allowedWindows.remove(window)
        }
        if settings.allowedWindows.isEmpty {
            settings.allowedWindows = [.minutes10, .minutes30, .hour1]
        }
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseTicketUpsert(bundleId: bundleId)
    }

    func loadAppUnlockSettings() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: SharedKeys.appUnlockSettings) else { return }
        if let decoded = try? JSONDecoder().decode([String: AppUnlockSettings].self, from: data) {
            // Normalize values that were previously clamped to 1
            appUnlockSettings = decoded.mapValues { settings in
                var s = settings
                if s.entryCostSteps == 1 { s.entryCostSteps = 0 }
                if s.dayPassCostSteps == 1 { s.dayPassCostSteps = 0 }
                return s
            }
        }
    }
    
    func persistAppUnlockSettings() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appUnlockSettings) {
            g.set(data, forKey: SharedKeys.appUnlockSettings)
        }
    }
}
