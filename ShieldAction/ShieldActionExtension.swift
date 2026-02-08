//
//  ShieldActionExtension.swift
//  ShieldAction
//
//  Created by Konstantin Pudan on 24.01.2026.
//

import Foundation
import ManagedSettings
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

private let appGroupId = "group.personal-project.StepsTrader"
private let shieldStateKey = "doomShieldState_v1"

// Локальная копия структуры настроек (минимальный набор полей, чтобы декодировать ключи).
private struct StoredUnlockSettings: Codable {
    let entryCostSteps: Int?
    let minuteTariffEnabled: Bool?
    let familyControlsModeEnabled: Bool?
}

// Override the functions below to customize the shield actions used in various situations.
// The system provides a default response for any functions that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            completionHandler(.close)
            return
        }
        
        // ВАЖНО: Проверяем, не разблокирована ли уже группа с этим приложением
        if isAppCurrentlyUnlocked(application: application, defaults: defaults) {
            print("✅ ShieldAction: App is currently unlocked, allowing access")
            completionHandler(.close)
            return
        }
        
        let currentState = defaults.integer(forKey: shieldStateKey)
        
        switch action {
        case .primaryButtonPressed:
            if currentState == 0 {
                // Первый тап по "Unlock": переключаемся в состояние "waitingPush" и шлём пуш
                defaults.set(1, forKey: shieldStateKey)
                sendUnlockNotification(for: application, using: defaults)
                completionHandler(.defer)
            } else {
                // Во втором состоянии кнопка "Push not received" — просто ещё раз шлём пуш
                sendUnlockNotification(for: application, using: defaults)
                completionHandler(.defer)
            }
        case .secondaryButtonPressed:
            // На всякий случай — просто просим систему заново перерисовать щит
            completionHandler(.defer)
        @unknown default:
            completionHandler(.close)
        }
    }
    
    /// Проверяет, разблокировано ли приложение в рамках какой-либо группы
    private func isAppCurrentlyUnlocked(application: ApplicationToken, defaults: UserDefaults) -> Bool {
        #if canImport(FamilyControls)
        let now = Date()
        
        // Check ticket groups (then legacy shield groups)
        guard let groupsData = defaults.data(forKey: "ticketGroups_v1") ?? defaults.data(forKey: "shieldGroups_v1"),
              let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: groupsData)
        else {
            return false
        }
        
        for group in groups {
            // Проверяем, разблокирована ли эта группа
            let unlockKey = "groupUnlock_\(group.id)"
            guard let unlockUntil = defaults.object(forKey: unlockKey) as? Date,
                  now < unlockUntil
            else {
                continue // Группа не разблокирована
            }
            
            // Группа разблокирована - проверяем, есть ли в ней это приложение
            if let selectionData = group.selectionData,
               let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selectionData),
               sel.applicationTokens.contains(application) {
                print("✅ ShieldAction: App found in unlocked group \(group.name)")
                return true
            }
        }
        
        return false
        #else
        return false
        #endif
    }
    
    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }
    
    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }
    
    // MARK: - Private helpers
    
    private func sendUnlockNotification(for application: ApplicationToken, using defaults: UserDefaults?) {
        // Берём shared defaults из App Group (если вдруг nil — пытаемся ещё раз)
        guard let defaults = defaults ?? UserDefaults(suiteName: appGroupId) else {
            print("❌ ShieldAction: No UserDefaults for app group")
            return
        }
        
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "DOOM CTRL"
        content.body = "Tap to choose unlock time."
        content.sound = .default
        content.categoryIdentifier = "UNLOCK_APP"
        
        // Определяем bundleId и groupId для заблокированного приложения
        let resolved = resolveAppInfo(for: application, defaults: defaults)
        
        var userInfo: [String: Any] = ["action": "unlock"]
        if let bundleId = resolved.bundleId {
            userInfo["bundleId"] = bundleId
        }
        if let groupId = resolved.groupId {
            userInfo["groupId"] = groupId
        }
        content.userInfo = userInfo
        
        let request = UNNotificationRequest(
            identifier: "shield_unlock_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        center.add(request) { error in
            if let error = error {
                print("❌ ShieldAction: failed to schedule unlock notification: \(error)")
            } else {
                print("✅ ShieldAction: scheduled unlock notification (bundleId: \(resolved.bundleId ?? "nil"), groupId: \(resolved.groupId ?? "nil"))")
            }
        }
    }
    
    /// Определяем bundleId и groupId заблокированного приложения.
    private func resolveAppInfo(for application: ApplicationToken, defaults: UserDefaults) -> (bundleId: String?, groupId: String?) {
        #if canImport(FamilyControls)
        // 1) Check ticket groups (ticketGroups_v1 then shieldGroups_v1)
        if let groupsData = defaults.data(forKey: "ticketGroups_v1") ?? defaults.data(forKey: "shieldGroups_v1"),
           let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: groupsData) {
            for group in groups {
                if let selectionData = group.selectionData,
                   let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selectionData),
                   sel.applicationTokens.contains(application) {
                    // Нашли группу с этим приложением - получаем имя/bundleId
                    if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: application, requiringSecureCoding: true) {
                        let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                        if let appName = defaults.string(forKey: tokenKey) {
                            // Сохраняем для fallback
                            defaults.set(appName, forKey: "lastBlockedAppBundleId")
                            defaults.set(group.id, forKey: "lastBlockedGroupId")
                            return (bundleId: appName, groupId: group.id)
                        }
                    }
                    // Даже если не нашли имя, возвращаем groupId
                    defaults.set(group.id, forKey: "lastBlockedGroupId")
                    return (bundleId: nil, groupId: group.id)
                }
            }
        }
        
        // 2) Проверяем lastBlockedAppBundleId и убеждаемся, что его selection всё ещё содержит этот token
        if let existing = defaults.string(forKey: "lastBlockedAppBundleId") {
            let key = "timeAccessSelection_v1_\(existing)"
            if let data = defaults.data(forKey: key),
               let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: data),
               sel.applicationTokens.contains(application) {
                let groupId = defaults.string(forKey: "lastBlockedGroupId")
                return (bundleId: existing, groupId: groupId)
            }
        }
        
        // 3) Ищем по appUnlockSettings_v1
        if let data = defaults.data(forKey: "appUnlockSettings_v1"),
           let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data) {
            for (appId, _) in decoded {
                let key = "timeAccessSelection_v1_\(appId)"
                if let selData = defaults.data(forKey: key),
                   let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selData),
                   sel.applicationTokens.contains(application) {
                    defaults.set(appId, forKey: "lastBlockedAppBundleId")
                    return (bundleId: appId, groupId: nil)
                }
            }
        }
        
        // 4) Если ничего не нашли, очищаем старые значения чтобы не использовать неверные данные
        defaults.removeObject(forKey: "lastBlockedAppBundleId")
        defaults.removeObject(forKey: "lastBlockedGroupId")
        
        return (bundleId: nil, groupId: nil)
        #else
        return (bundleId: nil, groupId: nil)
        #endif
    }
    
    // Минимальная структура для декодирования групп щитов
    private struct ShieldGroupData: Codable {
        let id: String
        let name: String
        let selectionData: Data?
        
        enum CodingKeys: String, CodingKey {
            case id, name, selectionData
        }
    }
}
