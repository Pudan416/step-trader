import Foundation

// MARK: - UserDefaults Extension for Proof
extension UserDefaults {
    private static var hasLoggedGroupInfo = false
    
    /// Returns the shared App Group UserDefaults.
    /// In DEBUG builds, asserts if the container is unavailable (entitlements misconfiguration).
    /// In RELEASE builds, falls back to .standard with a warning — but data written here
    /// will NOT be visible to extensions, causing shields/charges to silently break (audit fix #24).
    static func stepsTrader() -> UserDefaults {
        let groupId = SharedKeys.appGroupId
        #if DEBUG
        if !hasLoggedGroupInfo {
            AppLogger.app.debug("bundle: \(Bundle.main.bundleIdentifier ?? "nil")")
            AppLogger.app.debug("group URL: \(String(describing: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)))")
            hasLoggedGroupInfo = true
        }
        #endif
        
        if let appGroup = UserDefaults(suiteName: groupId) {
            return appGroup
        }

        #if DEBUG
        assertionFailure("App Group container '\(groupId)' unavailable — check entitlements")
        #endif
        AppLogger.app.error("App Group container unavailable, falling back to .standard — extensions will NOT see this data")
        return .standard
    }
}
