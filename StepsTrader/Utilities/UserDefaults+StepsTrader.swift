import Foundation

// MARK: - UserDefaults Extension for Proof
extension UserDefaults {
    private static var hasLoggedFallback = false
    private static var hasLoggedGroupInfo = false
    
    static func stepsTrader() -> UserDefaults {
        let groupId = SharedKeys.appGroupId
        #if DEBUG
        if !hasLoggedGroupInfo {
            print("bundle:", Bundle.main.bundleIdentifier ?? "nil")
            print("group URL:", FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) as Any)
            hasLoggedGroupInfo = true
        }
        #endif
        
        // Check if App Group container is available (otherwise suiteName may return a warning).
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) != nil,
           let appGroup = UserDefaults(suiteName: groupId) {
            return appGroup
        }

        if !hasLoggedFallback {
            hasLoggedFallback = true
            AppLogger.app.error("App Group container unavailable, using standard UserDefaults")
        }
        return .standard
    }
}
