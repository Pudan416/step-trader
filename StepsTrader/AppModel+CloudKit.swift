import Foundation

// MARK: - CloudKit Sync Helpers
extension AppModel {
    func getAllShieldSettingsForCloud() -> [String: CloudShieldSettings] {
        var result: [String: CloudShieldSettings] = [:]
        for (bundleId, settings) in appUnlockSettings {
            result[bundleId] = CloudShieldSettings(
                entryCostSteps: settings.entryCostSteps,
                dayPassCostSteps: settings.dayPassCostSteps,
                minuteTariffEnabled: settings.minuteTariffEnabled,
                familyControlsModeEnabled: settings.familyControlsModeEnabled,
                allowedWindowsRaw: settings.allowedWindows.map { $0.rawValue }
            )
        }
        return result
    }
    
    func getStepsSpentByDayForCloud() -> [String: [String: Int]] {
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: "appStepsSpentByDay_v1"),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            return decoded
        }
        return [:]
    }
    
    func getDayPassesForCloud() -> [String: Date] {
        return dayPassGrants
    }
    
    func restoreShieldSettingsFromCloud(_ cloudSettings: [String: CloudShieldSettings]) async {
        for (bundleId, cloud) in cloudSettings {
            var settings = AppUnlockSettings(
                entryCostSteps: cloud.entryCostSteps,
                dayPassCostSteps: cloud.dayPassCostSteps
            )
            settings.minuteTariffEnabled = cloud.minuteTariffEnabled
            settings.familyControlsModeEnabled = cloud.familyControlsModeEnabled
            settings.allowedWindows = Set(cloud.allowedWindowsRaw.compactMap { AccessWindow(rawValue: $0) })
            
            appUnlockSettings[bundleId] = settings
        }
        persistAppUnlockSettings()
        print("☁️ Restored \(cloudSettings.count) shield settings from cloud")
    }
    
    func restoreStepsSpentFromCloud(_ cloudSteps: [String: [String: Int]]) async {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(cloudSteps) {
            g.set(data, forKey: "appStepsSpentByDay_v1")
        }
        self.loadAppStepsSpentToday()
        print("☁️ Restored steps spent data from cloud")
    }
    
    func restoreDayPassesFromCloud(_ cloudDayPasses: [String: Date]) async {
        dayPassGrants = cloudDayPasses
        persistDayPassGrants()
        print("☁️ Restored \(cloudDayPasses.count) day passes from cloud")
    }
}
