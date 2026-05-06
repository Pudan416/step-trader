import SwiftUI
import Combine
import UIKit
import UserNotifications
import BackgroundTasks

@main
struct StepsTraderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var authService = AuthenticationService.shared
    #if DEBUG
    @StateObject private var coachMarkManager = CoachMarkManager()
    #endif
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("hasSeenIntro_v3") private var hasSeenIntro: Bool = false
    @AppStorage("hasSeenEnergySetup_v1") private var hasSeenEnergySetup: Bool = false
    @AppStorage("hasCompletedOnboarding_v1") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasMigratedOnboarding_v1") private var hasMigratedOnboarding: Bool = false
    private let cleanupTimer = Timer.publish(every: AppConstants.Timing.cleanupTimerInterval, on: .main, in: .common).autoconnect()
    private let isUITest = ProcessInfo.processInfo.arguments.contains("ui-testing")

    init() {
        _model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())
        // Install notification delegate as early as possible so taps that *launch* the app
        // are routed through our handler (onAppear can be too late).
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Mirror theme to app-group so the wallpaper Shortcut intent can read it reliably.
        let themeRaw = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue
        UserDefaults(suiteName: SharedKeys.appGroupId)?.set(themeRaw, forKey: "appTheme")

        // Make NavigationStack backgrounds transparent so the shared energy gradient
        // shows through on every tab.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // Also make TabBar transparent (we use a custom tab bar)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding || isUITest {
                    if !isUITest && model.userEconomyStore.showPayGate {
                        PayGateView(model: model)
                            .onAppear {
                                AppLogger.app.debug("🎯 PayGateView appeared - target group: \(model.userEconomyStore.payGateTargetGroupId ?? "nil")")
                            }
                    } else if !isUITest && model.showQuickStatusPage {
                        #if DEBUG
                        QuickStatusView(model: model)
                        #else
                        MainTabView(model: model, theme: currentTheme)
                        #endif
                    } else {
                        MainTabView(model: model, theme: currentTheme)
                    }

                    // Handoff protection screen (disabled for Instagram flow and UI tests)
                    if !isUITest, model.showHandoffProtection, let token = model.handoffToken {
                        // Only show handoff protection for non-Instagram targets
                        if token.targetBundleId != "com.burbn.instagram" {
                            HandoffProtectionView(model: model, token: token) {
                                model.handleHandoffContinue()
                            } onCancel: {
                                model.handleHandoffCancel()
                            }
                        }
                    }
                } else {
                    OnboardingFlowView(
                        model: model,
                        authService: authService
                    ) {
                        hasSeenIntro = true
                        hasSeenEnergySetup = true
                        hasCompletedOnboarding = true
                        Task {
                            await model.refreshStepsIfAuthorized()
                            await model.refreshSleepIfAuthorized()
                        }
                        #if DEBUG
                        if UserDefaults.standard.bool(forKey: "shouldStartCoachMark") {
                            UserDefaults.standard.removeObject(forKey: "shouldStartCoachMark")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                coachMarkManager.start()
                            }
                        }
                        #endif
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }

            }
            .themed(currentTheme)
            .tint(currentTheme.accentColor)
            .grayscale(0)
            #if DEBUG
            .environmentObject(coachMarkManager)
            #endif
            .alert(isPresented: $errorManager.showErrorAlert, error: errorManager.currentError) { _ in
                Button("OK", role: .cancel) {
                    errorManager.dismiss()
                }
            } message: { error in
                Text(error.recoverySuggestion ?? "")
            }
            .onAppear {
                // Language selection was removed — English only for v1.

                if !hasMigratedOnboarding && hasSeenIntro && hasSeenEnergySetup {
                    hasCompletedOnboarding = true
                    hasMigratedOnboarding = true
                }

                // Setup notification handling ASAP so model is set for delegate callbacks
                setupNotificationHandling()

                // Ensure bootstrap runs once; defer permission prompts to onboarding flow if needed.
                // IMPORTANT: checkForPayGateFlags runs AFTER bootstrap so ticket groups are loaded.
                if hasCompletedOnboarding {
                    Task {
                        await model.bootstrap(requestPermissions: !isUITest)
                        checkForPayGateFlags()
                    }
                } else {
                    Task { await model.bootstrap(requestPermissions: false) }
                }
                AppLogger.app.debug(
                    "🎭 StepsTraderApp appeared - showPayGate: \(model.userEconomyStore.showPayGate), showQuickStatusPage: \(model.showQuickStatusPage)"
                )
                AppLogger.app.debug(
                    "🎭 App state - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                AppLogger.app.debug(
                    "🎭 PayGate state - showPayGate: \(model.userEconomyStore.showPayGate), targetGroupId: \(model.userEconomyStore.payGateTargetGroupId ?? "nil")"
                )
                checkForHandoffToken()
            }
            .task {
                if hasCompletedOnboarding && !isUITest {
                    await model.refreshStepsIfAuthorized()
                }
            }
            .onReceive(cleanupTimer) { _ in
                model.checkDayBoundary()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    model.handleAppWillEnterForeground()
                    checkForHandoffToken()
                    checkForPayGateFlags()
                case .background:
                    UserDefaults(suiteName: SharedKeys.appGroupId)?.set(appThemeRaw, forKey: "appTheme")
                    model.handleAppDidEnterBackground()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.significantTimeChangeNotification)
            ) { _ in
                AppLogger.app.debug("🕛 Significant time change detected (day changed)")
                Task {
                    await MainActor.run {
                        model.checkDayBoundary()
                    }
                    await model.refreshStepsIfAuthorized()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.refresh")))
            { _ in
                model.handleAppWillEnterForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.showIntro")) ) { _ in
                hasCompletedOnboarding = false
                hasMigratedOnboarding = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.paygate")))
            { notification in
                AppLogger.app.debug("📱 App received PayGate notification")
                if let userInfo = notification.userInfo,
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    let g = UserDefaults.stepsTrader()
                    if let until = g.object(forKey: SharedKeys.payGateDismissedUntil) as? Date,
                       Date() < until
                    {
                        AppLogger.app.debug("🚫 PayGate notification suppressed after dismiss")
                        return
                    }
                    AppLogger.app.debug("📱 PayGate notification - target: \(target), bundleId: \(bundleId)")
                    Task { @MainActor in
                        model.openPayGateForBundleId(bundleId)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.local.paygate")))
            { notification in
                AppLogger.app.debug("📱 App received local notification")
                if let userInfo = notification.userInfo,
                   let action = userInfo["action"] as? String,
                   action == "paygate",
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    let g = UserDefaults.stepsTrader()
                    if let until = g.object(forKey: SharedKeys.payGateDismissedUntil) as? Date,
                       Date() < until
                    {
                        AppLogger.app.debug("🚫 PayGate local notification suppressed after dismiss")
                        return
                    }
                    let lastOpen = g.object(forKey: SharedKeys.lastAppOpenedFromStepsTrader(bundleId)) as? Date
                    if let lastOpen {
                        let elapsed = Date().timeIntervalSince(lastOpen)
                        if elapsed < 10 {
                                AppLogger.app.debug("PayGate local ignored for \(bundleId) to avoid loop (\(elapsed, format: .fixed(precision: 1))s since last open)")
                            return
                        }
                    }
                    AppLogger.app.debug("📱 Local notification PayGate - target: \(target), bundleId: \(bundleId)")
                    Task { @MainActor in
                        model.openPayGateForBundleId(bundleId)
                        AppLogger.app.debug("📱 PayGate state after setting - showPayGate: \(model.userEconomyStore.showPayGate), targetGroupId: \(model.userEconomyStore.payGateTargetGroupId ?? "nil")")
                    }
                }
            }
            .onOpenURL { url in
                handleWidgetOpenApp(url)
            }
            .tint(currentTheme.accentColor)
            .background(currentTheme.backgroundColor)
            .preferredColorScheme(currentTheme.colorScheme)
        }
    }

    private func handleWidgetOpenApp(_ url: URL) {
        guard url.host == "openapp",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let bundleId = components.queryItems?.first(where: { $0.name == "bundleId" })?.value,
              let scheme = TargetResolver.primaryAndFallbackSchemes(for: bundleId).first,
              let targetURL = URL(string: scheme)
        else { return }

        Task { @MainActor in
            UIApplication.shared.open(targetURL)
        }
    }

    private func checkForHandoffToken() {
        let userDefaults = UserDefaults.stepsTrader()

        AppLogger.app.debug("🔍 Checking for handoff token...")
        AppLogger.app.debug(
            "🔍 Current app state - showPayGate: \(model.userEconomyStore.showPayGate), showHandoffProtection: \(model.showHandoffProtection)"
        )

        // Check for handoff token
        if let tokenData = userDefaults.data(forKey: SharedKeys.handoffToken) {
            AppLogger.app.debug("🎫 Found handoff token data, decoding...")
            do {
                let token = try JSONDecoder().decode(HandoffToken.self, from: tokenData)
                AppLogger.app.debug("✅ Token decoded: \(token.targetAppName) (ID: \(token.tokenId))")

                // Check if token has expired
                if token.isExpired {
                    AppLogger.app.debug("⏰ Handoff token expired, removing")
                    userDefaults.removeObject(forKey: SharedKeys.handoffToken)
                    return
                }

                // Show handoff protection screen
                AppLogger.app.debug("🛡️ Setting handoff protection for \(token.targetAppName)")
                AppLogger.app.debug(
                    "🛡️ Before setting - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                model.handoffToken = token
                model.showHandoffProtection = true
                AppLogger.app.debug(
                    "🛡️ After setting - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                AppLogger.app.debug("🛡️ Handoff protection screen should now be visible!")

            } catch {
                AppLogger.app.debug("Failed to decode handoff token: \(error.localizedDescription)")
                userDefaults.removeObject(forKey: SharedKeys.handoffToken)
            }
        } else {
            AppLogger.app.debug("ℹ️ No handoff token found")
        }

    }
    
    private func checkForPayGateFlags() {
        let userDefaults = UserDefaults.stepsTrader()
        
        // Check if flags set to show PayGate (only set by notification intent)
        let shouldShowPayGate = userDefaults.bool(forKey: SharedKeys.shouldShowPayGate)
        
        guard shouldShowPayGate else {
            clearPayGateFlags(userDefaults)
            return
        }
        
        // User explicitly tapped a notification → override any dismiss cooldown.
        // The 10s cooldown exists to prevent re-open loops after manual dismiss,
        // but it must not block an intentional notification tap.
        userDefaults.removeObject(forKey: SharedKeys.payGateDismissedUntil)
        
        let targetGroupId = userDefaults.string(forKey: SharedKeys.payGateTargetGroupId)
        let targetBundleId = userDefaults.string(forKey: SharedKeys.payGateTargetBundleId)
        
        if let groupId = targetGroupId {
            if !model.userEconomyStore.showPayGate, isRecentPayGateOpen(groupId: groupId, userDefaults: userDefaults) {
                AppLogger.app.debug("🚫 PayGate flags ignored: recent PayGate open for group \(groupId)")
                clearPayGateFlags(userDefaults)
                return
            }
            AppLogger.app.debug("📲 checkForPayGateFlags: opening PayGate for group \(groupId)")
            model.openPayGate(for: groupId)
        } else if let bundleId = targetBundleId {
            AppLogger.app.debug("📲 checkForPayGateFlags: opening PayGate for bundleId \(bundleId)")
            model.openPayGateForBundleId(bundleId)
        } else {
            // Last-resort fallback: open the first ticket group if present.
            if let first = model.blockingStore.ticketGroups.first {
                AppLogger.app.debug("📲 checkForPayGateFlags: fallback to first group \(first.name)")
                model.openPayGate(for: first.id)
            }
        }
        
        clearPayGateFlags(userDefaults)
    }
    
    private func clearPayGateFlags(_ userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: SharedKeys.shouldShowPayGate)
        userDefaults.removeObject(forKey: SharedKeys.payGateTargetGroupId)
        userDefaults.removeObject(forKey: SharedKeys.payGateTargetBundleId)
    }

    private func isRecentPayGateOpen(groupId: String, userDefaults: UserDefaults) -> Bool {
        if let last = userDefaults.object(forKey: SharedKeys.lastPayGateAction) as? Date,
           Date().timeIntervalSince(last) < 5 {
            return true
        }
        if let last = userDefaults.object(forKey: SharedKeys.lastGroupPayGateOpen(groupId)) as? Date,
           Date().timeIntervalSince(last) < 5 {
            return true
        }
        return false
    }
    
}

private extension StepsTraderApp {
    var currentTheme: AppTheme {
        AppTheme.normalized(rawValue: appThemeRaw)
    }
}

// MARK: - Notification Handling
extension StepsTraderApp {
    func setupNotificationHandling() {
        NotificationDelegate.shared.model = model
    }
}
