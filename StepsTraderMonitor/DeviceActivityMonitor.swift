import DeviceActivity
import Foundation
import ManagedSettings
import FamilyControls
import UserNotifications
import AudioToolbox

// MARK: - Local UserDefaults Helper for Extension Target
extension UserDefaults {
    static func stepsTrader() -> UserDefaults {
        if let appGroup = UserDefaults(suiteName: "group.personal-project.StepsTrader") {
            return appGroup
        } else {
            // Simulator fallback to avoid CFPrefsPlistSource error
            print("⚠️ [Monitor] App Group not available, using standard UserDefaults")
            return .standard
        }
    }
}

class StepsTraderDeviceActivityMonitor: DeviceActivityMonitor {
    
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        print("🚀 DeviceActivityMonitor: Interval started for activity: \(activity)")
        print("   Time: \(Date())")
        
        // Проверяем информацию о выбранных приложениях
        let userDefaults = UserDefaults.stepsTrader()
        
        let selectedAppsCount = userDefaults.integer(forKey: "selectedAppsCount")
        let selectedCategoriesCount = userDefaults.integer(forKey: "selectedCategoriesCount")
        let budgetMinutes = userDefaults.object(forKey: "budgetMinutes") as? Int ?? 0
        let startTime = userDefaults.object(forKey: "monitoringStartTime") as? Date
        
        print("📊 MONITOR STATUS:")
        print("   - Selected apps: \(selectedAppsCount)")
        print("   - Selected categories: \(selectedCategoriesCount)")
        print("   - Budget minutes: \(budgetMinutes)")
        print("   - Start time: \(startTime?.description ?? "unknown")")
        
        if selectedAppsCount == 0 && selectedCategoriesCount == 0 {
            print("⚠️ WARNING: No apps or categories selected for monitoring!")
        } else {
            print("✅ Monitoring configuration looks valid")
        }
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        print("📱 Device activity monitoring ended for: \(activity)")
        
        // Снимаем блокировку в конце дня
        let store = ManagedSettingsStore()
        store.clearAllSettings()
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        print("🚨 DeviceActivityMonitor: TIME LIMIT REACHED!")
        print("   Event: \(event)")
        print("   Activity: \(activity)")
        print("   Time: \(Date())")
        
        // Обновляем потраченное время в shared UserDefaults
        let userDefaults = UserDefaults.stepsTrader()
        if let budgetMinutes = userDefaults.object(forKey: "budgetMinutes") as? Int {
            userDefaults.set(budgetMinutes, forKey: "spentMinutes")
            userDefaults.set(Date(), forKey: "spentTimeDate")
            print("💾 Updated spent time: \(budgetMinutes) minutes (limit reached)")
        }
        
        // Блокируем выбранные приложения
        let store = ManagedSettingsStore()
        
        // Пытаемся получить ApplicationTokens из UserDefaults
        if let tokensData = userDefaults.data(forKey: "selectedApplicationTokens"),
           !tokensData.isEmpty {
            
            do {
                // Пытаемся декодировать ApplicationTokens
                if let applicationTokens = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSSet.self], from: tokensData) as? Set<ApplicationToken> {
                    print("📊 Blocking \(applicationTokens.count) selected applications using ApplicationTokens")
                    store.shield.applications = applicationTokens
                    print("🛡️ Shield enabled for specific ApplicationTokens")
                } else {
                    print("❌ Failed to decode ApplicationTokens, using category fallback")
                    useCategoryFallback()
                }
            } catch {
                print("❌ Error decoding ApplicationTokens: \(error), using category fallback")
                useCategoryFallback()
            }
        } else {
            print("⚠️ No ApplicationTokens found, using category fallback")
            useCategoryFallback()
        }
        
        func useCategoryFallback() {
            // Fallback - блокируем основные категории
            let categoriesToBlock: [ActivityCategory] = [.socialNetworking, .entertainment, .games]
            store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(categoriesToBlock)
            print("🔄 Fallback: blocking categories \(categoriesToBlock)")
        }
        
        // Отправляем уведомление о том, что время истекло
        sendTimeExpiredNotification()
        
        // Звуковой сигнал
        AudioServicesPlaySystemSound(1005)
    }
    
    private func sendTimeExpiredNotification() {
        print("🔔 DeviceActivityMonitor: Sending time expired notification...")
        
        let content = UNMutableNotificationContent()
        content.title = "⏰ Steps Trader - Время истекло!"
        content.body = "Ваше время для выбранных приложений истекло! Сделайте больше шагов для дополнительного времени."
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "StepsTrader-TimeExpired-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ DeviceActivityMonitor: Notification error: \(error)")
            } else {
                print("✅ DeviceActivityMonitor: Notification sent successfully")
            }
        }
    }
    
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        print("⚠️ Warning: interval will start soon for \(activity)")
    }
    
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        print("⚠️ Warning: interval will end soon for \(activity)")
    }
    
    override func eventWillReachThresholdWarning(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        print("⚠️ Warning: event \(event) will reach threshold soon")
    }
}
