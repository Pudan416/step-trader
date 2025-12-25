import SwiftUI
import Combine
import Combine

@main
struct StepsTraderApp: App {
    @StateObject private var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"

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
                    MainTabView(model: model)
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
            }
            .onAppear {
                // Ensure bootstrap runs once on first launch to request permissions
                Task { await model.bootstrap() }
                print(
                    "🎭 StepsTraderApp appeared - showPayGate: \(model.showPayGate), showQuickStatusPage: \(model.showQuickStatusPage)"
                )
                print(
                    "🎭 App state - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                print(
                    "🎭 PayGate state - showPayGate: \(model.showPayGate), targetBundleId: \(model.payGateTargetBundleId ?? "nil")"
                )
                checkForHandoffToken()
                checkForPayGateFlags()
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
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.paygate")))
            { notification in
                print("📱 App received PayGate notification")
                if let userInfo = notification.userInfo,
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    print("📱 PayGate notification - target: \(target), bundleId: \(bundleId)")
                    model.payGateTargetBundleId = bundleId
                    model.showPayGate = true
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
                    let lastOpen = UserDefaults.stepsTrader().object(forKey: "lastAppOpenedFromStepsTrader") as? Date
                    if let lastOpen {
                        let elapsed = Date().timeIntervalSince(lastOpen)
                        if elapsed < 10 {
                            print("🚫 PayGate local ignored to avoid loop (\(String(format: "%.1f", elapsed))s since last open)")
                            return
                        }
                    }
                    print("📱 Local notification PayGate - target: \(target), bundleId: \(bundleId)")
                    print("📱 Setting PayGate - showPayGate: \(model.showPayGate) -> true")
                    print("📱 Setting PayGate - targetBundleId: \(model.payGateTargetBundleId ?? "nil") -> \(bundleId)")
                    model.payGateTargetBundleId = bundleId
                    model.showPayGate = true
                    print("📱 PayGate state after setting - showPayGate: \(model.showPayGate), targetBundleId: \(model.payGateTargetBundleId ?? "nil")")
                }
            }
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
        
        print("🔍 Checking PayGate flags - shouldShowPayGate: \(shouldShowPayGate), shortcutTriggered: \(shortcutTriggered)")
        
        if shouldShowPayGate || shortcutTriggered {
            let targetBundleId = userDefaults.string(forKey: "payGateTargetBundleId")
            let shortcutTarget = userDefaults.string(forKey: "shortcutTarget")
            let target = targetBundleId ?? shortcutTarget ?? "unknown"
            
            print("🎯 Shortcut triggered PayGate for: \(target)")
            print("🎯 shouldShowPayGate: \(shouldShowPayGate), shortcutTriggered: \(shortcutTriggered)")
            
            // Map shortcut target to bundle ID if needed
            var finalBundleId = targetBundleId
            if finalBundleId == nil, let shortcutTarget = shortcutTarget {
                switch shortcutTarget.lowercased() {
                case "instagram": finalBundleId = "com.burbn.instagram"
                case "tiktok": finalBundleId = "com.zhiliaoapp.musically"
                case "youtube": finalBundleId = "com.google.ios.youtube"
                default: finalBundleId = shortcutTarget
                }
            }
            
            print("🎯 Final bundle ID: \(finalBundleId ?? "nil")")
            model.payGateTargetBundleId = finalBundleId
            model.showPayGate = true
            
            // Clear the flags
            userDefaults.removeObject(forKey: "shouldShowPayGate")
            userDefaults.removeObject(forKey: "payGateTargetBundleId")
            userDefaults.removeObject(forKey: "shortcutTriggered")
            userDefaults.removeObject(forKey: "shortcutTarget")
            userDefaults.removeObject(forKey: "shortcutTriggerTime")
            
            print("🎯 PayGate should now be visible!")
        } else {
            print("🔍 No PayGate flags found")
        }
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
                    let totalSteps = Int(model.stepsToday)
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

    var body: some View {
        VStack(spacing: 12) {
            StepBalanceCard(
                remainingSteps: remainingStepsToday,
                totalSteps: Int(model.stepsToday)
            )
            .padding(.horizontal)
            TabView(selection: $selection) {
                StatusView(model: model)
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text(loc(appLanguage, "Status", "Статус"))
                    }
                    .tag(0)

                AppsPage(model: model, automationApps: SettingsView.automationAppsStatic, tariffs: Tariff.allCases)
                    .tabItem {
                        Image(systemName: "square.grid.2x2")
                        Text(loc(appLanguage, "Modules", "Модули"))
                    }
                    .tag(1)
                
                FAQPage(model: model)
                    .tabItem {
                        Image(systemName: "questionmark.circle")
                        Text(loc(appLanguage, "FAQ", "FAQ"))
                    }
                    .tag(2)
                
                SettingsView(model: model)
                    .tabItem {
                        Image(systemName: "gear")
                        Text(loc(appLanguage, "Settings", "Настройки"))
                    }
                    .tag(3)
            }
            .gesture(
                DragGesture().onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width > threshold {
                        selection = max(0, selection - 1)
                    } else if value.translation.width < -threshold {
                        selection = min(3, selection + 1)
                    }
                }
            )
        }
    }
    
    private var remainingStepsToday: Int {
        max(0, Int(model.stepsToday) - model.spentStepsToday)
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
                        Text("\(Int(model.stepsToday))")
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
                        Text("\(model.stepsBalance) steps")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(
                                model.stepsBalance >= model.entryCostSteps ? .green : .red)
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
    @State private var didForfeit: Bool = false
    @State private var timedOut: Bool = false
    private let totalCountdown: Int = 10
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.1), .purple.opacity(0.2)], startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                VStack(spacing: 16) {
                    Text("🎯")
                        .font(.system(size: 60))
                    
                    Text("Steps Trader")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Pay with steps to enter")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 20) {
                    if !timedOut {
                        let bundleId = model.payGateTargetBundleId
                        let settings = model.unlockSettings(for: bundleId)
                        let hasPass = model.hasDayPass(for: bundleId)
                        let isFree = settings.entryCostSteps == 0
                        let canPayEntry = hasPass || isFree || model.stepsBalance >= settings.entryCostSteps
                        let canPayDayPass =
                            bundleId != nil
                            && !hasPass
                            && !isFree
                            && model.stepsBalance >= settings.dayPassCostSteps
                        
                        // Баланс шагов
                        HStack {
                            Text("Step balance:")
                                .font(.title2)
                            Spacer()
                            Text("\(model.stepsBalance)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(
                                    hasPass || model.stepsBalance >= settings.entryCostSteps ? .green : .red)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                        // Countdown timer with ring
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                                    .frame(width: 90, height: 90)
                                Circle()
                                    .trim(from: 0, to: CGFloat(max(0, countdown)) / CGFloat(totalCountdown))
                                    .stroke(
                                        AngularGradient(
                                            gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                                            center: .center),
                                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 90, height: 90)
                                    .animation(.easeInOut(duration: 0.2), value: countdown)
                                Text("\(max(0, countdown))s")
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                            Text("Pay within 10 seconds to enter.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        if let bundleId {
                            if hasPass || isFree {
                                Button("Open \(getAppDisplayName(bundleId)) for free") {
                                    print("🎯 PayGate: User clicked open with day pass for \(bundleId)")
                                    guard countdown > 0, !didForfeit else {
                                        print("🚫 PayGate: Timer expired, ignoring open action")
                                        return
                                    }
                                    didForfeit = true
                                    Task {
                                        await model.handlePayGatePayment(for: bundleId)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .font(.headline)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                Text("Day pass active today")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                            let entryTitle = settings.entryCostSteps == 0
                                ? "Open \(getAppDisplayName(bundleId)) for free"
                                : "Pay \(settings.entryCostSteps) steps & open \(getAppDisplayName(bundleId))"
                                Button(entryTitle) {
                                    print("🎯 PayGate: User clicked pay button for \(bundleId)")
                                    guard countdown > 0, !didForfeit else {
                                        print("🚫 PayGate: Timer expired, ignoring pay action")
                                        return
                                    }

                                    didForfeit = true
                                    // Anti-loop check for PayGate button clicks
                                    let userDefaults = UserDefaults.stepsTrader()
                                    let now = Date()
                                    
                                    if let lastPayGateAction = userDefaults.object(forKey: "lastPayGateAction") as? Date {
                                        let timeSinceLastAction = now.timeIntervalSince(lastPayGateAction)
                                        if timeSinceLastAction < 1.0 {
                                            print("🚫 PayGate button clicked too recently (\(String(format: "%.1f", timeSinceLastAction))s), ignoring to prevent loop")
                                            return
                                        }
                                    }
                                    
                                    Task {
                                        await model.handlePayGatePayment(for: bundleId)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(
                                    canPayEntry && countdown > 0 && !didForfeit
                                        ? Color.blue : Color.gray
                                )
                                .foregroundColor(.white)
                                .font(.headline)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .disabled(!canPayEntry || countdown <= 0 || didForfeit)
                                
                                let dayPassTitle = "Pay \(settings.dayPassCostSteps) steps for day pass"
                                Button(dayPassTitle) {
                                    print("🌞 PayGate: User clicked day pass for \(bundleId)")
                                    guard countdown > 0, !didForfeit else {
                                        print("🚫 PayGate: Timer expired, ignoring day pass action")
                                        return
                                    }
                                    didForfeit = true
                                    Task { @MainActor in
                                        let success = model.payForDayPass(for: bundleId)
                                        if success {
                                            await model.handlePayGatePayment(for: bundleId)
                                        } else {
                                            model.message = "❌ Not enough steps for day pass (\(settings.dayPassCostSteps))"
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    canPayDayPass ? Color.orange : Color.gray
                                )
                                .foregroundColor(.white)
                                .font(.headline)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .disabled(!canPayDayPass || countdown <= 0 || didForfeit)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            if let bundleId = model.payGateTargetBundleId {
                                Text("You missed opening \(getAppDisplayName(bundleId)).")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                let settings = model.unlockSettings(for: bundleId)
                                Text("At least you saved \(settings.entryCostSteps) steps.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("You missed the window.")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    }
                    
                    Button("Close") {
                        didForfeit = true
                        model.dismissPayGate()
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
        .onAppear {
            countdown = totalCountdown
            didForfeit = false
            timedOut = false
        }
        .onReceive(countdownTimer) { _ in
            handleCountdownTick()
        }
        .onDisappear {
            didForfeit = true
        }
    }
}
extension PayGateView {
    private func handleCountdownTick() {
        guard model.showPayGate, !didForfeit else { return }
        if countdown > 0 {
            countdown -= 1
        }
        if countdown == 0 {
            didForfeit = true
            timedOut = true
            if let bundleId = model.payGateTargetBundleId {
                print("⏰ PayGate countdown expired for \(bundleId)")
            }
            Task { @MainActor in
                model.message = "⏰ Time expired. Please re-run the shortcut to try again."
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
