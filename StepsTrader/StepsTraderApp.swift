import SwiftUI
import Combine
import UIKit
import CoreLocation
import UserNotifications

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
                        skipText: loc(appLanguage, "Skip"),
                        nextText: loc(appLanguage, "Next"),
                        startText: loc(appLanguage, "Start"),
                        allowText: loc(appLanguage, "Allow"),
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
                            Task { try? await model.familyControlsService.requestAuthorization() }
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
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.significantTimeChangeNotification)
            ) { _ in
                print("🕛 Significant time change detected (day changed)")
                Task {
                    await model.refreshStepsIfAuthorized()
                }
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
                title: loc(appLanguage, "DOOM CTRL 🔥"),
                subtitle: loc(appLanguage, "Take back control from your apps"),
                symbol: "shield.checkered",
                gradient: [.purple, .pink],
                bullets: [
                    loc(appLanguage, "🛡️ Shield apps that steal your time"),
                    loc(appLanguage, "⚡ Pay with control to get access")
                ],
                action: .none
            ),
            // 2. Energy source
            OnboardingSlide(
                title: loc(appLanguage, "Daily Control ⚡"),
                subtitle: loc(appLanguage, "Move and choice build 100 points"),
                symbol: "bolt.fill",
                gradient: [.yellow, .orange],
                bullets: [
                    loc(appLanguage, "🏃 Sleep + steps + habits = Move points"),
                    loc(appLanguage, "💝 Choices = Joy points"),
                    loc(appLanguage, "🔋 Collect batteries on the map for bonus")
                ],
                action: .none
            ),
            // 3. Level up
            OnboardingSlide(
                title: loc(appLanguage, "Track Progress 📈"),
                subtitle: loc(appLanguage, "Spend control, see your impact"),
                symbol: "star.fill",
                gradient: [.blue, .purple],
                bullets: [
                    loc(appLanguage, "⭐ 10 levels per shield"),
                    loc(appLanguage, "📊 Track total control spent")
                ],
                action: .none
            ),
            // 4. Screen Time - Family Controls
            OnboardingSlide(
                title: loc(appLanguage, "Screen Time 📱"),
                subtitle: loc(appLanguage, "Track real app usage for minute mode"),
                symbol: "hourglass",
                gradient: [.indigo, .purple],
                bullets: [
                    loc(appLanguage, "⏱️ Pay per actual minute used"),
                    loc(appLanguage, "🔒 We only see usage, not content")
                ],
                action: .requestFamilyControls
            ),
            // 5. Map - location permission
            OnboardingSlide(
                title: loc(appLanguage, "Hunt Batteries 🗺️"),
                subtitle: loc(appLanguage, "Walk around → collect bonus control"),
                symbol: "map.fill",
                gradient: [.green, .teal],
                bullets: [
                    loc(appLanguage, "🔋 +5 control per battery"),
                    loc(appLanguage, "🧲 3 magnets/day to grab from afar")
                ],
                action: .requestLocation
            ),
            // 6. Health - steps permission
            OnboardingSlide(
                title: loc(appLanguage, "Connect Steps 🚶"),
                subtitle: loc(appLanguage, "Your walks = your power"),
                symbol: "figure.walk",
                gradient: [.pink, .purple],
                bullets: [
                    loc(appLanguage, "📊 We only read step count"),
                    loc(appLanguage, "🔒 Your data stays on device")
                ],
                action: .requestHealth
            ),
            // 7. Notifications
            OnboardingSlide(
                title: loc(appLanguage, "Stay Sharp 🔔"),
                subtitle: loc(appLanguage, "Know when access ends"),
                symbol: "bell.badge.fill",
                gradient: [.orange, .pink],
                bullets: [
                    loc(appLanguage, "⏰ Timers & reminders"),
                    loc(appLanguage, "🚫 Zero spam, only useful stuff")
                ],
                action: .requestNotifications
            )
        ]
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

// MARK: - Notification Handling
extension StepsTraderApp {
    func setupNotificationHandling() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationDelegate.shared.model = model
    }
}
