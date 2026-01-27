import Foundation
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

// Локальная копия минимальных настроек для декодинга appUnlockSettings_v1
private struct StoredUnlockSettingsForNotification: Codable {
    let entryCostSteps: Int?
    let minuteTariffEnabled: Bool?
    let familyControlsModeEnabled: Bool?
}

// Минимальная структура для декодинга групп щитов
private struct ShieldGroupDataForNotification: Codable {
    let id: String
    let name: String
    let selectionData: Data?
    
    enum CodingKeys: String, CodingKey {
        case id, name, selectionData
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var model: AppModel?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let action = userInfo["action"] as? String, action == "unlock" {
            // Пытаемся определить bundleId:
            // 1) прямо из userInfo;
            // 2) из lastBlockedAppBundleId в shared defaults;
            // 3) из групп щитов (shieldGroups_v1);
            // 4) из appUnlockSettings_v1 (берём первый включённый бандл или просто первый ключ).
            let directBundleId = userInfo["bundleId"] as? String
            let defaults = UserDefaults.stepsTrader()
            let sharedBundleId = defaults.string(forKey: "lastBlockedAppBundleId")
            
            // Проверяем группы щитов - ищем по имени приложения из lastBlockedAppBundleId
            let groupBundleId: String? = {
                guard let groupsData = defaults.data(forKey: "shieldGroups_v1"),
                      let groups = try? JSONDecoder().decode([ShieldGroupDataForNotification].self, from: groupsData),
                      !groups.isEmpty
                else { return nil }
                
                // Если есть lastBlockedAppBundleId, проверяем, есть ли он в группах
                if let blockedAppName = sharedBundleId {
                    for group in groups {
                        if let selectionData = group.selectionData,
                           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
                            // Проверяем, есть ли приложение с таким именем в группе
                            for token in sel.applicationTokens {
                                if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                                    let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                                    if let appName = defaults.string(forKey: tokenKey),
                                       (appName.lowercased() == blockedAppName.lowercased() ||
                                        blockedAppName.lowercased().contains(appName.lowercased()) ||
                                        appName.lowercased().contains(blockedAppName.lowercased())) {
                                        print("✅ Found app name in group: \(appName)")
                                        // Конвертируем appName в bundleId
                                        let bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                        print("✅ Resolved bundleId: \(bundleId)")
                                        return bundleId
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Если не нашли по имени, берем первое приложение из первой активной группы
                for group in groups {
                    if let selectionData = group.selectionData,
                       let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
                       !sel.applicationTokens.isEmpty {
                        // Берем имя первого приложения из группы
                        if let firstToken = sel.applicationTokens.first,
                           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
                            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                            if let appName = defaults.string(forKey: tokenKey) {
                                print("✅ Using first app from group: \(appName)")
                                // Конвертируем appName в bundleId
                                let bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                print("✅ Resolved bundleId: \(bundleId)")
                                return bundleId
                            }
                        }
                    }
                }
                return nil
            }()
            
            let fallbackBundleId: String? = {
                guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
                      let decoded = try? JSONDecoder().decode([String: StoredUnlockSettingsForNotification].self, from: data),
                      !decoded.isEmpty
                else { return nil }
                
                let enabledKey = decoded.first { (_, settings) in
                    (settings.minuteTariffEnabled ?? false) || (settings.familyControlsModeEnabled ?? false)
                }?.key
                return enabledKey ?? decoded.keys.first
            }()
            
            let bundleId = directBundleId ?? sharedBundleId ?? groupBundleId ?? fallbackBundleId
            
            if let bundleId {
                print("📲 Push notification tapped for unlock: \(bundleId)")
                print("   - directBundleId: \(directBundleId ?? "nil")")
                print("   - sharedBundleId: \(sharedBundleId ?? "nil")")
                print("   - groupBundleId: \(groupBundleId ?? "nil")")
                print("   - fallbackBundleId: \(fallbackBundleId ?? "nil")")
                
                // Open paygate - ищем группу по bundleId
                Task { @MainActor in
                    self.model?.openPayGateForBundleId(bundleId)
                }
            } else {
                print("⚠️ Push notification tapped for unlock, but bundleId not found")
                print("   - directBundleId: \(directBundleId ?? "nil")")
                print("   - sharedBundleId: \(sharedBundleId ?? "nil")")
                print("   - groupBundleId: \(groupBundleId ?? "nil")")
                print("   - fallbackBundleId: \(fallbackBundleId ?? "nil")")
                print("   - shieldGroups_v1 exists: \(defaults.data(forKey: "shieldGroups_v1") != nil)")
                
                // Попытка открыть PayGate с первым доступным bundleId из групп
                // Используем модель напрямую, так как она уже загружена
                Task { @MainActor in
                    guard let model = self.model else { 
                        print("⚠️ Fallback: Model is nil")
                        return 
                    }
                    
                    let defaults = UserDefaults.stepsTrader()
                    var bundleId: String? = nil
                    
                    // Способ 1: Используем lastBlockedAppBundleId (самый надежный)
                    if let blockedApp = defaults.string(forKey: "lastBlockedAppBundleId") {
                        bundleId = TargetResolver.bundleId(from: blockedApp) ?? blockedApp
                        print("🔄 Fallback: Using lastBlockedAppBundleId: \(blockedApp) -> \(bundleId ?? "nil")")
                    }
                    
                    // Способ 2: Если нет lastBlockedAppBundleId, используем первый bundleId из appUnlockSettings
                    if bundleId == nil {
                        if let data = defaults.data(forKey: "appUnlockSettings_v1") {
                            print("🔄 Fallback: Found appUnlockSettings_v1 data, size: \(data.count) bytes")
                            if let decoded = try? JSONDecoder().decode([String: StoredUnlockSettingsForNotification].self, from: data) {
                                print("🔄 Fallback: Decoded \(decoded.keys.count) app unlock settings")
                                // Ищем первый включенный или просто первый ключ
                                let enabledKey = decoded.first { (_, settings) in
                                    (settings.minuteTariffEnabled ?? false) || (settings.familyControlsModeEnabled ?? false)
                                }?.key
                                
                                let firstKey = enabledKey ?? decoded.keys.first
                                if let firstKey = firstKey {
                                    bundleId = TargetResolver.bundleId(from: firstKey) ?? firstKey
                                    print("🔄 Fallback: Using key from appUnlockSettings: \(firstKey) -> \(bundleId ?? "nil")")
                                } else {
                                    print("⚠️ Fallback: appUnlockSettings decoded but no keys found")
                                }
                            } else {
                                print("⚠️ Fallback: Could not decode appUnlockSettings_v1")
                            }
                        } else {
                            print("⚠️ Fallback: No appUnlockSettings_v1 data found")
                        }
                    }
                    
                    // Способ 3: Если есть shield groups, пробуем найти bundleId через все сохраненные имена приложений
                    if bundleId == nil {
                        if let firstGroup = model.shieldGroups.first(where: { !$0.selection.applicationTokens.isEmpty }) {
                            print("🔄 Fallback: Found group with \(firstGroup.selection.applicationTokens.count) apps")
                            
                            // Пробуем найти через все сохраненные имена приложений в UserDefaults
                            let allKeys = defaults.dictionaryRepresentation().keys
                            for key in allKeys where key.hasPrefix("fc_appName_") {
                                if let appName = defaults.string(forKey: key) {
                                    bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                    print("🔄 Fallback: Using first found app name from UserDefaults: \(appName) -> \(bundleId ?? "nil")")
                                    break
                                }
                            }
                            
                            // Если не нашли через UserDefaults, пробуем архивацию токена
                            if bundleId == nil {
                                #if canImport(FamilyControls)
                                if let firstToken = firstGroup.selection.applicationTokens.first {
                                    if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
                                        let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                                        if let appName = defaults.string(forKey: tokenKey) {
                                            bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                            print("🔄 Fallback: Found app name via archiving: \(appName) -> \(bundleId ?? "nil")")
                                        } else {
                                            print("⚠️ Fallback: Token archived but no app name found for key: \(tokenKey)")
                                        }
                                    } else {
                                        print("⚠️ Fallback: Could not archive token")
                                    }
                                }
                                #endif
                            }
                        } else {
                            print("⚠️ Fallback: No shield groups with apps found")
                        }
                    }
                    
                    // Открываем PayGate если нашли bundleId
                    if let bundleId = bundleId {
                        print("🔄 Fallback: Opening PayGate with bundleId: \(bundleId)")
                        model.openPayGateForBundleId(bundleId)
                    } else {
                        print("⚠️ Fallback: Could not find bundleId from any source")
                        
                        // Последняя попытка: если есть shield groups, открываем первую группу напрямую
                        if let firstGroup = model.shieldGroups.first {
                            print("🔄 Fallback: Using first shield group: \(firstGroup.name) (id: \(firstGroup.id))")
                            model.openPayGate(for: firstGroup.id)
                        } else {
                            print("⚠️ Fallback: No shield groups available")
                        }
                    }
                }
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
