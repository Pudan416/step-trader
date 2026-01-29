import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - App Selection Persistence
extension AppModel {
    // MARK: - App Selection Save/Load
    func saveAppSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        
        // Новая схема: сохраняем весь FamilyActivitySelection целиком (appSelection_v1),
        // чтобы его можно было восстановить и в основном приложении, и в экстеншенах.
        do {
            let data = try JSONEncoder().encode(appSelection)
            userDefaults.set(data, forKey: "appSelection_v1")
            userDefaults.set(Date(), forKey: "appSelectionSavedDate")
            print("💾 Saved app selection (appSelection_v1): \(appSelection.applicationTokens.count) apps, \(appSelection.categoryTokens.count) categories")
        } catch {
            print("❌ Failed to save app selection (appSelection_v1): \(error)")
        }
    }

    func loadAppSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        var hasSelection = false
        var newSelection = FamilyActivitySelection()

        // Сначала пробуем новую схему хранения (appSelection_v1).
        if let data = userDefaults.data(forKey: "appSelection_v1"),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           !decoded.applicationTokens.isEmpty || !decoded.categoryTokens.isEmpty {
            newSelection = decoded
            hasSelection = true
            print("📱 Restored app selection from appSelection_v1: \(decoded.applicationTokens.count) apps, \(decoded.categoryTokens.count) categories")
        }

        // Далее — fallback на старую схему с persistentApplicationTokens/persistentCategoryTokens
        // (оставляем на случай, если у пользователя есть данные старого формата).
        // Восстанавливаем ApplicationTokens
        if !hasSelection, let tokensData = userDefaults.data(forKey: "persistentApplicationTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: tokensData)
                if let applicationTokens = obj as? Set<ApplicationToken> {
                    newSelection.applicationTokens = applicationTokens
                    hasSelection = true
                    print("📱 Restored app selection: \(applicationTokens.count) apps")
                }
            } catch {
                print("❌ Failed to restore app selection: \(error)")
            }
        }

        // Восстанавливаем CategoryTokens
        if !hasSelection, let categoriesData = userDefaults.data(forKey: "persistentCategoryTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: categoriesData)
                if let categoryTokens = obj as? Set<ActivityCategoryToken> {
                    newSelection.categoryTokens = categoryTokens
                    hasSelection = true
                    print("📱 Restored category selection: \(categoryTokens.count) categories")
                }
            } catch {
                print("❌ Failed to restore category selection: \(error)")
            }
        }

        if hasSelection {
            // Обновляем выбор без вызова didSet (чтобы избежать повторного сохранения)
            self.appSelection = newSelection
            print("✅ App selection restored successfully")
            
            // Apply shield immediately after loading
            rebuildFamilyControlsShield()

            // Проверяем дату сохранения
            if let savedDate = userDefaults.object(forKey: "appSelectionSavedDate") as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                print("📅 App selection was saved on: \(formatter.string(from: savedDate))")
            }
        } else {
            print("📱 No saved app selection found")
            // Still apply shield in case there are per-app selections
            rebuildFamilyControlsShield()
        }
    }

    // MARK: - Family Controls Cards Sync
    func syncFamilyControlsCards(from selection: FamilyActivitySelection) {
        #if canImport(FamilyControls)
        let newAppTokens = selection.applicationTokens
        let newCategoryTokens = selection.categoryTokens
        
        // Копия настроек, которую будем мутировать.
        var updatedUnlock = appUnlockSettings
        
        // Построим карту token -> cardId для уже существующих карточек.
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
        
        // Отключаем карточки, чьи токены больше не выбраны.
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
        
        // Для каждого выбранного приложения гарантируем существование и включённость карточки.
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
        
        // То же для категорий (групп приложений).
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
        
        // Сохраняем обновлённые настройки карточек.
        appUnlockSettings = updatedUnlock
        persistAppUnlockSettings()
        
        // Обновляем глобальный selection для UI и shield.
        appSelection = selection
        
        // Пересобираем shield на основе карточек.
        rebuildFamilyControlsShield()
        #else
        _ = selection
        #endif
    }
}
