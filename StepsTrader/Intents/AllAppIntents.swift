import AppIntents
import Foundation

// Pay Gate shortcut with target app parameter using modern dynamic foreground mode

@available(iOS 17.0, *)
struct PayGateIntent: AppIntent {
    static var title: LocalizedStringResource = "Steps Trader: открыть Pay Gate"
    static var description = IntentDescription("Выберите приложение (Instagram/TikTok). После запуска откроется экран оплаты шагами")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Приложение")
    var target: TargetApp

    func perform() async throws -> some IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        
        print("🔍 PayGateIntent triggered for \(target.bundleId) at \(now)")
        
        // Защита от повторного срабатывания - проверяем, не запускался ли шорткат недавно
        if let lastTriggerTime = userDefaults.object(forKey: "lastShortcutTriggerTime") as? Date {
            let timeSinceLastTrigger = now.timeIntervalSince(lastTriggerTime)
            print("⏰ Time since last shortcut trigger: \(timeSinceLastTrigger) seconds")
            
            // Если шорткат запускался менее 10 секунд назад, игнорируем
            if timeSinceLastTrigger < 10.0 {
                print("🚫 Shortcut called too soon, ignoring to prevent loop")
                return .result()
            }
        }
        
        // Сохраняем время последнего запуска шортката
        userDefaults.set(now, forKey: "lastShortcutTriggerTime")
        
        // Сохраняем информацию о целевом приложении
        userDefaults.set(target.bundleId, forKey: "shortcutTargetBundleId")
        userDefaults.set(now, forKey: "shortcutTriggerTime")
        
        // Проверяем баланс шагов
        let stepsBalance = userDefaults.integer(forKey: "stepsBalance")
        let entryCost = userDefaults.integer(forKey: "entryCostSteps")
        
        print("💰 Steps balance: \(stepsBalance), Entry cost: \(entryCost)")
        
        if stepsBalance >= entryCost {
            // Достаточно шагов - показываем Pay Gate
            userDefaults.set(true, forKey: "shouldShowFocusGate")
            userDefaults.set(target.bundleId, forKey: "focusGateTargetBundleId")
            
            return .result()
        } else {
            // Недостаточно шагов - показываем сообщение
            let needed = entryCost - stepsBalance
            userDefaults.set("❌ Недостаточно шагов. Нужно еще: \(needed) шагов.", forKey: "shortcutMessage")
            userDefaults.set(false, forKey: "shouldShowFocusGate")
            
            return .result()
        }
    }
}

@available(iOS 17.0, *)
enum TargetApp: String, AppEnum, CaseDisplayRepresentable {
    case instagram
    case tiktok

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Приложение"

    static var caseDisplayRepresentations: [TargetApp: DisplayRepresentation] = [
        .instagram: "📱 Instagram",
        .tiktok: "🎵 TikTok"
    ]

    var bundleId: String {
        switch self {
        case .instagram: return "com.burbn.instagram"
        case .tiktok: return "com.zhiliaoapp.musically"
        }
    }
}