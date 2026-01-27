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
            allowedWindows: [.single, .minutes5, .hour1]
        )
        guard let bundleId else { return fallback }
        
        // Сначала проверяем группы щитов
        // Ищем группу, которая содержит это приложение
        #if canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()
        
        // Проходим по всем группам и ищем приложение
        for group in shieldGroups {
            // Проверяем все ApplicationToken в группе
            for token in group.selection.applicationTokens {
                if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                    let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                    
                    // Сохраняем маппинг token -> groupId для быстрого поиска в будущем
                    let groupIdKey = "fc_groupId_" + tokenData.base64EncodedString()
                    defaults.set(group.id, forKey: groupIdKey)
                    
                    // Проверяем сохраненное имя приложения
                    if let storedName = defaults.string(forKey: tokenKey) {
                        // Сравниваем bundleId с именем приложения (может совпадать или содержать)
                        let bundleIdLower = bundleId.lowercased()
                        let storedNameLower = storedName.lowercased()
                        
                        // Если имена совпадают или bundleId содержит имя (или наоборот)
                        if bundleIdLower == storedNameLower || 
                           bundleIdLower.contains(storedNameLower) ||
                           storedNameLower.contains(bundleIdLower) {
                            // Нашли группу, возвращаем её настройки
                            var settings = group.settings
                            if settings.allowedWindows.isEmpty {
                                settings.allowedWindows = [.single, .minutes5, .hour1]
                            }
                            return settings
                        }
                    }
                }
            }
        }
        #endif
        
        // Если не нашли в группах, используем старые настройки
        var settings = appUnlockSettings[bundleId] ?? fallback
        if settings.allowedWindows.isEmpty {
            settings.allowedWindows = [.single, .minutes5, .hour1]
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
        scheduleSupabaseShieldUpsert(bundleId: bundleId)
    }

    func allowedAccessWindows(for bundleId: String?) -> Set<AccessWindow> {
        // Сначала проверяем группы
        if let group = findShieldGroup(for: bundleId) {
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
            settings.allowedWindows = [.single, .minutes5, .hour1]
        }
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseShieldUpsert(bundleId: bundleId)
    }

    func deactivateShield(bundleId: String) {
        appUnlockSettings.removeValue(forKey: bundleId)
        persistAppUnlockSettings()
        rebuildFamilyControlsShield()
        
        Task { @MainActor in
            await self.deleteSupabaseShield(bundleId: bundleId)
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
