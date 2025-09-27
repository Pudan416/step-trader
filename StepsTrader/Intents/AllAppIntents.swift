import AppIntents
import Foundation
import SwiftUI

// MARK: - Intent Data Access

struct IntentDataManager {
    static func getRemainingMinutes() -> Int {
        let userDefaults = UserDefaults.stepsTrader()
        return userDefaults.integer(forKey: "remainingMinutes")
    }
}

// MARK: - One Sec Intent

@available(iOS 16.0, *)
struct OneSecIntent: AppIntent {
    static var title: LocalizedStringResource = "Как у One Sec"
    static var description = IntentDescription("Показывает всплывающее окно с оставшимся временем")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Обновляем данные в приложении
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), 
            CFNotificationName("com.steps.trader.refresh" as CFString), 
            nil, nil, true
        )
        
        let remaining = IntentDataManager.getRemainingMinutes()
        print("🎯 One Sec - Remaining: \(remaining) min")
        
        return .result(
            dialog: "⏱️ Доступно: \(remaining) мин",
            view: OneSecSnippetView(remaining: remaining)
        )
    }
}

// Добавьте новый Intent для открытия приложения
@available(iOS 16.0, *)
struct OpenStepsTraderIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть Steps Trader"
    static var description = IntentDescription("Открывает приложение Steps Trader")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - One Sec Snippet View

struct OneSecSnippetView: View {
    let remaining: Int
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundColor(color)
                Text("Steps Trader")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(remaining)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text(remaining == 1 ? "минута" : "минут")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer(minLength: 0)
            }

            Text("нагуляли \(remaining) минут думскроллинга")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(intent: OpenStepsTraderIntent()) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                    Text("Открыть приложение")
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.blue.opacity(0.15))
            .foregroundColor(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    
    private var color: Color {
        switch remaining {
        case 0: return .red
        case 1..<10: return .orange
        default: return .green
        }
    }
}

// MARK: - Автоматический выбор приложения
@available(iOS 16.0, *)
struct AutoSelectAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Автоматически выбрать приложение"
    static var description = IntentDescription("Автоматически выбрать популярные приложения для отслеживания")
    
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Приложение")
    var targetApp: AppSelectionEntity?
    
    func perform() async throws -> some IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        
        // Если указано конкретное приложение, используем его
        if let app = targetApp {
            let bundleId = app.bundleId
            userDefaults.set(bundleId, forKey: "shortcutTargetBundleId")
            print("🎯 AutoSelectAppIntent: Setting target app to \(bundleId)")
        }
        
        // Устанавливаем флаг для автоматического выбора
        userDefaults.set(true, forKey: "shouldAutoSelectApps")
        
        // Отправляем уведомление для обновления
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("com.steps.trader.refresh" as CFString), nil, nil, true)
        
        return .result()
    }
}

// MARK: - Параметр для выбора приложения
@available(iOS 16.0, *)
struct AppSelectionEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation("Приложение")
    static var defaultQuery = AppSelectionQuery()
    
    var id: String
    var name: String
    var bundleId: String
    
    init(id: String, name: String, bundleId: String) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

@available(iOS 16.0, *)
struct AppSelectionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AppSelectionEntity] {
        return getAllApps().filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [AppSelectionEntity] {
        return getAllApps()
    }
    
    private func getAllApps() -> [AppSelectionEntity] {
        return [
            AppSelectionEntity(id: "instagram", name: "📱 Instagram", bundleId: "com.burbn.instagram"),
            AppSelectionEntity(id: "tiktok", name: "🎵 TikTok", bundleId: "com.zhiliaoapp.musically"),
            AppSelectionEntity(id: "youtube", name: "📺 YouTube", bundleId: "com.google.ios.youtube")
        ]
    }
}