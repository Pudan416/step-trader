import Combine
import Foundation
import HealthKit
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - AppModel
@MainActor
final class AppModel: ObservableObject {
    // Dependencies
    let healthKitService: any HealthKitServiceProtocol
    let familyControlsService: any FamilyControlsServiceProtocol
    let notificationService: any NotificationServiceProtocol
    let budgetEngine: any BudgetEngineProtocol
    private let authService = AuthenticationService.shared
    
    // Stores
    let healthStore: HealthStore
    let blockingStore: BlockingStore
    let userEconomyStore: UserEconomyStore
    
    private var cancellables = Set<AnyCancellable>()
    private var sleepRefetchTask: Task<Void, Never>?

    nonisolated static func storedDayEnd() -> (hour: Int, minute: Int) {
        let g = UserDefaults.stepsTrader()
        let h = (g.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? (UserDefaults.standard.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? 0
        let m = (g.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? (UserDefaults.standard.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? 0
        return (h, m)
    }

    nonisolated static func dayKey(for date: Date) -> String {
        let de = storedDayEnd()
        return DayBoundary.dayKey(for: date, dayEndHour: de.hour, dayEndMinute: de.minute)
    }

    // MARK: - Forwarding to Stores
    
    // HealthStore
    var stepsToday: Double {
        get { healthStore.stepsToday }
        set { healthStore.stepsToday = newValue }
    }
    var dailySleepHours: Double {
        get { healthStore.dailySleepHours }
        set { healthStore.dailySleepHours = newValue }
    }
    var baseEnergyToday: Int {
        get { healthStore.baseEnergyToday }
        set { healthStore.baseEnergyToday = newValue }
    }
    /// Whether HealthKit has returned step data today.
    var hasStepsData: Bool { healthStore.hasStepsData }
    /// Whether HealthKit has returned sleep data today.
    var hasSleepData: Bool { healthStore.hasSleepData }

    var healthAuthorizationStatus: HKAuthorizationStatus {
        get { healthStore.authorizationStatus }
        set { healthStore.authorizationStatus = newValue }
    }
    
    // BlockingStore
    var ticketGroups: [TicketGroup] {
        get { blockingStore.ticketGroups }
        set { blockingStore.ticketGroups = newValue }
    }
    var appUnlockSettings: [String: AppUnlockSettings] {
        get { blockingStore.appUnlockSettings }
        set { blockingStore.appUnlockSettings = newValue }
    }
    var appSelection: FamilyActivitySelection {
        get { blockingStore.appSelection }
        set { blockingStore.appSelection = newValue }
    }
    var isBlocked: Bool {
        get { blockingStore.isBlocked }
        set { blockingStore.isBlocked = newValue }
    }
    
    // UserEconomyStore
    var entryCostSteps: Int {
        get { userEconomyStore.entryCostSteps }
        set { userEconomyStore.entryCostSteps = newValue }
    }
    var stepsBalance: Int {
        get { userEconomyStore.stepsBalance }
        set { userEconomyStore.stepsBalance = newValue }
    }
    var bonusSteps: Int {
        get { userEconomyStore.bonusSteps }
        set { userEconomyStore.bonusSteps = newValue }
    }
    var serverGrantedSteps: Int {
        get { userEconomyStore.serverGrantedSteps }
        set { userEconomyStore.serverGrantedSteps = newValue }
    }
    var totalStepsBalance: Int {
        get { userEconomyStore.totalStepsBalance }
        set { userEconomyStore.totalStepsBalance = newValue }
    }
    var showPayGate: Bool {
        get { userEconomyStore.showPayGate }
        set { userEconomyStore.showPayGate = newValue }
    }
    var payGateTargetGroupId: String? {
        get { userEconomyStore.payGateTargetGroupId }
        set { userEconomyStore.payGateTargetGroupId = newValue }
    }
    var payGateSessions: [String: PayGateSession] {
        get { userEconomyStore.payGateSessions }
        set { userEconomyStore.payGateSessions = newValue }
    }
    var currentPayGateSessionId: String? {
        get { userEconomyStore.currentPayGateSessionId }
        set { userEconomyStore.currentPayGateSessionId = newValue }
    }
    var appStepsSpentToday: [String: Int] {
        get { userEconomyStore.appStepsSpentToday }
        set { userEconomyStore.appStepsSpentToday = newValue }
    }
    var appStepsSpentByDay: [String: [String: Int]] {
        get { userEconomyStore.appStepsSpentByDay }
        set { userEconomyStore.appStepsSpentByDay = newValue }
    }
    var appStepsSpentLifetime: [String: Int] {
        get { userEconomyStore.appStepsSpentLifetime }
        set { userEconomyStore.appStepsSpentLifetime = newValue }
    }
    var dayPassGrants: [String: Date] {
        get { userEconomyStore.dayPassGrants }
        set { userEconomyStore.dayPassGrants = newValue }
    }
    
    func isFamilyControlsModeEnabled(for bundleId: String) -> Bool {
        unlockSettings(for: bundleId).familyControlsModeEnabled
    }

    func setFamilyControlsModeEnabled(_ enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        settings.familyControlsModeEnabled = enabled
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseTicketUpsert(bundleId: bundleId)
    }

    // Bootstrap state - prevent syncing during initialization
    @Published var isBootstrapping: Bool = true
    
    @Published var dailyActivitySelections: [String] = []
    @Published var dailyRestSelections: [String] = []
    @Published var dailyJoysSelections: [String] = []
    /// Canvas tab: 4 slots (category + option each). Synced with daily *Selections.
    @Published var dailyCanvasSlots: [DayCanvasSlot] = (0..<4).map { _ in DayCanvasSlot(category: nil, optionId: nil) }
    @Published var preferredActivityOptions: [String] = []
    @Published var preferredRestOptions: [String] = []
    @Published var preferredJoysOptions: [String] = []
    @Published var customEnergyOptions: [CustomEnergyOption] = []
    @Published var savedRoutines: [EnergyRoutine] = []
    
    /// Single source of truth: UserEconomyStore.spentSteps (persisted as SharedKeys.spentStepsToday).
    var spentStepsToday: Int {
        get { userEconomyStore.spentSteps }
        set { userEconomyStore.spentSteps = newValue }
    }

    @Published var dayEndHour: Int = storedDayEnd().hour
    @Published var dayEndMinute: Int = storedDayEnd().minute
    
    
    enum PayGateDismissReason {
        case userDismiss
        case background
        case programmatic
    }
    
    @Published var showQuickStatusPage = false
    /// Backing storage for workout suggestions (accessed via extension computed property).
    var _pendingWorkoutSuggestions: [DetectedWorkout] = []
    /// Backing storage for unified activity suggestions.
    var _pendingActivitySuggestions: [ActivitySuggestion] = []

    // Handoff token handling
    @Published var handoffToken: HandoffToken? = nil
    @Published var showHandoffProtection = false
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Safely update appSelection from external sources (e.g., FamilyControlsService callback)
    /// without triggering recursive didSet updates
    func updateAppSelectionFromService(_ selection: FamilyActivitySelection) {
        blockingStore.updateAppSelectionFromService(selection)
    }
    
    private var dayBoundaryTimer: Timer?
    private var lastDayKey: String

    init(
        healthKitService: any HealthKitServiceProtocol,
        familyControlsService: any FamilyControlsServiceProtocol,
        notificationService: any NotificationServiceProtocol,
        budgetEngine: any BudgetEngineProtocol
    ) {
        self.healthKitService = healthKitService
        self.familyControlsService = familyControlsService
        self.notificationService = notificationService
        self.budgetEngine = budgetEngine
        self.lastDayKey = Self.dayKey(for: Date())
        
        // Initialize Stores
        self.healthStore = HealthStore(healthKitService: healthKitService)
        self.blockingStore = BlockingStore(familyControlsService: familyControlsService)
        self.userEconomyStore = UserEconomyStore(budgetEngine: budgetEngine)
        
        // Subscribe to stores
        healthStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        // Recalc colors total when steps or sleep update (so total = activity + creativity + joys)
        Publishers.CombineLatest(healthStore.$stepsToday, healthStore.$dailySleepHours)
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.recalculateDailyEnergy()
                }
            }
            .store(in: &cancellables)
        
        blockingStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        userEconomyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func currentDayStart(for date: Date) -> Date {
        DayBoundary.currentDayStart(for: date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }
    
    func isSameCustomDay(_ a: Date, _ b: Date) -> Bool {
        currentDayStart(for: a) == currentDayStart(for: b)
    }

    func checkDayBoundary() {
        let currentKey = Self.dayKey(for: Date())
        let dayChanged = currentKey != lastDayKey
        if dayChanged {
            lastDayKey = currentKey
        }
        let didReset = resetDailyEnergyIfNeeded()
        budgetEngine.resetIfNeeded()
        loadSpentStepsBalance()
        if dayChanged {
            loadAppStepsSpentToday()
            clearAllUsageBudgets(reason: "dayBoundary")
        }
        if (didReset || dayChanged) && !isBootstrapping {
            Task { await refreshStepsIfAuthorized() }
        }
    }

    /// Wipes every active usage-budget key and stops DeviceActivity monitoring,
    /// then rebuilds shields so apps become blocked again.
    private func clearAllUsageBudgets(reason: String) {
        let defaults = UserDefaults.stepsTrader()
        var didClean = false

        for group in ticketGroups {
            let budgetKey = SharedKeys.usageBudgetKey(group.id)
            guard defaults.integer(forKey: budgetKey) > 0 else { continue }

            defaults.removeObject(forKey: budgetKey)
            defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
            defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))

            #if canImport(DeviceActivity)
            DeviceActivityCenter().stopMonitoring([DeviceActivityName("usageBudget_\(group.id)")])
            #endif

            AppLogger.shield.debug("🧹 Cleared usage budget for group \(group.id) (\(reason))")
            didClean = true
        }
        if didClean {
            rebuildFamilyControlsShield()
        }
    }

    func scheduleDayBoundaryTimer() {
        dayBoundaryTimer?.invalidate()
        let next = nextDayBoundary(after: Date())
        let interval = max(1, next.timeIntervalSinceNow)
        dayBoundaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkDayBoundary()
                self?.scheduleDayBoundaryTimer()
            }
        }
        AppLogger.app.debug("⏰ Next day boundary scheduled for \(next)")
    }

    private func nextDayBoundary(after date: Date) -> Date {
        DayBoundary.nextBoundary(after: date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }
    
    private func loadDayPassGrants() {
        userEconomyStore.loadDayPassGrants()
    }
    
    func persistDayPassGrants() {
        userEconomyStore.persistDayPassGrants()
    }
    
    func loadAppStepsSpentToday() {
        Task {
            await userEconomyStore.loadAppStepsSpentToday()
        }
    }
    
    func persistAppStepsSpentToday() {
        userEconomyStore.persistAppStepsSpentToday()
    }

    func persistAppStepsSpentByDay() {
        userEconomyStore.persistAppStepsSpentByDay()
    }

    private func loadAppStepsSpentLifetime() {
        Task {
            await userEconomyStore.loadAppStepsSpentLifetime()
        }
    }

    func persistAppStepsSpentLifetime() {
        userEconomyStore.persistAppStepsSpentLifetime()
    }
    
    
    func defaultDayPassCost(forEntryCost entryCost: Int) -> Int {
        if entryCost <= 0 { return 0 }
        return entryCost * 100
    }
    
    func handleAppWillEnterForeground() {
        AppLogger.app.debug("📱 App will enter foreground")
        if let service = familyControlsService as? FamilyControlsService {
            service.refreshAuthorizationStatus()
        }
        checkDayBoundary()
        scheduleDayBoundaryTimer()
        startPendingWidgetBudgetMonitoring()
        rebuildFamilyControlsShield()
        Task {
            await refreshStepsBalance()
            await refreshSleepIfAuthorized()
            scheduleDelayedSleepRefetchIfMorning()
            await refreshWorkoutSuggestions()
            await refreshNotificationAuthorizationStatus()
        }
    }
    
    /// Apple Watch can take 5-30 min to finalize sleep staging data after waking.
    /// If the app is opened in the morning, the first fetch often returns partial
    /// or zero sleep. Re-fetch after a delay to pick up late-arriving samples.
    private func scheduleDelayedSleepRefetchIfMorning() {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (5...11).contains(hour) else { return }
        
        sleepRefetchTask?.cancel()
        sleepRefetchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            AppLogger.healthKit.debug("🛌 Delayed sleep re-fetch (morning catchup)")
            await self?.refreshSleepIfAuthorized()
        }
    }

    func handleAppDidEnterBackground() {
        writeWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    
    func bootstrap(requestPermissions: Bool) async {
        AppLogger.app.debug("🚀 Bootstrapping AppModel...")
        isBootstrapping = true
        
        // 1. Load data from stores
        await userEconomyStore.loadAppStepsSpentToday()
        await userEconomyStore.loadAppStepsSpentLifetime()
        blockingStore.loadTicketGroups()
        loadAppUnlockSettings()
        loadDayPassGrants()
        
        // 1.5 Restore daily energy state and spent balance so colors counts persist across restarts
        loadEnergyPreferences()
        loadDailyEnergyState()
        loadCustomEnergyOptions()
        loadSavedRoutines()
        loadSpentStepsBalance()
        
        // 1.6 If authenticated but local selections are empty, attempt to restore from Supabase.
        // This covers fresh installs, device switches, and UserDefaults data loss.
        let hasLocalSelections = !dailyActivitySelections.isEmpty
            || !dailyRestSelections.isEmpty
            || !dailyJoysSelections.isEmpty
        let isAuthenticated = AuthenticationService.shared.isAuthenticated
        if isAuthenticated && !hasLocalSelections {
            AppLogger.app.debug("🔄 No local selections but authenticated — restoring from Supabase")
            let didRestore = await SupabaseSyncService.shared.restoreFromServer(model: self)
            if didRestore {
                AppLogger.app.debug("✅ Restored selections from Supabase")
            }
        }
        
        // 1.7 Recalculate EXP from loaded selections immediately so baseEnergyToday
        // reflects current selections even before HealthKit data arrives. Without this,
        // baseEnergyToday stays at whatever stale value was in UserDefaults, and if
        // HealthKit refresh fails, EXP from category selections is never counted.
        recalculateDailyEnergy()
        
        // 2. Request permissions if needed
        if requestPermissions {
            do {
                try await healthStore.requestAuthorization()
                try await blockingStore.requestAuthorization()
                await requestNotificationPermission()
            } catch {
                AppLogger.app.debug("Bootstrap permission request failed: \(error.localizedDescription)")
            }
        }
        
        // 3. Check day boundary BEFORE fetching so stale state is cleared first
        checkDayBoundary()
        
        // Schedule daily notifications (canvas reminder + day reset warning)
        if let nm = notificationService as? NotificationManager {
            nm.scheduleDailyCanvasReminder()
            nm.scheduleDayResetWarning(dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
        }

        isBootstrapping = false
        
        // 4. Refresh data AFTER day boundary reset so fresh values aren't wiped
        await refreshStepsIfAuthorized()
        await refreshSleepIfAuthorized()
        
        // 4.5 Snapshot notification authorization so permission badge is accurate on launch
        await refreshNotificationAuthorizationStatus()
        
        // 5. Schedule day boundary timer (was missing — only ran on foreground resume)
        scheduleDayBoundaryTimer()
        
        // 6. Check for workouts to suggest
        await refreshWorkoutSuggestions()
        
        AppLogger.app.debug("✅ AppModel bootstrap complete")
        
        // Drain any offline sync requests that failed previously
        Task { await SupabaseSyncService.shared.drainRetryQueue() }
    }
    
    deinit {
        dayBoundaryTimer?.invalidate()
        sleepRefetchTask?.cancel()
    }
}

// MARK: - Permissions helpers
extension AppModel {
    func requestNotificationPermission() async {
        do { try await notificationService.requestPermission() }
        catch { AppLogger.app.debug("Notification permission failed: \(error.localizedDescription)") }
        await refreshNotificationAuthorizationStatus()
    }

    func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
    }

    /// True when one or more permissions needed for the full experience are missing.
    var hasPermissionIssues: Bool {
        let healthMissing = !healthStore.hasStepsData && !healthStore.hasSleepData
        let familyMissing = !blockingStore.isAuthorized
        let notifMissing = notificationAuthorizationStatus != .authorized
        return healthMissing || familyMissing || notifMissing
    }
}
