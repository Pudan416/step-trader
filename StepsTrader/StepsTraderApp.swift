import SwiftUI
import Combine
import Combine

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
                        .onAppear {
                            print("🎯 FocusGateView appeared - target: \(model.focusGateTargetBundleId ?? "nil")")
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
                    "🎭 StepsTraderApp appeared - showFocusGate: \(model.showFocusGate), showQuickStatusPage: \(model.showQuickStatusPage)"
                )
                print(
                    "🎭 App state - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                print(
                    "🎭 FocusGate state - showFocusGate: \(model.showFocusGate), targetBundleId: \(model.focusGateTargetBundleId ?? "nil")"
                )
                checkForHandoffToken()
                checkForFocusGateFlags()
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
                checkForFocusGateFlags()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.refresh")))
            { _ in
                model.handleAppWillEnterForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.focusgate")))
            { notification in
                print("📱 App received FocusGate notification")
                if let userInfo = notification.userInfo,
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    print("📱 FocusGate notification - target: \(target), bundleId: \(bundleId)")
                    model.focusGateTargetBundleId = bundleId
                    model.showFocusGate = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.local.focusgate")))
            { notification in
                print("📱 App received local notification")
                if let userInfo = notification.userInfo,
                   let action = userInfo["action"] as? String,
                   action == "focusgate",
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    print("📱 Local notification FocusGate - target: \(target), bundleId: \(bundleId)")
                    print("📱 Setting FocusGate - showFocusGate: \(model.showFocusGate) -> true")
                    print("📱 Setting FocusGate - targetBundleId: \(model.focusGateTargetBundleId ?? "nil") -> \(bundleId)")
                    model.focusGateTargetBundleId = bundleId
                    model.showFocusGate = true
                    print("📱 FocusGate state after setting - showFocusGate: \(model.showFocusGate), targetBundleId: \(model.focusGateTargetBundleId ?? "nil")")
                }
            }
        }
    }

    private func checkForHandoffToken() {
        let userDefaults = UserDefaults.stepsTrader()

        print("🔍 Checking for handoff token...")
        print(
            "🔍 Current app state - showFocusGate: \(model.showFocusGate), showHandoffProtection: \(model.showHandoffProtection)"
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
    
    private func checkForFocusGateFlags() {
        let userDefaults = UserDefaults.stepsTrader()
        
        // Check if shortcut set flags to show FocusGate
        let shouldShowFocusGate = userDefaults.bool(forKey: "shouldShowFocusGate")
        let shortcutTriggered = userDefaults.bool(forKey: "shortcutTriggered")
        
        print("🔍 Checking FocusGate flags - shouldShowFocusGate: \(shouldShowFocusGate), shortcutTriggered: \(shortcutTriggered)")
        
        if shouldShowFocusGate || shortcutTriggered {
            let targetBundleId = userDefaults.string(forKey: "focusGateTargetBundleId")
            let shortcutTarget = userDefaults.string(forKey: "shortcutTarget")
            let target = targetBundleId ?? shortcutTarget ?? "unknown"
            
            print("🎯 Shortcut triggered FocusGate for: \(target)")
            print("🎯 shouldShowFocusGate: \(shouldShowFocusGate), shortcutTriggered: \(shortcutTriggered)")
            
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
            model.focusGateTargetBundleId = finalBundleId
            model.showFocusGate = true
            
            // Clear the flags
            userDefaults.removeObject(forKey: "shouldShowFocusGate")
            userDefaults.removeObject(forKey: "focusGateTargetBundleId")
            userDefaults.removeObject(forKey: "shortcutTriggered")
            userDefaults.removeObject(forKey: "shortcutTarget")
            userDefaults.removeObject(forKey: "shortcutTriggerTime")
            
            print("🎯 FocusGate should now be visible!")
        } else {
            print("🔍 No FocusGate flags found")
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
                    let cost = max(1, model.entryCostSteps)
                    let available = max(0, totalSteps - spent)
                    let opensLeft = available / cost

                    Text("Entries left today: \(opensLeft)")
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

    var body: some View {
            TabView {
                StatusView(model: model)
                    .tabItem {
                    Image(systemName: "chart.bar.fill")
                        Text("Status")
                    }
                
                SettingsView(model: model)
                    .tabItem {
                    Image(systemName: "gear")
                        Text("Settings")
                }
        }
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

// MARK: - FocusGateView
struct FocusGateView: View {
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
                        // Баланс шагов
                        HStack {
                            Text("Step balance:")
                                .font(.title2)
                            Spacer()
                            Text("\(model.stepsBalance)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(
                                    model.stepsBalance >= model.entryCostSteps ? .green : .red)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                        // Стоимость входа
                        HStack {
                            Text("Entry cost:")
                                .font(.title2)
                            Spacer()
                            Text("\(model.entryCostSteps) steps")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
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
                        
                        if let bundleId = model.focusGateTargetBundleId {
                            Button("Pay and open \(getAppDisplayName(bundleId))") {
                                print("🎯 FocusGate: User clicked pay button for \(bundleId)")
                                guard countdown > 0, !didForfeit else {
                                    print("🚫 FocusGate: Timer expired, ignoring pay action")
                                    return
                                }

                                didForfeit = true
                                // Anti-loop check for FocusGate button clicks
                                let userDefaults = UserDefaults.stepsTrader()
                                let now = Date()
                                
                                if let lastFocusGateAction = userDefaults.object(forKey: "lastFocusGateAction") as? Date {
                                    let timeSinceLastAction = now.timeIntervalSince(lastFocusGateAction)
                                    if timeSinceLastAction < 1.0 {
                                        print("🚫 FocusGate button clicked too recently (\(String(format: "%.1f", timeSinceLastAction))s), ignoring to prevent loop")
                                        return
                                    }
                                }
                                
                                Task {
                                    await model.handleFocusGatePayment(for: bundleId)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                model.stepsBalance >= model.entryCostSteps && countdown > 0 && !didForfeit
                                    ? Color.blue : Color.gray
                            )
                            .foregroundColor(.white)
                            .font(.headline)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .disabled(model.stepsBalance < model.entryCostSteps || countdown <= 0 || didForfeit)
                        }
                    } else {
                        VStack(spacing: 12) {
                            if let bundleId = model.focusGateTargetBundleId {
                                Text("You missed opening \(getAppDisplayName(bundleId)).")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                Text("At least you saved \(model.entryCostSteps) steps.")
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
extension FocusGateView {
    private func handleCountdownTick() {
        guard model.showFocusGate, !didForfeit else { return }
        if countdown > 0 {
            countdown -= 1
        }
        if countdown == 0 {
            didForfeit = true
            timedOut = true
            if let bundleId = model.focusGateTargetBundleId {
                print("⏰ FocusGate countdown expired for \(bundleId)")
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
