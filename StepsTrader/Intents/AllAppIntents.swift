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
        let now = Date()
        var settings = IntentSettings(defaults: userDefaults)

        print("🔍 PayGateIntent triggered for \(target.bundleId) at \(Date())")
        settings.selectedAppScheme = target.urlScheme

        // Always show in-app paygate; no system shield.
        userDefaults.set(true, forKey: "shouldShowPayGate")
        userDefaults.set(target.bundleId, forKey: "payGateTargetBundleId")
        
        // Also set a notification flag as backup
        userDefaults.set(true, forKey: "shortcutTriggered")
        userDefaults.set(target.rawValue, forKey: "shortcutTarget")
        userDefaults.set(now, forKey: "shortcutTriggerTime")
        userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader")

        // Send notification to app instead of trying URL schemes (works in background)
        print("📱 Sending notification to app for PayGate")
        
        // Send Darwin notification that the app can receive
        let notificationName = CFNotificationName("com.steps.trader.paygate" as CFString)
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
                name: .init("com.steps.trader.local.paygate"),
                object: nil,
                userInfo: [
                    "target": target.rawValue,
                    "bundleId": target.bundleId,
                    "action": "paygate"
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
        case "ph.telegra.Telegraph": return "Telegram"
        case "net.whatsapp.WhatsApp": return "WhatsApp"
        case "com.toyopagroup.picaboo": return "Snapchat"
        case "com.facebook.Facebook": return "Facebook"
        case "com.linkedin.LinkedIn": return "LinkedIn"
        case "com.atebits.Tweetie2": return "X"
        case "com.reddit.Reddit": return "Reddit"
        case "com.pinterest": return "Pinterest"
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
        userDefaults.set(true, forKey: "automationConfigured")
        userDefaults.set(target.bundleId, forKey: "automationBundleId")
        var configured = userDefaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        if !configured.contains(target.bundleId) {
            configured.append(target.bundleId)
            userDefaults.set(configured, forKey: "automationConfiguredBundles")
        }
        return .result(value: true)
    }
}

@available(iOS 17.0, *)
struct PopularModulesIntent: AppIntent {
    static var title: LocalizedStringResource = "Steps Trader: Popular Modules"
    static var description = IntentDescription(
        "Single shortcut that checks and opens PayGate for a selected popular app.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App")
    var target: TargetApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()

        let lastRunKey = "lastPopularModulesRun"
        if let lastRun = userDefaults.object(forKey: lastRunKey) as? Date {
            let elapsed = now.timeIntervalSince(lastRun)
            if elapsed < 10 {
                print("🚫 PopularModulesIntent: last run \(String(format: "%.1f", elapsed))s ago, skipping")
                return .result(value: false)
            }
        }
        userDefaults.set(now, forKey: lastRunKey)

        // Anti-loop guard
        if let lastOpen = userDefaults.object(forKey: "lastAppOpenedFromStepsTrader") as? Date {
            let elapsed = now.timeIntervalSince(lastOpen)
            if elapsed < 10 {
                print("🚫 PopularModulesIntent: last open \(String(format: "%.1f", elapsed))s ago, skipping")
                return .result(value: false)
            }
        }

        var settings = IntentSettings(defaults: userDefaults)
        settings.selectedAppScheme = target.urlScheme

        // Mark configured
        userDefaults.set(true, forKey: "automationConfigured")
        userDefaults.set(target.bundleId, forKey: "automationBundleId")
        var configured = userDefaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        if !configured.contains(target.bundleId) {
            configured.append(target.bundleId)
            userDefaults.set(configured, forKey: "automationConfiguredBundles")
        }

        // Trigger in-app PayGate/PayGate
        userDefaults.set(true, forKey: "shouldShowPayGate")
        userDefaults.set(target.bundleId, forKey: "payGateTargetBundleId")
        userDefaults.set(true, forKey: "shortcutTriggered")
        userDefaults.set(target.rawValue, forKey: "shortcutTarget")
        userDefaults.set(now, forKey: "shortcutTriggerTime")
        userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader")

        let notificationName = CFNotificationName("com.steps.trader.paygate" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            ["target": target.rawValue, "bundleId": target.bundleId] as CFDictionary,
            true
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: .init("com.steps.trader.local.paygate"),
                object: nil,
                userInfo: [
                    "target": target.rawValue,
                    "bundleId": target.bundleId,
                    "action": "paygate"
                ]
            )
        }

        return .result(value: true)
    }
}

@available(iOS 17.0, *)
enum TargetApp: String, AppEnum, CaseDisplayRepresentable {
    case instagram
    case tiktok
    case youtube
    case telegram
    case whatsapp
    case snapchat
    case facebook
    case linkedin
    case x
    case reddit
    case pinterest

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App"

    static var caseDisplayRepresentations: [TargetApp: DisplayRepresentation] = [
        .instagram: "📱 Instagram",
        .tiktok: "🎵 TikTok",
        .youtube: "▶️ YouTube",
        .telegram: "✈️ Telegram",
        .whatsapp: "💬 WhatsApp",
        .snapchat: "👻 Snapchat",
        .facebook: "📘 Facebook",
        .linkedin: "💼 LinkedIn",
        .x: "❌ X (Twitter)",
        .reddit: "👽 Reddit",
        .pinterest: "📌 Pinterest",
    ]

    var bundleId: String {
        switch self {
        case .instagram: return "com.burbn.instagram"
        case .tiktok: return "com.zhiliaoapp.musically"
        case .youtube: return "com.google.ios.youtube"
        case .telegram: return "ph.telegra.Telegraph"
        case .whatsapp: return "net.whatsapp.WhatsApp"
        case .snapchat: return "com.toyopagroup.picaboo"
        case .facebook: return "com.facebook.Facebook"
        case .linkedin: return "com.linkedin.LinkedIn"
        case .x: return "com.atebits.Tweetie2"
        case .reddit: return "com.reddit.Reddit"
        case .pinterest: return "com.pinterest"
        }
    }
    
    var urlScheme: String {
        switch self {
        case .instagram: return "instagram://"
        case .tiktok: return "tiktok://"
        case .youtube: return "youtube://"
        case .telegram: return "tg://"
        case .whatsapp: return "whatsapp://"
        case .snapchat: return "snapchat://"
        case .facebook: return "fb://"
        case .linkedin: return "linkedin://"
        case .x: return "twitter://"
        case .reddit: return "reddit://"
        case .pinterest: return "pinterest://"
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
