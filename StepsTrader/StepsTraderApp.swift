import SwiftUI
import Foundation
import Combine

// MARK: - UserDefaults Helper
extension UserDefaults {
    static func stepsTrader() -> UserDefaults {
        // Try App Group first, fallback to standard UserDefaults for simulator
        if let appGroup = UserDefaults(suiteName: "group.personal-project.StepsTrader") {
            return appGroup
        } else {
            print("⚠️ App Group not available, using standard UserDefaults")
            return UserDefaults.standard
        }
    }
}

@main
struct StepsTraderApp: App {
    var body: some Scene {
        WindowGroup { 
            ContentView() 
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var model: AppModel
    
    init() {
        self._model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())
    }
    
    var body: some View {
        // Show block screen if blocked
        if model.isBlocked {
            BlockScreen(model: model)
        }
        // Show Focus Gate if triggered by deeplink
        else if model.showFocusGate {
            FocusGateView(model: model)
        }
        // Show Quick Status for Intent
        else if model.showQuickStatusPage {
            QuickStatusView(model: model)
        }
        // Show normal tab interface
        else {
            TabView {
                StatusView(model: model)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Статус")
                    }
                
                SettingsView(model: model)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Настройки")
                    }
            }
            .task { await model.bootstrap() }
            .alert("Информация", isPresented: Binding(get: { model.message != nil }, set: { _ in model.message = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.message ?? "") }
            .onOpenURL { url in
                model.handleIncomingURL(url)
            }
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
                    
                    Text("Focus Gate")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Проверьте свой баланс времени")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 20) {
                    HStack {
                        Text("Доступно минут:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.budget.remainingMinutes)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(model.budget.remainingMinutes > 0 ? .green : .red)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    
                    if let bundleId = model.focusGateTargetBundleId {
                        Button("Открыть \(getAppDisplayName(bundleId))") {
                            openTargetAppAndClose(bundleId)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(model.budget.remainingMinutes > 0 ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(model.budget.remainingMinutes <= 0)
                    }
                    
                    Button("Закрыть") {
                        model.showFocusGate = false
                        model.focusGateTargetBundleId = nil
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .onAppear {
            model.reloadBudgetFromStorage()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            model.reloadBudgetFromStorage()
        }
    }
    
    private func getAppDisplayName(_ bundleId: String) -> String {
        switch bundleId {
        case "com.burbn.instagram": return "Instagram"
        case "com.zhiliaoapp.musically": return "TikTok"
        case "com.google.ios.youtube": return "YouTube"
        default: return "приложение"
        }
    }
    
    private func openTargetAppAndClose(_ bundleId: String) {
        // Записываем время открытия для anti-loop механизма
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(Date(), forKey: "focusGateLastOpen")
        
        // Закрываем Focus Gate
        model.showFocusGate = false
        model.focusGateTargetBundleId = nil
        
        // Открываем приложение
        let scheme: String
        switch bundleId {
        case "com.burbn.instagram": scheme = "instagram://"
        case "com.zhiliaoapp.musically": scheme = "tiktok://"
        case "com.google.ios.youtube": scheme = "youtube://"
        default: return
        }
        
        if let url = URL(string: scheme) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - QuickStatusView (только для Intent)
struct QuickStatusView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Заголовок
                    headerView
                    
                    // Мини-статистика
                    miniStatsView
                    
                    // Большое отображение времени
                    bigTimeDisplayView
                    
                    // Кнопки управления
                    controlButtonsView
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("📱")
                    .font(.title)
                Text("Steps Trader")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                Text("📱")
                    .font(.title)
            }
            
            Text("Quick Status")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var miniStatsView: some View {
        HStack(spacing: 16) {
            StatMiniCard(
                icon: "figure.walk",
                title: "Шаги",
                value: "\(Int(model.stepsToday))",
                color: .blue
            )
            
            StatMiniCard(
                icon: "timer",
                title: "Потрачено",
                value: "\(model.spentMinutes)м",
                color: .orange
            )
        }
    }
    
    private var bigTimeDisplayView: some View {
        VStack(spacing: 12) {
            if model.isBlocked {
                VStack(spacing: 8) {
                    Text("⏰")
                        .font(.system(size: 60))
                    
                    Text("Время прошло!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Осталось")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("\(model.budget.remainingMinutes)")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(model.budget.remainingMinutes > 10 ? .green : .orange)
                    
                    Text("минут")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(radius: 5)
        )
    }
    
    private var controlButtonsView: some View {
        VStack(spacing: 12) {
            Button("🔙 Закрыть и вернуться") {
                returnToBlockedApp()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button("📱 Остаться в приложении") {
                stayInApp()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    private func returnToBlockedApp() {
        // Устанавливаем anti-loop флаг на 30 секунд
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(Date(), forKey: "returnModeActivatedTime")
        
        // Закрываем Quick Status
        model.showQuickStatusPage = false
        
        // Пользователь должен вручную переключиться на предыдущее приложение
        print("🔄 User should manually switch to the previous app")
    }
    
    private func stayInApp() {
        // Устанавливаем anti-loop флаг
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(Date(), forKey: "returnModeActivatedTime")
        
        // Закрываем Quick Status и остаемся в основном приложении
        model.showQuickStatusPage = false
    }
}
