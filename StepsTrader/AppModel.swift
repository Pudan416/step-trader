import Combine
import Foundation
import HealthKit
import SwiftUI
import UIKit
import UserNotifications
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
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
    private var returnNotificationTask: Task<Void, Never>?
    private var periodicNotificationTask: Task<Void, Never>?

    nonisolated static func dayKey(for date: Date) -> String {
        let g = UserDefaults.stepsTrader()
        let hour = (g.object(forKey: "dayEndHour_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndHour_v1") as? Int)
            ?? 0
        let minute = (g.object(forKey: "dayEndMinute_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndMinute_v1") as? Int)
            ?? 0
        return DayBoundary.dayKey(for: date, dayEndHour: hour, dayEndMinute: minute)
    }

    nonisolated static func currentDayStartForDefaults(_ date: Date) -> Date {
        let g = UserDefaults.stepsTrader()
        let hour = (g.object(forKey: "dayEndHour_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndHour_v1") as? Int)
            ?? 0
        let minute = (g.object(forKey: "dayEndMinute_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndMinute_v1") as? Int)
            ?? 0
        return DayBoundary.currentDayStart(for: date, dayEndHour: hour, dayEndMinute: minute)
    }

    private var lastSupabaseSyncAt: Date = .distantPast
    
    // MARK: - Performance optimization
    var unlockExpiryTasks: [String: Task<Void, Never>] = [:]  // Tasks to rebuild shield when unlock expires
    
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
    var isTrackingTime: Bool {
        get { blockingStore.isTrackingTime }
        set { blockingStore.isTrackingTime = newValue }
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
    var spentSteps: Int {
        get { userEconomyStore.spentSteps }
        set { userEconomyStore.spentSteps = newValue }
    }
    var spentMinutes: Int {
        get { userEconomyStore.spentMinutes }
        set { userEconomyStore.spentMinutes = newValue }
    }
    var spentTariff: Tariff {
        get { userEconomyStore.spentTariff }
        set { userEconomyStore.spentTariff = newValue }
    }
    var dailyTariffSelections: [String: Tariff] {
        get { userEconomyStore.dailyTariffSelections }
        set { userEconomyStore.dailyTariffSelections = newValue }
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
    var minuteChargeLogs: [MinuteChargeLog] {
        get { userEconomyStore.minuteChargeLogs }
        set { userEconomyStore.minuteChargeLogs = newValue }
    }
    var minuteTimeByDay: [String: [String: Int]] {
        get { userEconomyStore.minuteTimeByDay }
        set { userEconomyStore.minuteTimeByDay = newValue }
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
    
    // Published properties (Remaining in AppModel for now)
    @Published var message: String?
    @Published var currentSessionElapsed: Int?

    @Published var dailyActivitySelections: [String] = []
    @Published var dailyRestSelections: [String] = []
    @Published var dailyJoysSelections: [String] = []
    /// Gallery tab: 4 slots (category + option each). Synced with daily *Selections.
    @Published var dailyGallerySlots: [DayGallerySlot] = (0..<4).map { _ in DayGallerySlot(category: nil, optionId: nil) }
    @Published var preferredActivityOptions: [String] = []
    @Published var preferredRestOptions: [String] = []
    @Published var preferredJoysOptions: [String] = []
    @Published var customEnergyOptions: [CustomEnergyOption] = []
    
    var effectiveStepsToday: Double { stepsToday + Double(bonusSteps) }
    /// Single source of truth: UserEconomyStore.spentSteps (persisted as SharedKeys.spentStepsToday).
    var spentStepsToday: Int {
        get { userEconomyStore.spentSteps }
        set { userEconomyStore.spentSteps = newValue }
    }

    // Budget properties that mirror BudgetEngine for UI updates
    @Published var dailyBudgetMinutes: Int = 0
    @Published var remainingMinutes: Int = 0
    @Published var dayEndHour: Int = {
        let g = UserDefaults.stepsTrader()
        return (g.object(forKey: "dayEndHour_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndHour_v1") as? Int)
            ?? 0
    }()
    @Published var dayEndMinute: Int = {
        let g = UserDefaults.stepsTrader()
        return (g.object(forKey: "dayEndMinute_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndMinute_v1") as? Int)
            ?? 0
    }()
    
    
    enum PayGateDismissReason {
        case userDismiss
        case background
        case programmatic
    }
    
    @Published var showQuickStatusPage = false  // Whether to show quick status page

    // Handoff token handling
    @Published var handoffToken: HandoffToken? = nil
    @Published var showHandoffProtection = false
    // Startup guard to prevent immediate deep link loops on cold launch
    private let appLaunchTime: Date = Date()

    @Published var isInstagramSelected: Bool = false {
        didSet {
            // Skip if value hasn't actually changed (important during init).
            guard isInstagramSelected != oldValue else { return }
            
            // Prevent recursion
            guard !isUpdatingInstagramSelection else { return }

            UserDefaults.stepsTrader().set(isInstagramSelected, forKey: "isInstagramSelected")
            if isInstagramSelected {
                // For Instagram specifically, we use the existing selection mechanism
                // but we don't call setAppAsTarget which triggers applyFamilyControlsSelection
                // Instead we just ensure the shield is rebuilt if needed
                rebuildFamilyControlsShield()
            } else {
                clearAppSelection()
            }
        }
    }

    // Flag to prevent recursion when updating Instagram selection
    private var isUpdatingInstagramSelection = false
    
    // MARK: - App Selection Race Condition Prevention
    /// Debounce task for saving app selection
    private var saveAppSelectionTask: Task<Void, Never>?
    /// Last saved selection for comparison
    private var lastSavedAppSelection: FamilyActivitySelection?
    
    /// Safely update appSelection from external sources (e.g., FamilyControlsService callback)
    /// without triggering recursive didSet updates
    func updateAppSelectionFromService(_ selection: FamilyActivitySelection) {
        blockingStore.updateAppSelectionFromService(selection)
    }
    
    private func clearAppSelection() {
        blockingStore.clearAppSelection()
    }

    // Internal (mutated from AppModel+BudgetTracking extension)
    var startTime: Date?
    var timer: Timer?
    var dayBoundaryTimer: Timer?
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
        
        // Recalc ink total when steps or sleep update (so total = activity + creativity + joys)
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
            loadMinuteChargeLogs()
        }
        if (didReset || dayChanged) && !isBootstrapping {
            Task { await refreshStepsIfAuthorized() }
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
    
    // MARK: - App display name
    func appDisplayName(for cardId: String) -> String {
        let defaults = UserDefaults.stepsTrader()
        let key = "timeAccessSelection_v1_\(cardId)"
        
        #if canImport(FamilyControls)
        if let data = defaults.data(forKey: key),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           let token = sel.applicationTokens.first {
            // Token-to-name key, written by ShieldConfiguration extension.
            if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                if let storedName = defaults.string(forKey: tokenKey) {
                    return storedName
                }
            }
        }
        
        // For categories (app groups)
        if let data = defaults.data(forKey: key),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           !sel.categoryTokens.isEmpty {
            return "App Group"
        }
        #else
        // Fallback when FamilyControls not available
        if let data = defaults.data(forKey: key),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            if !sel.categoryTokens.isEmpty {
                return "App Group"
            }
        }
        #endif
        
        // Fallback
        return "Selected app"
    }
    
    private func loadDayPassGrants() {
        userEconomyStore.loadDayPassGrants()
    }
    
    func persistDayPassGrants() {
        userEconomyStore.persistDayPassGrants()
    }
    
    // MARK: - Steps Spent Tracking (for display purposes)
    func totalStepsSpent(for bundleId: String) -> Int {
        if let total = appStepsSpentLifetime[bundleId] {
            return total
        }
        return appStepsSpentByDay.values.reduce(0) { acc, perDay in
            acc + (perDay[bundleId] ?? 0)
        }
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
    
    // MARK: - Supabase Shield Sync (stubs)
    
    func deleteSupabaseTicket(bundleId: String) async {
        await SupabaseSyncService.shared.deleteTicket(bundleId: bundleId)
    }
    
    /// Fully unlock a FamilyControls card (remove from shield).
    @MainActor
    func unlockFamilyControlsCard(_ cardId: String) {
        var settings = unlockSettings(for: cardId)
        settings.familyControlsModeEnabled = false
        settings.minuteTariffEnabled = false
        appUnlockSettings[cardId] = settings
        persistAppUnlockSettings()
        rebuildFamilyControlsShield()
        AppLogger.app.debug("🔓 FamilyControls card unlocked: \(cardId)")
    }

    private func handleBlockedRedirect() {
        let g = UserDefaults.stepsTrader()
        guard let bundleId = g.string(forKey: "blockedPaygateBundleId"),
              let ts = g.object(forKey: "blockedPaygateTimestamp") as? Date
        else { return }
        if Date().timeIntervalSince(ts) > 5 * 60 {
            g.removeObject(forKey: "blockedPaygateBundleId")
            g.removeObject(forKey: "blockedPaygateTimestamp")
            return
        }
        AppLogger.app.debug("🚫 Redirecting away due to active access window for \(bundleId)")
        g.removeObject(forKey: "blockedPaygateBundleId")
        g.removeObject(forKey: "blockedPaygateTimestamp")
        let schemes = TargetResolver.primaryAndFallbackSchemes(for: bundleId)
        Task { _ = await attemptOpen(schemes: schemes, index: 0, bundleId: bundleId, logCost: 0) }
    }

    private func attemptOpen(schemes: [String], index: Int, bundleId: String, logCost: Int) async -> Bool {
        guard index < schemes.count else { return false }
        let scheme = schemes[index]
        guard let url = URL(string: scheme) else {
            return await attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId, logCost: logCost)
        }
        let success = await UIApplication.shared.open(url, options: [:])
        if success {
            AppLogger.app.debug("✅ Opened \(bundleId) via \(scheme)")
            return true
        }
        AppLogger.app.debug("❌ Scheme \(scheme) failed for \(bundleId), trying next")
        return await attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId, logCost: logCost)
    }

    func accessWindowExpiration(_ window: AccessWindow, now: Date) -> Date? {
        switch window {
        case .minutes10:
            return now.addingTimeInterval(10 * 60)
        case .minutes30:
            return now.addingTimeInterval(30 * 60)
        case .hour1:
            return now.addingTimeInterval(60 * 60)
        }
    }
    
    
    func runDiagnostics() {
        AppLogger.app.debug("🔍 === FAMILY CONTROLS DIAGNOSTICS ===")

        // 1. Authorization check
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.checkAuthorizationStatus()
        }

        // 2. Selected apps check
        AppLogger.app.debug("📱 Selected applications:")
        AppLogger.app.debug("   - ApplicationTokens: \(self.appSelection.applicationTokens.count)")
        AppLogger.app.debug("   - CategoryTokens: \(self.appSelection.categoryTokens.count)")

        // 3. Budget check
        AppLogger.app.debug("💰 Budget:")
        AppLogger.app.debug("   - Total minutes: \(self.budgetEngine.dailyBudgetMinutes)")
        AppLogger.app.debug("   - Remaining minutes: \(self.budgetEngine.remainingMinutes)")
        AppLogger.app.debug("   - Spent minutes: \(self.spentMinutes)")

        // 4. Tracking state check
        AppLogger.app.debug("⏱️ Tracking status:")
        AppLogger.app.debug("   - Active: \(self.isTrackingTime)")
        AppLogger.app.debug("   - Blocked: \(self.isBlocked)")

        // 5. UserDefaults check
        let userDefaults = UserDefaults.stepsTrader()
        AppLogger.app.debug("💾 Shared UserDefaults:")
        AppLogger.app.debug("   - Budget minutes: \(String(describing: userDefaults.object(forKey: "budgetMinutes")))")
        AppLogger.app.debug("   - Spent minutes: \(String(describing: userDefaults.object(forKey: "spentMinutes")))")
        AppLogger.app.debug("   - Monitoring start: \(String(describing: userDefaults.object(forKey: "monitoringStartTime")))")

        // 6. DeviceActivity diagnostics
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.checkDeviceActivityStatus()
        }

        message = "🔍 Diagnostics complete. Check the Xcode console for details."
    }

    func resetStatistics() {
        AppLogger.app.debug("🔄 === RESET STATISTICS BEGIN ===")

        // 1. Stop tracking if active
        if isTrackingTime {
            stopTracking()
        }

        // 2. Reset time and state
        spentMinutes = 0
        spentSteps = 0
        spentTariff = .easy
        isBlocked = false
        currentSessionElapsed = nil

        // 3. Clear UserDefaults (App Group)
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.removeObject(forKey: "spentMinutes")
        userDefaults.removeObject(forKey: "spentTariff")
        userDefaults.removeObject(forKey: "spentTimeDate")
        userDefaults.removeObject(forKey: "budgetMinutes")
        userDefaults.removeObject(forKey: "monitoringStartTime")
        userDefaults.removeObject(forKey: "selectedAppsCount")
        userDefaults.removeObject(forKey: "selectedCategoriesCount")
        userDefaults.removeObject(forKey: "selectedApplicationTokens")
        userDefaults.removeObject(forKey: "persistentApplicationTokens")
        userDefaults.removeObject(forKey: "persistentCategoryTokens")
        userDefaults.removeObject(forKey: "appSelectionSavedDate")
        userDefaults.removeObject(forKey: "appUnlockSettings_v1")
        userDefaults.removeObject(forKey: "appDayPassGrants_v1")
        AppLogger.app.debug("💾 Cleared App Group UserDefaults")

        // 4. Clear standard UserDefaults
        UserDefaults.standard.removeObject(forKey: "dailyBudgetMinutes")
        UserDefaults.standard.removeObject(forKey: "remainingMinutes")
        UserDefaults.standard.removeObject(forKey: "todayAnchor")
        AppLogger.app.debug("💾 Cleared standard UserDefaults")

        // 5. Reset budget manually (resetForToday is private)
        let todayStart = currentDayStart(for: Date())
        UserDefaults.standard.set(todayStart, forKey: "todayAnchor")
        UserDefaults.standard.set(0, forKey: "dailyBudgetMinutes")
        UserDefaults.standard.set(0, forKey: "remainingMinutes")
        AppLogger.app.debug("💰 Budget reset")

        // 6. Remove all blocks
        // No ManagedSettings shielding anymore. Just stop DeviceActivity monitoring by clearing selection/settings.
        familyControlsService.updateSelection(FamilyActivitySelection())
        familyControlsService.updateMinuteModeMonitoring()

        // 7. Clear app selection (both selection and saved data)
        blockingStore.clearAppSelection()
        AppLogger.app.debug("📱 Cleared app selection and cached data")
        appUnlockSettings = [:]
        dayPassGrants = [:]

        // 8. Recalculate budget with current steps
        Task {
            do {
                stepsToday = try await fetchStepsForCurrentDay()
                let mins = budgetEngine.minutes(from: stepsToday)
                budgetEngine.setBudget(minutes: mins)
                syncBudgetProperties()  // Sync budget properties for UI updates
                message =
                    "🔄 Stats reset! New budget: \(mins) minutes from \(Int(stepsToday)) steps"
                AppLogger.app.debug("✅ Stats reset. New budget: \(mins) minutes")
            } catch {
                message =
                    "🔄 Stats reset, but refreshing steps failed: \(error.localizedDescription)"
                AppLogger.app.debug("Failed to refresh steps: \(error.localizedDescription)")
            }
        }

        AppLogger.app.debug("✅ === RESET COMPLETE ===")
    }

    func sendReturnToAppNotification() {
        returnNotificationTask?.cancel()
        periodicNotificationTask?.cancel()

        returnNotificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.scheduleReturnNotification()
        }

        periodicNotificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.schedulePeriodicNotifications()
        }
    }

    private func scheduleReturnNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Proof"
        content.body = "Your exhibition is still open."
        content.sound = .default
        content.badge = nil

        // Add action for quick return to app
        let returnAction = UNNotificationAction(
            identifier: "RETURN_TO_APP",
            title: "Open Proof",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "STEPS_REMINDER",
            actions: [returnAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "STEPS_REMINDER"

        let request = UNNotificationRequest(
            identifier: "stepsReminder-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.app.debug("Failed to send return notification: \(error.localizedDescription)")
            } else {
                AppLogger.app.debug("📤 Sent return to app notification")
            }
        }
    }

    func schedulePeriodicNotifications() {
        guard isBlocked else { return }

        let content = UNMutableNotificationContent()
        content.title = "Proof"
        content.body = "You have ink to earn."
        content.sound = .default

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["periodicReminder"])

        let request = UNNotificationRequest(
            identifier: "periodicReminder",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: true)
        )

        center.add(request)
    }

    func withTimeout(seconds: TimeInterval, operation: @escaping () async throws -> Void) async rethrows {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }
    
    func recalcSilently() async {
        budgetEngine.resetIfNeeded()
        do {
            stepsToday = try await fetchStepsForCurrentDay()
        } catch {
            AppLogger.app.debug("Could not fetch step data for silent recalc: \(error.localizedDescription)")
            #if targetEnvironment(simulator)
                stepsToday = 2500
            #else
                stepsToday = fallbackCachedSteps()
            #endif
        }
        let mins = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: mins)
        if spentMinutes > mins {
            AppLogger.app.debug("⚠️ Spent time (\(self.spentMinutes)) exceeds budget (\(mins)), correcting...")
            updateSpentTime(minutes: mins)
        }
        syncBudgetProperties()
        AppLogger.app.debug("🔄 Silent budget recalculation: \(mins) minutes from \(Int(self.stepsToday)) steps")
    }
    
    func handleAppWillEnterForeground() {
        AppLogger.app.debug("📱 App will enter foreground")
        // Refresh Family Controls auth status in case user revoked in Settings (audit fix #15)
        if let service = familyControlsService as? FamilyControlsService {
            service.refreshAuthorizationStatus()
        }
        checkDayBoundary()
        scheduleDayBoundaryTimer()
        cleanupExpiredUnlocks()
        purgeExpiredAccessWindows()
        // Always rebuild shield on foreground to guarantee consistency.
        // The DeviceActivity extension's expiry callback may not have fired
        // (system constraints, DateComponents issues), so the main app must
        // re-apply the correct shield state every time it resumes.
        rebuildFamilyControlsShield()
        Task {
            await refreshStepsBalance()
            await refreshSleepIfAuthorized()
        }
    }

    func toggleRealBlocking() {
        if isTrackingTime {
            stopTracking()
        } else {
            startTracking()
        }
    }
    
    func bootstrap(requestPermissions: Bool) async {
        AppLogger.app.debug("🚀 Bootstrapping AppModel...")
        isBootstrapping = true
        
        // 1. Load data from stores
        await userEconomyStore.loadAppStepsSpentToday()
        await userEconomyStore.loadAppStepsSpentLifetime()
        loadMinuteChargeLogs()
        blockingStore.loadTicketGroups()
        
        // 1.5 Restore daily energy state and spent balance so ink counts persist across restarts
        loadEnergyPreferences()
        loadDailyEnergyState()
        loadSpentStepsBalance()
        loadDailyTariffSelections()
        
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
        
        // 3. Refresh data
        await refreshStepsIfAuthorized()
        await refreshSleepIfAuthorized()
        
        // 4. Check state
        checkDayBoundary()
        cleanupExpiredUnlocks()
        
        isBootstrapping = false
        AppLogger.app.debug("✅ AppModel bootstrap complete")
        
        // Drain any offline sync requests that failed previously
        Task { await SupabaseSyncService.shared.drainRetryQueue() }
    }
    
    deinit {
        // Stop HealthKit observation
        // healthStore.stopObservingSteps() // Cannot call main actor method in deinit
        
        // Remove observer to avoid dangling callback and EXC_BAD_ACCESS
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )
    }
}

// MARK: - Permissions helpers
extension AppModel {
    func requestNotificationPermission() async {
        do { try await notificationService.requestPermission() }
        catch { AppLogger.app.debug("Notification permission failed: \(error.localizedDescription)") }
    }

    // Debug bonus removed: we intentionally do not support minting energy outside HealthKit/Outer World.
}
