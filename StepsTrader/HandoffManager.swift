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

        let scheme = bundleScheme(for: bundleId)

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
    
    private func bundleScheme(for bundleId: String) -> String {
        let map: [String: String] = [
            "com.burbn.instagram": "instagram://app",
            "com.zhiliaoapp.musically": "tiktok://",
            "com.google.ios.youtube": "youtube://",
            "ph.telegra.Telegraph": "tg://",
            "net.whatsapp.WhatsApp": "whatsapp://",
            "com.toyopagroup.picaboo": "snapchat://",
            "com.facebook.Facebook": "fb://",
            "com.linkedin.LinkedIn": "linkedin://",
            "com.atebits.Tweetie2": "twitter://",
            "com.reddit.Reddit": "reddit://",
            "com.pinterest": "pinterest://",
            "com.duolingo.DuolingoMobile": "duolingo://"
        ]
        return map[bundleId] ?? "instagram://app"
    }
}
