import SwiftUI
import Combine
import UIKit

@main
struct StepsTraderApp: App {
    @StateObject private var model: AppModel
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
                        skipText: "Skip",
                        nextText: "Next",
                        startText: "Start",
                        allowText: "Allow",
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
                title: "DOOM CTRL is here to stop your doomscroll",
                subtitle: "Raise shields to make crawls less doomed",
                emoji: "🛡"
            ),
            OnboardingSlide(
                title: "Your steps charge the batteries",
                subtitle: "Batteries power and level up your shields.",
                emoji: "📈"
            ),
            OnboardingSlide(
                title: "Share your steps",
                subtitle: "Give access to Health steps so we can turn them into charges for your battery.",
                emoji: "👟"
            ),
            OnboardingSlide(
                title: "Allow notifications",
                subtitle: "We ping you when shields are running out.",
                emoji: "🔔"
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
                    
                    JournalView(model: model, automationApps: SettingsView.automationAppsStatic, appLanguage: appLanguage)
                        .tabItem {
                            Image(systemName: "book")
                            Text(loc(appLanguage, "Journal", "Журнал"))
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
    private var activeTariff: Tariff { tariff(for: activeBundleId) }
    private var isCountdownActive: Bool {
        guard let session = activeSession, let bundleId = activeBundleId else { return false }
        return !timedOutSessions.contains(bundleId) && remainingSeconds(for: session) > 0
    }
    
    private func remainingSeconds(for session: AppModel.PayGateSession) -> Int {
        let elapsed = Date().timeIntervalSince(session.startedAt)
        return max(0, totalCountdown - Int(elapsed))
    }

    private func tariff(for bundleId: String?) -> Tariff {
        guard let bundleId else { return .hard }
        if let preset = model.presetTariff(for: bundleId) { return preset }
        let settings = model.unlockSettings(for: bundleId)
        if settings.entryCostSteps == 0 { return .free }
        if settings.entryCostSteps == Tariff.easy.entryCostSteps { return .easy }
        if settings.entryCostSteps == Tariff.medium.entryCostSteps { return .medium }
        if settings.entryCostSteps == Tariff.hard.entryCostSteps { return .hard }
        return .hard
    }
    
    @ViewBuilder
    private var centeredAppIconOverlay: some View {
        ZStack {
            if isCountdownActive {
                countdownBadge
                    .offset(y: -200)
            }
            
            VStack(spacing: 10) {
                if let bundleId = activeBundleId {
                    appIconView(bundleId)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    private var countdownBadge: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 96, height: 96)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, countdown)) / CGFloat(totalCountdown))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                            center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 96, height: 96)
                    .animation(.easeInOut(duration: 0.2), value: countdown)
                Text("\(max(0, countdown))s")
                    .font(.title3.bold())
                    .monospacedDigit()
            }
            Text(loc("to pay", "до оплаты"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    var body: some View {
        ZStack {
            payGateBackground()
                .ignoresSafeArea()
            
            VStack {
                stepsProgressBar
                    .padding(.horizontal, 20)
                    .padding(.top,60)
                Spacer()
            }
            
            ZStack {
                centeredAppIconOverlay
                
                VStack(spacing: 24) {
                    Spacer(minLength: 12)
                    
                    VStack(spacing: 20) {
                    if let bundleId = activeBundleId, let session = activeSession {
                        let isTimedOut = timedOutSessions.contains(bundleId) || remainingSeconds(for: session) <= 0
                        
                        if !isTimedOut {
                            VStack(spacing: 12) {
                                Text(loc("Choose access", "Выберите доступ"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                let allowed = model.allowedAccessWindows(for: bundleId)
                                let windows = [AccessWindow.day1, .hour1, .minutes5, .single].filter { allowed.contains($0) }
                                VStack(spacing: 10) {
                                    ForEach(windows, id: \.self) { window in
                                        accessWindowButton(window: window, bundleId: bundleId, isTimedOut: isTimedOut, isForfeited: isForfeited(bundleId))
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 12) {
                                Text(loc("You missed opening \(getAppDisplayName(bundleId)).", "Вы пропустили окно для \(getAppDisplayName(bundleId))."))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                Text("At least you saved some fuel.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                        }
                    } else {
                        VStack(spacing: 12) {
                            if let bundleId = model.payGateTargetBundleId {
                                Text(loc("You missed opening \(getAppDisplayName(bundleId)).", "Вы пропустили окно для \(getAppDisplayName(bundleId))."))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                Text(loc("At least you saved some fuel.", "Зато сохранили немного топлива."))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text(loc("You missed the window.", "Вы пропустили окно."))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    }
                }
                .padding(.horizontal, 20)
                
                Button(loc("Close", "Закрыть")) {
                    if let id = activeBundleId {
                        setForfeit(id)
                    }
                    performTransition(duration: 0.8) {
                        model.dismissPayGate()
                        sendAppToBackground()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color.gray.opacity(0.3))
                .foregroundColor(.primary)
                .font(.headline)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 72)
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
    
    @ViewBuilder
    private func centeredAppIcon() -> some View {
        if let bundleId = activeBundleId {
            GeometryReader { proxy in
                appIconView(bundleId)
                    .frame(width: 90, height: 90)
                    .shadow(radius: 10)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
    
    private func payGateBackground() -> some View {
        ZStack {
            Image("paygate")
                .resizable()
                .scaledToFill()
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.45)
                ]),
                startPoint: .top,
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

        return VStack(alignment: .leading, spacing: 6) {
            Text(loc("Steps today", "Шаги сегодня"))
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.7))
                    .frame(height: 10)
                GeometryReader { proxy in
                    Capsule()
                        .fill(pink)
                        .frame(width: proxy.size.width * CGFloat(remainingProgress), height: 10)
                }
                .frame(height: 10)
            }
            HStack {
                Text("\(used) used")
                Spacer()
                Text("\(remaining) left")
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white.opacity(0.9))
        }
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

    private func windowCost(for tariff: Tariff, window: AccessWindow) -> Int {
        switch tariff {
        case .free:
            return 0
        case .easy:
            switch window {
            case .single: return 10
            case .minutes5: return 50
            case .hour1: return 500
            case .day1: return 5000
            }
        case .medium:
            switch window {
            case .single: return 50
            case .minutes5: return 250
            case .hour1: return 2500
            case .day1: return 10000
            }
        case .hard:
            switch window {
            case .single: return 100
            case .minutes5: return 500
            case .hour1: return 5000
            case .day1: return 20000
            }
        }
    }

    private func accessWindowButton(window: AccessWindow, bundleId: String, isTimedOut: Bool, isForfeited: Bool) -> some View {
        let tariff = activeTariff
        let baseCost = windowCost(for: tariff, window: window)
        let hasPass = model.hasDayPass(for: bundleId)
        let effectiveCost = hasPass ? 0 : baseCost
        let canPay = effectiveCost == 0 || model.totalStepsBalance >= effectiveCost
        let name = accessWindowName(window)
        let fuelTitle = loc("fuel", "шагов")
        let title = "\(name) • \(effectiveCost) \(fuelTitle)"
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        let buttonColor = canPay && !isTimedOut && !isForfeited ? pink : Color.gray.opacity(0.6)

        return Button(title) {
            guard !isTimedOut, !isForfeited else { return }
            setForfeit(bundleId)
            Task {
                performTransition {
                    Task { await model.handlePayGatePayment(for: bundleId, window: window, costOverride: effectiveCost) }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(buttonColor)
        .foregroundColor(.white)
        .font(.subheadline.weight(.semibold))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: buttonColor.opacity(0.35), radius: 6, x: 0, y: 3)
        .disabled(!canPay || isTimedOut || isForfeited)
    }

    private func accessWindowName(_ window: AccessWindow) -> String {
        switch window {
        case .day1:
            return loc("Day pass", "Доступ на день")
        case .single:
            return loc("Single entry", "Однократный вход")
        case .minutes5:
            return loc("5 minutes", "5 минут")
        case .hour1:
            return loc("1 hour", "1 час")
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
struct OnboardingSlide: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let emoji: String
}

struct OnboardingStoriesView: View {
    @Binding var isPresented: Bool
    let slides: [OnboardingSlide]
    let accent: Color
    let skipText: String
    let nextText: String
    let startText: String
    let allowText: String
    let onHealthSlide: (() -> Void)?
    let onNotificationSlide: (() -> Void)?
    let onFinish: () -> Void
    @State private var index: Int = 0
    @State private var didTriggerHealthRequest = false
    @State private var didTriggerNotificationRequest = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                appLogo
                    .padding(.top, 28)

                progressBar
                    .padding(.top, 8)

                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        VStack(spacing: 20) {
                            Text(slide.emoji)
                                .font(.system(size: 68))

                            VStack(spacing: 12) {
                                Text(slide.title)
                                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color.white)
                                    )
                                Text(slide.subtitle)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(accentPink)
                                    .padding(.horizontal, 16)
                            }
                            .padding(.horizontal, 12)
                        }
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
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: next) {
                        let label: String = {
                            let lastIndex = slides.count - 1
                            let healthIndex = slides.count - 2
                            if index == lastIndex {
                                return startText
                            } else if index == healthIndex || index == lastIndex {
                                return allowText
                            } else {
                                return nextText
                            }
                        }()
                        Text(label)
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

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? accent : Color.white.opacity(0.4))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: index)
            }
        }
        .padding(.horizontal, 24)
    }

    private var accentPink: Color {
        Color(red: 0.878, green: 0.51, blue: 0.851)
    }

    private var appLogo: some View {
        Group {
            if let uiImage = appIconImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .white.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                Text("DOOM\nCTRL")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            }
        }
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
        let lastIndex = slides.count - 1
        let healthIndex = slides.count - 2

        if index < lastIndex {
            if index == healthIndex && !didTriggerHealthRequest {
                didTriggerHealthRequest = true
                onHealthSlide?()
            }
            withAnimation(.easeInOut) { index += 1 }
        } else {
            // Last slide
            if !didTriggerNotificationRequest {
                didTriggerNotificationRequest = true
                onNotificationSlide?()
            }
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
