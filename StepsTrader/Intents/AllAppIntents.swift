import AppIntents
import Foundation
import UserNotifications

// Pay Gate shortcut with handoff token architecture

@available(iOS 17.0, *)
struct PayGateIntent: AppIntent {
    static var title: LocalizedStringResource = "Steps Trader: Open Pay Gate"
    static var description = IntentDescription(
        "Opens the PayGate for the selected app. Pay with steps to proceed.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App")
    var target: TargetApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        _ = Date()
        var settings = IntentSettings(defaults: userDefaults)

        print("🔍 PayGateIntent triggered for \(target.bundleId) at \(Date())")
        settings.selectedAppScheme = target.urlScheme

        // Always show in-app paygate; no system shield.
        userDefaults.set(true, forKey: "shouldShowFocusGate")
        userDefaults.set(target.bundleId, forKey: "focusGateTargetBundleId")
        
        // Also set a notification flag as backup
        userDefaults.set(true, forKey: "shortcutTriggered")
        userDefaults.set(target.rawValue, forKey: "shortcutTarget")
        userDefaults.set(Date(), forKey: "shortcutTriggerTime")

        // Send notification to app instead of trying URL schemes (works in background)
        print("📱 Sending notification to app for FocusGate")
        
        // Send Darwin notification that the app can receive
        let notificationName = CFNotificationName("com.steps.trader.focusgate" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            ["target": target.rawValue, "bundleId": target.bundleId] as CFDictionary,
            true
        )
        
        print("📱 Darwin notification sent for target: \(target.rawValue)")
        
        // Post a local notification to the app (no user-visible notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: .init("com.steps.trader.local.focusgate"),
                object: nil,
                userInfo: [
                    "target": target.rawValue,
                    "bundleId": target.bundleId,
                    "action": "focusgate"
                ]
            )
            print("📱 Posted local notification to app")
        }
        
        return .result(value: true)
    }

    private func getAppDisplayName(_ bundleId: String) -> String {
        switch bundleId {
        case "com.burbn.instagram": return "Instagram"
        case "com.zhiliaoapp.musically": return "TikTok"
        case "com.google.ios.youtube": return "YouTube"
        default: return bundleId
        }
    }
}

@available(iOS 17.0, *)
struct CanOpenPayGateIntent: AppIntent {
    static var title: LocalizedStringResource = "Steps Trader: Can Open Pay Gate"
    static var description = IntentDescription(
        "Checks if Pay Gate can be opened now for the selected app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App")
    var target: TargetApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()

        // Anti-loop: if we opened the target app ourselves very recently, block to avoid a loop
        if let lastOpen = userDefaults.object(forKey: "lastAppOpenedFromStepsTrader") as? Date {
            let elapsed = now.timeIntervalSince(lastOpen)
            if elapsed < 10 {
                print("🚫 CanOpenPayGate: last open \(String(format: "%.1f", elapsed))s ago, returning false to prevent loop")
                return .result(value: false)
            }
        }

        // Remember the target scheme so the next Open Pay Gate uses the same app
        userDefaults.set(target.urlScheme, forKey: "selectedAppScheme")
        return .result(value: true)
    }
}

@available(iOS 17.0, *)
enum TargetApp: String, AppEnum, CaseDisplayRepresentable {
    case instagram
    case tiktok

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App"

    static var caseDisplayRepresentations: [TargetApp: DisplayRepresentation] = [
        .instagram: "📱 Instagram",
        .tiktok: "🎵 TikTok",
    ]

    var bundleId: String {
        switch self {
        case .instagram: return "com.burbn.instagram"
        case .tiktok: return "com.zhiliaoapp.musically"
        }
    }
    
    var urlScheme: String {
        switch self {
        case .instagram: return "instagram://"
        case .tiktok: return "tiktok://"
        }
    }
}

private struct IntentSettings {
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    var selectedAppScheme: String? {
        get { defaults.string(forKey: "selectedAppScheme") }
        set {
            if let value = newValue {
                defaults.set(value, forKey: "selectedAppScheme")
            } else {
                defaults.removeObject(forKey: "selectedAppScheme")
            }
        }
    }
}
