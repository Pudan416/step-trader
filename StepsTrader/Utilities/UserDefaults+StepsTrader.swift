import Foundation

// MARK: - UserDefaults Extension for Steps Trader
extension UserDefaults {
    private static var hasLoggedFallback = false
    private static var hasLoggedGroupInfo = false
    
    static func stepsTrader() -> UserDefaults {
        let groupId = "group.personal-project.StepsTrader"
        #if DEBUG
        if !hasLoggedGroupInfo {
            print("bundle:", Bundle.main.bundleIdentifier ?? "nil")
            print("group URL:", FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) as Any)
            hasLoggedGroupInfo = true
        }
        #endif
        
        // Проверяем, доступен ли контейнер App Group (иначе suiteName может вернуть предупреждение).
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) != nil,
           let appGroup = UserDefaults(suiteName: groupId) {
            return appGroup
        }

        if !hasLoggedFallback {
            hasLoggedFallback = true
            print("⚠️ App Group container unavailable, using standard UserDefaults")
        }
        return .standard
    }
}
