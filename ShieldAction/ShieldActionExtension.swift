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
        let defaults = UserDefaults(suiteName: appGroupId)
        let currentState = defaults?.integer(forKey: shieldStateKey) ?? 0
        
        switch action {
        case .primaryButtonPressed:
            if currentState == 0 {
                // Первый тап по "Unlock": переключаемся в состояние "waitingPush" и шлём пуш
                defaults?.set(1, forKey: shieldStateKey)
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
        
        // Пытаемся сопоставить текущий ApplicationToken с конкретной карточкой (appId),
        // используя per-card FamilyActivitySelection (timeAccessSelection_v1_<appId>).
        let bundleId = resolveBundleId(for: application, defaults: defaults)
        if let bundleId {
            content.userInfo = [
                "bundleId": bundleId,
                "action": "unlock"
            ]
        } else {
            content.userInfo = ["action": "unlock"]
        }
        
        let request = UNNotificationRequest(
            identifier: "shield_unlock_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        center.add(request) { error in
            if let error = error {
                print("❌ ShieldAction: failed to schedule unlock notification: \(error)")
            } else {
                print("✅ ShieldAction: scheduled unlock notification")
            }
        }
    }
    
    /// Пытаемся определить bundleId заблокированного приложения.
    private func resolveBundleId(for application: ApplicationToken, defaults: UserDefaults) -> String? {
        #if canImport(FamilyControls)
        // 1) Проверяем lastBlockedAppBundleId и убеждаемся, что его selection всё ещё содержит этот token.
        if let existing = defaults.string(forKey: "lastBlockedAppBundleId") {
            let key = "timeAccessSelection_v1_\(existing)"
            if let data = defaults.data(forKey: key),
               let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: data),
               sel.applicationTokens.contains(application) {
                return existing
            }
        }
        
        // 2) Проверяем группы щитов (shieldGroups_v1)
        if let groupsData = defaults.data(forKey: "shieldGroups_v1"),
           let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: groupsData) {
            for group in groups {
                if let selectionData = group.selectionData,
                   let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selectionData),
                   sel.applicationTokens.contains(application) {
                    // Сохраняем имя приложения из группы для поиска
                    if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: application, requiringSecureCoding: true) {
                        let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                        if let appName = defaults.string(forKey: tokenKey) {
                            // Используем имя приложения как bundleId для поиска
                            defaults.set(appName, forKey: "lastBlockedAppBundleId")
                            return appName
                        }
                    }
                }
            }
        }
        
        // 3) Ищем нужную карточку, проходя по всем appIds из appUnlockSettings_v1.
        guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data),
              !decoded.isEmpty
        else {
            return nil
        }
        
        for (appId, _) in decoded {
            let key = "timeAccessSelection_v1_\(appId)"
            if let selData = defaults.data(forKey: key),
               let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selData),
               sel.applicationTokens.contains(application) {
                defaults.set(appId, forKey: "lastBlockedAppBundleId")
                return appId
            }
        }
        return nil
        #else
        return nil
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
