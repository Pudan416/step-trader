import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Shield Groups Management
extension AppModel {
    // MARK: - Shield Groups Keys
    private var shieldGroupsKey: String { "shieldGroups_v1" }
    
    // MARK: - Shield Groups Management Functions
    func loadShieldGroups() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: shieldGroupsKey) else {
            // No groups found, initialize empty array
            shieldGroups = []
            return
        }
        if let decoded = try? JSONDecoder().decode([ShieldGroup].self, from: data) {
            shieldGroups = decoded
        } else {
            shieldGroups = []
        }
    }
    
    func persistShieldGroups() {
        let startTime = CFAbsoluteTimeGetCurrent()
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(shieldGroups) {
            g.set(data, forKey: shieldGroupsKey)
        }
        let persistTime = CFAbsoluteTimeGetCurrent() - startTime
        if persistTime > 0.05 {
            print("⏱️ persistShieldGroups took \(String(format: "%.3f", persistTime))s")
        }
        // Rebuild shield after group changes (async with delay to avoid blocking UI)
        // Cancel any existing rebuild task to debounce rapid updates
        rebuildShieldTask?.cancel()
        
        rebuildShieldTask = Task { @MainActor in
            // Debounce delay to prevent multiple rapid rebuild calls (especially from slider)
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard !Task.isCancelled else { return }
            self.rebuildFamilyControlsShield()
        }
    }
    
    func createShieldGroup(name: String, templateApp: String? = nil) -> ShieldGroup {
        let startTime = CFAbsoluteTimeGetCurrent()
        let defaultSettings = AppUnlockSettings(
            entryCostSteps: entryCostSteps,
            dayPassCostSteps: defaultDayPassCost(forEntryCost: entryCostSteps),
            allowedWindows: [.single, .minutes5, .minutes30, .hour1],
            minuteTariffEnabled: false,
            familyControlsModeEnabled: true
        )
        let group = ShieldGroup(name: name, settings: defaultSettings, templateApp: templateApp)
        shieldGroups.append(group)
        persistShieldGroups()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0.05 {
            print("⏱️ createShieldGroup took \(String(format: "%.3f", elapsed))s")
        }
        return group
    }
    
    func updateShieldGroup(_ group: ShieldGroup) {
        let startTime = CFAbsoluteTimeGetCurrent()
        if let index = shieldGroups.firstIndex(where: { $0.id == group.id }) {
            shieldGroups[index] = group
            // persistShieldGroups() already calls rebuildFamilyControlsShield() with debouncing
            persistShieldGroups()
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            if elapsed > 0.05 {
                print("⏱️ updateShieldGroup took \(String(format: "%.3f", elapsed))s")
            }
        }
    }
    
    func deleteShieldGroup(_ groupId: String) {
        let startTime = CFAbsoluteTimeGetCurrent()
        shieldGroups.removeAll { $0.id == groupId }
        persistShieldGroups()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0.05 {
            print("⏱️ deleteShieldGroup took \(String(format: "%.3f", elapsed))s")
        }
    }
    
    func addAppsToGroup(_ groupId: String, selection: FamilyActivitySelection) {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let index = shieldGroups.firstIndex(where: { $0.id == groupId }) else { return }
        var group = shieldGroups[index]
        // Merge existing selection with new one
        #if canImport(FamilyControls)
        group.selection.applicationTokens.formUnion(selection.applicationTokens)
        group.selection.categoryTokens.formUnion(selection.categoryTokens)
        #endif
        shieldGroups[index] = group
        persistShieldGroups()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0.05 {
            print("⏱️ addAppsToGroup took \(String(format: "%.3f", elapsed))s")
        }
    }
    
    // MARK: - Find Shield Group
    func findShieldGroup(for bundleId: String?) -> ShieldGroup? {
        guard let bundleId else { return nil }
        
        #if canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()
        
        // Iterate through all groups to find the app
        for group in shieldGroups {
            // Check all ApplicationTokens in the group
            for token in group.selection.applicationTokens {
                if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                    let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                    
                    // Check stored app name
                    if let storedName = defaults.string(forKey: tokenKey) {
                        let bundleIdLower = bundleId.lowercased()
                        let storedNameLower = storedName.lowercased()
                        
                        if bundleIdLower == storedNameLower || 
                           bundleIdLower.contains(storedNameLower) ||
                           storedNameLower.contains(bundleIdLower) {
                            return group
                        }
                    }
                }
            }
        }
        #endif
        
        return nil
    }
}
