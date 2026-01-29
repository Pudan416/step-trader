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

    static func dayKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    // MARK: - Outer World economy
    private let outerWorldDailyCapKey = "outerworld_dailyCap_v1"
    private let outerWorldLifetimeCollectedKey = "outerworld_totalcollected" // maintained by OuterWorldLocationManager
    private let serverGrantedStepsKey = "serverGrantedSteps_v1"
    private var lastSupabaseSyncAt: Date = .distantPast
    
    // MARK: - Performance optimization
    var rebuildShieldTask: Task<Void, Never>?
    var unlockExpiryTasks: [String: Task<Void, Never>] = [:]  // Tasks to rebuild shield when unlock expires
    

    func isFamilyControlsModeEnabled(for bundleId: String) -> Bool {
        unlockSettings(for: bundleId).familyControlsModeEnabled
    }

    func setFamilyControlsModeEnabled(_ enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        settings.familyControlsModeEnabled = enabled
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseShieldUpsert(bundleId: bundleId)
    }

    // Published properties
    @Published var stepsToday: Double = 0
    @Published var spentSteps: Int = 0
    @Published var spentMinutes: Int = 0  // Реальное время проведенное в приложении
    @Published var spentTariff: Tariff = .easy  // Тариф, по которому были потрачены минуты
    @Published var isTrackingTime = false
    @Published var isBlocked = false  // Показывать ли экран блокировки
    @Published var message: String?
    @Published var currentSessionElapsed: Int?

    // Оплата входа шагами
    @Published var entryCostSteps: Int = 5
    @Published var stepsBalance: Int = 0 {
        didSet {
            // Update totalStepsBalance when stepsBalance changes
            totalStepsBalance = max(0, stepsBalance + bonusSteps)
        }
    }
    @Published var baseEnergyToday: Int = 0
    @Published var dailySleepHours: Double = 0
    @Published var dailyMoveSelections: [String] = []
    @Published var dailyRebootSelections: [String] = []
    @Published var dailyJoySelections: [String] = []
    @Published var preferredMoveOptions: [String] = []
    @Published var preferredRebootOptions: [String] = []
    @Published var preferredJoyOptions: [String] = []
    /// Total non-HealthKit energy.
    /// We keep this as a single published value because many parts of the app rely on it.
    @Published var bonusSteps: Int = 0 {
        didSet {
            // Update totalStepsBalance when bonusSteps changes
            totalStepsBalance = max(0, stepsBalance + bonusSteps)
        }
    }
    /// Energy collected from the Outer World (map drops).
    @Published var outerWorldBonusSteps: Int = 0
    /// Energy granted from Supabase (admin grants / server-side economy).
    @Published var serverGrantedSteps: Int = 0
    @Published var totalStepsBalance: Int = 0
    
    // Helper to update totalStepsBalance from extensions
    @MainActor
    func updateTotalStepsBalance() {
        let newValue = max(0, stepsBalance + bonusSteps)
        if totalStepsBalance != newValue {
            totalStepsBalance = newValue
            // Explicitly notify observers
            objectWillChange.send()
        }
    }
    var effectiveStepsToday: Double { stepsToday + Double(bonusSteps) }
    @Published var spentStepsToday: Int = 0
    @Published var healthAuthorizationStatus: HKAuthorizationStatus = .notDetermined
    
    // Персональные настройки для приложений
    @Published var appUnlockSettings: [String: AppUnlockSettings] = [:]
    // Активированные безлимиты на день по bundleId (дата активации)
    @Published var dayPassGrants: [String: Date] = [:]
    
    @Published var minuteChargeLogs: [MinuteChargeLog] = []
    @Published var minuteTimeByDay: [String: [String: Int]] = [:] // [dayKey: [bundleId: minutes]]
    @Published var appStepsSpentToday: [String: Int] = [:]
    @Published var appStepsSpentByDay: [String: [String: Int]] = [:]
    @Published var appStepsSpentLifetime: [String: Int] = [:]
    
    // MARK: - Shield Groups
    @Published var shieldGroups: [ShieldGroup] = []

    // Budget properties that mirror BudgetEngine for UI updates
    @Published var dailyBudgetMinutes: Int = 0
    @Published var remainingMinutes: Int = 0
    @Published var dayEndHour: Int = UserDefaults.standard.object(forKey: "dayEndHour_v1") as? Int ?? 0
    @Published var dayEndMinute: Int = UserDefaults.standard.object(forKey: "dayEndMinute_v1") as? Int ?? 0
    // PayGate state
    @Published var showPayGate: Bool = false
    @Published var payGateTargetGroupId: String? = nil  // ID группы для PayGate
    
    
    enum PayGateDismissReason {
        case userDismiss
        case background
        case programmatic
    }
    
    @Published var payGateSessions: [String: PayGateSession] = [:]
    @Published var currentPayGateSessionId: String? = nil
    
    // Tariff selection per app per day
    @Published var dailyTariffSelections: [String: Tariff] = [:]
    @Published var showQuickStatusPage = false  // Показывать ли страницу быстрого статуса


    // Handoff token handling
    @Published var handoffToken: HandoffToken? = nil
    @Published var showHandoffProtection = false
    // Startup guard to prevent immediate deep link loops on cold launch
    private let appLaunchTime: Date = Date()

    @Published var appSelection = FamilyActivitySelection() {
        didSet {
            // Предотвращаем рекурсию (когда service обновляет нас обратно)
            guard !isUpdatingAppSelection else { return }
            
            // Проверяем реальные изменения
            let hasChanges = appSelection.applicationTokens != oldValue.applicationTokens
                || appSelection.categoryTokens != oldValue.categoryTokens
            
            guard hasChanges else { return }
            
            // Проверяем, не сохраняли ли мы уже это состояние
            if let lastSaved = lastSavedAppSelection,
               lastSaved.applicationTokens == appSelection.applicationTokens,
               lastSaved.categoryTokens == appSelection.categoryTokens {
                return
            }
            
            // Debounce: отменяем предыдущую задачу сохранения
            saveAppSelectionTask?.cancel()
            
            // Запускаем новую задачу с небольшой задержкой
            saveAppSelectionTask = Task { @MainActor [weak self] in
                // Небольшая задержка для группировки быстрых изменений
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                
                guard let self = self, !Task.isCancelled else { return }
                
                self.isUpdatingAppSelection = true
                defer { self.isUpdatingAppSelection = false }
                
                self.saveAppSelection()
                self.lastSavedAppSelection = self.appSelection
                
                if let service = self.familyControlsService as? FamilyControlsService {
                    service.updateSelection(self.appSelection)
                }
            }
        }
    }

    @Published var isInstagramSelected: Bool = false {
        didSet {
            // Не реагируем, если значение фактически не изменилось (важно для init).
            guard isInstagramSelected != oldValue else { return }
            
            // Предотвращаем рекурсию
            guard !isUpdatingInstagramSelection else { return }

            UserDefaults.standard.set(isInstagramSelected, forKey: "isInstagramSelected")
            if isInstagramSelected {
                setAppAsTarget(bundleId: "com.burbn.instagram")
            } else {
                clearAppSelection()
            }
        }
    }

    // Флаг для предотвращения рекурсии при обновлении Instagram selection
    private var isUpdatingInstagramSelection = false
    
    // MARK: - App Selection Race Condition Prevention
    /// Flag to prevent recursive updates when appSelection changes
    private var isUpdatingAppSelection = false
    /// Debounce task for saving app selection
    private var saveAppSelectionTask: Task<Void, Never>?
    /// Last saved selection for comparison
    private var lastSavedAppSelection: FamilyActivitySelection?
    
    /// Safely update appSelection from external sources (e.g., FamilyControlsService callback)
    /// without triggering recursive didSet updates
    func updateAppSelectionFromService(_ selection: FamilyActivitySelection) {
        guard !isUpdatingAppSelection else { return }
        
        // Skip if no actual change
        guard selection.applicationTokens != appSelection.applicationTokens
            || selection.categoryTokens != appSelection.categoryTokens else { return }
        
        isUpdatingAppSelection = true
        defer { isUpdatingAppSelection = false }
        
        appSelection = selection
        lastSavedAppSelection = selection
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
        // Use safe update to avoid triggering didSet recursively
        isUpdatingAppSelection = true
        defer { isUpdatingAppSelection = false }
        
        let emptySelection = FamilyActivitySelection()
        appSelection = emptySelection
        lastSavedAppSelection = emptySelection
        
        familyControlsService.updateSelection(emptySelection)
        rebuildFamilyControlsShield()
    }

    var startTime: Date?
    var timer: Timer?

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
    }

    func currentDayStart(for date: Date) -> Date {
        let cal = Calendar.current
        // If day end is set to midnight (0:00), use standard start of day
        if dayEndHour == 0 && dayEndMinute == 0 {
            return cal.startOfDay(for: date)
        }
        
        // Calculate the start of the current "day" based on dayEndHour:dayEndMinute
        // The day starts at the previous day's end time
        var comps = DateComponents()
        comps.hour = dayEndHour
        comps.minute = dayEndMinute
        let cutoffToday = cal.nextDate(after: cal.startOfDay(for: date), matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents)
        
        guard let cutoffToday = cutoffToday else {
            return cal.startOfDay(for: date)
        }
        if date >= cutoffToday {
            return cutoffToday
        } else if let prev = cal.date(byAdding: .day, value: -1, to: cutoffToday) {
            return prev
        } else {
            return cal.startOfDay(for: date)
        }
    }
    
    func isSameCustomDay(_ a: Date, _ b: Date) -> Bool {
        currentDayStart(for: a) == currentDayStart(for: b)
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
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "appDayPassGrants_v1") else { return }
        if let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            dayPassGrants = decoded
            clearExpiredDayPasses()
        }
    }
    
    func persistDayPassGrants() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(dayPassGrants) {
            g.set(data, forKey: "appDayPassGrants_v1")
        }
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
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: "appStepsSpentByDay_v1"),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            appStepsSpentByDay = decoded
        } else {
            appStepsSpentByDay = [:]
        }

        if appStepsSpentByDay.isEmpty,
           let legacyData = g.data(forKey: "appStepsSpentToday_v1"),
           let decodedLegacy = try? JSONDecoder().decode([String: Int].self, from: legacyData) {
            appStepsSpentByDay[Self.dayKey(for: Date())] = decodedLegacy
        }

        appStepsSpentToday = appStepsSpentByDay[Self.dayKey(for: Date())] ?? [:]

        if appStepsSpentLifetime.isEmpty {
            appStepsSpentLifetime = appStepsSpentByDay.values.reduce(into: [:]) { result, dayMap in
                for (bundleId, steps) in dayMap {
                    result[bundleId, default: 0] += steps
                }
            }
            persistAppStepsSpentLifetime()
        }
    }
    
    func persistAppStepsSpentToday() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appStepsSpentToday) {
            g.set(data, forKey: "appStepsSpentToday_v1")
        }
    }

    func persistAppStepsSpentByDay() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appStepsSpentByDay) {
            g.set(data, forKey: "appStepsSpentByDay_v1")
        }
    }

    private func loadAppStepsSpentLifetime() {
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: "appStepsSpentLifetime_v1"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            appStepsSpentLifetime = decoded
        } else {
            appStepsSpentLifetime = [:]
        }
    }

    func persistAppStepsSpentLifetime() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appStepsSpentLifetime) {
            g.set(data, forKey: "appStepsSpentLifetime_v1")
            // Sync stats to server
            authService.syncStats()
        }
    }
    
    
    func defaultDayPassCost(forEntryCost entryCost: Int) -> Int {
        if entryCost <= 0 { return 0 }
        return entryCost * 100
    }
    
    // MARK: - Supabase Shield Sync (stubs)
    
    func deleteSupabaseShield(bundleId: String) async {
        // TODO: Implement Supabase shield deletion
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
        case .single:
            return now.addingTimeInterval(60)
        case .minutes5:
            return now.addingTimeInterval(5 * 60)
        case .minutes15:
            return now.addingTimeInterval(15 * 60)
        case .minutes30:
            return now.addingTimeInterval(30 * 60)
        case .hour1:
            return now.addingTimeInterval(60 * 60)
        case .hour2:
            return now.addingTimeInterval(2 * 60 * 60)
        case .day1:
            var comps = DateComponents()
            comps.hour = dayEndHour
            comps.minute = dayEndMinute
            let cal = Calendar.current
            if let end = cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents) {
                return end
            }
            return now.addingTimeInterval(24 * 60 * 60)
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
        let todayStart = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(todayStart, forKey: "todayAnchor")
        UserDefaults.standard.set(0, forKey: "dailyBudgetMinutes")
        UserDefaults.standard.set(0, forKey: "remainingMinutes")
        print("💰 Budget reset")

        // 6. Снимаем все блокировки
        // No ManagedSettings shielding anymore. Just stop DeviceActivity monitoring by clearing selection/settings.
        familyControlsService.updateSelection(FamilyActivitySelection())
        familyControlsService.updateMinuteModeMonitoring()

        // 7. Очищаем выбор приложений (как выбор, так и сохраненные данные)
        isUpdatingAppSelection = true
        appSelection = FamilyActivitySelection()
        lastSavedAppSelection = FamilyActivitySelection()
        isUpdatingAppSelection = false
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

    func notifyAccessWindow(remainingSeconds: Int, bundleId: String) {
        let state = UIApplication.shared.applicationState
        if state == .active {
            let mins = max(0, remainingSeconds / 60)
            let secs = max(0, remainingSeconds % 60)
            let timeText = mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
            message = "⏱️ Access active for \(bundleId): \(timeText) left"
            print("⏱️ Foreground access reminder: \(bundleId) \(timeText)")
        }
    }
    
    private func schedulePeriodicNotifications() {
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

    func bootstrap(requestPermissions: Bool = true) async {
        print("🚀 DOOM CTRL: Starting bootstrap...")

        // Обновляем время из shared storage (на случай если DeviceActivity обновил его)
        // Note: spentMinutes and spentSteps are managed via updateSpentTime()

        do {
            let authStatus = healthKitService.authorizationStatus()
            print("🏥 HealthKit status at bootstrap: \(authStatus.rawValue) (note: this is WRITE status)")
            if requestPermissions {
                print("📊 Requesting HealthKit authorization...")
                try await healthKitService.requestAuthorization()
                print("✅ HealthKit authorization completed")
                
                print("🔐 Requesting Family Controls authorization...")
                do {
                    try await familyControlsService.requestAuthorization()
                    print("✅ Family Controls authorization completed")
                } catch {
                    print("⚠️ Family Controls authorization failed: \(error)")
                }
                
                print("🔔 Requesting notification permissions...")
                try await notificationService.requestPermission()
                print("✅ Notification permissions completed")
            } else {
                print("⏳ Skipping HealthKit prompt (intro not finished)")
                print("⏳ Skipping Family Controls prompt (intro not finished)")
                print("⏳ Skipping notifications prompt (intro not finished)")
            }

            // Always try to fetch steps - this is the only way to know if read access works
            // authorizationStatus() only shows WRITE status, not READ status
            print("📈 Fetching today's steps...")
            do {
                stepsToday = try await fetchStepsForCurrentDay()
                print("✅ Today's steps: \(Int(stepsToday))")
                cacheStepsToday()
                
                // Также обновляем данные о сне
                await refreshSleepIfAuthorized()
            } catch {
                print("⚠️ Could not fetch step data: \(error)")
                // На симуляторе или если нет данных, используем демо-значение
                #if targetEnvironment(simulator)
                    stepsToday = 2500  // Демо-значение для симулятора
                    print("🎮 Using demo steps for Simulator: \(Int(stepsToday))")
                #else
                    loadCachedStepsToday()
                    print("📱 Using cached steps: \(Int(stepsToday))")
                #endif
            }

            print("💰 Calculating budget...")
            budgetEngine.resetIfNeeded()
            let budgetMinutes = budgetEngine.minutes(from: stepsToday)
            
            // Load daily energy preferences and state
            loadEnergyPreferences()
            resetDailyEnergyIfNeeded()
            loadDailyEnergyState()
            
            // CRITICAL: Load spent steps balance BEFORE recalculating daily energy
            // This ensures spentStepsToday is loaded before stepsBalance is calculated
            loadSpentStepsBalance()
            
            recalculateDailyEnergy()
            
            // Load shield groups
            loadShieldGroups()
            
            // Clean up expired unlocks and rebuild shield
            cleanupExpiredUnlocks()
            
            // Load app unlock settings
            loadAppUnlockSettings()
            
            // Apply shield after bootstrap
            rebuildFamilyControlsShield()
            budgetEngine.setBudget(minutes: budgetMinutes)
            syncBudgetProperties()  // Sync budget properties for UI updates
            
            // Ensure totalStepsBalance is updated after all loading
            updateTotalStepsBalance()

        if stepsToday == 0 {
            print("⚠️ No steps available - budget is 0 minutes")
        } else {
            print("✅ Budget calculated: \(budgetMinutes) minutes from \(Int(stepsToday)) steps")
        }
        cacheStepsToday()

            print("🎉 Bootstrap completed successfully!")

            // Убрали автоматический выбор приложений — только ручной выбор

            // Проверяем, нужно ли показать Quick Status Page
            checkForQuickStatusPage()

        } catch {
            print("❌ Bootstrap failed: \(error)")
            message = "Initialization error: \(error.localizedDescription)"
        }
    }
    
    private func checkForQuickStatusPage() {
        // Check if we should show the quick status page
        // For now, we don't auto-show it, but this can be customized
        // based on conditions like first launch, specific state, etc.
        _ = UserDefaults.stepsTrader().bool(forKey: "hasShownQuickStatusPage")
        
        // Example: Show on first launch (can be customized)
        // if !hasShownQuickStatus {
        //     showQuickStatusPage = true
        //     defaults.set(true, forKey: "hasShownQuickStatusPage")
        // }
    }
    
    func withTimeout(seconds: TimeInterval, operation: @escaping () async throws -> Void) async rethrows {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Add the operation task
            group.addTask {
                try await operation()
            }
            
            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            
            // Wait for the first completed task
            _ = try await group.next()
            group.cancelAll()
        }
    }

    func recalc() async throws {
        budgetEngine.resetIfNeeded()

        do {
            stepsToday = try await fetchStepsForCurrentDay()
        } catch {
            print("⚠️ Could not fetch step data for recalc: \(error)")
            #if targetEnvironment(simulator)
                stepsToday = 2500  // Демо-значение для симулятора
            #else
                stepsToday = fallbackCachedSteps()
            #endif
        }
        cacheStepsToday()

        let mins = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: mins)

        // Проверяем и корректируем потраченное время после пересчета бюджета
        if spentMinutes > mins {
            print("⚠️ Spent time (\(spentMinutes)) exceeds budget (\(mins)), correcting...")
            updateSpentTime(minutes: mins)
        }

        syncBudgetProperties()  // Sync budget properties for UI updates
        message = "✅ Budget recalculated: \(mins) minutes (\(Int(stepsToday)) steps)"
    }

    func handleIncomingURL(_ url: URL) {
        // Handle incoming URL schemes
        print("🔗 Handling incoming URL: \(url)")
        // Add URL handling logic here if needed
    }
    
    func handleAppDidEnterBackground() {
        // Handle app entering background
        print("📱 App entered background")
        // Add background logic here if needed
    }
    
    func handleAppWillEnterForeground() {
        // Handle app entering foreground
        print("📱 App will enter foreground")
        
        // Clean up expired unlocks when app returns from background
        cleanupExpiredUnlocks()
        
        Task {
            await refreshStepsBalance()
            await refreshSleepIfAuthorized()
        }
    }
    
    func recalcSilently() async {
        budgetEngine.resetIfNeeded()

        do {
            stepsToday = try await fetchStepsForCurrentDay()
        } catch {
            print("⚠️ Could not fetch step data for silent recalc: \(error)")
            #if targetEnvironment(simulator)
                stepsToday = 2500  // Демо-значение для симулятора
            #else
                stepsToday = fallbackCachedSteps()
            #endif
        }
        cacheStepsToday()

        let mins = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: mins)

        // Проверяем и корректируем потраченное время после пересчета бюджета
        if spentMinutes > mins {
            print("⚠️ Spent time (\(spentMinutes)) exceeds budget (\(mins)), correcting...")
            updateSpentTime(minutes: mins)
        }

        syncBudgetProperties()  // Sync budget properties for UI updates
        print("🔄 Silent budget recalculation: \(mins) minutes from \(Int(stepsToday)) steps")
    }

    func toggleRealBlocking() {
        print("🚀 === TOGGLE REAL BLOCKING START ===")
        print("🔐 Family Controls authorized: \(familyControlsService.isAuthorized)")
        print("📱 Selected apps: \(appSelection.applicationTokens.count)")
        print("📂 Selected categories: \(appSelection.categoryTokens.count)")
        print("⏱️ Tracking active: \(isTrackingTime)")
        print("💰 Remaining minutes: \(budgetEngine.remainingMinutes)")

        guard familyControlsService.isAuthorized else {
            print("❌ Family Controls not authorized - aborting")
            message = "❌ Family Controls not authorized"
            return
        }

        guard !appSelection.applicationTokens.isEmpty || !appSelection.categoryTokens.isEmpty else {
            print("❌ No applications selected - aborting")
            message = "❌ Select an app to block first"
            return
        }

        if isTrackingTime {
            print("🛑 Stopping tracking")
            stopTracking()
            message = "🔓 Blocking disabled"
            print("✅ Tracking stopped")
        } else {
            print("🚀 Starting tracking")
            // Показываем сообщение сразу, чтобы UI не зависал
            message = "🛡️ Starting tracking..."
            print("📱 UI message set to 'Starting tracking...'")

            // Запускаем отслеживание асинхронно
            Task { [weak self] in
                print("🔄 Created async task to start tracking")
                await MainActor.run {
                    print("🎯 Running startTracking on the main thread")
                    self?.startTracking()
                    let appCount = self?.appSelection.applicationTokens.count ?? 0
                    let remainingMinutes = self?.budgetEngine.remainingMinutes ?? 0
                    self?.message =
                        "🛡️ Blocking active. Limit: \(remainingMinutes) minutes."
                    print(
                        "✅ Tracking started: \(appCount) apps, \(remainingMinutes) minutes"
                    )
                }
            }
        }

        print("🚀 === TOGGLE REAL BLOCKING END ===")
    }

    
    deinit {
        // Stop HealthKit observation
        healthKitService.stopObservingSteps()
        
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
