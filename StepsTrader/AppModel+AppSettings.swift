import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

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
        
        // Check ticket groups first
        // Find the group containing this app
        #if canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()
        
        // Search groups for this app
        let bundleIdLower = bundleId.lowercased()
        for group in ticketGroups {
            for token in group.selection.applicationTokens {
                guard let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { continue }
                let base64 = tokenData.base64EncodedString()
                
                // Cache token → groupId mapping
                defaults.set(group.id, forKey: "fc_groupId_" + base64)
                
                // Prefer exact bundleId match (avoids "Mail" matching "Gmail")
                if let storedBundleId = defaults.string(forKey: "fc_bundleId_" + base64) {
                    if bundleIdLower == storedBundleId.lowercased() {
                        var settings = group.settings
                        if settings.allowedWindows.isEmpty {
                            settings.allowedWindows = [.minutes10, .minutes30, .hour1]
                        }
                        return settings
                    }
                    continue
                }
                // Legacy: exact match on stored name only (no substring)
                if let storedName = defaults.string(forKey: "fc_appName_" + base64),
                   bundleIdLower == storedName.lowercased() {
                    var settings = group.settings
                    if settings.allowedWindows.isEmpty {
                        settings.allowedWindows = [.minutes10, .minutes30, .hour1]
                    }
                    return settings
                }
            }
        }
        #endif
        
        // If not found in groups, use legacy settings
        var settings = appUnlockSettings[bundleId] ?? fallback
        if settings.allowedWindows.isEmpty {
            settings.allowedWindows = [.minutes10, .minutes30, .hour1]
        }
        return settings
    }
    
    func updateUnlockSettings(for bundleId: String, tariff: Tariff) {
        updateUnlockSettings(
            for: bundleId,
            entryCost: tariff.entryCostSteps,
            dayPassCost: dayPassCost(for: tariff)
        )
    }
    
    func updateUnlockSettings(for bundleId: String, entryCost: Int? = nil, dayPassCost: Int? = nil) {
        var settings = unlockSettings(for: bundleId)
        if let entryCost { settings.entryCostSteps = max(0, entryCost) }
        if let dayPassCost { settings.dayPassCostSteps = max(0, dayPassCost) }
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseTicketUpsert(bundleId: bundleId)
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

    func deactivateTicket(bundleId: String) {
        appUnlockSettings.removeValue(forKey: bundleId)
        persistAppUnlockSettings()
        rebuildFamilyControlsShield()

        Task { @MainActor in
            await self.deleteSupabaseTicket(bundleId: bundleId)
        }
    }
    
    func loadAppUnlockSettings() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "appUnlockSettings_v1") else { return }
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
            g.set(data, forKey: "appUnlockSettings_v1")
        }
    }
}
