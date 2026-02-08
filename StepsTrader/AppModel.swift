import AVFoundation
import AudioToolbox
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

    private let serverGrantedStepsKey = "serverGrantedSteps_v1"
    private var lastSupabaseSyncAt: Date = .distantPast
    
    // MARK: - Performance optimization
    var rebuildShieldTask: Task<Void, Never>? {
        get { nil } // Deprecated/Moved to BlockingStore
        set {}
    }
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
    
    // Proxy methods for compatibility
    func updateTotalStepsBalance() {
        // Handled internally by UserEconomyStore
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
    @Published var spentStepsToday: Int = 0 // Legacy? Or duplicate of spentSteps?
    
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
    
    @Published var showQuickStatusPage = false  // Показывать ли страницу быстрого статуса

    // Handoff token handling
    @Published var handoffToken: HandoffToken? = nil
    @Published var showHandoffProtection = false
    // Startup guard to prevent immediate deep link loops on cold launch
    private let appLaunchTime: Date = Date()

    @Published var isInstagramSelected: Bool = false {
        didSet {
            // Не реагируем, если значение фактически не изменилось (важно для init).
            guard isInstagramSelected != oldValue else { return }
            
            // Предотвращаем рекурсию
            guard !isUpdatingInstagramSelection else { return }

            UserDefaults.standard.set(isInstagramSelected, forKey: "isInstagramSelected")
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

    // Флаг для предотвращения рекурсии при обновлении Instagram selection
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
    
    private func setAppAsTarget(bundleId: String) {
        // For Instagram specifically, we use the existing selection mechanism
        if bundleId == "com.burbn.instagram" {
            // Apply the existing time access selection for this bundle ID
            applyFamilyControlsSelection(for: bundleId)
        } else {
            // For other apps, apply their selection
            applyFamilyControlsSelection(for: bundleId)
        }
    }
    
    private func clearAppSelection() {
        blockingStore.clearAppSelection()
    }

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
        
        // Recalc experience total when steps or sleep update (so total = activity + creativity + joys)
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
        print("⏰ Next day boundary scheduled for \(next)")
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
            // Ключ для имени по токену, который пишет экстеншен ShieldConfiguration.
            if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                if let storedName = defaults.string(forKey: tokenKey) {
                    return storedName
                }
            }
        }
        
        // Для категорий (групп приложений)
        if let data = defaults.data(forKey: key),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           !sel.categoryTokens.isEmpty {
            return "App Group"
        }
        #else
        // Fallback для случаев без FamilyControls
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
        // TODO: Implement Supabase ticket deletion
        // This would delete the shield from Supabase
    }
    
    /// Полностью разблокировать карточку FamilyControls (убрать из щита).
    @MainActor
    func unlockFamilyControlsCard(_ cardId: String) {
        var settings = unlockSettings(for: cardId)
        settings.familyControlsModeEnabled = false
        settings.minuteTariffEnabled = false
        appUnlockSettings[cardId] = settings
        persistAppUnlockSettings()
        rebuildFamilyControlsShield()
        print("🔓 FamilyControls card unlocked: \(cardId)")
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
        print("🚫 Redirecting away due to active access window for \(bundleId)")
        g.removeObject(forKey: "blockedPaygateBundleId")
        g.removeObject(forKey: "blockedPaygateTimestamp")
        let schemes = primaryAndFallbackSchemes(for: bundleId)
        attemptOpen(schemes: schemes, index: 0, bundleId: bundleId, logCost: 0) { _ in }
    }
    
    private func primaryAndFallbackSchemes(for bundleId: String) -> [String] {
        switch bundleId {
        case "com.burbn.instagram":
            return [
                "instagram://app",
                "instagram://",
                "instagram://feed",
                "instagram://camera",
            ]
        case "com.zhiliaoapp.musically":
            return ["tiktok://"]
        case "com.google.ios.youtube":
            return ["youtube://"]
        case "ph.telegra.Telegraph":
            return ["tg://", "telegram://"]
        case "net.whatsapp.WhatsApp":
            return ["whatsapp://"]
        case "com.toyopagroup.picaboo":
            return ["snapchat://"]
        case "com.facebook.Facebook":
            return ["fb://", "facebook://"]
        case "com.linkedin.LinkedIn":
            return ["linkedin://"]
        case "com.atebits.Tweetie2":
            return ["twitter://", "x://"]
        case "com.reddit.Reddit":
            return ["reddit://"]
        case "com.pinterest":
            return ["pinterest://"]
        case "com.duolingo.DuolingoMobile":
            return ["duolingo://"]
        default:
            print("⚠️ Unknown bundle id \(bundleId), using instagram fallback")
            return ["instagram://"]
        }
    }
    
    private func attemptOpen(schemes: [String], index: Int, bundleId: String, logCost: Int, completion: @escaping (Bool) -> Void) {
        guard index < schemes.count else {
            completion(false)
            return
        }
        
        let scheme = schemes[index]
        guard let url = URL(string: scheme) else {
            attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId, logCost: logCost, completion: completion)
            return
        }
        
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    print("✅ Opened \(bundleId) via \(scheme)")
                    completion(true)
                } else {
                    print("❌ Scheme \(scheme) failed for \(bundleId), trying next")
                    self.attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId, logCost: logCost, completion: completion)
                }
            }
        }
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
        print("🔍 === FAMILY CONTROLS DIAGNOSTICS ===")

        // 1. Проверка авторизации
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.checkAuthorizationStatus()
        }

        // 2. Проверка выбранных приложений
        print("📱 Selected applications:")
        print("   - ApplicationTokens: \(appSelection.applicationTokens.count)")
        print("   - CategoryTokens: \(appSelection.categoryTokens.count)")

        // 3. Проверка бюджета
        print("💰 Budget:")
        print("   - Total minutes: \(budgetEngine.dailyBudgetMinutes)")
        print("   - Remaining minutes: \(budgetEngine.remainingMinutes)")
        print("   - Spent minutes: \(spentMinutes)")

        // 4. Проверка состояния отслеживания
        print("⏱️ Tracking status:")
        print("   - Active: \(isTrackingTime)")
        print("   - Blocked: \(isBlocked)")

        // 5. Проверка UserDefaults
        let userDefaults = UserDefaults.stepsTrader()
        print("💾 Shared UserDefaults:")
        print("   - Budget minutes: \(userDefaults.object(forKey: "budgetMinutes") ?? "nil")")
        print("   - Spent minutes: \(userDefaults.object(forKey: "spentMinutes") ?? "nil")")
        print(
            "   - Monitoring start: \(userDefaults.object(forKey: "monitoringStartTime") ?? "nil")")

        // 6. DeviceActivity диагностика
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.checkDeviceActivityStatus()
        }

        message = "🔍 Diagnostics complete. Check the Xcode console for details."
    }

    func resetStatistics() {
        print("🔄 === RESET STATISTICS BEGIN ===")

        // 1. Останавливаем отслеживание если активно
        if isTrackingTime {
            stopTracking()
        }

        // 2. Сбрасываем время и состояние
        spentMinutes = 0
        spentSteps = 0
        spentTariff = .easy
        isBlocked = false
        currentSessionElapsed = nil

        // 3. Очищаем UserDefaults (App Group)
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
        print("💾 Cleared App Group UserDefaults")

        // 4. Очищаем обычные UserDefaults
        UserDefaults.standard.removeObject(forKey: "dailyBudgetMinutes")
        UserDefaults.standard.removeObject(forKey: "remainingMinutes")
        UserDefaults.standard.removeObject(forKey: "todayAnchor")
        print("💾 Cleared standard UserDefaults")

        // 5. Сбрасываем бюджет вручную (так как resetForToday приватный)
        let todayStart = currentDayStart(for: Date())
        UserDefaults.standard.set(todayStart, forKey: "todayAnchor")
        UserDefaults.standard.set(0, forKey: "dailyBudgetMinutes")
        UserDefaults.standard.set(0, forKey: "remainingMinutes")
        print("💰 Budget reset")

        // 6. Снимаем все блокировки
        // No ManagedSettings shielding anymore. Just stop DeviceActivity monitoring by clearing selection/settings.
        familyControlsService.updateSelection(FamilyActivitySelection())
        familyControlsService.updateMinuteModeMonitoring()

        // 7. Очищаем выбор приложений (как выбор, так и сохраненные данные)
        blockingStore.clearAppSelection()
        print("📱 Cleared app selection and cached data")
        appUnlockSettings = [:]
        dayPassGrants = [:]

        // 8. Пересчитываем бюджет с текущими шагами
        Task {
            do {
                stepsToday = try await fetchStepsForCurrentDay()
                let mins = budgetEngine.minutes(from: stepsToday)
                budgetEngine.setBudget(minutes: mins)
                syncBudgetProperties()  // Sync budget properties for UI updates
                message =
                    "🔄 Stats reset! New budget: \(mins) minutes from \(Int(stepsToday)) steps"
                print("✅ Stats reset. New budget: \(mins) minutes")
            } catch {
                message =
                    "🔄 Stats reset, but refreshing steps failed: \(error.localizedDescription)"
                print("❌ Failed to refresh steps: \(error)")
            }
        }

        print("✅ === RESET COMPLETE ===")
    }

    func sendReturnToAppNotification() {
        // Отправляем первое уведомление через 30 секунд после блокировки
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.scheduleReturnNotification()
        }

        // Периодические напоминания каждые 5 минут
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            self?.schedulePeriodicNotifications()
        }
    }

    private func scheduleReturnNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🚶‍♂️ DOOM CTRL"
        content.body = "Walk more steps to earn extra entertainment time!"
        content.sound = .default
        content.badge = nil

        // Добавляем action для быстрого возврата в приложение
        let returnAction = UNNotificationAction(
            identifier: "RETURN_TO_APP",
            title: "Open DOOM CTRL",
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
                print("❌ Failed to send return notification: \(error)")
            } else {
                print("📤 Sent return to app notification")
            }
        }
    }

    func schedulePeriodicNotifications() {
        guard isBlocked else { return }

        let content = UNMutableNotificationContent()
        content.title = "⏰ DOOM CTRL"
        content.body = "Reminder: walk more steps to unlock!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "periodicReminder-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: true)  // every 5 minutes
        )

        UNUserNotificationCenter.current().add(request)

        // Повторяем через 5 минут если все еще заблокировано
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            self?.schedulePeriodicNotifications()
        }
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
            print("⚠️ Could not fetch step data for silent recalc: \(error)")
            #if targetEnvironment(simulator)
                stepsToday = 2500
            #else
                stepsToday = fallbackCachedSteps()
            #endif
        }
        cacheStepsToday()
        let mins = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: mins)
        if spentMinutes > mins {
            print("⚠️ Spent time (\(spentMinutes)) exceeds budget (\(mins)), correcting...")
            updateSpentTime(minutes: mins)
        }
        syncBudgetProperties()
        print("🔄 Silent budget recalculation: \(mins) minutes from \(Int(stepsToday)) steps")
    }
    
    func handleIncomingURL(_ url: URL) {
        print("🔗 Handling incoming URL: \(url)")
    }
    
    func handleAppDidEnterBackground() {
        print("📱 App entered background")
    }
    
    func handleAppWillEnterForeground() {
        print("📱 App will enter foreground")
        checkDayBoundary()
        scheduleDayBoundaryTimer()
        cleanupExpiredUnlocks()
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
        print("🚀 Bootstrapping AppModel...")
        isBootstrapping = true
        
        // 1. Load data from stores
        await userEconomyStore.loadAppStepsSpentToday()
        await userEconomyStore.loadAppStepsSpentLifetime()
        loadMinuteChargeLogs()
        blockingStore.loadTicketGroups()
        
        // 1.5 Restore daily energy state and spent balance so experience counts persist across restarts
        loadEnergyPreferences()
        loadDailyEnergyState()
        loadSpentStepsBalance()
        
        // 2. Request permissions if needed
        if requestPermissions {
            do {
                try await healthStore.requestAuthorization()
                try await blockingStore.requestAuthorization()
                await requestNotificationPermission()
            } catch {
                print("⚠️ Bootstrap permission request failed: \(error)")
            }
        }
        
        // 3. Refresh data
        await refreshStepsIfAuthorized()
        await refreshSleepIfAuthorized()
        
        // 4. Check state
        checkDayBoundary()
        cleanupExpiredUnlocks()
        
        isBootstrapping = false
        print("✅ AppModel bootstrap complete")
    }
    
    deinit {
        // Stop HealthKit observation
        // healthStore.stopObservingSteps() // Cannot call main actor method in deinit
        
        // Удаляем observer чтобы избежать dangling callback и EXC_BAD_ACCESS
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )
    }
}

@MainActor
private func requestNotificationPermissionIfNeeded() async {
    do { try await DIContainer.shared.makeNotificationService().requestPermission() } catch {
        print("❌ Notification permission failed: \(error)")
    }
}

// MARK: - Permissions helpers
extension AppModel {
    func requestNotificationPermission() async {
        do { try await notificationService.requestPermission() }
        catch { print("❌ Notification permission failed: \(error)") }
    }

    // Debug bonus removed: we intentionally do not support minting energy outside HealthKit/Outer World.
}
