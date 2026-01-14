import SwiftUI
import Combine
import UIKit
import CoreLocation

@main
struct StepsTraderApp: App {
    @StateObject private var model: AppModel
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var locationPermissionRequester = LocationPermissionRequester()
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("hasSeenIntro_v3") private var hasSeenIntro: Bool = false
    @State private var showIntro: Bool = false

    init() {
        _model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())
    }

    var body: some Scene {
        WindowGroup { 
            ZStack {
                if model.showPayGate {
                    PayGateView(model: model)
                        .onAppear {
                            print("🎯 PayGateView appeared - target: \(model.payGateTargetBundleId ?? "nil")")
                        }
                } else if model.showQuickStatusPage {
                    QuickStatusView(model: model)
                } else {
                    MainTabView(model: model, theme: currentTheme)
                }

                // Shortcut message overlay
                if model.showShortcutMessage, let message = model.shortcutMessage {
                    ShortcutMessageView(message: message) {
                        model.showShortcutMessage = false
                        model.shortcutMessage = nil
                    }
                }

                // Handoff protection screen (disabled for Instagram flow)
                if model.showHandoffProtection, let token = model.handoffToken {
                    // Only show handoff protection for non-Instagram targets
                    if token.targetBundleId != "com.burbn.instagram" {
                        HandoffProtectionView(model: model, token: token) {
                            model.handleHandoffContinue()
                        } onCancel: {
                            model.handleHandoffCancel()
                        }
                    }
                }

                if showIntro {
                    OnboardingStoriesView(
                        isPresented: $showIntro,
                        slides: introSlides(appLanguage: appLanguage),
                        accent: Color(red: 224/255, green: 130/255, blue: 217/255),
                        skipText: loc(appLanguage, "Skip", "Пропустить"),
                        nextText: loc(appLanguage, "Next", "Дальше"),
                        startText: loc(appLanguage, "Start", "Начать"),
                        allowText: loc(appLanguage, "Allow", "Разрешить"),
                        onLocationSlide: {
                            Task { @MainActor in
                                locationPermissionRequester.requestWhenInUse()
                            }
                        },
                        onHealthSlide: {
                            Task { await model.ensureHealthAuthorizationAndRefresh() }
                        },
                        onNotificationSlide: {
                            Task { await model.requestNotificationPermission() }
                        }
                    ) {
                        hasSeenIntro = true
                        Task { await model.refreshStepsIfAuthorized() }
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .onAppear {
                // Ensure bootstrap runs once; defer permission prompts to intro if needed
                if hasSeenIntro {
                    Task { await model.bootstrap(requestPermissions: true) }
                } else {
                    Task { await model.bootstrap(requestPermissions: false) }
                }
                print(
                    "🎭 StepsTraderApp appeared - showPayGate: \(model.showPayGate), showQuickStatusPage: \(model.showQuickStatusPage)"
                )
                print(
                    "🎭 App state - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                print(
                    "🎭 PayGate state - showPayGate: \(model.showPayGate), targetBundleId: \(model.payGateTargetBundleId ?? "nil")"
                )
                if let bundleId = model.payGateTargetBundleId, model.isAccessBlocked(for: bundleId) {
                    print("🚫 PayGate dismissed on appear: access window active for \(bundleId)")
                    model.dismissPayGate()
                    clearPayGateFlags(UserDefaults.stepsTrader())
                }
                checkForHandoffToken()
                checkForPayGateFlags()
                if !hasSeenIntro { showIntro = true }
            }
            .onOpenURL { url in
                print("🔗 App received URL: \(url)")
                print("🔗 URL scheme: \(url.scheme ?? "nil")")
                print("🔗 URL host: \(url.host ?? "nil")")
                print("🔗 URL path: \(url.path)")
                model.handleIncomingURL(url)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didEnterBackgroundNotification)
            ) { _ in
                model.handleAppDidEnterBackground()
            }
            .task {
                if hasSeenIntro {
                    await model.ensureHealthAuthorizationAndRefresh()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willEnterForegroundNotification)
            ) { _ in
                model.handleAppWillEnterForeground()
                checkForHandoffToken()
                checkForPayGateFlags()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.refresh")))
            { _ in
                model.handleAppWillEnterForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.showIntro")) ) { _ in
                showIntro = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.paygate")))
            { notification in
                print("📱 App received PayGate notification")
                if let userInfo = notification.userInfo,
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    if model.showPayGate {
                        print("ℹ️ PayGate already visible, ignoring notification")
                        return
                    }
                    if model.isAccessBlocked(for: bundleId) {
                        print("🚫 PayGate notification ignored: access window active for \(bundleId)")
                        model.dismissPayGate()
                        clearPayGateFlags(UserDefaults.stepsTrader())
                        reopenTargetIfPossible(bundleId: bundleId)
                        return
                    }
                    print("📱 PayGate notification - target: \(target), bundleId: \(bundleId)")
                    Task { @MainActor in
                        model.startPayGateSession(for: bundleId)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.local.paygate")))
            { notification in
                print("📱 App received local notification")
                if let userInfo = notification.userInfo,
                   let action = userInfo["action"] as? String,
                   action == "paygate",
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    let g = UserDefaults.stepsTrader()
                    let lastOpen = g.object(forKey: "lastAppOpenedFromStepsTrader_\(bundleId)") as? Date
                    if model.showPayGate {
                        print("ℹ️ PayGate already visible, ignoring local notification")
                        return
                    }
                    if model.isAccessBlocked(for: bundleId) {
                        print("🚫 PayGate local ignored: access window active for \(bundleId)")
                        model.dismissPayGate()
                        clearPayGateFlags(UserDefaults.stepsTrader())
                        reopenTargetIfPossible(bundleId: bundleId)
                        return
                    }
                    if let lastOpen {
                        let elapsed = Date().timeIntervalSince(lastOpen)
                        if elapsed < 10 {
                            let msg = String(format: "🚫 PayGate local ignored for %@ to avoid loop (%.1fs since last open)", bundleId, elapsed)
                            print(msg)
                            return
                        }
                    }
                    print("📱 Local notification PayGate - target: \(target), bundleId: \(bundleId)")
                    Task { @MainActor in
                        model.startPayGateSession(for: bundleId)
                        print("📱 PayGate state after setting - showPayGate: \(model.showPayGate), targetBundleId: \(model.payGateTargetBundleId ?? "nil")")
                    }
                }
            }
            .tint(currentTheme.accentColor)
            .background(currentTheme.backgroundColor)
            .preferredColorScheme(currentTheme.colorScheme)
        }
    }

    private func checkForHandoffToken() {
        let userDefaults = UserDefaults.stepsTrader()

        print("🔍 Checking for handoff token...")
        print(
            "🔍 Current app state - showPayGate: \(model.showPayGate), showHandoffProtection: \(model.showHandoffProtection)"
        )

        // Проверяем handoff-токен
        if let tokenData = userDefaults.data(forKey: "handoffToken") {
            print("🎫 Found handoff token data, decoding...")
            do {
                let token = try JSONDecoder().decode(HandoffToken.self, from: tokenData)
                print("✅ Token decoded: \(token.targetAppName) (ID: \(token.tokenId))")

                // Проверяем, не истек ли токен
                if token.isExpired {
                    print("⏰ Handoff token expired, removing")
                    userDefaults.removeObject(forKey: "handoffToken")
                    return
                }

                // Показываем защитный экран
                print("🛡️ Setting handoff protection for \(token.targetAppName)")
                print(
                    "🛡️ Before setting - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                model.handoffToken = token
                model.showHandoffProtection = true
                print(
                    "🛡️ After setting - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                print("🛡️ Handoff protection screen should now be visible!")

            } catch {
                print("❌ Failed to decode handoff token: \(error)")
                userDefaults.removeObject(forKey: "handoffToken")
            }
        } else {
            print("ℹ️ No handoff token found")
        }

        // Проверяем, есть ли сообщение от шортката (для ошибок)
        if let message = userDefaults.string(forKey: "shortcutMessage") {
            model.shortcutMessage = message
            model.showShortcutMessage = true
            userDefaults.removeObject(forKey: "shortcutMessage")
        }
    }
    
    private func checkForPayGateFlags() {
        let userDefaults = UserDefaults.stepsTrader()

        if let until = userDefaults.object(forKey: "suppressShortcutUntil") as? Date,
           Date() < until {
            print("🚫 PayGate suppressed (minute mode), skipping PayGate")
            clearPayGateFlags(userDefaults)
            return
        }
        
        // Check if shortcut set flags to show PayGate
        let shouldShowPayGate = userDefaults.bool(forKey: "shouldShowPayGate")
        let shortcutTriggered = userDefaults.bool(forKey: "shortcutTriggered")
        let triggerTime = userDefaults.object(forKey: "shortcutTriggerTime") as? Date
        let isRecentTrigger: Bool = {
            guard let triggerTime else { return false }
            // Даем больше времени на доставку уведомления/запуск приложения из шортката
            return Date().timeIntervalSince(triggerTime) < 120
        }()
        
        print("🔍 Checking PayGate flags - shouldShowPayGate: \(shouldShowPayGate), shortcutTriggered: \(shortcutTriggered), isRecentTrigger: \(isRecentTrigger)")
        
        if (shouldShowPayGate || shortcutTriggered) && isRecentTrigger {
            let targetBundleId = userDefaults.string(forKey: "payGateTargetBundleId")
            let shortcutTarget = userDefaults.string(forKey: "shortcutTarget")
            let target = targetBundleId ?? shortcutTarget ?? "unknown"
            
            print("🎯 Shortcut triggered PayGate for: \(target)")
            print("🎯 shouldShowPayGate: \(shouldShowPayGate), shortcutTriggered: \(shortcutTriggered)")
            
            // Map shortcut target to bundle ID if needed
            let finalBundleId = targetBundleId ?? TargetResolver.bundleId(from: shortcutTarget)
            
            print("🎯 Final bundle ID: \(finalBundleId ?? "nil")")
            if let bundleId = finalBundleId {
                if isRecentPayGateOpen(bundleId: bundleId, userDefaults: userDefaults) {
                    print("🚫 PayGate flags ignored: recent PayGate open for \(bundleId)")
                    clearPayGateFlags(userDefaults)
                    return
                }
                Task { @MainActor in
                    if model.isAccessBlocked(for: bundleId) {
                        print("🚫 PayGate flags ignored: access window active for \(bundleId)")
                        reopenTargetIfPossible(bundleId: bundleId)
                        clearPayGateFlags(userDefaults)
                        return
                    }
                    model.startPayGateSession(for: bundleId)
                }
            }
            
            // Clear the flags
            clearPayGateFlags(userDefaults)
            
            print("🎯 PayGate should now be visible!")
        } else {
            print("🔍 No PayGate flags found")
            // Cleanup stale flags so PayGate won't show on normal app launch
            clearPayGateFlags(userDefaults)
        }
    }
    
    private func clearPayGateFlags(_ userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: "shouldShowPayGate")
        userDefaults.removeObject(forKey: "payGateTargetBundleId")
        userDefaults.removeObject(forKey: "shortcutTriggered")
        userDefaults.removeObject(forKey: "shortcutTarget")
        userDefaults.removeObject(forKey: "shortcutTriggerTime")
    }

    private func isRecentPayGateOpen(bundleId: String, userDefaults: UserDefaults) -> Bool {
        if let last = userDefaults.object(forKey: "lastPayGateAction") as? Date,
           Date().timeIntervalSince(last) < 5 {
            return true
        }
        if let last = userDefaults.object(forKey: "lastAppOpenedFromStepsTrader_\(bundleId)") as? Date,
           Date().timeIntervalSince(last) < 5 {
            return true
        }
        return false
    }
    
    private func reopenTargetIfPossible(bundleId: String) {
        guard let scheme = TargetResolver.urlScheme(forBundleId: bundleId),
              let url = URL(string: scheme)
        else { return }
        Task { @MainActor in
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    model.recordAutomationOpen(bundleId: bundleId)
                }
            }
        }
    }

}

private extension StepsTraderApp {
    var currentTheme: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .system
    }

    func introSlides(appLanguage: String) -> [OnboardingSlide] {
        [
            OnboardingSlide(
                title: loc(appLanguage, "Welcome to DOOM CTRL", "Добро пожаловать в DOOM CTRL"),
                subtitle: loc(appLanguage, "Turn mindless app opens into a conscious choice.", "Преврати автопереходы в осознанный выбор."),
                symbol: "shield.fill",
                gradient: [.purple, .pink],
                bullets: [
                    loc(appLanguage, "Create Shields for distracting apps", "Создавай щиты для отвлекающих приложений"),
                    loc(appLanguage, "Unlocking costs Energy", "Открытие стоит энергии")
                ],
                action: .none
            ),
            OnboardingSlide(
                title: loc(appLanguage, "Energy = Steps + Outer World", "Энергия = Шаги + Внешний мир"),
                subtitle: loc(appLanguage, "Daily steps refill your Energy. Drops add extra fuel.", "Шаги каждый день пополняют энергию. Капли добавляют топливо."),
                symbol: "bolt.fill",
                gradient: [.yellow, .orange],
                bullets: [
                    loc(appLanguage, "Steps come from Health", "Шаги берём из Health"),
                    loc(appLanguage, "Outer World drops give +500 Energy", "Капли во Внешнем мире дают +500 энергии")
                ],
                action: .none
            ),
            OnboardingSlide(
                title: loc(appLanguage, "Shields level up", "Щиты прокачиваются"),
                subtitle: loc(appLanguage, "Invest Energy into a Shield to lower future prices.", "Инвестируй энергию в щит — будущие цены станут ниже."),
                symbol: "star.fill",
                gradient: [.blue, .purple],
                bullets: [
                    loc(appLanguage, "Each level has progress", "У каждого уровня есть прогресс"),
                    loc(appLanguage, "More invested = cheaper access", "Больше инвестиций = дешевле доступ")
                ],
                action: .none
            ),
            OnboardingSlide(
                title: loc(appLanguage, "Two access modes", "Два режима доступа"),
                subtitle: loc(appLanguage, "Pick what fits your behavior.", "Выбирай то, что подходит тебе."),
                symbol: "timer",
                gradient: [.cyan, .blue],
                bullets: [
                    loc(appLanguage, "Open mode: pay once for a time window", "Open mode: платишь один раз за окно времени"),
                    loc(appLanguage, "Minute mode: pay per minute of real use (needs Screen Time)", "Minute mode: платишь за минуту реального использования (нужен Screen Time)")
                ],
                action: .none
            ),
            OnboardingSlide(
                title: loc(appLanguage, "Outer World drops", "Капли во Внешнем мире"),
                subtitle: loc(appLanguage, "Walk to collect extra Energy on the map.", "Гуляй и собирай дополнительную энергию на карте."),
                symbol: "map.fill",
                gradient: [.blue, .purple],
                bullets: [
                    loc(appLanguage, "One drop at a time within 500m of you", "Одна капля за раз в радиусе 500м от тебя"),
                    loc(appLanguage, "Each drop gives +500 Energy (daily cap applies)", "Каждая капля даёт +500 энергии (действует дневной лимит)"),
                    loc(appLanguage, "Magnet: 3 uses/day to pull the drop", "Магнит: 3 раза в день притягивает каплю")
                ],
                action: .requestLocation
            ),
            OnboardingSlide(
                title: loc(appLanguage, "Connect your Steps", "Подключи шаги"),
                subtitle: loc(appLanguage, "We need access to count Steps and refill your Energy.", "Нужен доступ, чтобы считать шаги и пополнять энергию."),
                symbol: "figure.walk",
                gradient: [.pink, .purple],
                bullets: [
                    loc(appLanguage, "Used only to calculate Energy", "Используется только для расчёта энергии"),
                    loc(appLanguage, "You control everything in Settings", "Всё контролируется в Настройках")
                ],
                action: .requestHealth
            ),
            OnboardingSlide(
                title: loc(appLanguage, "Enable notifications", "Включи уведомления"),
                subtitle: loc(appLanguage, "We’ll remind you when access is about to end.", "Напомним, когда доступ скоро закончится."),
                symbol: "bell.badge.fill",
                gradient: [.orange, .pink],
                bullets: [
                    loc(appLanguage, "Timers and access reminders", "Таймеры и напоминания доступа"),
                    loc(appLanguage, "No spam — only useful signals", "Без спама — только полезные сигналы")
                ],
                action: .requestNotifications
            )
        ]
    }
}

// MARK: - Handoff Protection View
struct HandoffProtectionView: View {
    @ObservedObject var model: AppModel
    let token: HandoffToken
    let onContinue: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Text("🛡️")
                        .font(.system(size: 60))

                    Text("Protection Screen")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("You're about to open \(token.targetAppName)")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 20) {
                    let totalSteps = Int(model.effectiveStepsToday)
                    let spent = model.spentStepsToday
                    let cost = model.entryCostSteps
                    let available = max(0, totalSteps - spent)
                    let opensLeftText: String = {
                        if cost == 0 { return "Unlimited" }
                        return "\(available / max(cost, 1))"
                    }()

                    Text("Entries left today: \(opensLeftText)")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    HStack(spacing: 20) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button("Open \(token.targetAppName)") {
                            print("🛡️ User clicked Continue button for \(token.targetAppName)")
                            onContinue()
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
            .padding(.horizontal, 40)
        }
        .onAppear {
            print("🛡️ HandoffProtectionView appeared for \(token.targetAppName)")
            print("🛡️ Token ID: \(token.tokenId), Created: \(token.createdAt)")
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @ObservedObject var model: AppModel
    @State private var selection: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    var theme: AppTheme = .system

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StepBalanceCard(
                    remainingSteps: model.totalStepsBalance,
                    totalSteps: Int(model.effectiveStepsToday),
                    spentSteps: model.spentStepsToday,
                    // Show remaining energy split by source in the bar
                    healthKitSteps: model.stepsBalance,
                    outerWorldSteps: model.outerWorldBonusSteps,
                    showDetails: selection == 0
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                TabView(selection: $selection) {
                    StatusView(model: model)
                        .tabItem {
                            Image(systemName: "chart.bar.fill")
                            Text(loc(appLanguage, "Status", "Статус"))
                        }
                        .tag(0)

                    AppsPage(model: model, automationApps: SettingsView.automationAppsStatic)
                        .tabItem {
                            Image(systemName: "square.grid.2x2")
                            Text(loc(appLanguage, "Shields", "Щиты"))
                        }
                        .tag(1)
                    
                    OuterWorldView(model: model)
                        .tabItem {
                            Image(systemName: "map.fill")
                            Text(loc(appLanguage, "Outer World", "Внешний мир"))
                        }
                        .tag(2)
                    
                    ManualsPage(model: model)
                        .tabItem {
                            Image(systemName: "questionmark.circle")
                            Text(loc(appLanguage, "Manuals", "Мануалы"))
                        }
                        .tag(3)
                    
                    SettingsView(model: model)
                        .tabItem {
                            Image(systemName: "gear")
                            Text(loc(appLanguage, "Settings", "Настройки"))
                        }
                        .tag(4)
                }
                .animation(.easeInOut(duration: 0.2), value: selection)
            }
            .background(Color(.systemBackground))
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.open.modules"))) { _ in
            selection = 1
        }
    }
    
    private var remainingStepsToday: Int {
        max(0, Int(model.effectiveStepsToday) - model.spentStepsToday)
    }
    
}

// MARK: - Quick Status View
struct QuickStatusView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.green.opacity(0.1), .blue.opacity(0.2)], startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                VStack(spacing: 16) {
                    Text("📊")
                        .font(.system(size: 60))

                    Text("Quick Status")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Your progress overview")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 20) {
                    // Шаги сегодня
                    HStack {
                        Text("Steps today:")
                            .font(.title2)
                        Spacer()
                        Text("\(Int(model.effectiveStepsToday))")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    // Бюджет времени
                    HStack {
                        Text("Time budget:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.remainingMinutes) min")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(model.remainingMinutes > 0 ? .blue : .red)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    // Потрачено времени
                    HStack {
                        Text("Spent time:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.spentMinutes) min")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    // Баланс шагов для входа
                    HStack {
                        Text("Entry balance:")
                            .font(.title2)
                        Spacer()
                        Text("\(model.totalStepsBalance) steps")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(
                                model.totalStepsBalance >= model.entryCostSteps ? .green : .red)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }
                .padding(.horizontal, 20)

                Button("Close") {
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
                Text("📱 Shortcut")
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

// MARK: - PayGateView
struct PayGateView: View {
    @ObservedObject var model: AppModel
    @State private var countdown: Int = 10
    @State private var didForfeitSessions: Set<String> = []
    @State private var timedOutSessions: Set<String> = []
    @State private var lastSessionId: String? = nil
    @State private var showTransitionCircle: Bool = false
    @State private var transitionScale: CGFloat = 0.01
    @State private var selectedWindow: AccessWindow = .single
    private let totalCountdown: Int = 10
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var activeSession: AppModel.PayGateSession? {
        if let id = model.currentPayGateSessionId, let session = model.payGateSessions[id] {
            return session
        }
        if let id = model.payGateTargetBundleId, let session = model.payGateSessions[id] {
            return session
        }
        return nil
    }
    
    private var activeBundleId: String? { activeSession?.bundleId }
    private var activeLevel: ShieldLevel {
        guard let bundleId = activeBundleId else { return ShieldLevel.all.first! }
        return model.currentShieldLevel(for: bundleId)
    }
    private var isMinuteModeActive: Bool {
        guard let bundleId = activeBundleId else { return false }
        return model.isMinuteTariffEnabled(for: bundleId) || model.isFamilyControlsModeEnabled(for: bundleId)
    }
    private var isCountdownActive: Bool {
        guard let session = activeSession, let bundleId = activeBundleId else { return false }
        return !timedOutSessions.contains(bundleId) && remainingSeconds(for: session) > 0
    }
    
    private func remainingSeconds(for session: AppModel.PayGateSession) -> Int {
        let elapsed = Date().timeIntervalSince(session.startedAt)
        return max(0, totalCountdown - Int(elapsed))
    }

    
    private var countdownBadge: some View {
        let progress = CGFloat(max(0, countdown)) / CGFloat(totalCountdown)
        let countdownColor: Color = countdown > 5 ? .green : (countdown > 2 ? .orange : .red)
        
        return VStack(spacing: 8) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(countdownColor.opacity(0.15))
                    .frame(width: 110, height: 110)
                    .blur(radius: 10)
                
                // Background ring
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 88, height: 88)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [countdownColor, countdownColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88)
                    .animation(.easeInOut(duration: 0.3), value: countdown)
                
                // Inner circle with number
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 70, height: 70)
                
                Text("\(max(0, countdown))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .animation(.spring(response: 0.3), value: countdown)
            }
            
            Text(loc("seconds left", "секунд осталось"))
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial.opacity(0.5))
        )
    }
    
    var body: some View {
        ZStack {
            payGateBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top section with balance
                stepsProgressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                
                Spacer()
            
                // Center content - app icon and countdown
                if let bundleId = activeBundleId {
                    VStack(spacing: 24) {
                        // App icon with glow
            ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 120, height: 120)
                                .blur(radius: 20)
                            
                            appIconView(bundleId)
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        }
                        
                        // App name
                        Text(getAppDisplayName(bundleId))
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                        
                        // Countdown (if active)
                        if isCountdownActive {
                            countdownBadge
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.4), value: isCountdownActive)
                }
                
                Spacer()
                
                // Bottom action panel
                bottomActionPanel
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .overlay(transitionOverlay)
        .onAppear {
            refreshCountdown()
            didForfeitSessions.removeAll()
            timedOutSessions.removeAll()
            showTransitionCircle = false
            transitionScale = 0.01
        }
        .onReceive(countdownTimer) { _ in
            handleCountdownTick()
        }
        .onChange(of: model.currentPayGateSessionId) { _, _ in
            refreshCountdown()
        }
        .onDisappear {
            if let id = activeBundleId {
                didForfeitSessions.insert(id)
            }
            model.dismissPayGate()
        }
    }
    
    @ViewBuilder
    private var bottomActionPanel: some View {
        VStack(spacing: 12) {
                    if let bundleId = activeBundleId, let session = activeSession {
                        let isTimedOut = timedOutSessions.contains(bundleId) || remainingSeconds(for: session) <= 0
                        
                        if !isTimedOut {
                            if isMinuteModeActive {
                        minuteModePanel(bundleId: bundleId)
                    } else {
                        openModePanel(bundleId: bundleId, isTimedOut: isTimedOut)
                    }
                } else {
                    timedOutPanel(bundleId: bundleId)
                }
            } else {
                // No active session - missed state
                missedSessionPanel
            }
            
            // Close button (always visible at bottom)
            if let bundleId = activeBundleId {
                closeButton(bundleId: bundleId)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: -10)
        )
    }
    
    @ViewBuilder
    private func minuteModePanel(bundleId: String) -> some View {
                                let minutesLeft = model.minutesAvailable(for: bundleId)
                                let minutesText = minutesLeft == Int.max ? "∞" : "\(minutesLeft)"
                                let rate = model.unlockSettings(for: bundleId).entryCostSteps
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        let canStart = model.isDeviceActivityMinuteModeAvailable(for: bundleId)
        
        VStack(spacing: 16) {
            // Header with icon
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundColor(pink)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("Minute Mode", "Минутный режим"))
                                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(loc("\(rate) fuel per minute", "\(rate) топлива за минуту"))
                        .font(.caption)
                                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Minutes badge
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.caption)
                    Text(minutesText)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    Text("min")
                        .font(.caption)
                }
                .foregroundColor(minutesLeft > 10 ? .green : (minutesLeft > 3 ? .orange : .red))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(.systemBackground).opacity(0.8))
                )
            }
            
            // Enter button
            Button {
                                        Task { await model.handleMinuteTariffEntry(for: bundleId) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(loc("Start Session", "Начать сессию"))
                                    }
                                        .font(.headline)
                                    .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    LinearGradient(
                        colors: (minutesLeft > 0 && canStart) ? [pink, pink.opacity(0.8)] : [.gray, .gray.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: pink.opacity(0.4), radius: 10, x: 0, y: 5)
            }
            .contentShape(Rectangle())
            .disabled(minutesLeft <= 0 || !canStart)
            
            if !canStart {
                Text(loc("Connect Screen Time for Minute Mode", "Подключи Screen Time для минутного режима"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func openModePanel(bundleId: String, isTimedOut: Bool) -> some View {
                                    let allowed = model.allowedAccessWindows(for: bundleId)
                                    let windows = [AccessWindow.day1, .hour1, .minutes5, .single].filter { allowed.contains($0) }
        
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text(loc("Choose Access", "Выберите доступ"))
                    .font(.headline)
                Spacer()
                
                // Level badge
                Text("Lv.\(activeLevel.label)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
            }
            
            // Access options grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                        ForEach(windows, id: \.self) { window in
                    accessWindowCard(window: window, bundleId: bundleId, isTimedOut: isTimedOut, isForfeited: isForfeited(bundleId))
                }
            }
        }
    }
    
    @ViewBuilder
    private func accessWindowCard(window: AccessWindow, bundleId: String, isTimedOut: Bool, isForfeited: Bool) -> some View {
        let baseCost = windowCost(for: activeLevel, window: window)
        let hasPass = model.hasDayPass(for: bundleId)
        let effectiveCost = hasPass ? 0 : baseCost
        let canPay = effectiveCost == 0 || model.totalStepsBalance >= effectiveCost
        let isDisabled = !canPay || isTimedOut || isForfeited
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        
        Button {
            guard !isDisabled else { return }
            setForfeit(bundleId)
            Task {
                performTransition {
                    Task { await model.handlePayGatePayment(for: bundleId, window: window, costOverride: effectiveCost) }
                }
            }
        } label: {
            VStack(spacing: 8) {
                // Duration icon
                Image(systemName: windowIcon(window))
                    .font(.title2)
                    .foregroundColor(isDisabled ? .gray : pink)
                
                // Duration text
                Text(accessWindowShortName(window))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isDisabled ? .secondary : .primary)
                
                // Cost
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text("\(effectiveCost)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
                .foregroundColor(isDisabled ? .gray : (canPay ? .orange : .red))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDisabled ? Color.gray.opacity(0.1) : Color(.systemBackground))
                    .shadow(color: isDisabled ? .clear : .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDisabled ? Color.gray.opacity(0.2) : pink.opacity(0.3), lineWidth: 1)
            )
        }
        .contentShape(Rectangle())
        .disabled(isDisabled)
    }
    
    private func windowIcon(_ window: AccessWindow) -> String {
        switch window {
        case .single: return "arrow.right.circle"
        case .minutes5: return "5.circle"
        case .hour1: return "clock"
        case .day1: return "sun.max.fill"
        }
    }
    
    private func accessWindowShortName(_ window: AccessWindow) -> String {
        switch window {
        case .single: return loc("Entry", "Вход")
        case .minutes5: return loc("5 min", "5 мин")
        case .hour1: return loc("1 hour", "1 час")
        case .day1: return loc("Day", "День")
        }
    }
    
    @ViewBuilder
    private func timedOutPanel(bundleId: String) -> some View {
                            VStack(spacing: 12) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text(loc("Time's up!", "Время вышло!"))
                .font(.title3.weight(.bold))
                .foregroundColor(.primary)
            
            Text(loc("You saved \(windowCost(for: activeLevel, window: .single)) fuel", "Вы сохранили \(windowCost(for: activeLevel, window: .single)) топлива"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
                        }
    
    @ViewBuilder
    private var missedSessionPanel: some View {
                        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
                            if let bundleId = model.payGateTargetBundleId {
                Text(loc("Stopped yourself!", "Остановились!"))
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                
                Text(loc("You didn't open \(getAppDisplayName(bundleId))", "Вы не открыли \(getAppDisplayName(bundleId))"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                Text(loc("Session ended", "Сессия завершена"))
                    .font(.title3.weight(.bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
                    }
                
    @ViewBuilder
    private func closeButton(bundleId: String) -> some View {
        Button {
                        setForfeit(bundleId)
            performTransition(duration: 0.6) {
                            model.dismissPayGate()
                            sendAppToBackground()
                        }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                Text(loc("Close", "Закрыть"))
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .contentShape(Rectangle())
    }
}

extension PayGateView {
    private func refreshCountdown() {
        guard let session = activeSession else {
            countdown = 0
            return
        }
        if lastSessionId != session.bundleId {
            lastSessionId = session.bundleId
            countdown = remainingSeconds(for: session)
            // reset forfeit/timedOut for new session
            didForfeitSessions.remove(session.bundleId)
            timedOutSessions.remove(session.bundleId)
        } else {
            countdown = remainingSeconds(for: session)
        }
    }
    
    private func isForfeited(_ bundleId: String) -> Bool {
        didForfeitSessions.contains(bundleId) || timedOutSessions.contains(bundleId)
    }
    
    private func setForfeit(_ bundleId: String) {
        didForfeitSessions.insert(bundleId)
    }
}

// MARK: - PayGate transition helper
extension PayGateView {
    private func handleCountdownTick() {
        refreshCountdown()
        if let session = activeSession {
            let remaining = remainingSeconds(for: session)
            if remaining <= 0 {
                timedOutSessions.insert(session.bundleId)
            }
        }
    }
}

// MARK: - Helper Functions
private func getAppDisplayName(_ bundleId: String) -> String {
    if let name = SettingsView.automationAppsStatic.first(where: { $0.bundleId == bundleId })?.name {
        return name
    }
    return bundleId
}

// MARK: - PayGate transition helper
extension PayGateView {
    private func performTransition(duration: Double = 1.0, action: @escaping () -> Void) {
        guard !showTransitionCircle else {
            action()
            return
        }
        showTransitionCircle = true
        transitionScale = 0.01
        withAnimation(.easeInOut(duration: duration)) {
            transitionScale = 12
        }
        let delay = duration * 0.9
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }
    
    @ViewBuilder
    fileprivate var transitionOverlay: some View {
        if showTransitionCircle {
            GeometryReader { proxy in
                Circle()
                    .fill(Color.black)
                    .frame(width: 120, height: 120)
                    .scaleEffect(transitionScale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .ignoresSafeArea()
            }
        }
    }
    
    private func payGateBackground() -> some View {
        ZStack {
            // Base image
            Image("paygate")
                .resizable()
                .scaledToFill()
            
            // Gradient overlays for depth
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.8), location: 0),
                    .init(color: Color.black.opacity(0.4), location: 0.4),
                    .init(color: Color.black.opacity(0.6), location: 0.7),
                    .init(color: Color.black.opacity(0.9), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Subtle purple tint at the bottom for action area
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.purple.opacity(0.15)
                ]),
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
    
    private var stepsProgressBar: some View {
        let total = max(1, Int(model.effectiveStepsToday))
        let remaining = max(0, model.totalStepsBalance)
        let used = max(0, total - min(total, remaining))
        let denominator = Double(total)
        let displayRemaining = min(remaining, total)
        let remainingProgress = min(1, Double(displayRemaining) / denominator)
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        let progressColor = remaining > 500 ? pink : (remaining > 100 ? .orange : .red)

        return VStack(spacing: 12) {
            // Balance display
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundColor(progressColor)
                
                Text("\(remaining)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                
                Text(loc("fuel left", "топлива"))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                // Today's total
                VStack(alignment: .trailing, spacing: 2) {
                    Text(loc("Today", "Сегодня"))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(total)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .monospacedDigit()
                }
            }
            
            // Progress bar
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 8)
                
                // Progress
                GeometryReader { proxy in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [progressColor, progressColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * CGFloat(remainingProgress)), height: 8)
                        .shadow(color: progressColor.opacity(0.5), radius: 4, x: 0, y: 0)
                }
                .frame(height: 8)
            }
            
            // Labels
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text("\(used) " + loc("spent", "потрачено"))
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 6, height: 6)
                    Text("\(remaining) " + loc("available", "доступно"))
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.6))
        )
    }
    
    private func accentColor(for tariff: Tariff) -> Color {
        switch tariff {
        case .free: return Color.blue
        case .easy: return Color.green
        case .medium: return Color.orange
        case .hard: return Color.red
        }
    }
    
    private func dailyBoostEndTime() -> String {
        var comps = DateComponents()
        comps.hour = model.dayEndHour
        comps.minute = model.dayEndMinute
        let cal = Calendar.current
        let now = Date()
        let target = cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: target)
    }
    
    @ViewBuilder
    private func appIconView(_ bundleId: String) -> some View {
        if let imageName = SettingsView.automationAppsStatic.first(where: { $0.bundleId == bundleId })?.imageName,
           let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 4)
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.15))
                .overlay(Image(systemName: "app").foregroundColor(.secondary))
        }
    }
    
    @ViewBuilder
    private func tariffPicker(bundleId: String, selected: Tariff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("en", "Choose tariff for today", "Выберите тариф на сегодня"))
            .font(.caption)
            .foregroundColor(.red)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Tariff.allCases, id: \.self) { tariff in
                        Button {
                            Task { await handleTariffSelection(tariff, bundleId: bundleId) }
                        } label: {
                            Text(tariffDisplayName(tariff))
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(tariff == selected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(tariff == selected ? Color.blue : Color.clear, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }
    
    private func tariffDisplayName(_ tariff: Tariff) -> String {
        tariff.displayName
    }
    
    @MainActor
    private func handleTariffSelection(_ tariff: Tariff, bundleId: String) async {
        // Check balance for entry with this tariff
        model.updateUnlockSettings(for: bundleId, tariff: tariff)
        guard model.canPayForEntry(for: bundleId) else {
            model.message = loc("en", "Not enough steps for this tariff today.", "Недостаточно шагов для этого тарифа сегодня.")
            // Revert selection so picker stays visible
            model.dailyTariffSelections.removeValue(forKey: bundleId)
            return
        }
        model.selectTariffForToday(tariff, bundleId: bundleId)
        await model.handlePayGatePayment(for: bundleId, window: .single)
    }

    private func windowCost(for level: ShieldLevel, window: AccessWindow) -> Int {
        switch window {
        case .single: return level.entryCost
        case .minutes5: return level.fiveMinutesCost
        case .hour1: return level.hourCost
        case .day1: return level.dayCost
        }
    }

    private func sendAppToBackground() {
        // Move app to background (returns user to home screen)
        DispatchQueue.main.async {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
}

// MARK: - Onboarding Stories
enum OnboardingSlideAction: Equatable {
    case none
    case requestLocation
    case requestHealth
    case requestNotifications
}

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let gradient: [Color]
    let bullets: [String]
    let action: OnboardingSlideAction
}

struct OnboardingStoriesView: View {
    @Binding var isPresented: Bool
    let slides: [OnboardingSlide]
    let accent: Color
    let skipText: String
    let nextText: String
    let startText: String
    let allowText: String
    let onLocationSlide: (() -> Void)?
    let onHealthSlide: (() -> Void)?
    let onNotificationSlide: (() -> Void)?
    let onFinish: () -> Void
    @State private var index: Int = 0
    @State private var didTriggerLocationRequest = false
    @State private var didTriggerHealthRequest = false
    @State private var didTriggerNotificationRequest = false

    var body: some View {
        ZStack {
            onboardingBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                    .padding(.top, 18)

                progressBar
                    .padding(.top, 6)

                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        slideCard(slide: slide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 12)
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: index)

                HStack(spacing: 16) {
                    Button(action: finish) {
                        Text(skipText)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.90))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: next) {
                        Text(primaryButtonTitle)
                            .font(.headline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.bottom, 32)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 10)
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.35), Color.clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.22), Color.clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 520
            )
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? accent : Color.white.opacity(0.35))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: index)
            }
        }
        .padding(.horizontal, 24)
    }

    private var header: some View {
        HStack(spacing: 12) {
            appLogo

            VStack(alignment: .leading, spacing: 2) {
                Text("DOOM CTRL")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Fuel → Shields → Control")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .topTrailing) {
            Button(action: finish) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.trailing, 16)
        }
    }

    private var appLogo: some View {
        Group {
            if let uiImage = appIconImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Text("DC")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func slideCard(slide: OnboardingSlide) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.gradient.map { $0.opacity(0.90) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: slide.gradient.first?.opacity(0.35) ?? .clear, radius: 20, x: 0, y: 12)

                Image(systemName: slide.symbol)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)

            VStack(spacing: 10) {
                Text(slide.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                Text(slide.subtitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(slide.bullets, id: \.self) { text in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: slide.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.90))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var primaryButtonTitle: String {
        guard slides.indices.contains(index) else { return nextText }
        let lastIndex = slides.count - 1
        if index == lastIndex { return startText }
        if slides[index].action != .none { return allowText }
        return nextText
    }

    private func appIconImage() -> UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let last = files.last
        else { return nil }
        return UIImage(named: last)
    }

    private func next() {
        if slides.indices.contains(index) {
            let action = slides[index].action
            switch action {
            case .requestLocation:
                if !didTriggerLocationRequest {
                    didTriggerLocationRequest = true
                    onLocationSlide?()
                }
            case .requestHealth:
                if !didTriggerHealthRequest {
                didTriggerHealthRequest = true
                onHealthSlide?()
            }
            case .requestNotifications:
            if !didTriggerNotificationRequest {
                didTriggerNotificationRequest = true
                onNotificationSlide?()
            }
            case .none:
                break
            }
        }

        let lastIndex = slides.count - 1
        if index < lastIndex {
            withAnimation(.easeInOut) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        withAnimation(.easeInOut) {
            isPresented = false
        }
        onFinish()
    }
}

// MARK: - Location Permission (Onboarding)
final class LocationPermissionRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    @MainActor
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }
}
