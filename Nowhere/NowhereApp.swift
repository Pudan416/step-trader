import SwiftUI
import StoreKit
import Combine
import UserNotifications
import BackgroundTasks
import WidgetKit

struct Task7UITestAccessibilityConfiguration: Equatable {
    let dynamicTypeSize: DynamicTypeSize?
    let usesIncreasedContrast: Bool

    init(arguments: [String], environment: [String: String]) {
        guard arguments.contains("ui-testing-task7") else {
            dynamicTypeSize = nil
            usesIncreasedContrast = false
            return
        }

        switch environment["TASK7_DYNAMIC_TYPE_SIZE"] {
        case "accessibility1": dynamicTypeSize = .accessibility1
        case "accessibility2": dynamicTypeSize = .accessibility2
        case "accessibility3": dynamicTypeSize = .accessibility3
        case "accessibility4": dynamicTypeSize = .accessibility4
        case "accessibility5": dynamicTypeSize = .accessibility5
        default: dynamicTypeSize = nil
        }
        usesIncreasedContrast = environment["TASK7_INCREASED_CONTRAST"] == "1"
    }

    static var current: Self {
        Self(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func name(for dynamicTypeSize: DynamicTypeSize) -> String {
        switch dynamicTypeSize {
        case .xSmall: "xSmall"
        case .small: "small"
        case .medium: "medium"
        case .large: "large"
        case .xLarge: "xLarge"
        case .xxLarge: "xxLarge"
        case .xxxLarge: "xxxLarge"
        case .accessibility1: "accessibility1"
        case .accessibility2: "accessibility2"
        case .accessibility3: "accessibility3"
        case .accessibility4: "accessibility4"
        case .accessibility5: "accessibility5"
        @unknown default: "unknown"
        }
    }
}

private struct Task7UITestAccessibilityModifier: ViewModifier {
    let configuration: Task7UITestAccessibilityConfiguration

    @Environment(\.dynamicTypeSize) private var inheritedDynamicTypeSize

    func body(content: Content) -> some View {
        content
            .environment(
                \.dynamicTypeSize,
                configuration.dynamicTypeSize ?? inheritedDynamicTypeSize
            )
    }
}

// MARK: - AppDelegate (Remote Notifications)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }

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
struct NowhereApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("ui-testing") &&
                ProcessInfo.processInfo.arguments.contains("ui-testing-ticket-settings") {
                TicketSettingsUITestFixtureView()
            } else {
                NowhereProductionRoot()
            }
            #else
            NowhereProductionRoot()
            #endif
        }
    }
}

private struct NowhereProductionRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var errorManager = ErrorManager.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var announcementService = AnnouncementService.shared
    @State private var onboardingState = CanvasOnboardingState.shared
    @State private var hasStartedBootstrap = false
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("appLaunchCount") private var appLaunchCount: Int = 0
    @AppStorage("hasRequestedReview_v1") private var hasRequestedReview: Bool = false
    @Environment(\.requestReview) private var requestReview

    /// Currently presented feature tip (wallpaper / widgets nudge), or `nil`.
    /// Driven by `presentFeatureTipIfNeeded()` on scenePhase `.active`.
    @State private var activeFeatureTip: FeatureTip?
    @State private var presentedFeatureTip: FeatureTip?
    @State private var acceptedFeatureTipRoute: FeatureTipSettingsPage?
    @State private var featureTipTask: Task<Void, Never>?
    @State private var hasRequestedReviewThisSession = false
    @State private var pendingWidgetUnlock: (request: WidgetUnlockRequest, receivedAt: Date)?
    @State private var isProcessingWidgetUnlock = false

    /// At most one feature tip per process lifetime — repeated
    /// background→foreground cycles must not stack tips in one session.
    @State private var hasPresentedFeatureTipThisSession = false

    private var hasCompletedOnboarding: Bool { onboardingState.isCompleted }
    private var canPresentSessionUI: Bool {
        hasCompletedOnboarding && !CanvasTour.shared.isActive
    }
    private var isPreparingAutomaticOnboarding: Bool {
        allowsAutomaticCanvasOnboarding && !onboardingState.isCompleted
            && model.isBootstrapping && !CanvasTour.shared.isActive
    }
    private var hasBlockingSessionOverlay: Bool {
        guard canPresentSessionUI, !isUITest else { return false }
        if model.userEconomyStore.showPayGate { return true }
        if model.showHandoffProtection,
           let token = model.handoffToken,
           token.targetBundleId != "com.burbn.instagram" { return true }
        #if DEBUG
        return model.showQuickStatusPage
        #else
        return false
        #endif
    }
    private let cleanupTimer = Timer.publish(every: AppConstants.Timing.cleanupTimerInterval, on: .main, in: .common).autoconnect()
    private let isUITest = ProcessInfo.processInfo.arguments.contains("ui-testing")

    private var allowsAutomaticCanvasOnboarding: Bool {
        #if DEBUG
        !isUITest || ProcessInfo.processInfo.arguments.contains("canvas-onboarding-test-first-launch")
            || ProcessInfo.processInfo.arguments.contains("canvas-onboarding-enable-first-launch")
        #else
        !isUITest
        #endif
    }

    init() {
        let processArguments = ProcessInfo.processInfo.arguments

        if processArguments.contains("ui-testing-me-static-poster") {
            let dayKey = AppModel.dayKey(for: Date.now)
            var canvas = DayCanvas(dayKey: dayKey)
            let fixtureDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
            canvas.elements = [
                CanvasElement(
                    id: UUID(uuidString: "A83479D2-BEFA-40C8-AB45-A951FF2A7B0F")!,
                    kind: .circle,
                    optionId: "ui-test-static-poster",
                    label: "Static poster fixture",
                    hexColor: "#B58AE8",
                    hexColor2: "#4EC5D4",
                    size: 0.24,
                    basePosition: CGPoint(x: 0.5, y: 0.5),
                    phaseOffset: 0.75,
                    driftSpeed: 2,
                    driftAmplitude: 0.12,
                    pulseFrequency: 2.5,
                    pulseAmplitude: 0.1,
                    rotationSpeed: 1,
                    opacity: 0.9,
                    createdAt: fixtureDate,
                    shapeSeed: 42,
                    lastEditedAt: fixtureDate,
                    frozenShapeType: .snowflake
                )
            ]
            canvas.sleepPoints = 14
            canvas.stepsPoints = 16
            canvas.inkEarned = 30
            canvas.gradientStyle = GradientStyle.mesh.rawValue
            canvas.gradientPalette = GradientPalette.aurora.rawValue
            canvas.hasStepsData = true
            canvas.hasSleepData = true
            canvas.lastModified = fixtureDate
            CanvasStorageService.shared.saveCanvas(canvas)
        }

        // Task 7 screenshot scenarios mutate today's additions. Xcode reuses the
        // installed app container across UI-test methods, so without resetting
        // this fixture-only state an "all used" test empties the palette for
        // every test that follows it in the full suite.
        if ProcessInfo.processInfo.arguments.contains("ui-testing-task7") {
            UserDefaults.nowhere().removeObject(forKey: SharedKeys.todayAdditions)
            CanvasStorageService.shared.deleteCanvas(
                for: AppModel.dayKey(for: Date.now)
            )
        }
        if processArguments.contains("ui-testing-happening-editor"),
           processArguments.contains("ui-testing-task7") {
            let defaults = UserDefaults.nowhere()
            defaults.removeObject(forKey: SharedKeys.happeningPaletteSelection)
            defaults.removeObject(forKey: SharedKeys.happeningFrequentPalette)
            defaults.removeObject(forKey: SharedKeys.happeningCatalog)
        }
        if ProcessInfo.processInfo.arguments.contains("ui-testing-settings") {
            let appearance = UserDefaults.standard
            appearance.set(CanvasVisualStyle.legacy.rawValue, forKey: SharedKeys.canvasVisualStyle)
            appearance.set(GradientStyle.radial.rawValue, forKey: SharedKeys.gradientStyle)
            appearance.set(GradientPalette.warmSunset.rawValue, forKey: SharedKeys.gradientPalette)
            appearance.set(false, forKey: SharedKeys.dailyRandomThemeEnabled)
            let defaults = UserDefaults.nowhere()
            defaults.set(10_000.0, forKey: SharedKeys.userStepsTarget)
            defaults.set(8.0, forKey: SharedKeys.userSleepTarget)
            defaults.set(0, forKey: SharedKeys.dayEndHour)
            defaults.set(0, forKey: SharedKeys.dayEndMinute)
        }
        _model = StateObject(wrappedValue: DIContainer.shared.applicationModel)

        // Register the MetricKit subscriber early so diagnostics aggregated since
        // the last run (crashes/hangs/exceptions) are delivered and reported.
        DiagnosticsManager.shared.start()

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
        let themeRaw = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue
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

    /// Binding for the §5.1 PayGate-failure alert. Extracted so `body` stays
    /// inside the SwiftUI type-checker's complexity budget.
    private var payGateErrorBinding: Binding<Bool> {
        Binding(
            get: { canPresentSessionUI && model.payGateError != nil },
            set: { isPresented in if !isPresented { model.payGateError = nil } }
        )
    }

    var body: some View {
        Group {
            #if DEBUG
            // Debug-only shortcut: `-uiLab dayObjects` opens the experiment
            // straight from launch. Driving the settings path with synthetic
            // taps is unreliable enough that verifying a shader visually
            // otherwise costs more than building it.
            if let lab = ExperimentalLabRoute.current {
                NavigationStack { lab.view }
            } else {
                appBody
            }
            #else
            appBody
            #endif
        }
        .font(AppFonts.body)
        .modifier(NowhereLaunchPresentation())
        .modifier(TodayCanvasBackdropHost(model: model))
        .onOpenURL { handleWidgetOpenApp($0) }
        .onChange(of: model.didCompleteBootstrap) { _, ready in
            if ready { processPendingWidgetUnlock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { processPendingWidgetUnlock() }
        }
    }

    @ViewBuilder
    private var appBody: some View {
            GlassShimmerProvider {
            ZStack {
                // The Canvas tour anchors to the real app throughout first launch.
                MainTabView(model: model, allowsCanvasTipEngagement: canPresentSessionUI && activeFeatureTip == nil, theme: currentTheme)
                    .allowsHitTesting(!hasBlockingSessionOverlay && !isPreparingAutomaticOnboarding)
                    .accessibilityHidden(hasBlockingSessionOverlay || isPreparingAutomaticOnboarding)

                if isPreparingAutomaticOnboarding {
                    ProgressView()
                        .accessibilityLabel(String(localized: "Preparing your canvas"))
                }

                if canPresentSessionUI && !isUITest {
                    if model.userEconomyStore.showPayGate {
                        PayGateView(model: model)
                            .onAppear {
                                AppLogger.app.debug("🎯 PayGateView appeared - target group: \(model.userEconomyStore.payGateTargetGroupId ?? "nil")")
                            }
                    } else if model.showQuickStatusPage {
                        #if DEBUG
                        QuickStatusView(model: model)
                        #endif
                    }

                    if model.showHandoffProtection, let token = model.handoffToken,
                       token.targetBundleId != "com.burbn.instagram" {
                        HandoffProtectionView(model: model, token: token) {
                            model.handleHandoffContinue()
                        } onCancel: {
                            model.handleHandoffCancel()
                        }
                    }
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
            .sheet(item: $activeFeatureTip, onDismiss: finishFeatureTip) { tip in
                FeatureTipSheet(tip: tip, onContinue: {
                    FeatureTipStore.shared.recordAcceptance(tip)
                    acceptedFeatureTipRoute = tip.settingsPage
                })
                .onAppear {
                    guard presentedFeatureTip == nil else { return }
                    presentedFeatureTip = tip
                    hasPresentedFeatureTipThisSession = true
                    FeatureTipStore.shared.recordPresentation(tip)
                }
            }
            .themed(currentTheme)
            .grayscale(0)
            .modifier(
                Task7UITestAccessibilityModifier(
                    configuration: .current
                )
            )
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
                    get: { canPresentSessionUI && !isUITest && announcementService.activeAnnouncement != nil },
                    set: { if !$0, canPresentSessionUI, !isUITest, let a = announcementService.activeAnnouncement { announcementService.dismiss(a) } }
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

                // Setup notification handling ASAP so model is set for delegate callbacks
                setupNotificationHandling()

                // Startup reads existing authorization only. The tour and Settings
                // own explicit permission requests, including after choosing Later.
                if !hasStartedBootstrap {
                    hasStartedBootstrap = true
                    Task { @MainActor in
                        await model.bootstrap(requestPermissions: false)
                        guard !Task.isCancelled else { return }
                        startAutomaticCanvasOnboardingIfReady()
                        checkForPayGateFlags()
                        checkForHandoffToken()
                        processPendingWidgetUnlock()
                    }
                }
                Task { await announcementService.fetchActiveAnnouncement() }
                AppLogger.app.debug(
                    "🎭 NowhereApp appeared - showPayGate: \(model.userEconomyStore.showPayGate), showQuickStatusPage: \(model.showQuickStatusPage)"
                )
                AppLogger.app.debug(
                    "🎭 App state - showHandoffProtection: \(model.showHandoffProtection), handoffToken: \(model.handoffToken?.targetAppName ?? "nil")"
                )
                AppLogger.app.debug(
                    "🎭 PayGate state - showPayGate: \(model.userEconomyStore.showPayGate), targetGroupId: \(model.userEconomyStore.payGateTargetGroupId ?? "nil")"
                )
                checkForHandoffToken()
            }
            .onChange(of: model.isBootstrapping) { _, preparingLocalState in
                if !preparingLocalState { startAutomaticCanvasOnboardingIfReady() }
            }
            .onChange(of: onboardingState.isCompleted) { _, completed in
                guard completed else {
                    activeFeatureTip = nil
                    return
                }
                Task { @MainActor in
                    await model.refreshStepsIfAuthorized()
                    await model.refreshSleepIfAuthorized()
                    checkForPayGateFlags()
                    checkForHandoffToken()
                    processPendingWidgetUnlock()
                }
            }
            .onChange(of: CanvasTour.shared.isActive) { _, active in
                if active {
                    // An explicitly started replay must consume the pending
                    // automatic start even if bootstrap is still awaiting data.
                    _ = onboardingState.claimAutomaticStart()
                    activeFeatureTip = nil
                } else {
                    checkForPayGateFlags()
                    checkForHandoffToken()
                    processPendingWidgetUnlock()
                }
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
                    // We never show a feature tip in the same session as the
                    // App Store review prompt.
                    let didRequestReview = requestAppReviewIfNeeded()
                    if !didRequestReview {
                        presentFeatureTipIfNeeded()
                    }
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
                CanvasTour.shared.start(source: "replay")
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("com.steps.trader.paygate")))
            { notification in
                AppLogger.app.debug("📱 App received PayGate notification")
                if let userInfo = notification.userInfo,
                   let target = userInfo["target"] as? String,
                   let bundleId = userInfo["bundleId"] as? String {
                    let g = UserDefaults.nowhere()
                    if let until = g.object(forKey: SharedKeys.payGateDismissedUntil) as? Date,
                       Date.now < until
                    {
                        AppLogger.app.debug("🚫 PayGate notification suppressed after dismiss")
                        return
                    }
                    AppLogger.app.debug("📱 PayGate notification - target: \(target), bundleId: \(bundleId)")
                    Task { @MainActor in
                        guard canPresentSessionUI, !isUITest else {
                            g.set(true, forKey: SharedKeys.shouldShowPayGate)
                            g.removeObject(forKey: SharedKeys.payGateTargetGroupId)
                            g.set(bundleId, forKey: SharedKeys.payGateTargetBundleId)
                            g.set(Date.now, forKey: SharedKeys.payGateRequestedAt)
                            return
                        }
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
                    let g = UserDefaults.nowhere()
                    if let until = g.object(forKey: SharedKeys.payGateDismissedUntil) as? Date,
                       Date.now < until
                    {
                        AppLogger.app.debug("🚫 PayGate local notification suppressed after dismiss")
                        return
                    }
                    let lastOpen = g.object(forKey: SharedKeys.lastAppOpenedFromNowhere(bundleId)) as? Date
                    if let lastOpen {
                        let elapsed = Date.now.timeIntervalSince(lastOpen)
                        if elapsed < 10 {
                                AppLogger.app.debug("PayGate local ignored for \(bundleId) to avoid loop (\(elapsed, format: .fixed(precision: 1))s since last open)")
                            return
                        }
                    }
                    AppLogger.app.debug("📱 Local notification PayGate - target: \(target), bundleId: \(bundleId)")
                    Task { @MainActor in
                        guard canPresentSessionUI, !isUITest else {
                            g.set(true, forKey: SharedKeys.shouldShowPayGate)
                            g.removeObject(forKey: SharedKeys.payGateTargetGroupId)
                            g.set(bundleId, forKey: SharedKeys.payGateTargetBundleId)
                            g.set(Date.now, forKey: SharedKeys.payGateRequestedAt)
                            return
                        }
                        model.openPayGateForBundleId(bundleId)
                        AppLogger.app.debug("📱 PayGate state after setting - showPayGate: \(model.userEconomyStore.showPayGate), targetGroupId: \(model.userEconomyStore.payGateTargetGroupId ?? "nil")")
                    }
                }
            }
            .background(currentTheme.backgroundColor)
            .preferredColorScheme(currentTheme.colorScheme)
            } // GlassShimmerProvider
    }

    private func handleWidgetOpenApp(_ url: URL) {
        SharedKeys.recordWidgetInteraction("URL received scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil") state=\(UIApplication.shared.applicationState.rawValue)", source: "app")
        if url.scheme == "steps-trader", url.host == "unlock" {
            guard !isProcessingWidgetUnlock, pendingWidgetUnlock == nil,
                  let request = WidgetUnlockRequest.consume(url, defaults: SharedKeys.appGroupDefaults()) else {
                SharedKeys.recordWidgetInteraction("unlock URL rejected or already processing", source: "app")
                return
            }
            pendingWidgetUnlock = (request, Date())
            processPendingWidgetUnlock()
            return
        }
        // §5.7: validate `bundleId` against a strict reverse-DNS pattern before
        // looking it up. Caps the input shape to what real bundle IDs look like
        // (`com.example.app`, optionally with dots and hyphens) so unexpected
        // strings can't reach logs or any future telemetry through this path.
        let bundleIdPattern = #"^[a-zA-Z0-9](?:[a-zA-Z0-9\-]*\.)*[a-zA-Z0-9][a-zA-Z0-9\-]*$"#
        guard url.scheme == "steps-trader", url.host == "openapp",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let bundleId = components.queryItems?.first(where: { $0.name == "bundleId" })?.value,
              bundleId.range(of: bundleIdPattern, options: .regularExpression) != nil,
              TargetResolver.canOpen(bundleId: bundleId)
        else {
            SharedKeys.recordWidgetInteraction("URL rejected by openapp route validation", source: "app")
            return
        }

        Task { @MainActor in
            SharedKeys.recordWidgetInteraction("opening registered target=\(bundleId) state=\(UIApplication.shared.applicationState.rawValue)", source: "app")
            AppLauncher.open(bundleId: bundleId) { success in
                SharedKeys.recordWidgetInteraction("target open result=\(success) target=\(bundleId) state=\(UIApplication.shared.applicationState.rawValue)", source: "app")
            }
        }
    }

    private func startAutomaticCanvasOnboardingIfReady() {
        guard !model.isBootstrapping, allowsAutomaticCanvasOnboarding,
              !CanvasTour.shared.isActive, onboardingState.claimAutomaticStart() else { return }
        CanvasTour.shared.start(source: "firstLaunch")
    }

    private func processPendingWidgetUnlock() {
        guard model.didCompleteBootstrap, scenePhase == .active,
              canPresentSessionUI, !isUITest,
              !isProcessingWidgetUnlock, let pending = pendingWidgetUnlock else { return }
        pendingWidgetUnlock = nil
        guard Date().timeIntervalSince(pending.receivedAt) < 120 else {
            SharedKeys.recordWidgetInteraction("unlock request expired during startup", source: "app")
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        isProcessingWidgetUnlock = true
        Task { @MainActor in
            defer {
                isProcessingWidgetUnlock = false
                model.writeWidgetSnapshot()
                WidgetCenter.shared.reloadAllTimelines()
            }
            let request = pending.request
            guard let window = AccessWindow(rawValue: request.windowRaw),
                  let group = model.ticketGroups.first(where: { $0.id == request.groupId }),
                  group.settings.familyControlsModeEnabled,
                  group.enabledIntervals.contains(window) else {
                SharedKeys.recordWidgetInteraction("unlock rejected: group or interval no longer active", source: "app")
                return
            }
            model.checkDayBoundary()
            // AuthorizationCenter starts as notDetermined in each process. Refresh
            // it through the supported request API in the foreground main app.
            do {
                try await model.familyControlsService.requestAuthorization()
            } catch {
                model.payGateError = UsageBudgetMonitoringError.notAuthorized.userFacingMessage
                SharedKeys.recordWidgetInteraction("unlock authorization failed", source: "app")
                return
            }
            model.checkDayBoundary()
            guard model.totalStepsBalance >= group.cost(for: window) else {
                model.payGateError = String(localized: "Not enough colors")
                SharedKeys.recordWidgetInteraction("unlock refused: insufficient current balance", source: "app")
                return
            }
            SharedKeys.recordWidgetInteraction("unlock in app group=\(group.id) authorized=\(model.familyControlsService.isAuthorized)", source: "app")
            guard await model.handlePayGatePaymentForGroup(groupId: group.id, window: window, costOverride: nil) else {
                SharedKeys.recordWidgetInteraction("unlock purchase failed group=\(group.id)", source: "app")
                return
            }
            SharedKeys.recordWidgetInteraction("unlock completed group=\(group.id) minutes=\(window.minutes) balance=\(model.totalStepsBalance)", source: "app")
            // Purchasing time never launches the target. Its card remains the
            // separate, explicit launch action (including cached URL widgets).

        }
    }

    private func checkForHandoffToken() {
        guard canPresentSessionUI, !isUITest else { return }
        let userDefaults = UserDefaults.nowhere()

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
        guard canPresentSessionUI, !isUITest, model.didCompleteBootstrap else { return }
        let userDefaults = UserDefaults.nowhere()
        
        // Check if flags set to show PayGate (only set by notification intent)
        let shouldShowPayGate = userDefaults.bool(forKey: SharedKeys.shouldShowPayGate)
        
        guard shouldShowPayGate else {
            clearPayGateFlags(userDefaults)
            return
        }

        let requestedAt = userDefaults.object(forKey: SharedKeys.payGateRequestedAt) as? Date
        guard AppModel.isPayGateRequestFresh(requestedAt: requestedAt) else {
            AppLogger.app.debug("⌛️ PayGate flags ignored: request older than \(Int(AppModel.payGateRequestMaxAge / 60)) min")
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
        // Cleared with the rest of the request, so a consumed flag cannot leave its
        // timestamp behind for the next one to be judged against.
        userDefaults.removeObject(forKey: SharedKeys.payGateRequestedAt)
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

    /// Review requests share the global cooldown and reserve this process session.
    @discardableResult
    private func requestAppReviewIfNeeded() -> Bool {
        guard canPresentSessionUI, !isUITest, scenePhase == .active,
              !hasRequestedReviewThisSession, !hasPresentedFeatureTipThisSession,
              activeFeatureTip == nil, featureTipTask == nil,
              FeatureTipStore.shared.canPresentPrompt(),
              appLaunchCount >= 3, !hasRequestedReview else { return false }
        hasRequestedReviewThisSession = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, scenePhase == .active, canPresentSessionUI else { return }
            hasRequestedReview = true
            FeatureTipStore.shared.recordReviewRequest()
            requestReview()
        }
        return true
    }

    private var canPresentFeatureTip: Bool {
        return canPresentSessionUI
            && (!isUITest || ProcessInfo.processInfo.arguments.contains("ui-testing-feature-tips"))
            && scenePhase == .active
            && !hasPresentedFeatureTipThisSession && !hasRequestedReviewThisSession
            && activeFeatureTip == nil && !model.userEconomyStore.showPayGate
            && !model.showHandoffProtection
    }

    private func presentFeatureTipIfNeeded() {
        guard canPresentFeatureTip, featureTipTask == nil,
              FeatureTipStore.shared.canPresentPrompt() else { return }
        featureTipTask = Task { @MainActor in
            defer { featureTipTask = nil }
            // Let foregrounding settle, then recheck conditions before presenting.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, canPresentFeatureTip else { return }
            let hasWidget: Bool? = await withCheckedContinuation { continuation in
                WidgetCenter.shared.getCurrentConfigurations { result in
                    continuation.resume(returning: try? result.map { !$0.isEmpty }.get())
                }
            }
            guard !Task.isCancelled, canPresentFeatureTip else { return }
            if hasWidget == true {
                FeatureTipStore.shared.recordAcceptance(.widgets)
            }
            if model.hasWallpaperShortcut {
                FeatureTipStore.shared.recordAcceptance(.wallpaper)
            }
            let hasCanvas = !CanvasStorageService.shared.availableDayKeys().isEmpty
            for tip in FeatureTip.orderedByPriority {
                // An unavailable WidgetKit response is unknown, not "no widget".
                if tip == .widgets && hasWidget == nil { continue }
                let used = tip == .wallpaper ? model.hasWallpaperShortcut : hasWidget == true
                if FeatureTipStore.shared.isEligible(tip, launchCount: appLaunchCount,
                                                     hasCanvas: hasCanvas, featureUsed: used) {
                    activeFeatureTip = tip
                    return
                }
            }
        }
    }

    private func finishFeatureTip() {
        if let tip = presentedFeatureTip {
            // Swipe dismissal has the same meaning as Maybe later. Acceptance
            // is terminal, so recordDismissal cannot overwrite the CTA choice.
            FeatureTipStore.shared.recordDismissal(tip)
        }
        presentedFeatureTip = nil
        if let route = acceptedFeatureTipRoute {
            acceptedFeatureTipRoute = nil
            NotificationCenter.default.post(name: .openFeatureTipSettings, object: nil,
                userInfo: ["page": route.rawValue, "dismissalCompleted": true])
        }
    }
}

#if DEBUG
private struct TicketSettingsUITestFixtureView: View {
    @State private var group = TicketGroup(
        id: "ui-testing-study",
        name: "Study",
        settings: AppUnlockSettings(entryCostSteps: 10, dayPassCostSteps: 100),
        enabledIntervals: []
    )
    @State private var showsSettings = false
    @State private var isDeleted = false

    var body: some View {
        ZStack {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier("ui-testing-ticket-settings.isolatedRoot")
                .accessibilityLabel("Isolated ticket settings fixture")
                .allowsHitTesting(false)

            Button(String(localized: "Feeds")) {
                guard !isDeleted else { return }
                showsSettings = true
            }
            .accessibilityIdentifier("tab_feeds")
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                TicketSettingsContentView(
                    group: $group,
                    onEditApps: {},
                    onAfterDelete: {
                        showsSettings = false
                    },
                    updateGroup: { updatedGroup in
                        group = updatedGroup
                    },
                    deleteTicketGroup: { _ in
                        isDeleted = true
                    },
                    isUsageBudgetActive: { _ in false },
                    unspentUsageBudget: { _ in 0 },
                    availableStepsBalance: { 0 },
                    handlePayGatePayment: { _, _, _ in }
                )
                .padding()
                .navigationTitle(String(localized: "Study"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
#endif

private extension NowhereProductionRoot {
    var currentTheme: AppTheme {
        AppTheme.normalized(rawValue: appThemeRaw)
    }
}

// MARK: - Notification Handling
extension NowhereProductionRoot {
    func setupNotificationHandling() {
        NotificationDelegate.shared.model = model
    }
}
