import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - App Selection Persistence
extension AppModel {
    // MARK: - App Selection Save/Load
    func saveAppSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        
        // Save the full FamilyActivitySelection (appSelection_v1)
        // so it can be restored in both the main app and extensions.
        do {
            let data = try JSONEncoder().encode(appSelection)
            userDefaults.set(data, forKey: "appSelection_v1")
            userDefaults.set(Date(), forKey: "appSelectionSavedDate")
            AppLogger.familyControls.debug("💾 Saved app selection (appSelection_v1): \(self.appSelection.applicationTokens.count) apps, \(self.appSelection.categoryTokens.count) categories")
        } catch {
            AppLogger.familyControls.debug("Failed to save app selection (appSelection_v1): \(error.localizedDescription)")
        }
    }

    func loadAppSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        var hasSelection = false
        var newSelection = FamilyActivitySelection()

        // Try the new storage scheme first (appSelection_v1).
        if let data = userDefaults.data(forKey: "appSelection_v1"),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           !decoded.applicationTokens.isEmpty || !decoded.categoryTokens.isEmpty {
            newSelection = decoded
            hasSelection = true
            AppLogger.familyControls.debug("📱 Restored app selection from appSelection_v1: \(decoded.applicationTokens.count) apps, \(decoded.categoryTokens.count) categories")
        }

        // Fallback to legacy storage (persistentApplicationTokens/persistentCategoryTokens)
        // in case user has data in the old format.
        // Restore ApplicationTokens
        if !hasSelection, let tokensData = userDefaults.data(forKey: "persistentApplicationTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: tokensData)
                if let applicationTokens = obj as? Set<ApplicationToken> {
                    newSelection.applicationTokens = applicationTokens
                    hasSelection = true
                    AppLogger.familyControls.debug("📱 Restored app selection: \(applicationTokens.count) apps")
                }
            } catch {
                AppLogger.familyControls.debug("Failed to restore app selection: \(error.localizedDescription)")
            }
        }

        // Restore CategoryTokens
        if !hasSelection, let categoriesData = userDefaults.data(forKey: "persistentCategoryTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: categoriesData)
                if let categoryTokens = obj as? Set<ActivityCategoryToken> {
                    newSelection.categoryTokens = categoryTokens
                    hasSelection = true
                    AppLogger.familyControls.debug("📱 Restored category selection: \(categoryTokens.count) categories")
                }
            } catch {
                AppLogger.familyControls.debug("Failed to restore category selection: \(error.localizedDescription)")
            }
        }

        if hasSelection {
            // Update selection without triggering didSet (to avoid re-saving)
            self.appSelection = newSelection
            AppLogger.familyControls.debug("✅ App selection restored successfully")
            
            // Apply shield immediately after loading
            rebuildFamilyControlsShield()

            // Check save date
            if let savedDate = userDefaults.object(forKey: "appSelectionSavedDate") as? Date {
                AppLogger.familyControls.debug("📅 App selection was saved on: \(CachedFormatters.mediumDateTime.string(from: savedDate))")
            }
        } else {
            AppLogger.familyControls.debug("📱 No saved app selection found")
            // Still apply shield in case there are per-app selections
            rebuildFamilyControlsShield()
        }
    }

    // MARK: - Family Controls Cards Sync
    func syncFamilyControlsCards(from selection: FamilyActivitySelection) {
        #if canImport(FamilyControls)
        let newAppTokens = selection.applicationTokens
        let newCategoryTokens = selection.categoryTokens
        
        // Mutable copy of current settings.
        var updatedUnlock = appUnlockSettings
        
        // Build token → cardId map for existing cards.
        var appTokenToCard: [ApplicationToken: String] = [:]
        var categoryTokenToCard: [ActivityCategoryToken: String] = [:]
        
        for (cardId, _) in updatedUnlock {
            let sel = timeAccessSelection(for: cardId)
            if sel.applicationTokens.count == 1, let t = sel.applicationTokens.first {
                appTokenToCard[t] = cardId
            }
            if sel.categoryTokens.count == 1, let c = sel.categoryTokens.first {
                categoryTokenToCard[c] = cardId
            }
        }
        
        // Disable cards whose tokens are no longer selected.
        for (cardId, var settings) in updatedUnlock {
            let sel = timeAccessSelection(for: cardId)
            var stillSelected = false
            
            if sel.applicationTokens.count == 1, let t = sel.applicationTokens.first {
                if newAppTokens.contains(t) { stillSelected = true }
            }
            if sel.categoryTokens.count == 1, let c = sel.categoryTokens.first {
                if newCategoryTokens.contains(c) { stillSelected = true }
            }
            
            if !stillSelected {
                settings.familyControlsModeEnabled = false
                settings.minuteTariffEnabled = false
                updatedUnlock[cardId] = settings
            }
        }
        
        // Ensure each selected app has an enabled card.
        for token in newAppTokens {
            if let cardId = appTokenToCard[token] {
                var settings = updatedUnlock[cardId] ?? unlockSettings(for: cardId)
                settings.familyControlsModeEnabled = true
                updatedUnlock[cardId] = settings
                
                var sel = timeAccessSelection(for: cardId)
                sel.applicationTokens = [token]
                sel.categoryTokens = []
                saveTimeAccessSelection(sel, for: cardId)
            } else {
                let cardId = "fc_app_" + UUID().uuidString
                var settings = unlockSettings(for: cardId)
                settings.familyControlsModeEnabled = true
                updatedUnlock[cardId] = settings
                
                var sel = FamilyActivitySelection()
                sel.applicationTokens = [token]
                saveTimeAccessSelection(sel, for: cardId)
            }
        }
        
        // Same for categories (app groups).
        for cat in newCategoryTokens {
            if let cardId = categoryTokenToCard[cat] {
                var settings = updatedUnlock[cardId] ?? unlockSettings(for: cardId)
                settings.familyControlsModeEnabled = true
                updatedUnlock[cardId] = settings
                
                var sel = timeAccessSelection(for: cardId)
                sel.applicationTokens = []
                sel.categoryTokens = [cat]
                saveTimeAccessSelection(sel, for: cardId)
            } else {
                let cardId = "fc_cat_" + UUID().uuidString
                var settings = unlockSettings(for: cardId)
                settings.familyControlsModeEnabled = true
                updatedUnlock[cardId] = settings
                
                var sel = FamilyActivitySelection()
                sel.categoryTokens = [cat]
                saveTimeAccessSelection(sel, for: cardId)
            }
        }
        
        // Persist updated card settings.
        appUnlockSettings = updatedUnlock
        persistAppUnlockSettings()
        
        // Update global selection for UI and shield.
        appSelection = selection
        
        // Rebuild shield based on cards.
        rebuildFamilyControlsShield()
        #else
        _ = selection
        #endif
    }
}
