import AppIntents
import Foundation
import UserNotifications

@available(iOS 17.0, *)
struct TestOneShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Steps Trader: Test one shortcut"
    static var description = IntentDescription(
        "Opens PayGate for a selected app when no access window is active.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App")
    var target: TargetApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        let _: AccessWindow = .single
        let selectedTarget: TargetApp = {
            if let saved = userDefaults.string(forKey: "lastCheckedPaygateTarget"),
               let resolved = TargetApp(rawValue: saved) {
                return resolved
            }
            return target
        }()

        // Анти-луп: если окно уже активно — выходим без флагов
        if isWithinBlockWindow(now: now, userDefaults: userDefaults, bundleId: selectedTarget.bundleId) {
            let remaining = remainingBlockSeconds(now: now, userDefaults: userDefaults, bundleId: selectedTarget.bundleId) ?? -1
            print("🚫 TestOneShortcutIntent: blocked until window expires for \(selectedTarget.bundleId) (\(remaining)s left)")
            clearPayGateFlags(userDefaults)
            return .result(value: false)
        }

        // Анти-спам: не чаще, чем раз в 5 секунд
        if let lastRun = userDefaults.object(forKey: "lastTestOneShortcutRun") as? Date {
            let elapsed = now.timeIntervalSince(lastRun)
            if elapsed < 5 {
                print("🚫 TestOneShortcutIntent: last run \(String(format: "%.1f", elapsed))s ago, skipping")
                return .result(value: false)
            }
        }
        userDefaults.set(now, forKey: "lastTestOneShortcutRun")

        print("🔍 TestOneShortcutIntent triggered for \(selectedTarget.bundleId) at \(Date())")
        userDefaults.set(selectedTarget.urlScheme, forKey: "selectedAppScheme")

        // Запрашиваем показ PayGate в приложении
        userDefaults.set(true, forKey: "shouldShowPayGate")
        userDefaults.set(selectedTarget.bundleId, forKey: "payGateTargetBundleId")
        userDefaults.set(true, forKey: "shortcutTriggered")
        userDefaults.set(selectedTarget.rawValue, forKey: "shortcutTarget")
        userDefaults.set(now, forKey: "shortcutTriggerTime")

        // Уведомляем приложение через Darwin и локальное уведомление
        let notificationName = CFNotificationName("com.steps.trader.paygate" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            ["target": selectedTarget.rawValue, "bundleId": selectedTarget.bundleId] as CFDictionary,
            true
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: .init("com.steps.trader.local.paygate"),
                object: nil,
                userInfo: [
                    "target": selectedTarget.rawValue,
                    "bundleId": selectedTarget.bundleId,
                    "action": "paygate"
                ]
            )
        }

        return .result(value: true)
    }
}

@available(iOS 17.0, *)
struct CheckAccessWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "Steps Trader: Can trigger PayGate now?"
    static var description = IntentDescription(
        "Returns whether PayGate is allowed right now for the selected app (false when paid window is active).")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App")
    var target: TargetApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        let isBlocked = isWithinBlockWindow(now: now, userDefaults: userDefaults, bundleId: target.bundleId)
        if isBlocked {
            let remaining = remainingBlockSeconds(now: now, userDefaults: userDefaults, bundleId: target.bundleId) ?? -1
            print("🚫 CheckAccessWindowIntent: blocked for \(target.bundleId) (\(remaining)s left)")
            return .result(value: false)
        } else {
            userDefaults.set(target.rawValue, forKey: "lastCheckedPaygateTarget")
            print("✅ CheckAccessWindowIntent: allowed for \(target.bundleId)")
            return .result(value: true)
        }
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
        TargetResolver.bundleId(from: rawValue) ?? rawValue
    }
    
    var urlScheme: String {
        TargetResolver.urlScheme(for: rawValue) ?? ""
    }
}

// MARK: - Window helpers
@available(iOS 17.0, *)
private func blockKey(for bundleId: String) -> String {
    "shortcutBlockUntil_\(bundleId)"
}

@available(iOS 17.0, *)
private func isWithinBlockWindow(now: Date, userDefaults: UserDefaults, bundleId: String) -> Bool {
    guard let until = userDefaults.object(forKey: blockKey(for: bundleId)) as? Date else {
        return false
    }
    if now >= until {
        userDefaults.removeObject(forKey: blockKey(for: bundleId))
        return false
    }
    return true
}

@available(iOS 17.0, *)
private func remainingBlockSeconds(now: Date, userDefaults: UserDefaults, bundleId: String) -> Int? {
    guard let until = userDefaults.object(forKey: blockKey(for: bundleId)) as? Date else { return nil }
    let remaining = Int(until.timeIntervalSince(now))
    return remaining > 0 ? remaining : nil
}

@available(iOS 17.0, *)
private func blockUntilDate(from now: Date, window: AccessWindow, userDefaults: UserDefaults, bundleId: String) -> Date? {
    switch window {
    case .single:
        return now.addingTimeInterval(10)
    case .minutes5:
        return now.addingTimeInterval(5 * 60)
    case .hour1:
        return now.addingTimeInterval(60 * 60)
    case .day1:
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        if let endOfDay = cal.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) {
            return endOfDay
        }
        return now.addingTimeInterval(24 * 60 * 60)
    }
}

@available(iOS 17.0, *)
private func clearPayGateFlags(_ userDefaults: UserDefaults) {
    userDefaults.removeObject(forKey: "shouldShowPayGate")
    userDefaults.removeObject(forKey: "payGateTargetBundleId")
    userDefaults.removeObject(forKey: "shortcutTriggered")
    userDefaults.removeObject(forKey: "shortcutTarget")
    userDefaults.removeObject(forKey: "shortcutTriggerTime")
}

// MARK: - AccessWindow AppIntents plumbing
@available(iOS 17.0, *)
extension AccessWindow: AppEnum, CaseDisplayRepresentable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Access window"
    static var caseDisplayRepresentations: [AccessWindow: DisplayRepresentation] = [
        .single: "🔓 Один раз",
        .minutes5: "⏱️ 5 минут",
        .hour1: "🕐 1 час",
        .day1: "🌞 До конца дня"
    ]
}
