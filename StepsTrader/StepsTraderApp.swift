import SwiftUI
import StoreKit
import Combine
import UserNotifications
import BackgroundTasks

// MARK: - AppDelegate (Remote Notifications)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        AppLogger.notifications.debug("📲 APNs token: \(hex)")
        // Cache so sign-out / account-deletion can call removeDeviceToken with
        // a concrete value. Stored in `.standard` (not the app group) because
        // it's user-scoped, not extension-shared. See §5.2 in CODE_AUDIT.md.
        UserDefaults.standard.set(hex, forKey: AuthenticationService.pushTokenStorageKey)
        Task {
            await SupabaseSyncService.shared.registerDeviceToken(hex)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.notifications.error("📲 APNs registration failed: \(error.localizedDescription)")
    }
}

@main
struct StepsTraderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var announcementService = AnnouncementService.shared
    #if DEBUG
    @State private var coachMarkManager = CoachMarkManager()
    #endif
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.night.rawValue
    /// Single versioned int that replaces the old 4-flag onboarding state machine
    /// (`hasSeenIntro_v3`, `hasSeenEnergySetup_v1`, `hasCompletedOnboarding_v1`,
    /// `hasMigratedOnboarding_v1`). Migration from those flags happens once on
    /// first read in `migrateOnboardingStateIfNeeded()`.
    @AppStorage("onboarding_state_v1") private var onboardingStateRaw: Int = OnboardingState.notStarted.rawValue
    @AppStorage("appLaunchCount") private var appLaunchCount: Int = 0
    @AppStorage("hasRequestedReview_v1") private var hasRequestedReview: Bool = false
    @Environment(\.requestReview) private var requestReview

    /// One-shot post-onboarding paywall. Shown exactly once per device for
    /// non-Pro users immediately after they complete onboarding. Dismissal
    /// (purchase OR cancel) marks it as shown so it never reappears.
    @State private var showPostOnboardingPaywall = false

    private var hasCompletedOnboarding: Bool {
        onboardingStateRaw >= OnboardingState.completed.rawValue
    }
    private let cleanupTimer = Timer.publish(every: AppConstants.Timing.cleanupTimerInterval, on: .main, in: .common).autoconnect()
    private let isUITest = ProcessInfo.processInfo.arguments.contains("ui-testing")

    enum OnboardingState: Int {
        case notStarted = 0
        case completed = 1
    }

    init() {
        _model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())

        // Configure RevenueCat as early as possible. Reads `REVENUECAT_API_KEY` from
        // Info.plist (which interpolates from xcconfig at build time). Anonymous user
        // is fine — we'll `logIn(supabaseUserID:)` once Sign in with Apple completes.
        //
        // ORDER NOTE: configure() runs grandfather detection which reads
        // `appLaunchCount`. The increment below happens AFTER, so the threshold
        // logic in `SubscriptionStore.detectExistingUser` is order-independent
        // (it tolerates either ordering). Don't move this around carelessly.
        let rcKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
        SubscriptionStore.shared.configure(apiKey: rcKey)

        // Install notification delegate as early as possible so taps that *launch* the app
        // are routed through our handler (onAppear can be too late).
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Count one cold launch per process. Previously incremented on every
        // scenePhase `.active` transition, which inflated the count on
        // background→foreground cycles and triggered `requestReview()` early.
        // Use UserDefaults directly because @AppStorage wrappers are not safe
        // to mutate before the View graph is materialized.
        let standardDefaults = UserDefaults.standard
        let nextLaunchCount = standardDefaults.integer(forKey: "appLaunchCount") + 1
        standardDefaults.set(nextLaunchCount, forKey: "appLaunchCount")

        // Mirror theme to app-group so the wallpaper Shortcut intent can read it reliably.
        let themeRaw = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.night.rawValue
        UserDefaults(suiteName: SharedKeys.appGroupId)?.set(themeRaw, forKey: "appTheme")

        // NOTE: UINavigationBar / UITabBar appearance proxies were previously
        // installed here in init(). They have been moved to `installLegacyBarAppearances()`
        // and are now invoked from `.onAppear` of the root scene as a documented
        // stopgap to keep the shared energy gradient visible through chrome.
        // Follow-up: replace with scoped SwiftUI modifiers
        //   - MainTabView.swift  → `.toolbarBackground(.hidden, for: .tabBar)` on the TabView
        //   - Each NavigationStack across the app
        //         → `.toolbarBackground(.hidden, for: .navigationBar)` inside the stack
        // Once those land, delete `installLegacyBarAppearances()` and its `.onAppear` call.
    }

    /// TEMP: process-wide UIKit appearance install.
    /// Tracked for removal — see init() comment for the SwiftUI replacement plan.
    /// NOTE (L9): `UI*Appearance.appearance()` proxies are process-wide. Any extension
    /// (widget, intent handler, App Clip, share extension) that imports the same shared
    /// code will inherit these defaults if the file is included in their target. Today
    /// only the main app calls `installLegacyBarAppearances()`, so extensions are not
    /// affected — but if you ever add this file to another target, gate the call with
    /// `if Bundle.main.bundleURL.pathExtension == "app"` or a target-specific compile flag.
    private static func installLegacyBarAppearances() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    /// Run the in-app coach mark tour if the user opted into it on the last
    /// onboarding slide (see `OnboardingStoriesView.finish(wantsTour:)`).
    ///
    /// Blocks until the tour completes (or returns immediately if no tour was
    /// requested). The caller — the welcome-paywall `.task` — uses this as a
    /// gate so the paywall never appears over an in-progress coach mark.
    ///
    /// Coach marks themselves are DEBUG-only (`CoachMarkManager` is wrapped
    /// in `#if DEBUG`), so in release this method is a no-op.
    @MainActor
    private func runCoachMarksIfRequested() async {
        #if DEBUG
        let defaults = UserDefaults.standard
        let wantsTour = defaults.bool(forKey: "shouldStartCoachMark")

        // Start the tour if it was requested and not already running. We read
        // & clear `shouldStartCoachMark` here (instead of in `onFinish`) so
        // the start is sequenced inside the same task that gates the paywall.
        if wantsTour && !coachMarkManager.isActive {
            defaults.removeObject(forKey: "shouldStartCoachMark")
            // Let the canvas render before the first coach mark anchors so
            // overlay positions resolve against laid-out geometry.
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            coachMarkManager.start()
        }

        // Wait for any in-progress tour to complete (covers both the fresh
        // start above and the `.task` re-firing mid-tour after a view rebuild).
        while coachMarkManager.isActive {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }

        // Breathing room between the last coach mark dismissing and whatever
        // comes next (typically the welcome paywall sliding up).
        if wantsTour {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
        }
        #endif
    }

    /// Decide whether to flip `showPostOnboardingPaywall` to `true`.
    /// Called only after `runCoachMarksIfRequested()` has returned, so the
    /// tour (if any) is guaranteed to be finished by this point.
    @MainActor
    private func presentPostOnboardingPaywallIfNeeded() async {
        guard SubscriptionGate.shouldShowPostOnboardingPaywall(isPro: model.isPro) else { return }
        // Brief cosmetic delay so the welcome screen renders before the paywall.
        try? await Task.sleep(for: .milliseconds(600))
        if Task.isCancelled { return }
        showPostOnboardingPaywall = true
    }

    /// Binding for the §5.1 PayGate-failure alert. Extracted so `body` stays
    /// inside the SwiftUI type-checker's complexity budget.
    private var payGateErrorBinding: Binding<Bool> {
        Binding(
            get: { model.payGateError != nil },
            set: { isPresented in if !isPresented { model.payGateError = nil } }
        )
    }

    var body: some Scene {
        WindowGroup {
            GlassShimmerProvider {
            ZStack {
                if hasCompletedOnboarding || isUITest {
                    Group {
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
                    }
                    // Welcome paywall — gated to non-Pro users who haven't seen
                    // it yet. Driven from a `.task` here (not from the
                    // onboarding-completion closure) so it survives the case
                    // where the user kills the app between completing onboarding
                    // and the closure's deferred presentation.
                    .task {
                        guard !isUITest else { return }

                        // 1) Run the optional in-app coach mark tour FIRST.
                        // The paywall must never appear while the tour is
                        // active — it would slide up over the coach overlay
                        // and break the flow. `runCoachMarksIfRequested` is a
                        // no-op (returns immediately) when the user declined
                        // the tour, so non-tour users don't pay any latency.
                        await runCoachMarksIfRequested()
                        if Task.isCancelled { return }

                        // 2) Wait for subscription state to settle off transient
                        // states (`.unknown` and `.loadingFromCache`) so we
                        // don't accidentally show paywall to a grandfathered
                        // or freshly-restored user before RC bootstraps.
                        // 2s budget is plenty for cached/local resolution;
                        // if RC is offline we proceed anyway based on cached
                        // `isPro` (correct: cached==true → no paywall).
                        // .task cancels when the view disappears — make sure
                        // sleeps don't keep us "alive" past that point and
                        // accidentally trigger the paywall on a stale view.
                        // (§3.7)
                        for _ in 0..<10 {
                            switch model.subscriptionStore.state {
                            case .unknown, .loadingFromCache: break
                            default:
                                await presentPostOnboardingPaywallIfNeeded()
                                return
                            }
                            try? await Task.sleep(for: .milliseconds(200))
                            if Task.isCancelled { return }
                        }
                        // Fallback after timeout: respect cached isPro.
                        await presentPostOnboardingPaywallIfNeeded()
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
                        onboardingStateRaw = OnboardingState.completed.rawValue
                        Task {
                            await model.refreshStepsIfAuthorized()
                            await model.refreshSleepIfAuthorized()
                        }

                        // NOTE: Post-onboarding paywall AND the optional coach
                        // mark tour are both triggered from the `.task` on the
                        // `hasCompletedOnboarding` branch above — that path
                        // always fires when the root flips, even if the user
                        // kills the app immediately after onboarding completes
                        // (the paywall marker is set on dismiss, so a kill-
                        // before-dismiss still allows it to appear on the next
                        // cold launch). The `.task` runs the tour first and
                        // only then evaluates the paywall, so the welcome flow
                        // is never interrupted mid-tour.
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }

            }
            // §5.1: surface PayGate-side failures (DeviceActivity monitoring couldn't
            // start after a successful purchase). Attached at the ZStack level so it
            // stays visible after PayGateView dismisses itself.
            .alert(
                String(localized: "Couldn't start the timer", comment: "PayGate failure – alert title"),
                isPresented: payGateErrorBinding
            ) {
                Button(String(localized: "OK", comment: "Generic alert dismiss button")) {
                    model.payGateError = nil
                }
            } message: {
                Text(model.payGateError ?? "")
            }
            .fullScreenCover(isPresented: $showPostOnboardingPaywall, onDismiss: {
                // Whether they purchased or skipped, we mark this user as having
                // seen the welcome paywall — they'll only encounter the paywall
                // again via in-app feature gates (1-group limit, custom activities, etc.)
                SubscriptionGate.markPostOnboardingPaywallShown()
            }) {
                PaywallView(
                    model: model,
                    store: model.subscriptionStore,
                    source: .promotion
                )
            }
            .themed(currentTheme)
            .tint(currentTheme.accentColor)
            .grayscale(0)
            #if DEBUG
            .environment(coachMarkManager)
            #endif
            .alert(isPresented: $errorManager.showErrorAlert, error: errorManager.currentError) { _ in
                Button("OK", role: .cancel) {
                    errorManager.dismiss()
                }
            } message: { error in
                Text(error.recoverySuggestion ?? "")
            }
            .alert(
                announcementService.activeAnnouncement?.title ?? "",
                isPresented: Binding(
                    get: { announcementService.activeAnnouncement != nil },
                    set: { if !$0, let a = announcementService.activeAnnouncement { announcementService.dismiss(a) } }
                )
            ) {
                Button("OK", role: .cancel) {
                    if let a = announcementService.activeAnnouncement { announcementService.dismiss(a) }
                }
            } message: {
                Text(announcementService.activeAnnouncement?.message ?? "")
            }
            .onAppear {
                // STOPGAP: install legacy bar appearances after init() instead of during it.
                // This avoids doing UIKit work in App.init while keeping the transparent
                // chrome that the shared energy gradient relies on. Remove once scoped
                // `.toolbarBackground(.hidden, for:)` modifiers are added in MainTabView
                // and the various NavigationStacks across the app.
                Self.installLegacyBarAppearances()

                // Language selection was removed — English only for v1.

                migrateOnboardingStateIfNeeded()

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
                Task { await announcementService.fetchActiveAnnouncement() }
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
            .onReceive(cleanupTimer) { _ in
                model.checkDayBoundary()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    // Skip the foregrounding refresh while bootstrap is still in flight,
                    // and on the first `.active` after cold launch (bootstrap covers it).
                    // `model.didCompleteBootstrap` flips to true at the end of `bootstrap()`,
                    // so subsequent real background→foreground cycles trigger a refresh.
                    if model.didCompleteBootstrap {
                        model.handleAppWillEnterForeground()
                    }
                    // Roll a new daily-random theme if the calendar day changed
                    // since the last roll (no-op if toggle is OFF).
                    model.applyDailyRandomThemeIfNeeded()
                    checkForHandoffToken()
                    checkForPayGateFlags()
                    requestAppReviewIfNeeded()
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
                onboardingStateRaw = OnboardingState.notStarted.rawValue
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.paygate")))
            { notification in
                AppLogger.app.debug("📱 App received PayGate notification")
                if let userInfo = notification.userInfo,
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    let g = UserDefaults.stepsTrader()
                    if let until = g.object(forKey: SharedKeys.payGateDismissedUntil) as? Date,
                       Date.now < until
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
                       Date.now < until
                    {
                        AppLogger.app.debug("🚫 PayGate local notification suppressed after dismiss")
                        return
                    }
                    let lastOpen = g.object(forKey: SharedKeys.lastAppOpenedFromStepsTrader(bundleId)) as? Date
                    if let lastOpen {
                        let elapsed = Date.now.timeIntervalSince(lastOpen)
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
            } // GlassShimmerProvider
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
           Date.now.timeIntervalSince(last) < 5 {
            return true
        }
        if let last = userDefaults.object(forKey: SharedKeys.lastGroupPayGateOpen(groupId)) as? Date,
           Date.now.timeIntervalSince(last) < 5 {
            return true
        }
        return false
    }

    private func requestAppReviewIfNeeded() {
        guard hasCompletedOnboarding, !isUITest else { return }
        // `appLaunchCount` is incremented exactly once per process launch in `init()`.
        // Use `>= 3` (not strict equality) plus a one-shot `hasRequestedReview` flag so
        // users coming from earlier buggy builds with inflated counts (10–30) still see
        // the prompt exactly once.
        guard appLaunchCount >= 3, !hasRequestedReview else { return }
        hasRequestedReview = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        }
    }

    /// Migrates the legacy 4-flag onboarding state (`hasSeenIntro_v3`,
    /// `hasSeenEnergySetup_v1`, `hasCompletedOnboarding_v1`,
    /// `hasMigratedOnboarding_v1`) into the single `onboarding_state_v1` int.
    /// Idempotent and cheap — runs on every `.onAppear` and no-ops once migrated.
    private func migrateOnboardingStateIfNeeded() {
        guard onboardingStateRaw == OnboardingState.notStarted.rawValue else { return }
        let defaults = UserDefaults.standard
        let legacyComplete = defaults.bool(forKey: "hasCompletedOnboarding_v1")
        let legacyIntro = defaults.bool(forKey: "hasSeenIntro_v3")
        let legacyEnergy = defaults.bool(forKey: "hasSeenEnergySetup_v1")
        if legacyComplete || (legacyIntro && legacyEnergy) {
            onboardingStateRaw = OnboardingState.completed.rawValue
        }
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
