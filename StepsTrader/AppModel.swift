import AVFoundation
import AudioToolbox
import Combine
import Foundation
import HealthKit
import UIKit
import SwiftUI
import UIKit
import UserNotifications

// MARK: - AppModel
@MainActor
final class AppModel: ObservableObject {
    // Dependencies
    private let healthKitService: any HealthKitServiceProtocol
    let familyControlsService: any FamilyControlsServiceProtocol
    let notificationService: any NotificationServiceProtocol
    private let budgetEngine: any BudgetEngineProtocol
    private let shortcutInstallURLString = "https://www.icloud.com/shortcuts/"

    static func dayKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private let minuteTariffBundleKey = "minuteTariffBundleId_v1"
    private let minuteTariffLastTickKey = "minuteTariffLastTick_v1"
    private let minuteTariffRateKey = "minuteTariffRate_v1"

    private func timeAccessSelectionKey(for bundleId: String) -> String {
        "timeAccessSelection_v1_\(bundleId)"
    }

    func timeAccessSelection(for bundleId: String) -> FamilyActivitySelection {
        let g = UserDefaults.stepsTrader()
        #if canImport(FamilyControls)
        if let data = g.data(forKey: timeAccessSelectionKey(for: bundleId)),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            return decoded
        }
        #endif
        return FamilyActivitySelection()
    }

    func saveTimeAccessSelection(_ selection: FamilyActivitySelection, for bundleId: String) {
        let g = UserDefaults.stepsTrader()
        #if canImport(FamilyControls)
        if let data = try? JSONEncoder().encode(selection) {
            g.set(data, forKey: timeAccessSelectionKey(for: bundleId))
        }
        #endif
    }

    func applyFamilyControlsSelection(for bundleId: String) {
        _ = bundleId
        rebuildFamilyControlsShield()
    }

    func disableFamilyControlsShield() {
        rebuildFamilyControlsShield()
    }

    func rebuildFamilyControlsShield() {
        var combined = FamilyActivitySelection()
        for (bundleId, settings) in appUnlockSettings where settings.familyControlsModeEnabled {
            let selection = timeAccessSelection(for: bundleId)
            combined.applicationTokens.formUnion(selection.applicationTokens)
            combined.categoryTokens.formUnion(selection.categoryTokens)
        }
        if let service = familyControlsService as? FamilyControlsService {
            service.updateSelection(combined)
            if combined.applicationTokens.isEmpty && combined.categoryTokens.isEmpty {
                service.disableShield()
            } else {
                service.enableShield()
            }
            service.updateMinuteModeMonitoring()
        }
    }

    func isTimeAccessEnabled(for bundleId: String) -> Bool {
        let selection = timeAccessSelection(for: bundleId)
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    func isMinuteTariffEnabled(for bundleId: String) -> Bool {
        unlockSettings(for: bundleId).minuteTariffEnabled
    }

    func setMinuteTariffEnabled(_ enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        settings.minuteTariffEnabled = enabled
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
    }

    func isFamilyControlsModeEnabled(for bundleId: String) -> Bool {
        unlockSettings(for: bundleId).familyControlsModeEnabled
    }

    func setFamilyControlsModeEnabled(_ enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        settings.familyControlsModeEnabled = enabled
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
    }

    func minutesAvailable(for bundleId: String) -> Int {
        let costPerMinute = unlockSettings(for: bundleId).entryCostSteps
        guard costPerMinute > 0 else { return Int.max }
        return max(0, totalStepsBalance / costPerMinute)
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
    @Published var entryCostSteps: Int = 100
    @Published var stepsBalance: Int = 0
    /// Total non-HealthKit energy (sum of debug + Outer World).
    /// Kept as a single published value because many parts of the app rely on it.
    @Published private(set) var bonusSteps: Int = 0
    /// Energy collected from the Outer World (map drops).
    @Published private(set) var outerWorldBonusSteps: Int = 0
    /// Debug/other bonus energy (e.g. secret taps / legacy values).
    @Published private(set) var debugBonusSteps: Int = 0
    var totalStepsBalance: Int { max(0, stepsBalance + bonusSteps) }
    var effectiveStepsToday: Double { stepsToday + Double(bonusSteps) }
    @Published var spentStepsToday: Int = 0
    @Published var healthAuthorizationStatus: HKAuthorizationStatus = .notDetermined
    
    struct AppUnlockSettings: Codable {
        var entryCostSteps: Int
        var dayPassCostSteps: Int
        var allowedWindows: Set<AccessWindow> = [.single, .minutes5, .hour1] // day pass off by default
        var minuteTariffEnabled: Bool = false
        var familyControlsModeEnabled: Bool = false
    }
    
    struct AppOpenLog: Codable, Identifiable {
        var id: UUID = UUID()
        let bundleId: String
        let date: Date
        let spentSteps: Int?
    }
    
    struct MinuteChargeLog: Codable, Identifiable {
        var id: UUID { UUID() }
        let bundleId: String
        let timestamp: Date
        let cost: Int
        let balanceAfter: Int
    }
    
    @Published var appOpenLogs: [AppOpenLog] = []
    @Published var minuteChargeLogs: [MinuteChargeLog] = []
    @Published var minuteTimeByDay: [String: [String: Int]] = [:] // [dayKey: [bundleId: minutes]]
    @Published var appStepsSpentToday: [String: Int] = [:]
    @Published var appStepsSpentByDay: [String: [String: Int]] = [:]
    @Published var appStepsSpentLifetime: [String: Int] = [:]
    
    struct DailyStory: Codable {
        let dateKey: String
        let english: String
        let russian: String
        let createdAt: Date
    }
    @Published var dailyStories: [String: DailyStory] = [:]
    
    // Персональные настройки для приложений
    @Published private(set) var appUnlockSettings: [String: AppUnlockSettings] = [:]
    // Активированные безлимиты на день по bundleId (дата активации)
    @Published private var dayPassGrants: [String: Date] = [:]

    // Budget properties that mirror BudgetEngine for UI updates
    @Published var dailyBudgetMinutes: Int = 0
    @Published var remainingMinutes: Int = 0
    @Published var dayEndHour: Int = UserDefaults.standard.object(forKey: "dayEndHour_v1") as? Int ?? 0
    @Published var dayEndMinute: Int = UserDefaults.standard.object(forKey: "dayEndMinute_v1") as? Int ?? 0
    // PayGate state
    @Published var showPayGate: Bool = false
    @Published var payGateTargetBundleId: String? = nil  // Mirrors current session for legacy uses
    
    struct PayGateSession: Identifiable {
        let id: String  // bundleId
        let bundleId: String
        let startedAt: Date
    }
    @Published var payGateSessions: [String: PayGateSession] = [:]
    @Published var currentPayGateSessionId: String? = nil
    
    // Tariff selection per app per day
    @Published var dailyTariffSelections: [String: Tariff] = [:]
    @Published var showQuickStatusPage = false  // Показывать ли страницу быстрого статуса

    // Shortcut message handling
    @Published var shortcutMessage: String? = nil
    @Published var showShortcutMessage = false

    // Handoff token handling
    @Published var handoffToken: HandoffToken? = nil
    @Published var showHandoffProtection = false
    // Startup guard to prevent immediate deep link loops on cold launch
    private let appLaunchTime: Date = Date()

    @Published var appSelection = FamilyActivitySelection() {
        didSet {
            // Синхронизируем с FamilyControlsService только если есть реальные изменения
            if appSelection.applicationTokens != oldValue.applicationTokens
                || appSelection.categoryTokens != oldValue.categoryTokens
            {
                syncAppSelectionToService()
                saveAppSelection()  // Сохраняем выбор пользователя
                if let service = familyControlsService as? FamilyControlsService {
                    service.updateSelection(appSelection)
                }
            }
        }
    }

    @Published var isInstagramSelected: Bool = false {
        didSet {
            // Предотвращаем рекурсию
            guard !isUpdatingInstagramSelection else { return }

            UserDefaults.standard.set(isInstagramSelected, forKey: "isInstagramSelected")
            if isInstagramSelected {
                setInstagramAsTarget()
            } else {
                clearAppSelection()
            }
        }
    }

    // Флаг для предотвращения рекурсии при обновлении Instagram selection
    private var isUpdatingInstagramSelection = false

    private var startTime: Date?
    private var timer: Timer?

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

        // Initialize budget properties
        self.dailyBudgetMinutes = budgetEngine.dailyBudgetMinutes
        self.remainingMinutes = budgetEngine.remainingMinutes
        if let engine = budgetEngine as? BudgetEngine {
            self.dayEndHour = engine.dayEndHour
            self.dayEndMinute = engine.dayEndMinute
        }
        
        // Sync entry cost with current tariff
        syncEntryCostWithTariff()

        // Восстановим закреплённый выбор приложений (если есть)
        if let service = familyControlsService as? FamilyControlsService {
            // FamilyControlsService сам вызвал restorePersistentSelection() в init
            self.appSelection = service.selection
        }

        // Загрузка бонусного баланса от секретного действия
        loadDebugStepsBonus()
        // Загрузка баланса шагов
        loadSpentStepsBalance()
        // Загрузка стоимости входа
        loadEntryCost()
        // Загрузка индивидуальных настроек
        loadAppUnlockSettings()
        rebuildFamilyControlsShield()
        loadDayPassGrants()
        loadAppOpenLogs()
        loadMinuteChargeLogs()
        loadAppStepsSpentLifetime()
        loadAppStepsSpentToday()
        loadDailyTariffSelections()
        loadDailyStories()
        loadCachedStepsToday()
        if stepsToday > 0 {
            // Use cached steps to keep UI/budget non-zero on cold launch
            let mins = budgetEngine.minutes(from: stepsToday)
            budgetEngine.setBudget(minutes: mins)
            syncBudgetProperties()
            stepsBalance = max(0, Int(stepsToday) - spentStepsToday)
            UserDefaults.stepsTrader().set(stepsBalance, forKey: "stepsBalance")
        }

        // Инициализируем значения по умолчанию если их нет
        if entryCostSteps == 0 {
            entryCostSteps = 100  // 100 шагов по умолчанию
            persistEntryCost(tariff: .easy)
        }

        // Обновляем баланс шагов и запрашиваем HealthKit, если онбординг уже пройден
        let hasSeenIntro = UserDefaults.standard.bool(forKey: "hasSeenIntro_v3")
        if hasSeenIntro {
            Task {
                await ensureHealthAuthorizationAndRefresh()
            }
        } else {
            print("⏳ Skipping HealthKit prompt until intro is finished")
        }
        
        // Start automatic step updates if onboarding finished
        if hasSeenIntro {
            startStepObservation()
        } else {
            print("⏳ Skipping step observation until intro is finished")
        }

        print("🎯 AppModel initialized with dependencies")

        // Загружаем сохраненное состояние Instagram
        self.isInstagramSelected = UserDefaults.standard.bool(forKey: "isInstagramSelected")

        // Синхронизируем начальное состояние без вызова didSet
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Сначала загружаем сохраненный выбор приложений
            self.loadAppSelection()

            // Если нет сохраненного выбора, пробуем загрузить из FamilyControlsService
            if self.appSelection.applicationTokens.isEmpty
                && self.appSelection.categoryTokens.isEmpty
            {
                print("🔄 No saved selection found, checking FamilyControlsService...")
                if !self.familyControlsService.selection.applicationTokens.isEmpty
                    || !self.familyControlsService.selection.categoryTokens.isEmpty
                {
                    self.appSelection = self.familyControlsService.selection
                    print(
                        "🔄 Loaded from FamilyControlsService: \(self.appSelection.applicationTokens.count) apps"
                    )
                }
            } else {
                // Если есть сохраненный выбор, синхронизируем его с FamilyControlsService
                print("🔄 Found saved selection, syncing to FamilyControlsService...")
                self.syncAppSelectionToService()
            }

            // Восстанавливаем сохраненное время использования
            self.loadSpentTime()
            print(
                "🔄 Initial sync complete: \(self.appSelection.applicationTokens.count) apps, \(self.appSelection.categoryTokens.count) categories"
            )
        }

        // Подписываемся на уведомления о жизненном цикле приложения
        setupAppLifecycleObservers()
        
        // Подписка на уведомление о сборе энергии из Outer World
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnergyCollected(_:)),
            name: NSNotification.Name("com.steps.trader.energy.collected"),
            object: nil
        )

        // Подписка на дарвиновское уведомление от сниппета/интента (безопасная привязка observer)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, name, object, userInfo in
                guard let observer = observer, let name = name else { return }
                let `self` = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
                if name.rawValue as String == "com.steps.trader.refresh" {
                    Task { @MainActor in
                        await `self`.recalcSilently()
                        `self`.loadSpentTime()
                    }
                } else if name.rawValue as String == "com.steps.trader.paygate" {
                    Task { @MainActor in
                        print("📱 Received PayGate notification from shortcut")
                        if let userInfo = userInfo as? [String: Any],
                           let target = userInfo["target"] as? String,
                           let bundleId = userInfo["bundleId"] as? String {
                            print("📱 PayGate notification - target: \(target), bundleId: \(bundleId)")
                            `self`.startPayGateSession(for: bundleId)
                        }
                    }
                } else if name.rawValue as String == "com.steps.trader.logs" {
                    Task { @MainActor in
                        `self`.loadAppOpenLogs()
                    }
                }
            },
            "com.steps.trader.refresh" as CFString,
            nil,
            .deliverImmediately
        )
    }
    
    // MARK: - Outer World Energy Collection
    
    @objc private func handleEnergyCollected(_ notification: Notification) {
        guard let energy = notification.userInfo?["energy"] as? Int else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Add energy to Outer World bonus (separated from HealthKit energy)
            self.outerWorldBonusSteps += energy
            self.syncAndPersistBonusBreakdown()
            
            // Update total collected stats
            let collectedKey = "outerworld_totalcollected_global"
            let current = UserDefaults.standard.integer(forKey: collectedKey)
            UserDefaults.standard.set(current + energy, forKey: collectedKey)
            
            print("⚡ Outer World: Collected \(energy) energy. Bonus now: \(self.bonusSteps)")
        }
    }

    // MARK: - PayGate handlers + Pay per entry
    func handleIncomingURL(_ url: URL) {
        let host = url.host?.lowercased() ?? ""
        let scheme = url.scheme?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let target = components?.queryItems?.first(where: { $0.name == "target" })?.value
        
        print("🔗 handleIncomingURL called with: \(url)")
        print("🔗 URL details - scheme: \(scheme), host: \(host), target: \(target ?? "nil")")
        
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        
        // Check for recent URL handling to prevent rapid successive calls
        if let lastURLHandleTime = userDefaults.object(forKey: "lastURLHandleTime") as? Date {
            let timeSinceLastHandle = now.timeIntervalSince(lastURLHandleTime)
            if timeSinceLastHandle < 1.0 {
                print("🚫 URL handled too recently (\(String(format: "%.1f", timeSinceLastHandle))s), ignoring to prevent loop")
                return
            }
        }

        // Update last URL handle time
        userDefaults.set(now, forKey: "lastURLHandleTime")

        if host == "pay" {
            let bundleIdForPay = TargetResolver.bundleId(from: target)
            if let bundleIdForPay, isFamilyControlsModeEnabled(for: bundleIdForPay) {
                print("🛡️ Shield pay deeplink for minute mode: \(bundleIdForPay)")
                Task { @MainActor in
                    if let familyService = familyControlsService as? FamilyControlsService {
                        familyService.allowOneSession()
                    }
                    let now = Date()
                    userDefaults.set(now, forKey: "lastPayGateAction")
                    userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader")
                    userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader_\(bundleIdForPay)")
                    await handleMinuteTariffEntry(for: bundleIdForPay)
                }
                return
            }

            Task { @MainActor in
                await refreshStepsBalance()
                startPayGateSession(for: bundleIdForPay ?? "unknown")
                let settings = unlockSettings(for: bundleIdForPay)
                if hasDayPass(for: bundleIdForPay) {
                    message = "✅ Day pass already active for today."
                } else if canPayForEntry(for: bundleIdForPay) {
                    _ = payForEntry(for: bundleIdForPay)
                    message = "✅ \(settings.entryCostSteps) steps deducted. Access granted."
                } else {
                    let shortage = max(0, settings.entryCostSteps - totalStepsBalance)
                    message =
                        "❌ Not enough steps. Need another \(shortage) steps."
                }
            }
            return
        }

        // поддержка: steps-trader://pay?target=instagram | steps-trader://guard?target=instagram
        let isPay = (host == "pay" || url.path.contains("pay"))
        let isGuard = (host == "guard" || url.path.contains("guard"))
        guard isPay || isGuard else { return }
        let bundleId: String? = TargetResolver.bundleId(from: target)
        if let bid = bundleId { startPayGateSession(for: bid) }
        print("🎯 Deeplink: host=\(url.host ?? "nil") target=\(bundleId ?? "nil")")

        // Если guard-режим: сразу включаем shielding и открываем целевое приложение → iOS покажет системную шторку
        if isGuard, let familyService = familyControlsService as? FamilyControlsService {
            // Включаем щит для текущего selection (ожидается, что пользователь заранее выбрал приложение)
            familyService.enableShield()
            // Пытаемся открыть target для вызова системной шторки
            if let bid = bundleId {
                let scheme: String
                switch bid {
                case "com.burbn.instagram": scheme = "instagram://"
                case "com.zhiliaoapp.musically": scheme = "tiktok://"
                case "com.google.ios.youtube": scheme = "youtube://"
                default: scheme = ""
                }
                if let url = URL(string: scheme), !scheme.isEmpty { UIApplication.shared.open(url) }
            }
            return
        }

        // Otherwise show our pay gate overlay with a pay button
        if let bundleId {
            startPayGateSession(for: bundleId)
        }
        print("🎯 PayGate: target=\(payGateTargetBundleId ?? "nil") show=\(showPayGate)")
        if let engine = budgetEngine as? BudgetEngine { engine.reloadFromStorage() }
    }

    // MARK: - PayGate payment pipeline
    func handlePayGatePayment(
        for bundleId: String,
        window: AccessWindow = .single,
        costOverride: Int? = nil
    ) async {
        if isFamilyControlsModeEnabled(for: bundleId) || isMinuteTariffEnabled(for: bundleId) {
            if let familyService = familyControlsService as? FamilyControlsService {
                familyService.disableShield()
                familyService.updateMinuteModeMonitoring()
            }
            await handleMinuteTariffEntry(for: bundleId)
            return
        }

        _ = UserDefaults.stepsTrader()
        await refreshStepsBalance()
        let settings = unlockSettings(for: bundleId)
        let effectiveCost = costOverride ?? settings.entryCostSteps
        print("🎯 PayGate: Evaluating payment for \(bundleId)")
        print("   - stepsToday: \(Int(stepsToday))")
        print("   - stepsBalance: base \(stepsBalance), bonus \(bonusSteps), total \(totalStepsBalance)")
        print("   - entryCostSteps: \(effectiveCost)")
        print("   - dayPassCostSteps: \(settings.dayPassCostSteps)")
        print("   - selected apps: \(appSelection.applicationTokens.count)")
        print("   - selected categories: \(appSelection.categoryTokens.count)")

        let dayPassActive = hasDayPass(for: bundleId)
        if dayPassActive {
            message = "✅ Day pass active for today."
            print("✅ PayGate: Day pass already active for \(bundleId)")
        } else {
            guard canPayForEntry(for: bundleId, costOverride: costOverride) else {
                let shortage = max(0, effectiveCost - totalStepsBalance)
                message =
                    "❌ Not enough steps. Need another \(shortage) steps."
                print("❌ PayGate: Not enough steps (total balance \(totalStepsBalance) < cost \(effectiveCost))")
                return
            }

            guard payForEntry(for: bundleId, costOverride: costOverride) else {
                print("❌ PayGate: payForEntry() returned false")
                return
            }
            print("✅ PayGate: payForEntry() succeeded; new balance \(totalStepsBalance)")

            message = "✅ \(effectiveCost) steps deducted. Access granted."
        }

        print("✅ PayGate: Steps deducted or day pass active, proceeding to open target app")

        let appliedWindow: AccessWindow = (dayPassActive || window == .day1) ? .day1 : window
        applyAccessWindow(appliedWindow, for: bundleId)

        let logCost: Int = (appliedWindow == .single && !dayPassActive) ? effectiveCost : 0

        markPayGateOpen(for: bundleId)

        openTargetAppFromPayGate(bundleId, logCost: logCost) { [weak self] opened in
            guard let self = self else { return }
            if opened {
            } else {
                self.message = "⚠️ Could not open the target app. Try again."
            }
            self.endPayGateSession(bundleId)
        }
    }

    func handleMinuteTariffEntry(for bundleId: String) async {
        await refreshStepsBalance()
        let settings = unlockSettings(for: bundleId)
        let rate = settings.entryCostSteps
        guard rate > 0 else {
            message = "✅ Access granted."
            openTargetAppFromPayGate(bundleId, logCost: 0) { [weak self] opened in
                guard let self = self else { return }
                if !opened {
                    self.message = "⚠️ Could not open the target app. Try again."
                }
                self.endPayGateSession(bundleId)
            }
            return
        }

        let minutesLeft = minutesAvailable(for: bundleId)
        guard minutesLeft > 0 else {
            message = "❌ Not enough steps for minute access."
            return
        }

        startMinuteTariffSession(for: bundleId, rate: rate)
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(Date().addingTimeInterval(8), forKey: "suppressShortcutUntil")
        markPayGateOpen(for: bundleId)

        openTargetAppFromPayGate(bundleId, logCost: 0) { [weak self] opened in
            guard let self = self else { return }
            if !opened {
                self.message = "⚠️ Could not open the target app. Try again."
            }
            self.endPayGateSession(bundleId)
        }
    }

    private func markPayGateOpen(for bundleId: String) {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader")
        userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader_\(bundleId)")
        userDefaults.set(now, forKey: "lastPayGateAction")
        userDefaults.set(now, forKey: "payGateLastOpen")
        userDefaults.removeObject(forKey: "shouldShowPayGate")
        userDefaults.removeObject(forKey: "payGateTargetBundleId")
        userDefaults.removeObject(forKey: "shortcutTriggered")
        userDefaults.removeObject(forKey: "shortcutTarget")
        userDefaults.removeObject(forKey: "shortcutTriggerTime")
    }

    private func persistSessionAllowanceMetadata() {
        guard !appSelection.applicationTokens.isEmpty else { return }

        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(Date().addingTimeInterval(60 * 5), forKey: "sessionAllowedUntil")

        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: appSelection.applicationTokens as NSSet, requiringSecureCoding: true)
        {
            userDefaults.set(data, forKey: "sessionAllowedTokens")
        }
    }

    private func openTargetAppFromPayGate(_ bundleId: String, logCost: Int, completion: @escaping (Bool) -> Void) {
        let schemes = primaryAndFallbackSchemes(for: bundleId)
        guard !schemes.isEmpty else {
            print("❌ PayGate: No URL schemes available for bundle \(bundleId)")
            completion(false)
            return
        }

        let target = bundleId
        showPayGate = false
        payGateTargetBundleId = nil
        payGateSessions.removeAll()
        currentPayGateSessionId = nil
        attemptOpen(schemes: schemes, index: 0, bundleId: target, logCost: logCost, completion: completion)
    }

    private func attemptOpen(
        schemes: [String],
        index: Int,
        bundleId: String,
        logCost: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < schemes.count else {
            print("❌ PayGate: Failed to open \(bundleId) after trying all schemes")
            completion(false)
            return
        }

        let scheme = schemes[index]
        guard let url = URL(string: scheme) else {
            print("⚠️ PayGate: Invalid URL scheme \(scheme), trying next")
            attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId, logCost: logCost, completion: completion)
            return
        }

        print("🚀 PayGate: Attempting to open \(bundleId) with scheme \(scheme)")
        UIApplication.shared.open(url) { [weak self] success in
            guard let self = self else { return }

            if success {
                print("✅ PayGate: Successfully opened \(bundleId)")
                self.recordAutomationOpen(bundleId: bundleId, spentSteps: logCost)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self.showPayGate = false
                    self.payGateTargetBundleId = nil
                    completion(true)
                }
            } else {
                print("❌ PayGate: Scheme \(scheme) failed for \(bundleId), trying next")
                self.attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId, logCost: logCost, completion: completion)
            }
        }
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
            print("⚠️ PayGate: Unknown bundle id \(bundleId), using instagram fallback")
            return ["instagram://"]
        }
    }

    // MARK: - PayGate sessions
    @MainActor
    func startPayGateSession(for bundleId: String) {
        if isAccessBlocked(for: bundleId) {
            print("🚫 PayGate blocked until window expires for \(bundleId)")
            if let remaining = remainingAccessSeconds(for: bundleId) {
                notifyAccessWindow(remainingSeconds: remaining, bundleId: bundleId)
            }
            // Продолжаем показывать PayGate, чтобы пользователь видел статус и мог управлять доступом
        }
        
        // Align PayGate cost with the current level available for this shield
        applyCurrentLevelCosts(for: bundleId)

        let session = PayGateSession(id: bundleId, bundleId: bundleId, startedAt: Date())
        payGateSessions[bundleId] = session
        currentPayGateSessionId = bundleId
        payGateTargetBundleId = bundleId
        showPayGate = true
        
        let g = UserDefaults.stepsTrader()
        g.set(true, forKey: "shouldShowPayGate")
        g.set(bundleId, forKey: "payGateTargetBundleId")
    }
    
    @MainActor
    func endPayGateSession(_ bundleId: String) {
        payGateSessions.removeValue(forKey: bundleId)
        if currentPayGateSessionId == bundleId {
            currentPayGateSessionId = payGateSessions.keys.first
            payGateTargetBundleId = currentPayGateSessionId
        }
        if payGateSessions.isEmpty {
            showPayGate = false
            payGateTargetBundleId = nil
        }
    }

    private func setupAppLifecycleObservers() {
        // Когда приложение уходит в фон
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleAppDidEnterBackground()
            }
        }

        // Когда приложение возвращается на передний план
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleAppWillEnterForeground()
            }
        }
    }

    func handleAppDidEnterBackground() {
        print("📱 App entered background - timer will be suspended")
        // Закрываем PayGate, если пользователь свернул приложение
        dismissPayGate()

        if isTrackingTime {
            // Сохраняем время ухода в фон
            UserDefaults.standard.set(Date(), forKey: "backgroundTime")
            print("💾 Saved background time for tracking calculation")
        }
    }

    func handleAppWillEnterForeground() {
        print("📱 App entering foreground - checking elapsed time")
        purgeExpiredAccessWindows()
        handleBlockedRedirect()
        applyMinuteTariffCatchup()
        
        // Reload minute mode and steps data from storage (may have been updated by extensions)
        loadAppStepsSpentToday()
        loadMinuteChargeLogs()
        loadAppStepsSpentLifetime()

        // Принудительно восстанавливаем выбор приложений при возврате в приложение
        forceRestoreAppSelection()

        // Проверяем, сколько времени прошло в фоне (только если включено отслеживание)
        if isTrackingTime {
            if let backgroundTime = UserDefaults.standard.object(forKey: "backgroundTime") as? Date
            {
                let elapsedSeconds = Date().timeIntervalSince(backgroundTime)
                let elapsedMinutes = Int(elapsedSeconds / 60)

                if elapsedMinutes > 0 {
                    print("⏰ App was in background for \(elapsedMinutes) minutes")

                    // Симулируем использование приложения за время в фоне
                    for _ in 0..<elapsedMinutes {
                        guard remainingMinutes > 0 else {
                            // Время истекло пока были в фоне
                            stopTracking()
                            isBlocked = true
                            message = "⏰ Time expired while you were away!"

                            if let familyService = familyControlsService as? FamilyControlsService {
                                familyService.enableShield()
                            }

                            notificationService.sendTimeExpiredNotification()
                            sendReturnToAppNotification()
                            AudioServicesPlaySystemSound(1005)
                            break
                        }

                        updateSpentTime(minutes: spentMinutes + 1)
                        consumeMinutes(1)
                    }

                    print("⏱️ Updated: spent \(spentMinutes) min, remaining \(remainingMinutes) min")
                }

                UserDefaults.standard.removeObject(forKey: "backgroundTime")
            }
        }

        // Проверяем, нужно ли показать Quick Status Page (независимо от tracking)
        checkForQuickStatusPage()
        
        // Автогенерация дневника за вчера (если ещё не сгенерирован)
        ensureYesterdayStoryGenerated()

        // Всегда обновляем шаги из HealthKit при возвращении в приложение
        Task { @MainActor in
            await refreshStepsBalance()
        }

    }

    // Convenience computed properties for backward compatibility
    var budget: any BudgetEngineProtocol { budgetEngine }
    var family: any FamilyControlsServiceProtocol { familyControlsService }

    // MARK: - Budget Sync
    private func syncBudgetProperties() {
        dailyBudgetMinutes = budgetEngine.dailyBudgetMinutes
        remainingMinutes = budgetEngine.remainingMinutes
        if let engine = budgetEngine as? BudgetEngine {
            dayEndHour = engine.dayEndHour
            dayEndMinute = engine.dayEndMinute
        }
    }

    private func syncAppSelectionToService() {
        print(
            "🔄 Syncing app selection to service: \(appSelection.applicationTokens.count) apps, \(appSelection.categoryTokens.count) categories"
        )

        // Применяем ограничение только одного элемента
        var finalSelection = appSelection

        if appSelection.applicationTokens.count > 1 {
            finalSelection = FamilyActivitySelection()
            if let firstApp = appSelection.applicationTokens.first {
                finalSelection.applicationTokens.insert(firstApp)
            }
            print("🔄 Limited to first app")
        } else if appSelection.categoryTokens.count > 1 {
            finalSelection = FamilyActivitySelection()
            if let firstCategory = appSelection.categoryTokens.first {
                finalSelection.categoryTokens.insert(firstCategory)
            }
            print("🔄 Limited to first category")
        }

        // Обновляем сервис напрямую без вызова updateSelection (избегаем циклов)
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.selection = finalSelection
            print(
                "✅ Service updated with \(finalSelection.applicationTokens.count) apps, \(finalSelection.categoryTokens.count) categories"
            )
        } else {
            print("❌ Failed to cast familyControlsService to FamilyControlsService")
        }
    }

    func loadSpentTime() {
        let userDefaults = UserDefaults.stepsTrader()
        let savedSpentMinutes = userDefaults.integer(forKey: "spentMinutes")
        let savedDate = userDefaults.object(forKey: "spentTimeDate") as? Date ?? Date()
        let savedSpentTariffRaw = userDefaults.string(forKey: "spentTariff") ?? "light"
        let savedSpentTariff = Tariff(rawValue: savedSpentTariffRaw) ?? .easy

        // Сбрасываем время если прошел день
        if !Calendar.current.isDate(savedDate, inSameDayAs: Date()) {
            spentMinutes = 0
            spentSteps = 0
            spentTariff = .easy
            saveSpentTime()
            print("🔄 Reset spent time for new day")
        } else {
            // Ограничиваем загруженное время максимальным доступным бюджетом
            let maxSpentMinutes = budgetEngine.dailyBudgetMinutes
            spentMinutes = min(savedSpentMinutes, maxSpentMinutes)
            spentTariff = savedSpentTariff
            spentSteps = spentMinutes * Int(spentTariff.stepsPerMinute)
            syncBudgetProperties()  // Sync budget properties for UI updates
            print(
                "📊 Loaded spent time: \(spentMinutes) minutes, \(spentSteps) steps (max: \(maxSpentMinutes))"
            )
        }
    }

    private func saveSpentTime() {
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(spentMinutes, forKey: "spentMinutes")
        userDefaults.set(spentTariff.rawValue, forKey: "spentTariff")
        userDefaults.set(Date(), forKey: "spentTimeDate")
        print("💾 Saved spent time: \(spentMinutes) minutes with tariff: \(spentTariff.rawValue)")
    }

    // MARK: - Steps Balance (per-entry payment)
    func refreshStepsBalance() async {
        do {
            let now = Date()
            let start = currentDayStart(for: now)
            stepsToday = try await healthKitService.fetchSteps(from: start, to: now)
        } catch {
            print("❌ Failed to refresh steps from HealthKit: \(error.localizedDescription)")

            if let hkError = error as? HKError {
                switch hkError.code {
                case .errorAuthorizationDenied:
                    message =
                        "❌ HealthKit access denied. Open the Health app → Sources → DOOM CTRL and enable step reading."
                case .errorAuthorizationNotDetermined:
                    message = "⚠️ Step access not granted yet. Requesting permission..."
                    do {
                        try await healthKitService.requestAuthorization()
                    } catch {
                        print(
                            "❌ Failed to re-request HealthKit authorization: \(error.localizedDescription)"
                        )
                    }
                default:
                    message =
                        "❌ Could not fetch steps. Open HealthKit and re-enable access."
                }
            } else {
                message =
                    "❌ HealthKit error. Try again or verify the permission in the Health app."
            }

            #if targetEnvironment(simulator)
                stepsToday = 2500
            #else
                stepsToday = fallbackCachedSteps()
            #endif
        }
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: "stepsBalanceAnchor") as? Date ?? .distantPast
        if !isSameCustomDay(anchor, Date()) {
            spentStepsToday = 0
            g.set(currentDayStart(for: Date()), forKey: "stepsBalanceAnchor")
        }
        stepsBalance = max(0, Int(stepsToday) - spentStepsToday)
        g.set(spentStepsToday, forKey: "spentStepsToday")
        g.set(stepsBalance, forKey: "stepsBalance")
        clearExpiredDayPasses()
    }
    
    // MARK: - Custom day boundary
    private func currentDayStart(for date: Date) -> Date {
        let cal = Calendar.current
        guard let cutoffToday = cal.date(
            bySettingHour: dayEndHour,
            minute: dayEndMinute,
            second: 0,
            of: date
        ) else {
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

    func ensureHealthAuthorizationAndRefresh() async {
        let status = healthKitService.authorizationStatus()
        print("🏥 HealthKit status before ensure: \(status.rawValue)")
        healthAuthorizationStatus = status
        switch status {
        case .sharingAuthorized:
            print("🏥 HealthKit already authorized, refreshing steps")
        case .sharingDenied:
            print("❌ HealthKit access denied. Open the Health app → Sources → DOOM CTRL and enable step reading.")
            return
        case .notDetermined:
            print("🏥 HealthKit not determined. Requesting authorization...")
            do {
                try await healthKitService.requestAuthorization()
            print("✅ HealthKit authorization completed (ensureHealthAuthorizationAndRefresh)")
            healthAuthorizationStatus = healthKitService.authorizationStatus()
        } catch {
            print("❌ HealthKit authorization failed: \(error.localizedDescription)")
            return
        }
        @unknown default:
            print("❓ HealthKit status unknown: \(status.rawValue). Attempting authorization.")
            do {
                try await healthKitService.requestAuthorization()
            } catch {
                print("❌ HealthKit authorization failed: \(error.localizedDescription)")
                return
            }
        }
        await refreshStepsBalance()
        startStepObservation()
    }
    
    private func isSameCustomDay(_ a: Date, _ b: Date) -> Bool {
        currentDayStart(for: a) == currentDayStart(for: b)
    }
    
    private func fetchStepsForCurrentDay() async throws -> Double {
        let now = Date()
        let start = currentDayStart(for: now)
        return try await healthKitService.fetchSteps(from: start, to: now)
    }
    
    // MARK: - App open logs
    private func loadAppOpenLogs() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "appOpenLogs_v1"),
              let decoded = try? JSONDecoder().decode([AppOpenLog].self, from: data) else { return }
        appOpenLogs = decoded
        trimOpenLogs()
    }
    
    private func persistAppOpenLogs() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appOpenLogs) {
            g.set(data, forKey: "appOpenLogs_v1")
        }
    }
    
    func loadMinuteChargeLogs() {
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: "minuteChargeLogs_v1"),
           let decoded = try? JSONDecoder().decode([MinuteChargeLog].self, from: data) {
            minuteChargeLogs = decoded
        }
        if let data = g.data(forKey: "minuteTimeByDay_v1"),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            minuteTimeByDay = decoded
        }
    }
    
    func refreshMinuteChargeLogs() {
        loadMinuteChargeLogs()
    }
    
    func clearMinuteChargeLogs() {
        let g = UserDefaults.stepsTrader()
        g.removeObject(forKey: "minuteChargeLogs_v1")
        minuteChargeLogs = []
    }
    
    func minuteTimeToday(for bundleId: String) -> Int {
        let dayKey = Self.dayKey(for: Date())
        return minuteTimeByDay[dayKey]?[bundleId] ?? 0
    }
    
    func totalMinutesToday() -> Int {
        let dayKey = Self.dayKey(for: Date())
        guard let dayMap = minuteTimeByDay[dayKey] else { return 0 }
        return dayMap.values.reduce(0, +)
    }
    
    private func trimOpenLogs() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        appOpenLogs = appOpenLogs.filter { $0.date >= cutoff }
    }
    
    // MARK: - Daily stories
    private func loadDailyStories() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "dailyStories_v1"),
              let decoded = try? JSONDecoder().decode([String: DailyStory].self, from: data) else { return }
        dailyStories = decoded
    }
    
    private func persistDailyStories() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(dailyStories) {
            g.set(data, forKey: "dailyStories_v1")
        }
    }
    
    private func loadDailyTariffSelections() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: "dailyTariffSelectionsAnchor") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(anchor) {
            dailyTariffSelections = [:]
            g.set(Calendar.current.startOfDay(for: Date()), forKey: "dailyTariffSelectionsAnchor")
            g.removeObject(forKey: "dailyTariffSelections_v1")
            return
        }
        if let data = g.data(forKey: "dailyTariffSelections_v1"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            var result: [String: Tariff] = [:]
            for (k,v) in decoded {
                if let t = Tariff(rawValue: v) {
                    result[k] = t
                }
            }
            dailyTariffSelections = result
        }
    }
    
    private func persistDailyTariffSelections() {
        let g = UserDefaults.stepsTrader()
        let dict = dailyTariffSelections.mapValues { $0.rawValue }
        if let data = try? JSONEncoder().encode(dict) {
            g.set(data, forKey: "dailyTariffSelections_v1")
        }
        g.set(Calendar.current.startOfDay(for: Date()), forKey: "dailyTariffSelectionsAnchor")
    }
    
    private func dateKey(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
    
    func story(for date: Date) -> DailyStory? {
        dailyStories[dateKey(date)]
    }
    
    @MainActor
    func saveStory(for date: Date, english: String, russian: String) {
        let key = dateKey(date)
        dailyStories[key] = DailyStory(dateKey: key, english: english, russian: russian, createdAt: Date())
        persistDailyStories()
    }
    
    func ensureYesterdayStoryGenerated() {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) else { return }
        let key = dateKey(yesterday)
        guard dailyStories[key] == nil else { return }
        let entries = appOpenLogs.filter { cal.isDate($0.date, inSameDayAs: yesterday) }
        guard !entries.isEmpty else { return }
        Task {
            await generateAndStoreStory(for: yesterday, entries: entries)
        }
    }
    
    private func generateAndStoreStory(for date: Date, entries: [AppOpenLog]) async {
        let promptEN = buildStoryPromptEnglish(for: date, entries: entries)
        do {
            let english = try await LLMService.shared.generateCosmicJournal(prompt: promptEN)
            let translatePrompt = "Translate the following captain's log into Russian, keep the cosmic pilot vibe and warmth, keep 4-6 sentences:\n\(english)"
            let russian = try await LLMService.shared.generateCosmicJournal(prompt: translatePrompt)
            await MainActor.run {
                saveStory(for: date, english: english, russian: russian)
            }
        } catch {
            print("❌ Failed to auto-generate story for \(dateKey(date)): \(error)")
        }
    }
    
    private func buildStoryPromptEnglish(for date: Date, entries: [AppOpenLog]) -> String {
        let cal = Calendar.current
        let uniqueUsageDays = usageDayCount()
        let stepsMade = cal.isDateInToday(date) ? Int(stepsToday) : nil
        let stepsSpent = cal.isDateInToday(date) ? appStepsSpentToday.values.reduce(0, +) : nil
        let remaining = cal.isDateInToday(date) ? max(0, Int(stepsToday) - spentStepsToday) : nil
        let dayPassActive: [String] = cal.isDateInToday(date)
            ? Array(dayPassGrants.keys.filter { hasDayPass(for: $0) })
            : []
        
        let df = DateFormatter()
        df.dateStyle = .medium
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        
        var lines: [String] = []
        lines.append("Date: \(df.string(from: date))")
        lines.append("Days using app: \(uniqueUsageDays)")
        if let made = stepsMade { lines.append("Steps made: \(made)") }
        if let spent = stepsSpent { lines.append("Steps spent: \(spent)") }
        if let rem = remaining { lines.append("Fuel left: \(rem)") }
        if !dayPassActive.isEmpty {
            let joined = dayPassActive.joined(separator: ", ")
            lines.append("Day passes active: \(joined)")
        }
        lines.append("Jumps:")
        
        let sortedEntries = entries.sorted { $0.date < $1.date }
        for (idx, entry) in sortedEntries.enumerated() {
            let time = tf.string(from: entry.date)
            let name = entry.bundleId
            var gapText = ""
            if idx > 0 {
                let delta = entry.date.timeIntervalSince(sortedEntries[idx-1].date)
                let minutes = Int(delta / 60)
                gapText = " | pause \(minutes) min"
            }
            lines.append("- \(time): jumped to universe \(name)\(gapText)")
        }
        
        lines.append("Write a short captain's log of a spaceship pilot, warm and imaginative (4-6 sentences). Use metaphors of fuel and jumps between universes. Language: English.")
        return lines.joined(separator: "\n")
    }

    private func usageDayCount() -> Int {
        let cal = Calendar.current
        let unique = Set(appOpenLogs.map { cal.startOfDay(for: $0.date) })
        return unique.count
    }

    func canPayForEntry(for bundleId: String? = nil, costOverride: Int? = nil) -> Bool {
        if hasDayPass(for: bundleId) { return true }
        let cost = costOverride ?? unlockSettings(for: bundleId).entryCostSteps
        return totalStepsBalance >= cost
    }

    func canPayForDayPass(for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        if hasDayPass(for: bundleId) { return true }
        let cost = unlockSettings(for: bundleId).dayPassCostSteps
        return totalStepsBalance >= cost
    }

    @discardableResult
    func payForEntry(for bundleId: String? = nil, costOverride: Int? = nil) -> Bool {
        if hasDayPass(for: bundleId) { return true }
        let cost = costOverride ?? unlockSettings(for: bundleId).entryCostSteps
        let success = pay(cost: cost)
        if success, let bundleId { addSpentSteps(cost, for: bundleId) }
        return success
    }
    
    @discardableResult
    func payForDayPass(for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        if hasDayPass(for: bundleId) { return true }
        let cost = unlockSettings(for: bundleId).dayPassCostSteps
        guard pay(cost: cost) else { return false }
        addSpentSteps(cost, for: bundleId)
        dayPassGrants[bundleId] = Date()
        persistDayPassGrants()
        return true
    }
    
    private func pay(cost: Int) -> Bool {
        guard totalStepsBalance >= cost else { return false }
        // Не позволяем тратить больше, чем пройдено сегодня
        let todaysSteps = Int(stepsToday)
        let baseAvailable = stepsBalance
        let consumeFromBase = min(baseAvailable, cost)
        let newSpent = min(spentStepsToday + consumeFromBase, max(0, todaysSteps))
        spentStepsToday = newSpent
        stepsBalance = max(0, todaysSteps - spentStepsToday)

        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            consumeBonusSteps(remainingCost)
        }

        let g = UserDefaults.stepsTrader()
        g.set(spentStepsToday, forKey: "spentStepsToday")
        g.set(stepsBalance, forKey: "stepsBalance")
        g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
        return true
    }

    func loadSpentStepsBalance() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: "stepsBalanceAnchor") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(anchor) {
            spentStepsToday = 0
            g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
        } else {
            spentStepsToday = g.integer(forKey: "spentStepsToday")
        }
        // Клэмп только если уже знаем число шагов (иначе при запуске с stepsToday=0 мы затираем данные)
        let todaysSteps = Int(stepsToday)
        if todaysSteps > 0, spentStepsToday > todaysSteps { spentStepsToday = todaysSteps }
        stepsBalance = g.integer(forKey: "stepsBalance")
        if stepsBalance == 0, todaysSteps > 0 {
            stepsBalance = max(0, todaysSteps - spentStepsToday)
        }
    }

    private func loadDebugStepsBonus() {
        let g = UserDefaults.stepsTrader()
        
        // New keys (split source)
        let debugKey = "debugStepsBonus_debug_v1"
        let outerWorldKey = "debugStepsBonus_outerworld_v1"
        
        // Legacy key (single bucket)
        let legacyTotal = g.integer(forKey: "debugStepsBonus_v1")
        
        let hasNewDebug = g.object(forKey: debugKey) != nil
        let hasNewOuter = g.object(forKey: outerWorldKey) != nil
        
        if !hasNewDebug && !hasNewOuter {
            // Migration: treat legacy as "debug/other" (so we don't accidentally attribute it to Outer World)
            debugBonusSteps = legacyTotal
            outerWorldBonusSteps = 0
        } else {
            debugBonusSteps = g.integer(forKey: debugKey)
            outerWorldBonusSteps = g.integer(forKey: outerWorldKey)
        }
        
        syncAndPersistBonusBreakdown()
    }

    private func persistDebugStepsBonus() {
        syncAndPersistBonusBreakdown()
    }

    private func syncAndPersistBonusBreakdown() {
        bonusSteps = max(0, debugBonusSteps + outerWorldBonusSteps)
        
        let g = UserDefaults.stepsTrader()
        g.set(bonusSteps, forKey: "debugStepsBonus_v1") // keep compatibility (extensions / older code)
        g.set(debugBonusSteps, forKey: "debugStepsBonus_debug_v1")
        g.set(outerWorldBonusSteps, forKey: "debugStepsBonus_outerworld_v1")
    }

    private func consumeBonusSteps(_ cost: Int) {
        guard cost > 0 else { return }
        
        let consumeFromOuterWorld = min(outerWorldBonusSteps, cost)
        outerWorldBonusSteps = max(0, outerWorldBonusSteps - consumeFromOuterWorld)
        
        let remaining = max(0, cost - consumeFromOuterWorld)
        if remaining > 0 {
            debugBonusSteps = max(0, debugBonusSteps - remaining)
        }
        
        syncAndPersistBonusBreakdown()
    }

    func loadEntryCost() {
        let g = UserDefaults.stepsTrader()
        let raw = g.string(forKey: "entryCostTariff")
        if let raw, let t = Tariff(rawValue: raw) {
            entryCostSteps = t.entryCostSteps
        } else {
            // Fallback to current tariff's entry cost
            entryCostSteps = budgetEngine.tariff.entryCostSteps
        }
    }

    func persistEntryCost(tariff: Tariff) {
        let g = UserDefaults.stepsTrader()
        g.set(tariff.rawValue, forKey: "entryCostTariff")
        entryCostSteps = tariff.entryCostSteps
    }
    
    // MARK: - Per-app unlock settings
    func unlockSettings(for bundleId: String?) -> AppUnlockSettings {
        let fallback = AppUnlockSettings(
            entryCostSteps: entryCostSteps,
            dayPassCostSteps: defaultDayPassCost(forEntryCost: entryCostSteps),
            allowedWindows: [.single, .minutes5, .hour1]
        )
        guard let bundleId else { return fallback }
        var settings = appUnlockSettings[bundleId] ?? fallback
        if settings.allowedWindows.isEmpty {
            settings.allowedWindows = [.single, .minutes5, .hour1]
        }
        return settings
    }
    
    func presetTariff(for bundleId: String?) -> Tariff? {
        let settings = unlockSettings(for: bundleId)
        switch (settings.entryCostSteps, settings.dayPassCostSteps) {
        case (0, 0): return .free
        case (Tariff.easy.entryCostSteps, 1000): return .easy
        case (Tariff.medium.entryCostSteps, 5000): return .medium
        case (Tariff.hard.entryCostSteps, 10000): return .hard
        default: return nil
        }
    }
    
    func updateUnlockSettings(for bundleId: String, tariff: Tariff) {
        updateUnlockSettings(
            for: bundleId,
            entryCost: tariff.entryCostSteps,
            dayPassCost: dayPassCost(for: tariff)
        )
    }
    
    func updateUnlockSettings(for bundleId: String, entryCost: Int? = nil, dayPassCost: Int? = nil) {
        var settings = unlockSettings(for: bundleId)
        if let entryCost { settings.entryCostSteps = max(0, entryCost) }
        if let dayPassCost { settings.dayPassCostSteps = max(0, dayPassCost) }
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
    }

    func allowedAccessWindows(for bundleId: String?) -> Set<AccessWindow> {
        unlockSettings(for: bundleId).allowedWindows
    }

    func updateAccessWindow(_ window: AccessWindow, enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        if enabled {
            settings.allowedWindows.insert(window)
        } else {
            settings.allowedWindows.remove(window)
        }
        if settings.allowedWindows.isEmpty {
            settings.allowedWindows = [.single, .minutes5, .hour1]
        }
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
    }
    
    // MARK: - Shield levels
    func totalStepsSpent(for bundleId: String) -> Int {
        if let total = appStepsSpentLifetime[bundleId] {
            return total
        }
        return appStepsSpentByDay.values.reduce(0) { acc, perDay in
            acc + (perDay[bundleId] ?? 0)
        }
    }

    func currentShieldLevel(for bundleId: String) -> ShieldLevel {
        ShieldLevel.current(forSpent: totalStepsSpent(for: bundleId))
    }

    func stepsToNextShieldLevel(for bundleId: String) -> Int? {
        ShieldLevel.stepsToNext(forSpent: totalStepsSpent(for: bundleId))
    }

    func applyCurrentLevelCosts(for bundleId: String) {
        let level = currentShieldLevel(for: bundleId)
        updateUnlockSettings(for: bundleId, entryCost: level.entryCost, dayPassCost: level.dayCost)
    }
    
    func hasDayPass(for bundleId: String?) -> Bool {
        guard let bundleId, let date = dayPassGrants[bundleId] else { return false }
        if Calendar.current.isDateInToday(date) { return true }
        dayPassGrants.removeValue(forKey: bundleId)
        persistDayPassGrants()
        return false
    }
    
    func tariffForToday(_ bundleId: String) -> Tariff? {
        if let t = dailyTariffSelections[bundleId] { return t }
        let settings = unlockSettings(for: bundleId)
        return Tariff.allCases.first(where: { $0.entryCostSteps == settings.entryCostSteps && dayPassCost(for: $0) == settings.dayPassCostSteps })
    }

    @MainActor
    func selectTariffForToday(_ tariff: Tariff, bundleId: String) {
        dailyTariffSelections[bundleId] = tariff
        persistDailyTariffSelections()
        updateUnlockSettings(for: bundleId, tariff: tariff)
    }
    
    func clearExpiredDayPasses() {
        let today = Calendar.current.startOfDay(for: Date())
        dayPassGrants = dayPassGrants.filter { _, value in
            Calendar.current.isDate(value, inSameDayAs: today)
        }
        persistDayPassGrants()
    }
    
    private func loadAppUnlockSettings() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "appUnlockSettings_v1") else { return }
        if let decoded = try? JSONDecoder().decode([String: AppUnlockSettings].self, from: data) {
            // Normalize values that were previously clamped to 1
            appUnlockSettings = decoded.mapValues { settings in
                var s = settings
                if s.entryCostSteps == 1 { s.entryCostSteps = 0 }
                if s.dayPassCostSteps == 1 { s.dayPassCostSteps = 0 }
                return s
            }
        }
    }
    
    private func persistAppUnlockSettings() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appUnlockSettings) {
            g.set(data, forKey: "appUnlockSettings_v1")
        }
    }
    
    private func loadDayPassGrants() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "appDayPassGrants_v1") else { return }
        if let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            dayPassGrants = decoded
            clearExpiredDayPasses()
        }
    }
    
    private func persistDayPassGrants() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(dayPassGrants) {
            g.set(data, forKey: "appDayPassGrants_v1")
        }
    }
    
    private func loadAppStepsSpentToday() {
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
    
    private func persistAppStepsSpentToday() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appStepsSpentToday) {
            g.set(data, forKey: "appStepsSpentToday_v1")
        }
    }

    private func persistAppStepsSpentByDay() {
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

    private func persistAppStepsSpentLifetime() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appStepsSpentLifetime) {
            g.set(data, forKey: "appStepsSpentLifetime_v1")
        }
    }
    
    private func dayPassCost(for tariff: Tariff) -> Int {
        switch tariff {
        case .free: return 0
        case .easy: return 1000
        case .medium: return 5000
        case .hard: return 10000
        }
    }
    
    private func defaultDayPassCost(forEntryCost entryCost: Int) -> Int {
        if entryCost <= 0 { return 0 }
        return entryCost * 100
    }
    
    private func addSpentSteps(_ cost: Int, for bundleId: String) {
        appStepsSpentToday[bundleId, default: 0] += cost
        appStepsSpentLifetime[bundleId, default: 0] += cost
        let key = Self.dayKey(for: Date())
        var perDay = appStepsSpentByDay[key] ?? [:]
        perDay[bundleId, default: 0] += cost
        appStepsSpentByDay[key] = perDay
        persistAppStepsSpentToday()
        persistAppStepsSpentByDay()
        persistAppStepsSpentLifetime()
    }

    // MARK: - Access window helpers
    func applyAccessWindow(_ window: AccessWindow, for bundleId: String) {
        let g = UserDefaults.stepsTrader()
        guard let until = accessWindowExpiration(window, now: Date()) else {
            g.removeObject(forKey: accessBlockKey(for: bundleId))
            return
        }
        g.set(until, forKey: accessBlockKey(for: bundleId))
        let remaining = Int(until.timeIntervalSince(Date()))
        print("⏱️ Access window set for \(bundleId) until \(until) (\(remaining) seconds)")
        // Push notifications on payment/activation removed per request
    }

    func isAccessBlocked(for bundleId: String) -> Bool {
        let g = UserDefaults.stepsTrader()
        guard let until = g.object(forKey: accessBlockKey(for: bundleId)) as? Date else {
            return false
        }
        if Date() >= until {
            g.removeObject(forKey: accessBlockKey(for: bundleId))
            return false
        }
        let remaining = Int(until.timeIntervalSince(Date()))
        print("⏱️ Access window active for \(bundleId), remaining \(remaining) seconds")
        return true
    }

    func remainingAccessSeconds(for bundleId: String) -> Int? {
        let g = UserDefaults.stepsTrader()
        guard let until = g.object(forKey: accessBlockKey(for: bundleId)) as? Date else { return nil }
        let remaining = Int(until.timeIntervalSince(Date()))
        if remaining <= 0 {
            g.removeObject(forKey: accessBlockKey(for: bundleId))
            return nil
        }
        return remaining
    }

    private func accessBlockKey(for bundleId: String) -> String {
        "shortcutBlockUntil_\(bundleId)"
    }

    private func purgeExpiredAccessWindows() {
        let g = UserDefaults.stepsTrader()
        let now = Date()
        let keys = g.dictionaryRepresentation().keys.filter { $0.hasPrefix("shortcutBlockUntil_") }
        for key in keys {
            if let until = g.object(forKey: key) as? Date {
                if now >= until {
                    g.removeObject(forKey: key)
                }
            } else {
                g.removeObject(forKey: key)
            }
        }
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

    private func accessWindowExpiration(_ window: AccessWindow, now: Date) -> Date? {
        switch window {
        case .single:
            // Короткий кулдаун 10 секунд, чтобы предотвратить мгновенные повторы
            return now.addingTimeInterval(10)
        case .minutes5:
            return now.addingTimeInterval(5 * 60)
        case .hour1:
            return now.addingTimeInterval(60 * 60)
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
    
    // MARK: - PayGate helpers
    func dismissPayGate() {
        showPayGate = false
        payGateTargetBundleId = nil
        payGateSessions.removeAll()
        currentPayGateSessionId = nil
        let g = UserDefaults.stepsTrader()
        g.removeObject(forKey: "shouldShowPayGate")
        g.removeObject(forKey: "payGateTargetBundleId")
    }
    
    func recordAutomationOpen(bundleId: String, spentSteps: Int? = nil) {
        let defaults = UserDefaults.stepsTrader()
        var dict: [String: Date] = [:]
        if let data = defaults.data(forKey: "automationLastOpened_v1"),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            dict = decoded
        }
        dict[bundleId] = Date()
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: "automationLastOpened_v1")
        }
        
        // Mark as configured and clear pending once opened
        var configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        if !configured.contains(bundleId) {
            configured.append(bundleId)
            defaults.set(configured, forKey: "automationConfiguredBundles")
        }
        var pending = defaults.array(forKey: "automationPendingBundles") as? [String] ?? []
        if let idx = pending.firstIndex(of: bundleId) {
            pending.remove(at: idx)
            defaults.set(pending, forKey: "automationPendingBundles")
        }
        if let pendingData = defaults.data(forKey: "automationPendingTimestamps_v1"),
           var ts = try? JSONDecoder().decode([String: Date].self, from: pendingData) {
            ts.removeValue(forKey: bundleId)
            if let data = try? JSONEncoder().encode(ts) {
                defaults.set(data, forKey: "automationPendingTimestamps_v1")
            }
        }
        // Log open for chart analytics
        appOpenLogs.append(AppOpenLog(bundleId: bundleId, date: Date(), spentSteps: spentSteps))
        trimOpenLogs()
        persistAppOpenLogs()
    }
    
    // Sync entry cost with current tariff
    private func syncEntryCostWithTariff() {
        if entryCostSteps <= 0 {
            entryCostSteps = 100
        }
    }

    func updateSpentTime(minutes: Int) {
        // Ограничиваем потраченное время максимальным доступным бюджетом
        let maxSpentMinutes = budgetEngine.dailyBudgetMinutes
        spentMinutes = min(minutes, maxSpentMinutes)
        spentSteps = spentMinutes * Int(spentTariff.stepsPerMinute)
        saveSpentTime()
        syncBudgetProperties()  // Sync budget properties for UI updates
        print(
            "🕐 Updated spent time: \(spentMinutes) minutes (\(spentSteps) steps) (max: \(maxSpentMinutes))"
        )
    }

    func consumeMinutes(_ minutes: Int) {
        budgetEngine.consume(mins: minutes)

        // Устанавливаем тариф, по которому тратятся минуты
        spentTariff = budgetEngine.tariff

        // Обновляем потраченное время с учетом ограничений
        updateSpentTime(minutes: spentMinutes + minutes)

        syncBudgetProperties()  // Sync budget properties for UI updates
        print("⏱️ Consumed \(minutes) minutes, remaining: \(remainingMinutes)")
    }

    // MARK: - App Selection Persistence

    private func saveAppSelection() {
        let userDefaults = UserDefaults.stepsTrader()

        // Сохраняем ApplicationTokens
        if !appSelection.applicationTokens.isEmpty {
            do {
                let tokensData = try NSKeyedArchiver.archivedData(
                    withRootObject: appSelection.applicationTokens, requiringSecureCoding: true)
                userDefaults.set(tokensData, forKey: "persistentApplicationTokens")
                print("💾 Saved app selection: \(appSelection.applicationTokens.count) apps")
            } catch {
                print("❌ Failed to save app selection: \(error)")
            }
        } else {
            userDefaults.removeObject(forKey: "persistentApplicationTokens")
        }

        // Сохраняем CategoryTokens
        if !appSelection.categoryTokens.isEmpty {
            do {
                let categoriesData = try NSKeyedArchiver.archivedData(
                    withRootObject: appSelection.categoryTokens, requiringSecureCoding: true)
                userDefaults.set(categoriesData, forKey: "persistentCategoryTokens")
                print("💾 Saved category selection: \(appSelection.categoryTokens.count) categories")
            } catch {
                print("❌ Failed to save category selection: \(error)")
            }
        } else {
            userDefaults.removeObject(forKey: "persistentCategoryTokens")
        }

        // Сохраняем дату сохранения
        userDefaults.set(Date(), forKey: "appSelectionSavedDate")
    }

    private func loadAppSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        var hasSelection = false
        var newSelection = FamilyActivitySelection()

        // Восстанавливаем ApplicationTokens
        if let tokensData = userDefaults.data(forKey: "persistentApplicationTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: tokensData)
                if let applicationTokens = obj as? Set<ApplicationToken> {
                    newSelection.applicationTokens = applicationTokens
                    hasSelection = true
                    print("📱 Restored app selection: \(applicationTokens.count) apps")
                }
            } catch {
                print("❌ Failed to restore app selection: \(error)")
            }
        }

        // Восстанавливаем CategoryTokens
        if let categoriesData = userDefaults.data(forKey: "persistentCategoryTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: categoriesData)
                if let categoryTokens = obj as? Set<ActivityCategoryToken> {
                    newSelection.categoryTokens = categoryTokens
                    hasSelection = true
                    print("📱 Restored category selection: \(categoryTokens.count) categories")
                }
            } catch {
                print("❌ Failed to restore category selection: \(error)")
            }
        }

        if hasSelection {
            // Обновляем выбор без вызова didSet (чтобы избежать повторного сохранения)
            self.appSelection = newSelection
            print("✅ App selection restored successfully")

            // Проверяем дату сохранения
            if let savedDate = userDefaults.object(forKey: "appSelectionSavedDate") as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                print("📅 App selection was saved on: \(formatter.string(from: savedDate))")
            }
        } else {
            print("📱 No saved app selection found")
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
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.stopMonitoring()
            familyService.disableShield()
            print("🛡️ Disabled shields")
        }

        // 7. Очищаем выбор приложений (как выбор, так и сохраненные данные)
        appSelection = FamilyActivitySelection()
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
        loadSpentTime()

        do {
            let authStatus = healthKitService.authorizationStatus()
            print("🏥 HealthKit status at bootstrap: \(authStatus.rawValue)")
            if requestPermissions {
                if authStatus == .sharingAuthorized {
                    print("📊 HealthKit already authorized (bootstrap)")
                } else {
                    print("📊 Requesting HealthKit authorization...")
                    try await healthKitService.requestAuthorization()
                    print("✅ HealthKit authorization completed")
                }
            } else {
                print("⏳ Skipping HealthKit prompt (intro not finished)")
            }

            print("🔐 Requesting Family Controls authorization...")
            do {
                try await familyControlsService.requestAuthorization()
                print("✅ Family Controls authorization completed")
            } catch {
                print("⚠️ Family Controls authorization failed: \(error)")
                // Не блокируем весь bootstrap из-за Family Controls
            }

            if requestPermissions {
                print("🔔 Requesting notification permissions...")
                try await notificationService.requestPermission()
                print("✅ Notification permissions completed")
            } else {
                print("⏳ Skipping notifications prompt (intro not finished)")
            }

            print("📈 Fetching today's steps...")
            let finalStatus = healthKitService.authorizationStatus()
            if finalStatus == .sharingAuthorized {
                do {
                    stepsToday = try await fetchStepsForCurrentDay()
                    print("✅ Today's steps: \(Int(stepsToday))")
                    cacheStepsToday()
                } catch {
                    print("⚠️ Could not fetch step data: \(error)")
                    // На симуляторе или если нет данных, используем демо-значение
                    #if targetEnvironment(simulator)
                        stepsToday = 2500  // Демо-значение для симулятора
                        print("🎮 Using demo steps for Simulator: \(Int(stepsToday))")
                    #else
                        stepsToday = 0
                        print("📱 No step data available on device, using 0")
                    #endif
                }
            } else {
                print("ℹ️ HealthKit not authorized, skipping steps fetch for now")
                if stepsToday == 0 {
                    print("ℹ️ Using cached steps if available: \(Int(stepsToday))")
                }
            }

            print("💰 Calculating budget...")
            budgetEngine.resetIfNeeded()
            let budgetMinutes = budgetEngine.minutes(from: stepsToday)
            budgetEngine.setBudget(minutes: budgetMinutes)
            syncBudgetProperties()  // Sync budget properties for UI updates

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

    private func startTracking() {
        print("🎯 === START TRACKING BEGIN ===")

        // Пересчитываем бюджет с текущим тарифом перед запуском отслеживания
        Task {
            await recalcSilently()
            await MainActor.run {
                print("💰 Budget recalculated: \(budgetEngine.remainingMinutes) minutes")

                guard budgetEngine.remainingMinutes > 0 else {
                    print("❌ No remaining time - aborting")
                    message = "DOOM CTRL: No time left! Walk more steps."
                    return
                }

                continueStartTracking()
            }
        }
    }

    private func continueStartTracking() {
        print("🎯 === START TRACKING CONTINUE ===")
        print("💰 Checking budget: \(budgetEngine.remainingMinutes) minutes")

        print(
            "📱 Checking selection: \(appSelection.applicationTokens.count) apps, \(appSelection.categoryTokens.count) categories"
        )
        guard !appSelection.applicationTokens.isEmpty || !appSelection.categoryTokens.isEmpty else {
            print("❌ No applications selected - aborting")
            message = "❌ Choose an app to track"
            return
        }

        print("✅ Checks passed, starting tracking")
        isTrackingTime = true
        startTime = Date()
        currentSessionElapsed = 0
        print("⏱️ Tracking flags set: isTrackingTime=true, startTime=\(Date())")

        let appCount = appSelection.applicationTokens.count
        print("🚀 Started tracking for \(appCount) selected applications")
        print("⏱️ Available time: \(budgetEngine.remainingMinutes) minutes")
        print("🎯 Using DeviceActivity for real-time usage monitoring")

        // Запускаем DeviceActivity мониторинг для реального отслеживания времени
        if let familyService = familyControlsService as? FamilyControlsService {
            print("🔧 DEBUG: Starting monitoring with:")
            print("   - Selected apps: \(appSelection.applicationTokens.count)")
            print("   - Selected categories: \(appSelection.categoryTokens.count)")
            print("   - Budget minutes: \(budgetEngine.remainingMinutes)")

            // Запускаем мониторинг с таймаутом
            Task { [weak self] in
                print("🔄 Created task to start monitoring with a 10s timeout")
                await self?.withTimeout(seconds: 10) {
                    print("⏰ Calling startMonitoring in FamilyControlsService")
                    await MainActor.run {
                        familyService.startMonitoring(
                            budgetMinutes: self?.budgetEngine.remainingMinutes ?? 0)
                    }
                    print("✅ startMonitoring finished")
                }

                print("🔍 Running DeviceActivity diagnostics")
                // Run diagnostic after starting monitoring
                familyService.checkDeviceActivityStatus()
                print("✅ Diagnostics finished")
            }
        } else {
            print("❌ Failed to cast familyControlsService to FamilyControlsService")
        }

        // Проверяем, работает ли DeviceActivity
        #if targetEnvironment(simulator)
            // В симуляторе используем таймер как fallback
            print("⚠️ Using timer-based tracking (Simulator - DeviceActivity not available)")
            startTimerFallback()
        #else
            // На реальном устройстве проверяем наличие DeviceActivity
            if familyControlsService.isAuthorized {
                print("✅ Using DeviceActivity for real background tracking")
                print("✅ Real tracking enabled. Time counts in the background.")
            } else {
                print("⚠️ Using timer-based tracking (Family Controls not authorized)")
                startTimerFallback()
            }
        #endif
    }

    private func startTimerFallback() {
        // Таймер каждые 60 секунд симулирует 1 минуту использования (1:1 соответствие)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulateAppUsage()
            }
        }

        print("⚠️ Demo mode: time decreases every real minute (in-app only)")
    }

    func stopTracking() {
        isTrackingTime = false
        isBlocked = false  // Снимаем блокировку
        timer?.invalidate()
        timer = nil
        startTime = nil
        currentSessionElapsed = nil

        // Останавливаем DeviceActivity мониторинг
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.stopMonitoring()
        }

        print("🛑 Tracking stopped - DeviceActivity monitoring disabled")
    }

    private func startMinuteTariffSession(for bundleId: String, rate: Int) {
        let g = UserDefaults.stepsTrader()
        g.set(bundleId, forKey: minuteTariffBundleKey)
        g.set(rate, forKey: minuteTariffRateKey)
        g.set(Date(), forKey: minuteTariffLastTickKey)
        g.removeObject(forKey: accessBlockKey(for: bundleId))
    }

    private func setCustomAccessWindow(until: Date, for bundleId: String) {
        let g = UserDefaults.stepsTrader()
        g.set(until, forKey: accessBlockKey(for: bundleId))
        let remaining = Int(until.timeIntervalSince(Date()))
        print("⏱️ Custom access window set for \(bundleId) until \(until) (\(remaining) seconds)")
    }

    private func applyMinuteTariffCatchup() {
        let g = UserDefaults.stepsTrader()
        guard let bundleId = g.string(forKey: minuteTariffBundleKey),
              let lastTick = g.object(forKey: minuteTariffLastTickKey) as? Date
        else { return }

        let rate = g.integer(forKey: minuteTariffRateKey)
        guard rate > 0 else { return }

        let elapsedMinutes = Int(Date().timeIntervalSince(lastTick) / 60)
        guard elapsedMinutes > 0 else { return }

        let minutesToCharge = min(elapsedMinutes, minutesAvailable(for: bundleId))
        guard minutesToCharge > 0 else {
            g.removeObject(forKey: minuteTariffBundleKey)
            g.removeObject(forKey: minuteTariffLastTickKey)
            g.removeObject(forKey: minuteTariffRateKey)
            return
        }

        let totalCost = minutesToCharge * rate
        if pay(cost: totalCost) {
            addSpentSteps(totalCost, for: bundleId)
            let remainingMinutes = minutesAvailable(for: bundleId)
            if remainingMinutes <= 0 {
                g.removeObject(forKey: accessBlockKey(for: bundleId))
                g.removeObject(forKey: minuteTariffBundleKey)
                g.removeObject(forKey: minuteTariffLastTickKey)
                g.removeObject(forKey: minuteTariffRateKey)
            }
        }

        g.set(Date(), forKey: minuteTariffLastTickKey)
    }

    // Timer-based tracking (fallback without DeviceActivity entitlement)

    private func simulateAppUsage() {
        guard isTrackingTime else { return }
        print("⏱️ DEMO: Simulating 1 minute of app usage")

        // Увеличиваем время использования приложения на 1 минуту
        updateSpentTime(minutes: spentMinutes + 1)

        // Списываем из бюджета
        consumeMinutes(1)

        print("⏱️ Spent: \(spentMinutes) min, Remaining: \(remainingMinutes) min")

        if remainingMinutes <= 0 {
            stopTracking()
            isBlocked = true
            message = "⏰ DEMO: Time is up!"

            // Применяем реальную блокировку приложений через ManagedSettings
            if let familyService = familyControlsService as? FamilyControlsService {
                familyService.enableShield()
                print("🛡️ Applied real app blocking via ManagedSettings")
            }

            notificationService.sendTimeExpiredNotification()
            sendReturnToAppNotification()
            AudioServicesPlaySystemSound(1005)
        }
    }

    func checkForQuickStatusPage() {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        let shouldShow = userDefaults.bool(forKey: "shouldShowQuickStatusPage")
        let shouldShowPayGate = userDefaults.bool(forKey: "shouldShowPayGate")
        let shouldAutoSelectApps = userDefaults.bool(forKey: "shouldAutoSelectApps")
        let shouldPayBeforeOpen = userDefaults.bool(forKey: "shouldPayBeforeOpen")

        print(
            "🔍 Checking flags - Quick Status: \(shouldShow), Auto Select: \(shouldAutoSelectApps)")

        // Автоматический выбор приложений отключен (только ручной выбор)

        if shouldShow {
            print("🎯 Setting showQuickStatusPage = true")
            showQuickStatusPage = true
            // Очищаем флаг
            userDefaults.removeObject(forKey: "shouldShowQuickStatusPage")
            print("🎯 Opening Quick Status Page from Intent")

            // Проверяем автоматическое сопоставление приложения из шортката
            checkShortcutAppMatching(userDefaults: userDefaults)

            // Проверяем, нужно ли автоматически закрыть через секунду
            let shouldAutoClose = userDefaults.bool(forKey: "shouldAutoCloseQuickStatus")
            if shouldAutoClose {
                let targetApp =
                    userDefaults.string(forKey: "targetAppForReturn") ?? "unknown app"
                print("🔄 Auto-close requested, target app: \(targetApp)")
                userDefaults.removeObject(forKey: "shouldAutoCloseQuickStatus")
                userDefaults.removeObject(forKey: "targetAppForReturn")
                
                // Anti-loop on cold launch: wait until app has been active for at least 1.5s
                let baseDelay: TimeInterval = max(1.0, 1.5 - Date().timeIntervalSince(self.appLaunchTime))
                func scheduleOpen(after delay: TimeInterval) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        // Ensure app is active before redirect to avoid UI freeze
                        if UIApplication.shared.applicationState != .active {
                            scheduleOpen(after: 0.5)
                            return
                        }
                        print("🔄 Auto-closing QuickStatusView and opening \(targetApp) after delay: \(delay)s")
                        self.showQuickStatusPage = false

                        if shouldPayBeforeOpen {
                            Task { @MainActor in
                                await self.refreshStepsBalance()
                                if self.canPayForEntry() { _ = self.payForEntry() }
                            }
                            userDefaults.removeObject(forKey: "shouldPayBeforeOpen")
                        }

                        userDefaults.set(Date(), forKey: "returnModeActivatedTime")
                        self.openTargetApp(targetApp)
                    }
                }
                scheduleOpen(after: baseDelay)
            }
        } else {
            print("🔍 No Quick Status flag found")
        }

        if shouldShowPayGate {
            if let bundleId = userDefaults.string(forKey: "payGateTargetBundleId") {
                if let lastOpen = userDefaults.object(forKey: "lastAppOpenedFromStepsTrader_\(bundleId)") as? Date {
                    let elapsed = now.timeIntervalSince(lastOpen)
                    if elapsed < 10 {
                        print("🚫 PayGate ignored for \(bundleId) to avoid loop (\(String(format: "%.1f", elapsed))s since last open)")
                        userDefaults.removeObject(forKey: "shouldShowPayGate")
                        userDefaults.removeObject(forKey: "payGateTargetBundleId")
                        return
                    }
                }
                startPayGateSession(for: bundleId)
            }
            userDefaults.removeObject(forKey: "shouldShowPayGate")
            print(
                "🎯 PayGate (from UserDefaults): show=\(showPayGate), target=\(payGateTargetBundleId ?? "nil")"
            )
        }
    }

    // MARK: - Public helpers for views
    func reloadBudgetFromStorage() {
        if let engine = budgetEngine as? BudgetEngine {
            engine.reloadFromStorage()
            syncBudgetProperties()  // Sync budget properties for UI updates
        }
    }

    func updateDayEnd(hour: Int, minute: Int) {
        let clampedHour = max(0, min(23, hour))
        let clampedMinute = max(0, min(59, minute))
        dayEndHour = clampedHour
        dayEndMinute = clampedMinute
        budgetEngine.updateDayEnd(hour: clampedHour, minute: clampedMinute)
    }
    
    func installPayGateShortcut() {
        guard let url = URL(string: shortcutInstallURLString) else {
            message = "Shortcut link is not configured."
            print("❌ Invalid shortcut install URL")
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                print("✅ Opened shortcut install link")
            } else {
                self.message = "Could not open Shortcuts."
                print("❌ Failed to open shortcut install link")
            }
        }
    }

    func forceRestoreAppSelection() {
        print("🔄 Force restoring app selection...")

        // Сначала загружаем из UserDefaults
        let userDefaults = UserDefaults.stepsTrader()
        var hasSelection = false
        var newSelection = FamilyActivitySelection()

        // Восстанавливаем ApplicationTokens
        if let tokensData = userDefaults.data(forKey: "persistentApplicationTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: tokensData)
                if let applicationTokens = obj as? Set<ApplicationToken> {
                    newSelection.applicationTokens = applicationTokens
                    hasSelection = true
                    print("📱 Restored app selection: \(applicationTokens.count) apps")
                }
            } catch {
                print("❌ Failed to restore app selection: \(error)")
            }
        }

        // Восстанавливаем CategoryTokens
        if let categoriesData = userDefaults.data(forKey: "persistentCategoryTokens") {
            do {
                let obj = try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSSet.self, from: categoriesData)
                if let categoryTokens = obj as? Set<ActivityCategoryToken> {
                    newSelection.categoryTokens = categoryTokens
                    hasSelection = true
                    print("📱 Restored category selection: \(categoryTokens.count) categories")
                }
            } catch {
                print("❌ Failed to restore category selection: \(error)")
            }
        }

        if hasSelection {
            // Принудительно обновляем appSelection (это вызовет didSet и обновит UI)
            self.appSelection = newSelection
            print("✅ App selection restored and UI updated")
            // Включаем always-on shield
            if let svc = familyControlsService as? FamilyControlsService {
                svc.enableShield()
                print("🛡️ Always-on shield enabled after restore")
            }
        } else {
            print("ℹ️ No saved selection found")
        }
    }

    func forceSaveAppSelection() {
        print("💾 Force saving current app selection...")
        saveAppSelection()
        print("✅ Current selection saved to UserDefaults")
    }

    private func openTargetApp(_ appName: String) {
        print("🚀 Attempting to open target app: \(appName)")

        let urlScheme: String
        switch appName.lowercased() {
        case "instagram":
            urlScheme = "instagram://"
        case "tiktok":
            urlScheme = "tiktok://"
        case "youtube":
            urlScheme = "youtube://"
        default:
            print("❌ Unknown app: \(appName)")
            return
        }

        guard let url = URL(string: urlScheme) else {
            print("❌ Invalid URL scheme: \(urlScheme)")
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(url) { success in
                if success {
                    print("✅ Successfully opened \(appName)")
                    let bundleId: String?
                    switch appName.lowercased() {
                    case "instagram": bundleId = "com.burbn.instagram"
                    case "tiktok": bundleId = "com.zhiliaoapp.musically"
                    case "youtube": bundleId = "com.google.ios.youtube"
                    default: bundleId = nil
                    }
                    if let bundleId { self.recordAutomationOpen(bundleId: bundleId) }
                } else {
                    print("❌ Failed to open \(appName) - app might not be installed")
                }
            }
        }
    }

    private func checkShortcutAppMatching(userDefaults: UserDefaults?) {
        guard let userDefaults = userDefaults,
            let bundleId = userDefaults.string(forKey: "shortcutTargetBundleId")
        else {
            return
        }

        print("🔗 Checking shortcut app matching for bundle: \(bundleId)")
        if isAccessBlocked(for: bundleId) {
            print("🚫 Access window active for \(bundleId); opening target directly")
            let schemes = primaryAndFallbackSchemes(for: bundleId)
            attemptOpen(schemes: schemes, index: 0, bundleId: bundleId, logCost: 0) { _ in }
            userDefaults.removeObject(forKey: "shortcutTargetBundleId")
            return
        }

        if appSelection.applicationTokens.isEmpty {
            // Автоматически устанавливаем приложение из шортката
            print("🔗 No apps selected, auto-setting target from shortcut: \(bundleId)")
            autoSetTargetApp(bundleId: bundleId)

            DispatchQueue.main.async {
                self.message =
                    "🎯 Automatically selected \(self.getBundleIdDisplayName(bundleId)) from the shortcut!"
            }
        } else {
            print("🔗 Apps already selected, using existing selection")
        }

        // Показываем PayGate для выбранной цели
        payGateTargetBundleId = bundleId
        showPayGate = true

        // Очищаем флаг после обработки
        userDefaults.removeObject(forKey: "shortcutTargetBundleId")
    }

    private func getBundleIdDisplayName(_ bundleId: String) -> String {
        TargetResolver.displayName(for: bundleId)
    }

    private func reopenTargetIfPossible(bundleId: String) {
        guard let scheme = TargetResolver.urlScheme(forBundleId: bundleId),
              let url = URL(string: scheme)
        else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - App Selection Methods

    func toggleInstagramSelection(_ enabled: Bool) {
        isInstagramSelected = enabled
    }

    private func setInstagramAsTarget() {
        // Не меняем appSelection программно — выбор делает пользователь в FamilyActivityPicker
        print("🎯 Instagram: user-driven selection via FamilyActivityPicker (no-op)")
        isUpdatingInstagramSelection = true
        defer { isUpdatingInstagramSelection = false }
        isInstagramSelected = true
    }

    private func clearAppSelection() {
        print("🧹 === CLEAR SELECTION BEGIN ===")

        // Устанавливаем флаг для предотвращения рекурсии
        isUpdatingInstagramSelection = true
        defer { isUpdatingInstagramSelection = false }

        appSelection = FamilyActivitySelection()
        print("📱 App selection cleared")

        // Сбрасываем флаг Instagram без вызова didSet (избегаем рекурсии)
        isInstagramSelected = false
        print("✅ isInstagramSelected = false (no recursion)")

        print("🧹 === CLEAR SELECTION END ===")
    }

    // MARK: - Smart App Selection

    /// Автоматически устанавливает приложение для отслеживания по bundle ID
    private func autoSetTargetApp(bundleId: String) {
        print("🎯 Auto-setting target app: \(bundleId)")

        switch bundleId {
        case "com.burbn.instagram":
            setInstagramAsTarget()
        case "com.zhiliaoapp.musically", "com.google.ios.youtube":
            // Для TikTok и YouTube оставляем только сохранение метаданных (ручной выбор)
            break
        default:
            // Без автозаполнения — только ручной выбор в FamilyActivityPicker
            break
        }

        // Сохраняем информацию о том, что выбор был автоматическим
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(bundleId, forKey: "autoSelectedAppBundleId")
        userDefaults.set(Date(), forKey: "autoSelectionDate")

        print("✅ Auto-selected app: \(getBundleIdDisplayName(bundleId))")
    }

    // Автоматический выбор приложений удален — используем только ручной выбор

    // Автоматический умный выбор удален — используем только ручной выбор

    private func setEntertainmentAsTarget() {
        let newSelection = FamilyActivitySelection()
        // Оставляем пустой выбор - DeviceActivityMonitor будет использовать fallback категории
        appSelection = newSelection
        print("📱 Entertainment apps selected for tracking")
    }

    // setSocialMediaAsTarget удален — оставляем только ручной выбор в FamilyActivityPicker

    // MARK: - Utility Functions

    private func withTimeout<T>(seconds: TimeInterval, operation: @Sendable @escaping () async -> T)
        async -> T?
    {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            var result: T? = nil
            while let value = await group.next() {
                if let unwrapped = value {
                    result = unwrapped
                    group.cancelAll()
                    break
                }
            }
            return result
        }
    }

    // MARK: - Step Observation
    private func startStepObservation() {
        healthKitService.startObservingSteps { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStepsBalance()
                if let steps = self?.stepsToday {
                    print("📊 Auto-updated steps (custom day): \(Int(steps))")
                }
            }
        }
    }
    
    // MARK: - CloudKit Sync Helpers
    
    func getAllShieldSettingsForCloud() -> [String: CloudShieldSettings] {
        var result: [String: CloudShieldSettings] = [:]
        for (bundleId, settings) in appUnlockSettings {
            result[bundleId] = CloudShieldSettings(
                entryCostSteps: settings.entryCostSteps,
                dayPassCostSteps: settings.dayPassCostSteps,
                minuteTariffEnabled: settings.minuteTariffEnabled,
                familyControlsModeEnabled: settings.familyControlsModeEnabled,
                allowedWindowsRaw: settings.allowedWindows.map { $0.rawValue }
            )
        }
        return result
    }
    
    func getStepsSpentByDayForCloud() -> [String: [String: Int]] {
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: "appStepsSpentByDay_v1"),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            return decoded
        }
        return [:]
    }
    
    func getDayPassesForCloud() -> [String: Date] {
        return dayPassGrants
    }
    
    func restoreShieldSettingsFromCloud(_ cloudSettings: [String: CloudShieldSettings]) async {
        for (bundleId, cloud) in cloudSettings {
            var settings = AppUnlockSettings(
                entryCostSteps: cloud.entryCostSteps,
                dayPassCostSteps: cloud.dayPassCostSteps
            )
            settings.minuteTariffEnabled = cloud.minuteTariffEnabled
            settings.familyControlsModeEnabled = cloud.familyControlsModeEnabled
            settings.allowedWindows = Set(cloud.allowedWindowsRaw.compactMap { AccessWindow(rawValue: $0) })
            
            appUnlockSettings[bundleId] = settings
        }
        persistAppUnlockSettings()
        print("☁️ Restored \(cloudSettings.count) shield settings from cloud")
    }
    
    func restoreStepsSpentFromCloud(_ cloudSteps: [String: [String: Int]]) async {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(cloudSteps) {
            g.set(data, forKey: "appStepsSpentByDay_v1")
        }
        loadAppStepsSpentToday()
        print("☁️ Restored steps spent data from cloud")
    }
    
    func restoreDayPassesFromCloud(_ cloudDayPasses: [String: Date]) async {
        dayPassGrants = cloudDayPasses
        persistDayPassGrants()
        print("☁️ Restored \(cloudDayPasses.count) day passes from cloud")
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

    func refreshStepsIfAuthorized() async {
        let status = healthKitService.authorizationStatus()
        guard status == .sharingAuthorized else {
            print("ℹ️ HealthKit not authorized yet, skipping refresh")
            return
        }
        await refreshStepsBalance()
    }

    func cacheStepsToday() {
        let g = UserDefaults.stepsTrader()
        g.set(Int(stepsToday), forKey: "cachedStepsToday")
    }
    
    func loadCachedStepsToday() {
        let g = UserDefaults.stepsTrader()
        let cached = g.integer(forKey: "cachedStepsToday")
        if cached > 0 {
            stepsToday = Double(cached)
            print("💾 Loaded cached stepsToday: \(cached)")
        }
    }

    private func fallbackCachedSteps() -> Double {
        let g = UserDefaults.stepsTrader()
        let cached = g.integer(forKey: "cachedStepsToday")
        if cached > 0 {
            print("💾 Falling back to cached steps: \(cached)")
            return Double(cached)
        }
        return 0
    }

    func addDebugSteps(_ count: Int) {
        debugBonusSteps += count
        cacheStepsToday()
        syncAndPersistBonusBreakdown()
        print("🧪 Debug: added \(count) steps. Bonus now \(bonusSteps), total \(totalStepsBalance)")
    }
}
