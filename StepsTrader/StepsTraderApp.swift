import SwiftUI
import Combine
import UIKit
import CoreLocation
import UserNotifications

// Локальная копия минимальных настроек для декодинга appUnlockSettings_v1
private struct StoredUnlockSettingsForNotification: Codable {
    let entryCostSteps: Int?
    let minuteTariffEnabled: Bool?
    let familyControlsModeEnabled: Bool?
}

// Минимальная структура для декодинга групп щитов
private struct ShieldGroupDataForNotification: Codable {
    let id: String
    let name: String
    let selectionData: Data?
    
    enum CodingKeys: String, CodingKey {
        case id, name, selectionData
    }
}

@main
struct StepsTraderApp: App {
    @StateObject private var model: AppModel
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var locationPermissionRequester = LocationPermissionRequester()
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("hasSeenIntro_v3") private var hasSeenIntro: Bool = false
    @AppStorage("hasSeenEnergySetup_v1") private var hasSeenEnergySetup: Bool = false
    @State private var showIntro: Bool = false
    @State private var showEnergySetup: Bool = false

    init() {
        _model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())
    }

    var body: some Scene {
        WindowGroup { 
            ZStack {
                if model.showPayGate {
                    PayGateView(model: model)
                        .onAppear {
                            print("🎯 PayGateView appeared - target group: \(model.payGateTargetGroupId ?? "nil")")
                        }
                } else if model.showQuickStatusPage {
                    QuickStatusView(model: model)
                } else {
                    MainTabView(model: model, theme: currentTheme)
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
                        accent: AppColors.brandPink,
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
                        },
                        onFamilyControlsSlide: {
                            Task { try? await model.family.requestAuthorization() }
                        }
                    ) {
                        hasSeenIntro = true
                        Task {
                            await model.refreshStepsIfAuthorized()
                            await model.refreshSleepIfAuthorized()
                        }
                        if !hasSeenEnergySetup {
                            showEnergySetup = true
                        }
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .sheet(isPresented: $showEnergySetup, onDismiss: {
                hasSeenEnergySetup = true
            }) {
                NavigationView {
                    EnergySetupView(model: model)
                }
            }
            .onAppear {
                // Language selection was removed; keep the UI in English if an old value was persisted.
                if appLanguage == "ru" { appLanguage = "en" }

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
                
                // Setup notification handling
                setupNotificationHandling()
                print(
                    "🎭 PayGate state - showPayGate: \(model.showPayGate), targetGroupId: \(model.payGateTargetGroupId ?? "nil")"
                )
                checkForHandoffToken()
                checkForPayGateFlags()
                if !hasSeenIntro { showIntro = true }
                if hasSeenIntro && !hasSeenEnergySetup {
                    showEnergySetup = true
                }
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
                    let g = UserDefaults.stepsTrader()
                    if let until = g.object(forKey: "payGateDismissedUntil_v1") as? Date,
                       Date() < until
                    {
                        print("🚫 PayGate notification suppressed after dismiss")
                        return
                    }
                    if model.isAccessBlocked(for: bundleId) {
                        print("🚫 PayGate notification ignored: access window active for \(bundleId)")
                        model.dismissPayGate(reason: .programmatic)
                        clearPayGateFlags(UserDefaults.stepsTrader())
                        reopenTargetIfPossible(bundleId: bundleId)
                        return
                    }
                    print("📱 PayGate notification - target: \(target), bundleId: \(bundleId)")
                    Task { @MainActor in
                        model.openPayGateForBundleId(bundleId)
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
                    if let until = g.object(forKey: "payGateDismissedUntil_v1") as? Date,
                       Date() < until
                    {
                        print("🚫 PayGate local notification suppressed after dismiss")
                        return
                    }
                    let lastOpen = g.object(forKey: "lastAppOpenedFromStepsTrader_\(bundleId)") as? Date
                    if model.isAccessBlocked(for: bundleId) {
                        print("🚫 PayGate local ignored: access window active for \(bundleId)")
                        model.dismissPayGate(reason: .programmatic)
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
                        print("📱 PayGate state after setting - showPayGate: \(model.showPayGate), targetGroupId: \(model.payGateTargetGroupId ?? "nil")")
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

    }
    
    private func checkForPayGateFlags() {
        let userDefaults = UserDefaults.stepsTrader()


        if let until = userDefaults.object(forKey: "payGateDismissedUntil_v1") as? Date,
           Date() < until
        {
            print("🚫 PayGate suppressed after dismiss, skipping PayGate")
            clearPayGateFlags(userDefaults)
            return
        }
        
        // Check if flags set to show PayGate
        let shouldShowPayGate = userDefaults.bool(forKey: "shouldShowPayGate")
        
        if shouldShowPayGate {
            let targetGroupId = userDefaults.string(forKey: "payGateTargetGroupId")
            
            if let groupId = targetGroupId {
                if !model.showPayGate, isRecentPayGateOpen(groupId: groupId, userDefaults: userDefaults) {
                    print("🚫 PayGate flags ignored: recent PayGate open for group \(groupId)")
                    clearPayGateFlags(userDefaults)
                    return
                }
                Task { @MainActor in
                    model.openPayGate(for: groupId)
                }
            }
            
            clearPayGateFlags(userDefaults)
        } else {
            clearPayGateFlags(userDefaults)
        }
    }
    
    private func clearPayGateFlags(_ userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: "shouldShowPayGate")
        userDefaults.removeObject(forKey: "payGateTargetGroupId")
    }

    private func isRecentPayGateOpen(groupId: String, userDefaults: UserDefaults) -> Bool {
        if let last = userDefaults.object(forKey: "lastPayGateAction") as? Date,
           Date().timeIntervalSince(last) < 5 {
            return true
        }
        if let last = userDefaults.object(forKey: "lastGroupPayGateOpen_\(groupId)") as? Date,
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
            // 1. Welcome - bold intro
            OnboardingSlide(
                title: loc(appLanguage, "DOOM CTRL 🔥", "DOOM CTRL 🔥"),
                subtitle: loc(appLanguage, "Take back control from your apps", "Верни себе контроль над приложениями"),
                symbol: "shield.checkered",
                gradient: [.purple, .pink],
                bullets: [
                    loc(appLanguage, "🛡️ Shield apps that steal your time", "🛡️ Ставь щиты на пожирателей времени"),
                    loc(appLanguage, "⚡ Pay with Energy to get access", "⚡ Плати энергией за доступ")
                ],
                action: .none
            ),
            // 2. Energy source
            OnboardingSlide(
                title: loc(appLanguage, "Daily Energy ⚡", "Энергия дня ⚡"),
                subtitle: loc(appLanguage, "Recovery, activity, and joy build 100 points", "Восстановление, активность и радость дают 100 баллов"),
                symbol: "bolt.fill",
                gradient: [.yellow, .orange],
                bullets: [
                    loc(appLanguage, "😴 Sleep + habits = Recovery points", "😴 Сон + практики = очки восстановления"),
                    loc(appLanguage, "🚶 Steps + workouts = Activity points", "🚶 Шаги + тренировки = очки активности"),
                    loc(appLanguage, "🔋 Collect batteries on the map for bonus", "🔋 Собирай батарейки на карте для бонуса")
                ],
                action: .none
            ),
            // 3. Level up
            OnboardingSlide(
                title: loc(appLanguage, "Track Progress 📈", "Следи за прогрессом 📈"),
                subtitle: loc(appLanguage, "Spend energy, see your impact", "Трать энергию и смотри на результат"),
                symbol: "star.fill",
                gradient: [.blue, .purple],
                bullets: [
                    loc(appLanguage, "⭐ 10 levels per shield", "⭐ 10 уровней на каждый щит"),
                    loc(appLanguage, "📊 Track total energy spent", "📊 Смотри, сколько энергии потрачено")
                ],
                action: .none
            ),
            // 4. Screen Time - Family Controls
            OnboardingSlide(
                title: loc(appLanguage, "Screen Time 📱", "Screen Time 📱"),
                subtitle: loc(appLanguage, "Track real app usage for minute mode", "Отслеживай реальное время для минутного режима"),
                symbol: "hourglass",
                gradient: [.indigo, .purple],
                bullets: [
                    loc(appLanguage, "⏱️ Pay per actual minute used", "⏱️ Плати за реальные минуты"),
                    loc(appLanguage, "🔒 We only see usage, not content", "🔒 Видим только время, не контент")
                ],
                action: .requestFamilyControls
            ),
            // 5. Map - location permission
            OnboardingSlide(
                title: loc(appLanguage, "Hunt Batteries 🗺️", "Охота за батареями 🗺️"),
                subtitle: loc(appLanguage, "Walk around → collect bonus Energy", "Гуляй → собирай бонусную энергию"),
                symbol: "map.fill",
                gradient: [.green, .teal],
                bullets: [
                    loc(appLanguage, "🔋 +5 Energy per battery", "🔋 +5 энергии за батарейку"),
                    loc(appLanguage, "🧲 3 magnets/day to grab from afar", "🧲 3 магнита/день чтобы притянуть издалека")
                ],
                action: .requestLocation
            ),
            // 6. Health - steps permission
            OnboardingSlide(
                title: loc(appLanguage, "Connect Steps 🚶", "Подключи шаги 🚶"),
                subtitle: loc(appLanguage, "Your walks = your power", "Твои прогулки = твоя сила"),
                symbol: "figure.walk",
                gradient: [.pink, .purple],
                bullets: [
                    loc(appLanguage, "📊 We only read step count", "📊 Читаем только количество шагов"),
                    loc(appLanguage, "🔒 Your data stays on device", "🔒 Данные остаются на устройстве")
                ],
                action: .requestHealth
            ),
            // 7. Notifications
            OnboardingSlide(
                title: loc(appLanguage, "Stay Sharp 🔔", "Будь начеку 🔔"),
                subtitle: loc(appLanguage, "Know when access ends", "Узнавай когда доступ заканчивается"),
                symbol: "bell.badge.fill",
                gradient: [.orange, .pink],
                bullets: [
                    loc(appLanguage, "⏰ Timers & reminders", "⏰ Таймеры и напоминалки"),
                    loc(appLanguage, "🚫 Zero spam, only useful stuff", "🚫 Ноль спама, только по делу")
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
                        .accessibilityHidden(true)

                    Text("Protection Screen")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)

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
                        .accessibilityLabel("Cancel opening \(token.targetAppName)")

                        Button("Open \(token.targetAppName)") {
                            print("🛡️ User clicked Continue button for \(token.targetAppName)")
                            onContinue()
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Open \(token.targetAppName)")
                        .accessibilityHint("Opens the app \(token.targetAppName) after confirming access")
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
    @State private var selectedCategory: EnergyCategory? = nil
    @State private var showCategoryDetail = false
    @State private var showOuterWorldDetail = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                StepBalanceCard(
                    remainingSteps: model.totalStepsBalance,
                    totalSteps: model.baseEnergyToday + model.bonusSteps,
                    spentSteps: model.spentStepsToday,
                    healthKitSteps: model.stepsBalance,
                    outerWorldSteps: model.outerWorldBonusSteps,
                    grantedSteps: model.serverGrantedSteps,
                    dayEndHour: model.dayEndHour,
                    dayEndMinute: model.dayEndMinute,
                    showDetails: selection == 0, // Show category details only on Shields tab
                    recoveryPoints: model.recoveryPointsToday,
                    activityPoints: model.activityPointsToday,
                    joyPoints: model.joyCategoryPointsToday,
                    baseEnergyToday: model.baseEnergyToday,
                    onRecoveryTap: {
                        selectedCategory = .recovery
                        showCategoryDetail = true
                    },
                    onActivityTap: {
                        selectedCategory = .activity
                        showCategoryDetail = true
                    },
                    onJoyTap: {
                        selectedCategory = .joy
                        showCategoryDetail = true
                    },
                    onOuterWorldTap: {
                        showOuterWorldDetail = true
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

                TabView(selection: $selection) {
                    // 0: Shields (first tab)
                    AppsPageSimplified(model: model)
                        .tabItem {
                            Image(systemName: "square.grid.2x2")
                            Text(loc(appLanguage, "Shields", "Щиты"))
                        }
                        .sheet(isPresented: $showCategoryDetail) {
                            if let category = selectedCategory {
                                CategoryDetailView(
                                    model: model,
                                    category: category,
                                    outerWorldSteps: model.outerWorldBonusSteps
                                )
                            }
                        }
                        .sheet(isPresented: $showOuterWorldDetail) {
                            CategoryDetailView(
                                model: model,
                                category: nil,
                                outerWorldSteps: model.outerWorldBonusSteps
                            )
                        }
                        .tag(0)

                    // 1: Status (second tab)
                    StatusView(model: model)
                        .tabItem {
                            Image(systemName: "chart.bar.fill")
                            Text(loc(appLanguage, "Status", "Статус"))
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
            selection = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenShieldSettings"))) { notification in
            print("🔧 Received OpenShieldSettings notification")
            // Navigate to shields tab (now first tab)
            selection = 0
            if let bundleId = notification.userInfo?["bundleId"] as? String {
                print("🔧 Will open shield for bundleId: \(bundleId)")
                // Post delayed notification to open specific shield
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🔧 Posting OpenShieldForBundle notification")
                    NotificationCenter.default.post(
                        name: .init("OpenShieldForBundle"),
                        object: nil,
                        userInfo: ["bundleId": bundleId]
                    )
                }
            }
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
                .accessibilityLabel("Close quick status")
                .accessibilityHint("Closes the quick status view")
            }
        }
    }
}


// MARK: - PayGate Background Style
enum PayGateBackgroundStyle: String, CaseIterable, Identifiable {
    case midnight = "midnight"
    case aurora = "aurora"
    case sunset = "sunset"
    case ocean = "ocean"
    case neon = "neon"
    case minimal = "minimal"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .neon: return "Neon"
        case .minimal: return "Minimal"
        }
    }
    
    var displayNameRU: String {
        switch self {
        case .midnight: return "Полночь"
        case .aurora: return "Аврора"
        case .sunset: return "Закат"
        case .ocean: return "Океан"
        case .neon: return "Неон"
        case .minimal: return "Минимализм"
        }
    }
    
    var colors: [Color] {
        switch self {
        case .midnight:
            return [
                AppColors.PayGate.midnight1,
                AppColors.PayGate.midnight2,
                AppColors.PayGate.midnight3,
                AppColors.PayGate.midnight4
            ]
        case .aurora:
            return [
                AppColors.PayGate.aurora1,
                AppColors.PayGate.aurora2,
                AppColors.PayGate.aurora3,
                AppColors.PayGate.aurora4
            ]
        case .sunset:
            return [
                AppColors.PayGate.sunset1,
                AppColors.PayGate.sunset2,
                AppColors.PayGate.sunset3,
                AppColors.PayGate.sunset4
            ]
        case .ocean:
            return [
                AppColors.PayGate.ocean1,
                AppColors.PayGate.ocean2,
                AppColors.PayGate.ocean3,
                AppColors.PayGate.ocean4
            ]
        case .neon:
            return [
                AppColors.PayGate.neon1,
                AppColors.PayGate.neon2,
                AppColors.PayGate.neon3,
                AppColors.PayGate.neon4
            ]
        case .minimal:
            return [
                AppColors.PayGate.minimal1,
                AppColors.PayGate.minimal2,
                AppColors.PayGate.minimal3,
                AppColors.PayGate.minimal4
            ]
        }
    }
    
    var accentColor: Color {
        switch self {
        case .midnight: return .purple
        case .aurora: return .cyan
        case .sunset: return .orange
        case .ocean: return .blue
        case .neon: return .pink
        case .minimal: return .white.opacity(0.3)
        }
    }
}

// MARK: - PayGateView
struct PayGateView: View {
    @ObservedObject var model: AppModel
    @AppStorage("payGateBackgroundStyle") private var backgroundStyle: String = PayGateBackgroundStyle.midnight.rawValue
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
        if let id = model.payGateTargetGroupId, let session = model.payGateSessions[id] {
            return session
        }
        return nil
    }
    
    private var activeGroup: AppModel.ShieldGroup? {
        guard let groupId = activeSession?.groupId else { return nil }
        return model.shieldGroups.first(where: { $0.id == groupId })
    }
    
    private var isCountdownActive: Bool {
        guard let session = activeSession else { return false }
        return !timedOutSessions.contains(session.groupId) && remainingSeconds(for: session) > 0
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
    
    // Compact countdown for smaller screens
    private var countdownBadgeCompact: some View {
        let progress = CGFloat(max(0, countdown)) / CGFloat(totalCountdown)
        let countdownColor: Color = countdown > 5 ? .green : (countdown > 2 ? .orange : .red)
        
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 44, height: 44)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(countdownColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                    .animation(.easeInOut(duration: 0.3), value: countdown)
                
                Text("\(max(0, countdown))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
            
            Text(loc("seconds left", "секунд"))
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.5))
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                payGateBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top section with balance
                    stepsProgressBar
                        .padding(.horizontal, 20)
                        .padding(.top, 50)
                    
                    Spacer(minLength: 10)
                
                    // Center content - app icons and countdown
                    if let group = activeGroup {
                        VStack(spacing: 16) {
                            // App icons from group
                            groupAppIconsView(group: group)
                                .frame(height: 100)
                            
                            // Group name
                            Text(group.name.isEmpty ? "Shield Group" : group.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            // Difficulty level badge
                            difficultyLevelBadge(level: group.difficultyLevel)
                        }
                    }
                    
                    Spacer(minLength: 10)
                    
                    // Bottom action panel - scrollable for small screens
                    ScrollView(showsIndicators: false) {
                        bottomActionPanel
                    }
                    .frame(maxHeight: geometry.size.height * 0.45)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .overlay(transitionOverlay)
        .onDisappear {
            if let id = activeSession?.groupId {
                didForfeitSessions.insert(id)
            }
            model.dismissPayGate(reason: .programmatic)
        }
    }
    
    @ViewBuilder
    private var bottomActionPanel: some View {
        VStack(spacing: 16) {
            if let group = activeGroup {
                openModePanel(group: group, isTimedOut: timedOutSessions.contains(group.id))
                closeButton(groupId: group.id)
            } else {
                Text(loc("No group selected", "Группа не выбрана"))
                    .foregroundColor(.secondary)
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
    private func openModePanel(group: AppModel.ShieldGroup, isTimedOut: Bool) -> some View {
        let windows = Array(group.enabledIntervals).sorted { $0.minutes < $1.minutes }
        
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text(loc("Choose Access", "Выберите доступ"))
                    .font(.headline)
                Spacer()
                
                // Difficulty level badge
                difficultyLevelBadge(level: group.difficultyLevel)
            }
            
            // Access options grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(windows, id: \.self) { window in
                    accessWindowCard(window: window, group: group, isTimedOut: isTimedOut, isForfeited: isForfeited(group.id))
                }
            }
        }
    }
    
    @ViewBuilder
    private func accessWindowCard(window: AccessWindow, group: AppModel.ShieldGroup, isTimedOut: Bool, isForfeited: Bool) -> some View {
        let baseCost = group.cost(for: window)
        let effectiveCost = baseCost
        let canPay = effectiveCost == 0 || model.totalStepsBalance >= effectiveCost
        let isDisabled = !canPay || isTimedOut || isForfeited
        let pink = AppColors.brandPink
        
        Button {
            guard !isDisabled else { return }
            setForfeit(group.id)
            Task {
                performTransition {
                    Task { await model.handlePayGatePaymentForGroup(groupId: group.id, window: window, costOverride: effectiveCost) }
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
        .accessibilityLabel("\(accessWindowShortName(window)) access, \(effectiveCost) energy")
        .accessibilityHint(isDisabled ? "Not enough energy or timed out" : "Opens access for \(accessWindowShortName(window))")
        .accessibilityValue(canPay ? "Available" : "Insufficient energy")
    }
    
    private func windowIcon(_ window: AccessWindow) -> String {
        switch window {
        case .single: return "arrow.right.circle"
        case .minutes5: return "5.circle"
        case .minutes15: return "15.circle"
        case .minutes30: return "30.circle"
        case .hour1: return "clock"
        case .hour2: return "clock.fill"
        case .day1: return "sun.max.fill"
        }
    }
    
    private func accessWindowShortName(_ window: AccessWindow) -> String {
        switch window {
        case .single: return loc("1 min", "1 мин")
        case .minutes5: return loc("5 min", "5 мин")
        case .minutes15: return loc("15 min", "15 мин")
        case .minutes30: return loc("30 min", "30 мин")
        case .hour1: return loc("1 hour", "1 час")
        case .hour2: return loc("2 hours", "2 часа")
        case .day1: return loc("Day", "День")
        }
    }
    
                
    @ViewBuilder
    private func closeButton(groupId: String) -> some View {
        Button {
            setForfeit(groupId)
            performTransition(duration: 0.6) {
                model.dismissPayGate(reason: .userDismiss)
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
        .accessibilityLabel(loc("Close", "Закрыть"))
        .accessibilityHint("Closes the pay gate and returns to home screen")
    }
}

extension PayGateView {
    private func refreshCountdown() {
        guard let session = activeSession else {
            countdown = 0
            return
        }
        if lastSessionId != session.groupId {
            lastSessionId = session.groupId
            countdown = remainingSeconds(for: session)
            // reset forfeit/timedOut for new session
            didForfeitSessions.remove(session.groupId)
            timedOutSessions.remove(session.groupId)
        } else {
            countdown = remainingSeconds(for: session)
        }
    }
    
    private func isForfeited(_ groupId: String) -> Bool {
        didForfeitSessions.contains(groupId) || timedOutSessions.contains(groupId)
    }
    
    private func setForfeit(_ groupId: String) {
        didForfeitSessions.insert(groupId)
    }
    
    // MARK: - Group App Icons View
    @ViewBuilder
    private func groupAppIconsView(group: AppModel.ShieldGroup) -> some View {
        #if canImport(FamilyControls)
        let appTokens = Array(group.selection.applicationTokens.prefix(3))
        let remainingSlots = max(0, 3 - appTokens.count)
        let categoryTokens = Array(group.selection.categoryTokens.prefix(remainingSlots))
        let hasMore = (group.selection.applicationTokens.count + group.selection.categoryTokens.count) > 3
        
        ZStack {
            // Glow
            Circle()
                .fill(selectedBackgroundStyle.accentColor.opacity(0.2))
                .frame(width: 120, height: 120)
                .blur(radius: 30)
            
            // App icons stack
            ForEach(Array(appTokens.enumerated()), id: \.offset) { index, token in
                AppIconView(token: token)
                    .frame(width: iconSizeForPayGate(index), height: iconSizeForPayGate(index))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    .offset(x: iconOffsetForPayGate(index).x, y: iconOffsetForPayGate(index).y)
                    .zIndex(Double(3 - index))
            }
            
            // Category icons
            ForEach(Array(categoryTokens.enumerated()), id: \.offset) { offset, token in
                let index = appTokens.count + offset
                CategoryIconView(token: token)
                    .frame(width: iconSizeForPayGate(index), height: iconSizeForPayGate(index))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    .offset(x: iconOffsetForPayGate(index).x, y: iconOffsetForPayGate(index).y)
                    .zIndex(Double(3 - index))
            }
            
            // +N badge if more apps
            if hasMore {
                let totalCount = group.selection.applicationTokens.count + group.selection.categoryTokens.count
                Text("+\(totalCount - 3)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .offset(x: 20, y: 20)
                    .zIndex(10)
            }
        }
        #else
        Image(systemName: "app.fill")
            .font(.system(size: 48))
            .foregroundColor(.white)
        #endif
    }
    
    private func iconSizeForPayGate(_ index: Int) -> CGFloat {
        switch index {
        case 0: return 64
        case 1: return 56
        default: return 48
        }
    }
    
    private func iconOffsetForPayGate(_ index: Int) -> (x: CGFloat, y: CGFloat) {
        switch index {
        case 0: return (-12, -8)
        case 1: return (12, 8)
        default: return (0, 16)
        }
    }
    
    @ViewBuilder
    private func difficultyLevelBadge(level: Int) -> some View {
        let color = difficultyColor(for: level)
        Text("Level \(level)")
            .font(.caption.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }
    
    private func difficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
}

// MARK: - PayGate transition helper
extension PayGateView {
    private func handleCountdownTick() {
        refreshCountdown()
        if let session = activeSession {
            let remaining = remainingSeconds(for: session)
            if remaining <= 0 {
                timedOutSessions.insert(session.groupId)
            }
        }
    }
}

// MARK: - Helper Functions
private func getAppDisplayName(_ bundleId: String) -> String {
    // 1) Старые преднастроенные приложения (Instagram, TikTok и т.п.)
    if let name = SettingsView.automationAppsStatic.first(where: { $0.bundleId == bundleId })?.name {
        return name
    }
    
    // 2) Новые карточки FamilyControls: пробуем взять имя из selection по токену.
    let defaults = UserDefaults.stepsTrader()
    let key = "timeAccessSelection_v1_\(bundleId)"
    if let data = defaults.data(forKey: key),
       let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
       let token = sel.applicationTokens.first {
        // Ключ для имени по токену, который пишет экстеншен ShieldConfiguration.
        if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
            if let storedName = defaults.string(forKey: tokenKey) {
                return storedName
            }
        }
    }
    
    // 3) Fallback: не светим внутренний id, показываем общее имя.
    return "Selected app"
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
    
    private var selectedBackgroundStyle: PayGateBackgroundStyle {
        PayGateBackgroundStyle(rawValue: backgroundStyle) ?? .midnight
    }
    
    private func payGateBackground() -> some View {
        let style = selectedBackgroundStyle
        
        return ZStack {
            // Base gradient
            LinearGradient(
                gradient: Gradient(colors: style.colors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Soft gradient orbs (no blur - GPU safe)
            GeometryReader { geo in
                ZStack {
                    // Large soft circle (using radial gradient instead of blur)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [style.accentColor.opacity(0.2), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.5
                            )
                        )
                        .frame(width: geo.size.width * 1.2)
                        .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.15)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [style.colors[1].opacity(0.25), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.4
                            )
                        )
                        .frame(width: geo.size.width * 0.9)
                        .offset(x: geo.size.width * 0.25, y: geo.size.height * 0.35)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [style.accentColor.opacity(0.15), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.35
                            )
                        )
                        .frame(width: geo.size.width * 0.7)
                        .offset(x: 0, y: geo.size.height * 0.45)
                }
            }
            
            // Top and bottom vignette
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.6), location: 0),
                    .init(color: Color.clear, location: 0.3),
                    .init(color: Color.clear, location: 0.7),
                    .init(color: Color.black.opacity(0.7), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Subtle accent glow at bottom
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    style.accentColor.opacity(0.1)
                ]),
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
    
    private var stepsProgressBar: some View {
        // Текущий баланс = stepsBalance (из шагов) + bonusSteps
        // Это реальный баланс энергии, который отображается в приложении
        let remaining = max(0, model.totalStepsBalance)
        
        // Общее количество энергии за сегодня = базовая энергия + бонусы
        // Если текущий баланс больше начальной энергии (добавились бонусы), используем баланс как total
        let total = max(remaining, model.baseEnergyToday + model.bonusSteps)
        
        // Потрачено = общая энергия - текущий баланс
        let used = max(0, total - remaining)
        let denominator = Double(max(1, total))
        let displayRemaining = min(remaining, total)
        let remainingProgress = min(1, Double(displayRemaining) / denominator)
        let pink = AppColors.brandPink
        let progressColor = remaining > 50 ? pink : (remaining > 20 ? .orange : .red)

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
                
                Text(loc("energy left", "энергии"))
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
    private var doomCtrlIconView: some View {
        // Try to load the actual app icon
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last,
           let uiImage = UIImage(named: last) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            // Fallback to styled icon
            ZStack {
                LinearGradient(
                    colors: [Color.purple, Color.pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                Image(systemName: "bolt.shield.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
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
            model.message = loc("en", "Not enough energy for this option today.", "Недостаточно энергии для этого варианта сегодня.")
            // Revert selection so picker stays visible
            model.dailyTariffSelections.removeValue(forKey: bundleId)
            return
        }
        model.selectTariffForToday(tariff, bundleId: bundleId)
        await model.handlePayGatePayment(for: bundleId, window: .single)
    }

    private func windowCost(for level: ShieldLevel, window: AccessWindow, bundleId: String? = nil) -> Int {
        // Если есть bundleId, используем настройки из unlockSettings
        if let bundleId = bundleId {
            let settings = model.unlockSettings(for: bundleId)
            let baseCost = settings.entryCostSteps
            
            // Рассчитываем стоимость для разных окон на основе entryCostSteps
            switch window {
            case .single: return baseCost
            case .minutes5: return max(1, baseCost * 5)
            case .minutes15: return max(1, baseCost * 15)
            case .minutes30: return max(1, baseCost * 30)
            case .hour1: return max(1, baseCost * 60)
            case .hour2: return max(1, baseCost * 120)
            case .day1: return max(1, baseCost * 1440)
            }
        }
        
        // Fallback на старую логику с уровнями
        switch window {
        case .single: return 1
        case .minutes5: return 2
        case .minutes15: return 5
        case .minutes30: return 10
        case .hour1: return 20
        case .hour2: return 40
        case .day1: return 20
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
    case requestFamilyControls
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
    let onFamilyControlsSlide: (() -> Void)?
    let onFinish: () -> Void
    @State private var index: Int = 0
    @State private var didTriggerLocationRequest = false
    @State private var didTriggerHealthRequest = false
    @State private var didTriggerNotificationRequest = false
    @State private var didTriggerFamilyControlsRequest = false

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
                    .accessibilityLabel(skipText)
                    .accessibilityHint("Skips the onboarding and goes to the main app")

                    Button(action: next) {
                        Text(primaryButtonTitle)
                            .font(.headline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel(primaryButtonTitle)
                    .accessibilityHint("Continues to the next onboarding slide or starts the app")
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
            case .requestFamilyControls:
                if !didTriggerFamilyControlsRequest {
                    didTriggerFamilyControlsRequest = true
                    onFamilyControlsSlide?()
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

// MARK: - Notification Handling
extension StepsTraderApp {
    func setupNotificationHandling() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationDelegate.shared.model = model
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var model: AppModel?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let action = userInfo["action"] as? String, action == "unlock" {
            // Пытаемся определить bundleId:
            // 1) прямо из userInfo;
            // 2) из lastBlockedAppBundleId в shared defaults;
            // 3) из групп щитов (shieldGroups_v1);
            // 4) из appUnlockSettings_v1 (берём первый включённый бандл или просто первый ключ).
            let directBundleId = userInfo["bundleId"] as? String
            let defaults = UserDefaults.stepsTrader()
            let sharedBundleId = defaults.string(forKey: "lastBlockedAppBundleId")
            
            // Проверяем группы щитов - ищем по имени приложения из lastBlockedAppBundleId
            let groupBundleId: String? = {
                guard let groupsData = defaults.data(forKey: "shieldGroups_v1"),
                      let groups = try? JSONDecoder().decode([ShieldGroupDataForNotification].self, from: groupsData),
                      !groups.isEmpty
                else { return nil }
                
                // Если есть lastBlockedAppBundleId, проверяем, есть ли он в группах
                if let blockedAppName = sharedBundleId {
                    for group in groups {
                        if let selectionData = group.selectionData,
                           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
                            // Проверяем, есть ли приложение с таким именем в группе
                            for token in sel.applicationTokens {
                                if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                                    let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                                    if let appName = defaults.string(forKey: tokenKey),
                                       (appName.lowercased() == blockedAppName.lowercased() ||
                                        blockedAppName.lowercased().contains(appName.lowercased()) ||
                                        appName.lowercased().contains(blockedAppName.lowercased())) {
                                        print("✅ Found app name in group: \(appName)")
                                        // Конвертируем appName в bundleId
                                        let bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                        print("✅ Resolved bundleId: \(bundleId)")
                                        return bundleId
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Если не нашли по имени, берем первое приложение из первой активной группы
                for group in groups {
                    if let selectionData = group.selectionData,
                       let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
                       !sel.applicationTokens.isEmpty {
                        // Берем имя первого приложения из группы
                        if let firstToken = sel.applicationTokens.first,
                           let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
                            let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                            if let appName = defaults.string(forKey: tokenKey) {
                                print("✅ Using first app from group: \(appName)")
                                // Конвертируем appName в bundleId
                                let bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                print("✅ Resolved bundleId: \(bundleId)")
                                return bundleId
                            }
                        }
                    }
                }
                return nil
            }()
            
            let fallbackBundleId: String? = {
                guard let data = defaults.data(forKey: "appUnlockSettings_v1"),
                      let decoded = try? JSONDecoder().decode([String: StoredUnlockSettingsForNotification].self, from: data),
                      !decoded.isEmpty
                else { return nil }
                
                let enabledKey = decoded.first { (_, settings) in
                    (settings.minuteTariffEnabled ?? false) || (settings.familyControlsModeEnabled ?? false)
                }?.key
                return enabledKey ?? decoded.keys.first
            }()
            
            let bundleId = directBundleId ?? sharedBundleId ?? groupBundleId ?? fallbackBundleId
            
            if let bundleId {
                print("📲 Push notification tapped for unlock: \(bundleId)")
                print("   - directBundleId: \(directBundleId ?? "nil")")
                print("   - sharedBundleId: \(sharedBundleId ?? "nil")")
                print("   - groupBundleId: \(groupBundleId ?? "nil")")
                print("   - fallbackBundleId: \(fallbackBundleId ?? "nil")")
                
                // Open paygate - ищем группу по bundleId
                Task { @MainActor in
                    self.model?.openPayGateForBundleId(bundleId)
                }
            } else {
                print("⚠️ Push notification tapped for unlock, but bundleId not found")
                print("   - directBundleId: \(directBundleId ?? "nil")")
                print("   - sharedBundleId: \(sharedBundleId ?? "nil")")
                print("   - groupBundleId: \(groupBundleId ?? "nil")")
                print("   - fallbackBundleId: \(fallbackBundleId ?? "nil")")
                print("   - shieldGroups_v1 exists: \(defaults.data(forKey: "shieldGroups_v1") != nil)")
                
                // Попытка открыть PayGate с первым доступным bundleId из групп
                // Используем модель напрямую, так как она уже загружена
                Task { @MainActor in
                    guard let model = self.model else { 
                        print("⚠️ Fallback: Model is nil")
                        return 
                    }
                    
                    let defaults = UserDefaults.stepsTrader()
                    var bundleId: String? = nil
                    
                    // Способ 1: Используем lastBlockedAppBundleId (самый надежный)
                    if let blockedApp = defaults.string(forKey: "lastBlockedAppBundleId") {
                        bundleId = TargetResolver.bundleId(from: blockedApp) ?? blockedApp
                        print("🔄 Fallback: Using lastBlockedAppBundleId: \(blockedApp) -> \(bundleId ?? "nil")")
                    }
                    
                    // Способ 2: Если нет lastBlockedAppBundleId, используем первый bundleId из appUnlockSettings
                    if bundleId == nil {
                        if let data = defaults.data(forKey: "appUnlockSettings_v1") {
                            print("🔄 Fallback: Found appUnlockSettings_v1 data, size: \(data.count) bytes")
                            if let decoded = try? JSONDecoder().decode([String: StoredUnlockSettingsForNotification].self, from: data) {
                                print("🔄 Fallback: Decoded \(decoded.keys.count) app unlock settings")
                                // Ищем первый включенный или просто первый ключ
                                let enabledKey = decoded.first { (_, settings) in
                                    (settings.minuteTariffEnabled ?? false) || (settings.familyControlsModeEnabled ?? false)
                                }?.key
                                
                                let firstKey = enabledKey ?? decoded.keys.first
                                if let firstKey = firstKey {
                                    bundleId = TargetResolver.bundleId(from: firstKey) ?? firstKey
                                    print("🔄 Fallback: Using key from appUnlockSettings: \(firstKey) -> \(bundleId ?? "nil")")
                                } else {
                                    print("⚠️ Fallback: appUnlockSettings decoded but no keys found")
                                }
                            } else {
                                print("⚠️ Fallback: Could not decode appUnlockSettings_v1")
                            }
                        } else {
                            print("⚠️ Fallback: No appUnlockSettings_v1 data found")
                        }
                    }
                    
                    // Способ 3: Если есть shield groups, пробуем найти bundleId через все сохраненные имена приложений
                    if bundleId == nil {
                        if let firstGroup = model.shieldGroups.first(where: { !$0.selection.applicationTokens.isEmpty }) {
                            print("🔄 Fallback: Found group with \(firstGroup.selection.applicationTokens.count) apps")
                            
                            // Пробуем найти через все сохраненные имена приложений в UserDefaults
                            let allKeys = defaults.dictionaryRepresentation().keys
                            for key in allKeys where key.hasPrefix("fc_appName_") {
                                if let appName = defaults.string(forKey: key) {
                                    bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                    print("🔄 Fallback: Using first found app name from UserDefaults: \(appName) -> \(bundleId ?? "nil")")
                                    break
                                }
                            }
                            
                            // Если не нашли через UserDefaults, пробуем архивацию токена
                            if bundleId == nil {
                                #if canImport(FamilyControls)
                                if let firstToken = firstGroup.selection.applicationTokens.first {
                                    if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
                                        let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                                        if let appName = defaults.string(forKey: tokenKey) {
                                            bundleId = TargetResolver.bundleId(from: appName) ?? appName
                                            print("🔄 Fallback: Found app name via archiving: \(appName) -> \(bundleId ?? "nil")")
                                        } else {
                                            print("⚠️ Fallback: Token archived but no app name found for key: \(tokenKey)")
                                        }
                                    } else {
                                        print("⚠️ Fallback: Could not archive token")
                                    }
                                }
                                #endif
                            }
                        } else {
                            print("⚠️ Fallback: No shield groups with apps found")
                        }
                    }
                    
                    // Открываем PayGate если нашли bundleId
                    if let bundleId = bundleId {
                        print("🔄 Fallback: Opening PayGate with bundleId: \(bundleId)")
                        model.openPayGateForBundleId(bundleId)
                    } else {
                        print("⚠️ Fallback: Could not find bundleId from any source")
                        
                        // Последняя попытка: если есть shield groups, открываем первую группу напрямую
                        if let firstGroup = model.shieldGroups.first {
                            print("🔄 Fallback: Using first shield group: \(firstGroup.name) (id: \(firstGroup.id))")
                            model.openPayGate(for: firstGroup.id)
                        } else {
                            print("⚠️ Fallback: No shield groups available")
                        }
                    }
                }
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
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
