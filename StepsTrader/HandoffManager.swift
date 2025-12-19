import Foundation
import UIKit

// MARK: - Handoff Manager Extension for AppModel
extension AppModel {

    func handleHandoffContinue() {
        guard let token = handoffToken else {
            print("❌ handleHandoffContinue called but no handoffToken found")
            return
        }

        print("🚀 User continued with handoff for \(token.targetAppName)")
        print(
            "🚀 Before - showHandoffProtection: \(showHandoffProtection), handoffToken: \(handoffToken?.targetAppName ?? "nil")"
        )

        let userDefaults = UserDefaults.stepsTrader()

        // Скрываем защитный экран
        showHandoffProtection = false
        handoffToken = nil
        print(
            "🚀 After - showHandoffProtection: \(showHandoffProtection), handoffToken: \(handoffToken?.targetAppName ?? "nil")"
        )

        // Удаляем токен
        userDefaults.removeObject(forKey: "handoffToken")
        print("🚀 Removed handoff token from UserDefaults")

        // Открываем целевое приложение
        print("🚀 Opening target app: \(token.targetBundleId)")
        openTargetApp(bundleId: token.targetBundleId)
    }

    func handleHandoffCancel() {
        print("❌ User cancelled handoff")

        // Скрываем защитный экран
        showHandoffProtection = false
        handoffToken = nil

        // Удаляем токен
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.removeObject(forKey: "handoffToken")
    }

    private func openTargetApp(bundleId: String) {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader")

        print("🚀 Opening \(bundleId) from HandoffManager and setting protection flag at \(now)")

        let scheme: String
        switch bundleId {
        case "com.burbn.instagram": scheme = "instagram://app"
        case "com.zhiliaoapp.musically": scheme = "tiktok://"
        case "com.google.ios.youtube": scheme = "youtube://"
        default: scheme = "instagram://app"
        }

        if let url = URL(string: scheme) {
            UIApplication.shared.open(url) { success in
                if success {
                    print("✅ Successfully opened \(bundleId)")
                } else {
                    print("❌ Failed to open \(bundleId)")
                }
            }
        }
    }
}
