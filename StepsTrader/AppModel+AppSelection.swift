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
            userDefaults.set(data, forKey: SharedKeys.appSelection)
            userDefaults.set(Date(), forKey: SharedKeys.appSelectionSavedDate)
            AppLogger.familyControls.debug("💾 Saved app selection (appSelection_v1): \(self.appSelection.applicationTokens.count) apps, \(self.appSelection.categoryTokens.count) categories")
        } catch {
            AppLogger.familyControls.error("Failed to save app selection (appSelection_v1): \(error.localizedDescription)")
            ErrorManager.shared.handle(AppError.persistenceError(error))
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
            for t in sel.applicationTokens {
                appTokenToCard[t] = cardId
            }
            for c in sel.categoryTokens {
                categoryTokenToCard[c] = cardId
            }
        }
        
        // Disable cards whose tokens are no longer selected; remove fully disabled cards.
        var cardIdsToRemove: [String] = []
        for (cardId, var settings) in updatedUnlock {
            let sel = timeAccessSelection(for: cardId)
            let hasApp = sel.applicationTokens.contains(where: { newAppTokens.contains($0) })
            let hasCat = sel.categoryTokens.contains(where: { newCategoryTokens.contains($0) })
            
            if !hasApp && !hasCat {
                settings.familyControlsModeEnabled = false
                updatedUnlock[cardId] = settings
                cardIdsToRemove.append(cardId)
            }
        }
        for cardId in cardIdsToRemove {
            updatedUnlock.removeValue(forKey: cardId)
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
