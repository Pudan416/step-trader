import Foundation
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Shield Management
extension AppModel {
    // MARK: - Shield Management Keys
    private func timeAccessSelectionKey(for bundleId: String) -> String {
        "timeAccessSelection_v1_\(bundleId)"
    }
    
    // MARK: - Shield Management Functions
    func timeAccessSelection(for bundleId: String) -> FamilyActivitySelection {
        let g = UserDefaults.stepsTrader()
        #if canImport(FamilyControls)
        if let data = g.data(forKey: timeAccessSelectionKey(for: bundleId)),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            return decoded
        }
        #endif
        return FamilyActivitySelection()
    }

    func saveTimeAccessSelection(_ selection: FamilyActivitySelection, for bundleId: String) {
        let g = UserDefaults.stepsTrader()
        #if canImport(FamilyControls)
        if let data = try? JSONEncoder().encode(selection) {
            g.set(data, forKey: timeAccessSelectionKey(for: bundleId))
        }
        #endif
    }

    func applyFamilyControlsSelection(for bundleId: String) {
        _ = bundleId
        rebuildFamilyControlsShield()
    }

    func disableFamilyControlsShield() {
        rebuildFamilyControlsShield()
    }

    func rebuildFamilyControlsShield() {
        // Отменяем предыдущую задачу, если она еще не выполнилась (дебаунсинг)
        rebuildShieldTask?.cancel()
        
        rebuildShieldTask = Task { @MainActor in
            // Небольшая задержка для дебаунсинга (50ms)
            try? await Task.sleep(nanoseconds: 50_000_000)
            
            // Проверяем, не была ли задача отменена
            guard !Task.isCancelled else { return }
            
            // Проверяем авторизацию перед выполнением
            guard familyControlsService.isAuthorized else {
                print("⚠️ Cannot rebuild shield: Family Controls not authorized")
                return
            }
            
            let startTime = CFAbsoluteTimeGetCurrent()
            var combined = FamilyActivitySelection()
            
            // Добавляем приложения из групп щитов (исключая временно разблокированные)
            let defaults = UserDefaults.stepsTrader()
            let now = Date()
            
            for group in shieldGroups {
                // Проверяем, не разблокирована ли группа временно
                let unlockKey = "groupUnlock_\(group.id)"
                if let unlockUntil = defaults.object(forKey: unlockKey) as? Date {
                    if now < unlockUntil {
                        print("⏭️ Skipping group \(group.name) - unlocked until \(unlockUntil)")
                        continue
                    } else {
                        // Unlock expired - clean it up
                        print("🧹 Cleaning expired unlock for group \(group.name)")
                        defaults.removeObject(forKey: unlockKey)
                    }
                }
                
                if group.settings.familyControlsModeEnabled == true || group.settings.minuteTariffEnabled == true {
                    #if canImport(FamilyControls)
                    // Фильтруем токены, которые временно разблокированы
                    var groupTokens = group.selection.applicationTokens
                    let groupCategories = group.selection.categoryTokens
                    
                    // Убираем временно разблокированные токены
                    groupTokens = groupTokens.filter { token in
                        if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                            let tokenKey = "fc_unlockUntil_" + tokenData.base64EncodedString()
                            if let unlockUntil = defaults.object(forKey: tokenKey) as? Date {
                                return now >= unlockUntil // Включаем только если разблокировка истекла
                            }
                        }
                        return true // Если нет информации о разблокировке, включаем
                    }
                    
                    combined.applicationTokens.formUnion(groupTokens)
                    combined.categoryTokens.formUnion(groupCategories)
                    #endif
                }
            }
            
            // Также добавляем старые карточки для обратной совместимости
            for (cardId, settings) in appUnlockSettings {
                if settings.familyControlsModeEnabled == true || settings.minuteTariffEnabled == true {
                    let selection = timeAccessSelection(for: cardId)
                    combined.applicationTokens.formUnion(selection.applicationTokens)
                    combined.categoryTokens.formUnion(selection.categoryTokens)
                }
            }
            
            familyControlsService.updateSelection(combined)
            
            // Обновляем мониторинг минутного режима (может быть тяжелым)
            // updateMinuteModeMonitoring() уже асинхронный внутри, не блокирует главный поток
            familyControlsService.updateMinuteModeMonitoring()
            
            familyControlsService.updateShieldSchedule()
            
            // Apply shield immediately (don't wait for intervalDidStart)
            applyShieldImmediately(selection: combined)
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            if elapsed > 0.1 {
                print("⚠️ rebuildFamilyControlsShield took \(String(format: "%.3f", elapsed))s")
            }
            
            // Сбрасываем состояние щита на первый экран при любом обновлении выбора
            let sharedDefaults = UserDefaults.stepsTrader()
            sharedDefaults.set(0, forKey: "doomShieldState_v1")
        }
    }
    
    #if canImport(ManagedSettings)
    private func applyShieldImmediately(selection: FamilyActivitySelection) {
        // Проверяем авторизацию перед применением щита
        guard familyControlsService.isAuthorized else {
            print("⚠️ Cannot apply shield: Family Controls not authorized")
            return
        }
        
        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        print("🛡️ Shield applied immediately: \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories")
    }
    #endif

    func isTimeAccessEnabled(for bundleId: String) -> Bool {
        let selection = timeAccessSelection(for: bundleId)
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }
    
    // MARK: - Cleanup Expired Unlocks
    func cleanupExpiredUnlocks() {
        let defaults = UserDefaults.stepsTrader()
        let now = Date()
        var cleanedCount = 0
        
        // Clean up expired group unlocks
        for group in shieldGroups {
            let unlockKey = "groupUnlock_\(group.id)"
            if let unlockUntil = defaults.object(forKey: unlockKey) as? Date,
               now >= unlockUntil {
                defaults.removeObject(forKey: unlockKey)
                cleanedCount += 1
                print("🧹 Cleaned expired unlock for group \(group.name)")
            }
        }
        
        if cleanedCount > 0 {
            print("🧹 Cleaned \(cleanedCount) expired unlock(s), rebuilding shield...")
            rebuildFamilyControlsShield()
        }
    }
    
    func scheduleSupabaseShieldUpsert(bundleId: String) {
        // TODO: Implement Supabase shield sync
        // This would schedule an async upsert to Supabase for the shield settings
    }
}
