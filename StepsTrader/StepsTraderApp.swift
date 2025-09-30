import SwiftUI
import FamilyControls

@main
struct StepsTraderApp: App {
    @StateObject private var model: AppModel
    
    init() {
        _model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if model.showFocusGate {
                    FocusGateView(model: model)
                } else if model.showQuickStatusPage {
                    QuickStatusView(model: model)
                } else {
                    MainTabView()
                        .environmentObject(model)
                }
                
                // Shortcut message overlay
                if model.showShortcutMessage, let message = model.shortcutMessage {
                    ShortcutMessageView(message: message) {
                        model.showShortcutMessage = false
                        model.shortcutMessage = nil
                    }
                }
            }
            .onAppear {
                print("🎭 StepsTraderApp appeared - showFocusGate: \(model.showFocusGate), showQuickStatusPage: \(model.showQuickStatusPage)")
                checkForShortcutMessage()
            }
            .onOpenURL { url in
                model.handleIncomingURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                model.handleAppDidEnterBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                model.handleAppWillEnterForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.refresh"))) { _ in
                model.handleAppWillEnterForeground()
            }
        }
    }
    
    private func checkForShortcutMessage() {
        let userDefaults = UserDefaults.stepsTrader()
        
        // Проверяем, не открывалось ли приложение недавно через наше приложение
        if let lastAppOpenTime = userDefaults.object(forKey: "lastAppOpenedFromStepsTrader") as? Date {
            let timeSinceAppOpen = Date().timeIntervalSince(lastAppOpenTime)
            print("⏰ Time since app opened from Steps Trader: \(timeSinceAppOpen) seconds")
            
            // Если приложение открывалось из нашего приложения менее 30 секунд назад, игнорируем шорткат
            if timeSinceAppOpen < 30.0 {
                print("🚫 App recently opened from Steps Trader, ignoring shortcut to prevent loop")
                return
            }
        }
        
        // Проверяем, есть ли сообщение от шортката
        if let message = userDefaults.string(forKey: "shortcutMessage") {
            model.shortcutMessage = message
            model.showShortcutMessage = true
            
            // Очищаем сообщение после показа
            userDefaults.removeObject(forKey: "shortcutMessage")
        }
        
        // Проверяем, нужно ли показать Focus Gate
        if userDefaults.bool(forKey: "shouldShowFocusGate") {
            if let targetBundleId = userDefaults.string(forKey: "focusGateTargetBundleId") {
                model.focusGateTargetBundleId = targetBundleId
                model.showFocusGate = true
            }
            
            // Очищаем флаги
            userDefaults.removeObject(forKey: "shouldShowFocusGate")
            userDefaults.removeObject(forKey: "focusGateTargetBundleId")
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var model: AppModel
    
    var body: some View {
        TabView {
            StatusView(model: model)
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Статус")
                }
            
            SettingsView(model: model)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Настройки")
                }
        }
    }
}

// MARK: - Quick Status View
struct QuickStatusView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.green.opacity(0.1), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Text("📊")
                        .font(.system(size: 60))
                    
                    Text("Быстрый статус")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Обзор вашего прогресса")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 20) {
                    // Шаги сегодня
                    HStack {
                        Text("Шаги сегодня:")
                            .font(.title2)
                        Spacer()
                        Text("\(Int(model.stepsToday))")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    
                    // Бюджет времени
                    HStack {
                        Text("Бюджет времени:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.remainingMinutes) мин")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(model.remainingMinutes > 0 ? .blue : .red)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    
                    // Потрачено времени
                    HStack {
                        Text("Потрачено:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.spentMinutes) мин")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    
                    // Баланс шагов для входа
                    HStack {
                        Text("Баланс для входа:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.stepsBalance) шагов")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(model.stepsBalance >= model.entryCostSteps ? .green : .red)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }
                .padding(.horizontal, 20)
                
                Button("Закрыть") {
                    model.showQuickStatusPage = false
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .font(.headline)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Shortcut Message View
struct ShortcutMessageView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("📱 Шорткат")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                
                Button("OK") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - FocusGateView
struct FocusGateView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.1), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                VStack(spacing: 16) {
                    Text("🎯")
                        .font(.system(size: 60))
                    
                    Text("Steps Trader")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Оплатите вход шагами")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 20) {
                    // Баланс шагов
                    HStack {
                        Text("Баланс шагов:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.stepsBalance)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(model.stepsBalance >= model.entryCostSteps ? .green : .red)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    
                    // Стоимость входа
                    HStack {
                        Text("Стоимость входа:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.entryCostSteps) шагов")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    
                    if let bundleId = model.focusGateTargetBundleId {
                        Button("Оплатить и открыть \(getAppDisplayName(bundleId))") {
                            Task {
                                await model.refreshStepsBalance()
                                if model.canPayForEntry() {
                                    _ = model.payForEntry()
                                    openTargetAppAndClose(bundleId)
                                } else {
                                    model.message = "❌ Недостаточно шагов. Нужно еще: \(model.entryCostSteps - model.stepsBalance) шагов."
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(model.stepsBalance >= model.entryCostSteps ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(model.stepsBalance < model.entryCostSteps)
                    }
                    
                    Button("Закрыть") {
                        model.showFocusGate = false
                        model.focusGateTargetBundleId = nil
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.gray.opacity(0.3))
                    .foregroundColor(.primary)
                    .font(.headline)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func openTargetAppAndClose(_ bundleId: String) {
        // Устанавливаем флаг, что приложение открывается через наше приложение
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader")
        
        print("🚀 Opening \(bundleId) and setting protection flag at \(now)")
        
        // Открываем целевое приложение
        let scheme: String
        switch bundleId {
        case "com.burbn.instagram": scheme = "instagram://app"
        case "com.zhiliaoapp.musically": scheme = "tiktok://"
        case "com.google.ios.youtube": scheme = "youtube://"
        default: scheme = "instagram://app" // fallback
        }
        
        if let url = URL(string: scheme) {
            UIApplication.shared.open(url) { success in
                if success {
                    print("✅ Successfully opened \(bundleId)")
                    // Закрываем Focus Gate после успешного открытия
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        model.showFocusGate = false
                        model.focusGateTargetBundleId = nil
                    }
                } else {
                    print("❌ Failed to open \(bundleId)")
                }
            }
        }
    }
}

// MARK: - Helper Functions
private func getAppDisplayName(_ bundleId: String) -> String {
    switch bundleId {
    case "com.burbn.instagram": return "Instagram"
    case "com.zhiliaoapp.musically": return "TikTok"
    case "com.google.ios.youtube": return "YouTube"
    default: return bundleId
    }
}