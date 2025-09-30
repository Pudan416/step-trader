import Foundation

// MARK: - UserDefaults Extension for Steps Trader
extension UserDefaults {
    static func stepsTrader() -> UserDefaults {
        if let appGroup = UserDefaults(suiteName: "group.personal-project.StepsTrader") {
            return appGroup
        } else {
            // Fallback to standard UserDefaults if App Group is not available
            print("⚠️ App Group not available, using standard UserDefaults")
            return .standard
        }
    }
}
