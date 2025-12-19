import AVFoundation
import AudioToolbox
import Combine
import DeviceActivity
import FamilyControls
import Foundation
import HealthKit
import ManagedSettings
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
    @Published var entryCostSteps: Int = Tariff.easy.entryCostSteps
    @Published var stepsBalance: Int = 0
    @Published var spentStepsToday: Int = 0

    // Budget properties that mirror BudgetEngine for UI updates
    @Published var dailyBudgetMinutes: Int = 0
    @Published var remainingMinutes: Int = 0
    // Focus-gate state
    @Published var showFocusGate: Bool = false
    @Published var focusGateTargetBundleId: String? = nil
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
        
        // Sync entry cost with current tariff
        syncEntryCostWithTariff()

        // Восстановим закреплённый выбор приложений (если есть)
        if let service = familyControlsService as? FamilyControlsService {
            // FamilyControlsService сам вызвал restorePersistentSelection() в init
            self.appSelection = service.selection
        }

        // Загрузка баланса шагов
        loadSpentStepsBalance()
        // Загрузка стоимости входа
        loadEntryCost()

        // Инициализируем значения по умолчанию если их нет
        if entryCostSteps == 0 {
            entryCostSteps = 100  // 100 шагов по умолчанию
            persistEntryCost(tariff: .easy)
        }

        // Обновляем баланс шагов
        Task {
            await refreshStepsBalance()
        }
        
        // Start automatic step updates
        startStepObservation()

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
                } else if name.rawValue as String == "com.steps.trader.focusgate" {
                    Task { @MainActor in
                        print("📱 Received FocusGate notification from shortcut")
                        if let userInfo = userInfo as? [String: Any],
                           let target = userInfo["target"] as? String,
                           let bundleId = userInfo["bundleId"] as? String {
                            print("📱 FocusGate notification - target: \(target), bundleId: \(bundleId)")
                            `self`.focusGateTargetBundleId = bundleId
                            `self`.showFocusGate = true
                        }
                    }
                }
            },
            "com.steps.trader.refresh" as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Focus Gate handlers + Pay per entry
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

        // Intercept Instagram launches
        if scheme == "instagram" {
            print("🎯 Instagram launch intercepted: \(url)")
            print("🎯 Current FocusGate state - showFocusGate: \(showFocusGate), targetBundleId: \(focusGateTargetBundleId ?? "nil")")
            
            // Check if we just opened Instagram ourselves (anti-loop protection)
            let userDefaults = UserDefaults.stepsTrader()
            if let lastAppOpenTime = userDefaults.object(forKey: "lastAppOpenedFromStepsTrader") as? Date {
                let timeSinceOpen = Date().timeIntervalSince(lastAppOpenTime)
                if timeSinceOpen < 3.0 {
                    print("🚫 Ignoring Instagram launch - we just opened it ourselves (\(Int(timeSinceOpen))s ago)")
                    return
                }
            }
            
            // Clear any existing handoff tokens for Instagram
            if handoffToken?.targetBundleId == "com.burbn.instagram" {
                handoffToken = nil
                showHandoffProtection = false
                userDefaults.removeObject(forKey: "handoffToken")
            }
            
            // Show pay gate for Instagram immediately
            print("🎯 Setting FocusGate for Instagram - showFocusGate: \(showFocusGate) -> true")
            focusGateTargetBundleId = "com.burbn.instagram"
            showFocusGate = true
            print("🎯 FocusGate set - showFocusGate: \(showFocusGate), targetBundleId: \(focusGateTargetBundleId ?? "nil")")
            return
        }

        if host == "pay" {
            Task { @MainActor in
                await refreshStepsBalance()
                if canPayForEntry() {
                    _ = payForEntry()
                    message = "✅ \(entryCostSteps) steps deducted. Access granted."
                } else {
                    message =
                        "❌ Not enough steps. Need another \(max(0, entryCostSteps - stepsBalance))."
                }
            }
            return
        }

        // поддержка: steps-trader://focus?target=instagram | steps-trader://guard?target=instagram
        let isFocus = (host == "focus" || url.path.contains("focus"))
        let isGuard = (host == "guard" || url.path.contains("guard"))
        guard isFocus || isGuard else { return }
        var bundleId: String? = target
        if let t = target, !t.contains(".") {
            // маппинг короткого имени в bundle id
            switch t.lowercased() {
            case "instagram": bundleId = "com.burbn.instagram"
            case "tiktok": bundleId = "com.zhiliaoapp.musically"
            case "youtube": bundleId = "com.google.ios.youtube"
            default: break
            }
        }
        focusGateTargetBundleId = bundleId
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

        // Otherwise show our focus gate overlay with a pay button
        showFocusGate = bundleId != nil
        print("🎯 FocusGate: target=\(focusGateTargetBundleId ?? "nil") show=\(showFocusGate)")
        if let engine = budgetEngine as? BudgetEngine { engine.reloadFromStorage() }
    }

    // MARK: - Focus Gate payment pipeline
    func handleFocusGatePayment(for bundleId: String) async {
        let userDefaults = UserDefaults.stepsTrader()
        await refreshStepsBalance()
        print("🎯 FocusGate: Evaluating payment for \(bundleId)")
        print("   - stepsToday: \(Int(stepsToday))")
        print("   - stepsBalance: \(stepsBalance)")
        print("   - entryCostSteps: \(entryCostSteps)")
        print("   - selected apps: \(appSelection.applicationTokens.count)")
        print("   - selected categories: \(appSelection.categoryTokens.count)")

        guard canPayForEntry() else {
            message =
                "❌ Not enough steps. Need another \(max(0, entryCostSteps - stepsBalance)) steps."
            print("❌ FocusGate: Not enough steps (balance \(stepsBalance) < cost \(entryCostSteps))")
            return
        }

        guard payForEntry() else {
            print("❌ FocusGate: payForEntry() returned false")
            return
        }
        print("✅ FocusGate: payForEntry() succeeded; new balance \(stepsBalance)")

        message = "✅ \(entryCostSteps) steps deducted. Access granted."
        print("✅ FocusGate: Steps deducted, proceeding to open target app")

        // Update guard flags before attempting to open the target app
        let now = Date()
        userDefaults.set(now, forKey: "lastAppOpenedFromStepsTrader")
        userDefaults.set(now, forKey: "lastFocusGateAction")
        userDefaults.set(now, forKey: "focusGateLastOpen")

        openTargetAppFromFocusGate(bundleId)
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

    private func openTargetAppFromFocusGate(_ bundleId: String) {
        let schemes = primaryAndFallbackSchemes(for: bundleId)
        guard !schemes.isEmpty else {
            print("❌ FocusGate: No URL schemes available for bundle \(bundleId)")
            return
        }

        showFocusGate = false
        focusGateTargetBundleId = bundleId
        attemptOpen(schemes: schemes, index: 0, bundleId: bundleId)
    }

    private func attemptOpen(schemes: [String], index: Int, bundleId: String) {
        guard index < schemes.count else {
            print("❌ FocusGate: Failed to open \(bundleId) after trying all schemes")
            return
        }

        let scheme = schemes[index]
        guard let url = URL(string: scheme) else {
            print("⚠️ FocusGate: Invalid URL scheme \(scheme), trying next")
            attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId)
            return
        }

        print("🚀 FocusGate: Attempting to open \(bundleId) with scheme \(scheme)")
        UIApplication.shared.open(url) { [weak self] success in
            guard let self = self else { return }

            if success {
                print("✅ FocusGate: Successfully opened \(bundleId)")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self.showFocusGate = false
                    self.focusGateTargetBundleId = nil
                }
            } else {
                print("❌ FocusGate: Scheme \(scheme) failed for \(bundleId), trying next")
                self.attemptOpen(schemes: schemes, index: index + 1, bundleId: bundleId)
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
        default:
            print("⚠️ FocusGate: Unknown bundle id \(bundleId), using instagram fallback")
            return ["instagram://"]
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
        if isTrackingTime {
            // Сохраняем время ухода в фон
            UserDefaults.standard.set(Date(), forKey: "backgroundTime")
            print("💾 Saved background time for tracking calculation")
        }
    }

    func handleAppWillEnterForeground() {
        print("📱 App entering foreground - checking elapsed time")

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

    }

    // Convenience computed properties for backward compatibility
    var budget: any BudgetEngineProtocol { budgetEngine }
    var family: any FamilyControlsServiceProtocol { familyControlsService }

    // MARK: - Budget Sync
    private func syncBudgetProperties() {
        dailyBudgetMinutes = budgetEngine.dailyBudgetMinutes
        remainingMinutes = budgetEngine.remainingMinutes
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
        let savedSpentTariffRaw = userDefaults.string(forKey: "spentTariff") ?? "easy"
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
            stepsToday = try await healthKitService.fetchTodaySteps()
        } catch {
            print("❌ Failed to refresh steps from HealthKit: \(error.localizedDescription)")

            if let hkError = error as? HKError {
                switch hkError.code {
                case .errorAuthorizationDenied:
                    message =
                        "❌ HealthKit access denied. Open the Health app → Sources → Steps Trader and enable step reading."
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
                stepsToday = 0
            #endif
        }
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: "stepsBalanceAnchor") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(anchor) {
            spentStepsToday = 0
            g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
        }
        stepsBalance = max(0, Int(stepsToday) - spentStepsToday)
        g.set(spentStepsToday, forKey: "spentStepsToday")
        g.set(stepsBalance, forKey: "stepsBalance")
    }

    func canPayForEntry() -> Bool {
        stepsBalance >= entryCostSteps
    }

    @discardableResult
    func payForEntry() -> Bool {
        guard canPayForEntry() else { return false }
        // Не позволяем тратить больше, чем пройдено сегодня
        let todaysSteps = Int(stepsToday)
        let newSpent = min(spentStepsToday + entryCostSteps, max(0, todaysSteps))
        spentStepsToday = newSpent
        stepsBalance = max(0, todaysSteps - spentStepsToday)
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
        // Клэмп, чтобы потраченные шаги не превышали пройденные за сегодня
        let todaysSteps = Int(stepsToday)
        if spentStepsToday > todaysSteps { spentStepsToday = todaysSteps }
        stepsBalance = g.integer(forKey: "stepsBalance")
        if stepsBalance == 0 {
            stepsBalance = max(0, todaysSteps - spentStepsToday)
        }
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
    
    // Sync entry cost with current tariff
    private func syncEntryCostWithTariff() {
        entryCostSteps = budgetEngine.tariff.entryCostSteps
        print("💰 Synced entry cost: \(entryCostSteps) steps for \(budgetEngine.tariff.displayName)")
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

        // 8. Пересчитываем бюджет с текущими шагами
        Task {
            do {
                stepsToday = try await healthKitService.fetchTodaySteps()
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
        content.title = "🚶‍♂️ Steps Trader"
        content.body = "Walk more steps to earn extra entertainment time!"
        content.sound = .default
        content.badge = 1

        // Добавляем action для быстрого возврата в приложение
        let returnAction = UNNotificationAction(
            identifier: "RETURN_TO_APP",
            title: "Open Steps Trader",
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

    private func schedulePeriodicNotifications() {
        guard isBlocked else { return }

        let content = UNMutableNotificationContent()
        content.title = "⏰ Steps Trader"
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

    func bootstrap() async {
        print("🚀 Steps Trader: Starting bootstrap...")

        // Обновляем время из shared storage (на случай если DeviceActivity обновил его)
        loadSpentTime()

        do {
            print("📊 Requesting HealthKit authorization...")
            try await healthKitService.requestAuthorization()
            print("✅ HealthKit authorization completed")

            print("🔐 Requesting Family Controls authorization...")
            do {
                try await familyControlsService.requestAuthorization()
                print("✅ Family Controls authorization completed")
            } catch {
                print("⚠️ Family Controls authorization failed: \(error)")
                // Не блокируем весь bootstrap из-за Family Controls
            }

            print("🔔 Requesting notification permissions...")
            try await notificationService.requestPermission()
            print("✅ Notification permissions completed")

            print("📈 Fetching today's steps...")
            do {
                stepsToday = try await healthKitService.fetchTodaySteps()
                print("✅ Today's steps: \(Int(stepsToday))")
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
            stepsToday = try await healthKitService.fetchTodaySteps()
        } catch {
            print("⚠️ Could not fetch step data for recalc: \(error)")
            #if targetEnvironment(simulator)
                stepsToday = 2500  // Демо-значение для симулятора
            #else
                stepsToday = 0
            #endif
        }

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
            stepsToday = try await healthKitService.fetchTodaySteps()
        } catch {
            print("⚠️ Could not fetch step data for silent recalc: \(error)")
            #if targetEnvironment(simulator)
                stepsToday = 2500  // Демо-значение для симулятора
            #else
                stepsToday = 0
            #endif
        }

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
                    message = "Steps Trader: No time left! Walk more steps."
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
        let shouldShowFocusGate = userDefaults.bool(forKey: "shouldShowFocusGate")
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

        if shouldShowFocusGate {
            focusGateTargetBundleId = userDefaults.string(forKey: "focusGateTargetBundleId")
            showFocusGate = focusGateTargetBundleId != nil
            userDefaults.removeObject(forKey: "shouldShowFocusGate")
            print(
                "🎯 FocusGate (from UserDefaults): show=\(showFocusGate), target=\(focusGateTargetBundleId ?? "nil")"
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

        // Показываем Focus Gate для выбранной цели
        focusGateTargetBundleId = bundleId
        showFocusGate = true

        // Очищаем флаг после обработки
        userDefaults.removeObject(forKey: "shortcutTargetBundleId")
    }

    private func getBundleIdDisplayName(_ bundleId: String) -> String {
        switch bundleId {
        case "com.burbn.instagram": return "Instagram"
        case "com.zhiliaoapp.musically": return "TikTok"
        case "com.google.ios.youtube": return "YouTube"
        default: return bundleId
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
        healthKitService.startObservingSteps { [weak self] newSteps in
            Task { @MainActor in
                self?.stepsToday = newSteps
                await self?.refreshStepsBalance()
                print("📊 Auto-updated steps: \(Int(newSteps))")
            }
        }
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
private func requestFamilyControlsIfNeeded() async {
    let center = AuthorizationCenter.shared
    switch center.authorizationStatus {
    case .notDetermined:
        do { try await center.requestAuthorization(for: .individual) } catch {
            print("❌ FamilyControls auth failed: \(error)")
        }
    default: break
    }
}

@MainActor
private func requestNotificationPermissionIfNeeded() async {
    do { try await DIContainer.shared.makeNotificationService().requestPermission() } catch {
        print("❌ Notification permission failed: \(error)")
    }
}
