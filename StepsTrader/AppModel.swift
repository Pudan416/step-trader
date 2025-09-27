import Foundation
import Combine
import SwiftUI
import HealthKit
import FamilyControls
import DeviceActivity
import ManagedSettings
import UserNotifications
import AVFoundation
import AudioToolbox
import UIKit

// MARK: - AppModel
@MainActor
final class AppModel: ObservableObject {
    // Dependencies
    private let healthKitService: any HealthKitServiceProtocol
    let familyControlsService: any FamilyControlsServiceProtocol
    private let notificationService: any NotificationServiceProtocol
    private let budgetEngine: any BudgetEngineProtocol
    
    // Published properties
    @Published var stepsToday: Double = 0
    @Published var spentSteps: Int = 0
    @Published var spentMinutes: Int = 0  // Реальное время проведенное в приложении
    @Published var isTrackingTime = false
    @Published var isBlocked = false  // Показывать ли экран блокировки
    @Published var message: String?
    @Published var currentSessionElapsed: Int?
    
    // Budget properties that mirror BudgetEngine for UI updates
    @Published var dailyBudgetMinutes: Int = 0
    @Published var remainingMinutes: Int = 0
    // Focus-gate state
    @Published var showFocusGate: Bool = false
    @Published var focusGateTargetBundleId: String? = nil
    @Published var showQuickStatusPage = false  // Показывать ли страницу быстрого статуса
    @Published var appSelection = FamilyActivitySelection() {
        didSet {
            // Синхронизируем с FamilyControlsService только если есть реальные изменения
            if appSelection.applicationTokens != oldValue.applicationTokens || 
               appSelection.categoryTokens != oldValue.categoryTokens {
                syncAppSelectionToService()
                saveAppSelection() // Сохраняем выбор пользователя
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
        
        print("🎯 AppModel initialized with dependencies")
        
        // Загружаем сохраненное состояние Instagram
        self.isInstagramSelected = UserDefaults.standard.bool(forKey: "isInstagramSelected")
        
        // Синхронизируем начальное состояние без вызова didSet
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Сначала загружаем сохраненный выбор приложений
            self.loadAppSelection()
            
            // Затем синхронизируем с FamilyControlsService
            if self.appSelection.applicationTokens.isEmpty && self.appSelection.categoryTokens.isEmpty {
                self.appSelection = self.familyControlsService.selection
            }
            
            // Восстанавливаем сохраненное время использования
            self.loadSpentTime()
            print("🔄 Initial sync: \(self.appSelection.applicationTokens.count) apps")
        }
        
        // Подписываемся на уведомления о жизненном цикле приложения
        setupAppLifecycleObservers()

        // Подписка на дарвиновское уведомление от сниппета/интента (безопасная привязка observer)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, name, _, _ in
                guard let observer = observer, let name = name else { return }
                let `self` = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
                if name.rawValue as String == "com.steps.trader.refresh" {
                    Task { @MainActor in
                        await `self`.recalcSilently()
                        `self`.loadSpentTime()
                    }
                }
            },
            "com.steps.trader.refresh" as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Focus Gate handlers
    func handleIncomingURL(_ url: URL) {
        // поддержка: steps-trader://focus?target=instagram | myfocusapp://guard?target=instagram
        let isFocus = (url.host == "focus" || url.path.contains("focus"))
        let isGuard = (url.host == "guard" || url.path.contains("guard"))
        guard isFocus || isGuard else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let target = components?.queryItems?.first(where: { $0.name == "target" })?.value
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

        // Иначе показываем наши фокус-ворота (визуальная шторка) с кнопкой "Открыть"
        showFocusGate = bundleId != nil
        print("🎯 FocusGate: target=\(focusGateTargetBundleId ?? "nil") show=\(showFocusGate)")
        if let engine = budgetEngine as? BudgetEngine { engine.reloadFromStorage() }
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
    
    private func handleAppDidEnterBackground() {
        print("📱 App entered background - timer will be suspended")
        if isTrackingTime {
            // Сохраняем время ухода в фон
            UserDefaults.standard.set(Date(), forKey: "backgroundTime")
            print("💾 Saved background time for tracking calculation")
        }
    }
    
    private func handleAppWillEnterForeground() {
        print("📱 App entering foreground - checking elapsed time")
        
        // Проверяем, сколько времени прошло в фоне (только если включено отслеживание)
        if isTrackingTime {
        if let backgroundTime = UserDefaults.standard.object(forKey: "backgroundTime") as? Date {
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
                        message = "⏰ Время истекло пока вы были вне приложения!"
                        
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
        print("🔄 Syncing app selection to service: \(appSelection.applicationTokens.count) apps, \(appSelection.categoryTokens.count) categories")
        
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            (self.familyControlsService as? FamilyControlsService)?.selection = finalSelection
            print("✅ Service updated with \(finalSelection.applicationTokens.count) apps")
        }
    }

    private func loadSpentTime() {
        let userDefaults = UserDefaults.stepsTrader()
        let savedSpentMinutes = userDefaults.integer(forKey: "spentMinutes")
        let savedDate = userDefaults.object(forKey: "spentTimeDate") as? Date ?? Date()
        
        // Сбрасываем время если прошел день
        if !Calendar.current.isDate(savedDate, inSameDayAs: Date()) {
            spentMinutes = 0
            spentSteps = 0
            saveSpentTime()
            print("🔄 Reset spent time for new day")
        } else {
            spentMinutes = savedSpentMinutes
            spentSteps = spentMinutes * Int(budgetEngine.stepsPerMinute)
            syncBudgetProperties() // Sync budget properties for UI updates
            print("📊 Loaded spent time: \(spentMinutes) minutes, \(spentSteps) steps")
        }
    }
    
    private func saveSpentTime() {
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.set(spentMinutes, forKey: "spentMinutes")
        userDefaults.set(Date(), forKey: "spentTimeDate")
        print("💾 Saved spent time: \(spentMinutes) minutes")
    }
    
    func updateSpentTime(minutes: Int) {
        spentMinutes = minutes
        spentSteps = spentMinutes * Int(budgetEngine.stepsPerMinute)
        saveSpentTime()
        syncBudgetProperties() // Sync budget properties for UI updates
        print("🕐 Updated spent time: \(spentMinutes) minutes (\(spentSteps) steps)")
    }
    
    func consumeMinutes(_ minutes: Int) {
        budgetEngine.consume(mins: minutes)
        syncBudgetProperties() // Sync budget properties for UI updates
        print("⏱️ Consumed \(minutes) minutes, remaining: \(remainingMinutes)")
    }
    
    // MARK: - App Selection Persistence
    
    private func saveAppSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        
        // Сохраняем ApplicationTokens
        if !appSelection.applicationTokens.isEmpty {
            do {
                let tokensData = try NSKeyedArchiver.archivedData(withRootObject: appSelection.applicationTokens, requiringSecureCoding: true)
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
                let categoriesData = try NSKeyedArchiver.archivedData(withRootObject: appSelection.categoryTokens, requiringSecureCoding: true)
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
                let obj = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSSet.self, from: tokensData)
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
                let obj = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSSet.self, from: categoriesData)
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
        print("🔍 === ДИАГНОСТИКА FAMILY CONTROLS ===")
        
        // 1. Проверка авторизации
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.checkAuthorizationStatus()
        }
        
        // 2. Проверка выбранных приложений
        print("📱 Выбранные приложения:")
        print("   - ApplicationTokens: \(appSelection.applicationTokens.count)")
        print("   - CategoryTokens: \(appSelection.categoryTokens.count)")
        
        // 3. Проверка бюджета
        print("💰 Бюджет:")
        print("   - Всего минут: \(budgetEngine.dailyBudgetMinutes)")
        print("   - Осталось минут: \(budgetEngine.remainingMinutes)")
        print("   - Потрачено минут: \(spentMinutes)")
        
        // 4. Проверка состояния отслеживания
        print("⏱️ Состояние отслеживания:")
        print("   - Активно: \(isTrackingTime)")
        print("   - Заблокировано: \(isBlocked)")
        
        // 5. Проверка UserDefaults
        let userDefaults = UserDefaults.stepsTrader()
        print("💾 Shared UserDefaults:")
        print("   - Budget minutes: \(userDefaults.object(forKey: "budgetMinutes") ?? "nil")")
        print("   - Spent minutes: \(userDefaults.object(forKey: "spentMinutes") ?? "nil")")
        print("   - Monitoring start: \(userDefaults.object(forKey: "monitoringStartTime") ?? "nil")")
        
        // 6. DeviceActivity диагностика
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.checkDeviceActivityStatus()
        }
        
        message = "🔍 Диагностика завершена. Проверьте консоль Xcode для деталей."
    }
    
    func resetStatistics() {
        print("🔄 === СБРОС СТАТИСТИКИ ===")
        
        // 1. Останавливаем отслеживание если активно
        if isTrackingTime {
            stopTracking()
        }
        
        // 2. Сбрасываем время и состояние
        spentMinutes = 0
        spentSteps = 0
        isBlocked = false
        currentSessionElapsed = nil
        
        // 3. Очищаем UserDefaults (App Group)
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.removeObject(forKey: "spentMinutes")
        userDefaults.removeObject(forKey: "spentTimeDate")
        userDefaults.removeObject(forKey: "budgetMinutes")
        userDefaults.removeObject(forKey: "monitoringStartTime")
        userDefaults.removeObject(forKey: "selectedAppsCount")
        userDefaults.removeObject(forKey: "selectedCategoriesCount")
        userDefaults.removeObject(forKey: "selectedApplicationTokens")
        userDefaults.removeObject(forKey: "persistentApplicationTokens")
        userDefaults.removeObject(forKey: "persistentCategoryTokens")
        userDefaults.removeObject(forKey: "appSelectionSavedDate")
        print("💾 Очищены App Group UserDefaults")
        
        // 4. Очищаем обычные UserDefaults
        UserDefaults.standard.removeObject(forKey: "dailyBudgetMinutes")
        UserDefaults.standard.removeObject(forKey: "remainingMinutes")
        UserDefaults.standard.removeObject(forKey: "todayAnchor")
        print("💾 Очищены стандартные UserDefaults")
        
        // 5. Сбрасываем бюджет вручную (так как resetForToday приватный)
        let todayStart = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(todayStart, forKey: "todayAnchor")
        UserDefaults.standard.set(0, forKey: "dailyBudgetMinutes")
        UserDefaults.standard.set(0, forKey: "remainingMinutes")
        print("💰 Сброшен бюджет")
        
        // 6. Снимаем все блокировки
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.stopMonitoring()
            familyService.disableShield()
            print("🛡️ Отключены блокировки")
        }
        
        // 7. Очищаем выбор приложений (как выбор, так и сохраненные данные)
        appSelection = FamilyActivitySelection()
        print("📱 Очищен выбор приложений и сохраненные данные")
        
        // 8. Пересчитываем бюджет с текущими шагами
        Task {
            do {
                stepsToday = try await healthKitService.fetchTodaySteps()
                let mins = budgetEngine.minutes(from: stepsToday)
                budgetEngine.setBudget(minutes: mins)
                syncBudgetProperties() // Sync budget properties for UI updates
                message = "🔄 Статистика сброшена! Новый бюджет: \(mins) минут из \(Int(stepsToday)) шагов"
                print("✅ Статистика сброшена. Новый бюджет: \(mins) минут")
        } catch {
                message = "🔄 Статистика сброшена, но ошибка обновления шагов: \(error.localizedDescription)"
                print("❌ Ошибка при обновлении шагов: \(error)")
            }
        }
        
        print("✅ === СБРОС ЗАВЕРШЕН ===")
    }
    
    private func sendReturnToAppNotification() {
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
        content.body = "Сделайте больше шагов, чтобы получить дополнительное время для развлечений!"
        content.sound = .default
        content.badge = 1
        
        // Добавляем action для быстрого возврата в приложение
        let returnAction = UNNotificationAction(
            identifier: "RETURN_TO_APP",
            title: "Открыть Steps Trader",
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
        content.body = "Напоминание: сделайте больше шагов для разблокировки!"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "periodicReminder-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: true) // каждые 5 минут
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
                stepsToday = 2500 // Демо-значение для симулятора
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
            syncBudgetProperties() // Sync budget properties for UI updates
            
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
            message = "Ошибка инициализации: \(error.localizedDescription)"
        }
    }

    func recalc() async throws {
        budgetEngine.resetIfNeeded()
        
        do {
            stepsToday = try await healthKitService.fetchTodaySteps()
        } catch {
            print("⚠️ Could not fetch step data for recalc: \(error)")
            #if targetEnvironment(simulator)
            stepsToday = 2500 // Демо-значение для симулятора
            #else
            stepsToday = 0
            #endif
        }
        
        let mins = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: mins)
        syncBudgetProperties() // Sync budget properties for UI updates
        message = "✅ Бюджет пересчитан: \(mins) минут (\(Int(stepsToday)) шагов)"
    }
    
    func recalcSilently() async {
        budgetEngine.resetIfNeeded()
        
        do {
            stepsToday = try await healthKitService.fetchTodaySteps()
        } catch {
            print("⚠️ Could not fetch step data for silent recalc: \(error)")
            #if targetEnvironment(simulator)
            stepsToday = 2500 // Демо-значение для симулятора
            #else
            stepsToday = 0
            #endif
        }
        
        let mins = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: mins)
        syncBudgetProperties() // Sync budget properties for UI updates
        print("🔄 Silent budget recalculation: \(mins) minutes from \(Int(stepsToday)) steps")
    }
    
    func toggleRealBlocking() {
        print("🚀 === НАЧАЛО TOGGLE REAL BLOCKING ===")
        print("🔐 Family Controls авторизован: \(familyControlsService.isAuthorized)")
        print("📱 Выбрано приложений: \(appSelection.applicationTokens.count)")
        print("📂 Выбрано категорий: \(appSelection.categoryTokens.count)")
        print("⏱️ Отслеживание активно: \(isTrackingTime)")
        print("💰 Осталось минут: \(budgetEngine.remainingMinutes)")
        
        guard familyControlsService.isAuthorized else {
            print("❌ Family Controls не авторизован - выход")
            message = "❌ Family Controls не авторизован"
            return
        }
        
        guard !appSelection.applicationTokens.isEmpty || !appSelection.categoryTokens.isEmpty else {
            print("❌ Нет выбранных приложений - выход")
            message = "❌ Сначала выберите приложение для блокировки"
            return
        }
        
        if isTrackingTime {
            print("🛑 Останавливаем отслеживание")
            stopTracking()
            message = "🔓 Блокировка снята"
            print("✅ Отслеживание остановлено")
        } else {
            print("🚀 Запускаем отслеживание")
            // Показываем сообщение сразу, чтобы UI не зависал
            message = "🛡️ Запуск отслеживания..."
            print("📱 UI сообщение установлено: 'Запуск отслеживания...'")
            
            // Запускаем отслеживание асинхронно
            Task { [weak self] in
                print("🔄 Создана асинхронная задача для запуска отслеживания")
                await MainActor.run {
                    print("🎯 Выполняем startTracking в главном потоке")
                    self?.startTracking()
                    let appCount = self?.appSelection.applicationTokens.count ?? 0
                    let remainingMinutes = self?.budgetEngine.remainingMinutes ?? 0
                    self?.message = "🛡️ Блокировка активна для приложения. Лимит: \(remainingMinutes) минут"
                    print("✅ Отслеживание запущено: \(appCount) приложений, \(remainingMinutes) минут")
                }
            }
        }
        
        print("🚀 === ЗАВЕРШЕНИЕ TOGGLE REAL BLOCKING ===")
    }
    
    private func startTracking() {
        print("🎯 === НАЧАЛО START TRACKING ===")
        print("💰 Проверяем бюджет: \(budgetEngine.remainingMinutes) минут")
        
        guard budgetEngine.remainingMinutes > 0 else {
            print("❌ Нет доступного времени - выход")
            message = "Steps Trader: Нет доступного времени! Сделайте больше шагов."
            return
        }
        
        print("📱 Проверяем выбор приложений: \(appSelection.applicationTokens.count) apps, \(appSelection.categoryTokens.count) categories")
        guard !appSelection.applicationTokens.isEmpty || !appSelection.categoryTokens.isEmpty else {
            print("❌ Нет выбранных приложений - выход")
            message = "❌ Выберите приложение для отслеживания"
            return
        }
        
        print("✅ Все проверки пройдены, запускаем отслеживание")
        isTrackingTime = true
        startTime = Date()
        currentSessionElapsed = 0
        print("⏱️ Установлены флаги отслеживания: isTrackingTime=true, startTime=\(Date())")
        
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
                print("🔄 Создана задача для запуска мониторинга с таймаутом 10 сек")
                await self?.withTimeout(seconds: 10) {
                    print("⏰ Запускаем startMonitoring в FamilyControlsService")
                    await MainActor.run {
                        familyService.startMonitoring(budgetMinutes: self?.budgetEngine.remainingMinutes ?? 0)
                    }
                    print("✅ startMonitoring завершен")
                }
                
                print("🔍 Запускаем диагностику DeviceActivity")
                // Run diagnostic after starting monitoring
                familyService.checkDeviceActivityStatus()
                print("✅ Диагностика завершена")
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
            print("✅ Реальное отслеживание активировано. Время считается в фоне.")
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
        
        print("⚠️ Демо-режим: время списывается каждую реальную минуту (только в приложении)")
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
            message = "⏰ ДЕМО: Время истекло!"
            
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
        let shouldShow = userDefaults.bool(forKey: "shouldShowQuickStatusPage")
        let shouldShowFocusGate = userDefaults.bool(forKey: "shouldShowFocusGate")
        let shouldAutoSelectApps = userDefaults.bool(forKey: "shouldAutoSelectApps")
        
        print("🔍 Checking flags - Quick Status: \(shouldShow), Auto Select: \(shouldAutoSelectApps)")
        
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
                let targetApp = userDefaults.string(forKey: "targetAppForReturn") ?? "неизвестное приложение"
                print("🔄 Auto-close scheduled in 1 second, target app: \(targetApp)")
                userDefaults.removeObject(forKey: "shouldAutoCloseQuickStatus")
                userDefaults.removeObject(forKey: "targetAppForReturn")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("🔄 Auto-closing QuickStatusView and opening \(targetApp)")
                    self.showQuickStatusPage = false
                    
                    // Активируем блокировку Intent'а
                    userDefaults.set(Date(), forKey: "returnModeActivatedTime")
                    
                    // Открываем целевое приложение
                    self.openTargetApp(targetApp)
                }
            }
        } else {
            print("🔍 No Quick Status flag found")
        }

        if shouldShowFocusGate {
            focusGateTargetBundleId = userDefaults.string(forKey: "focusGateTargetBundleId")
            showFocusGate = focusGateTargetBundleId != nil
            userDefaults.removeObject(forKey: "shouldShowFocusGate")
            print("🎯 FocusGate (from UserDefaults): show=\(showFocusGate), target=\(focusGateTargetBundleId ?? "nil")")
        }
    }

    // MARK: - Public helpers for views
    func reloadBudgetFromStorage() {
        if let engine = budgetEngine as? BudgetEngine {
            engine.reloadFromStorage()
            syncBudgetProperties() // Sync budget properties for UI updates
        }
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
              let bundleId = userDefaults.string(forKey: "shortcutTargetBundleId") else {
            return
        }
        
        print("🔗 Checking shortcut app matching for bundle: \(bundleId)")
        
        if appSelection.applicationTokens.isEmpty {
            // Автоматически устанавливаем приложение из шортката
            print("🔗 No apps selected, auto-setting target from shortcut: \(bundleId)")
            autoSetTargetApp(bundleId: bundleId)
            
            DispatchQueue.main.async {
                self.message = "🎯 Автоматически выбрано \(self.getBundleIdDisplayName(bundleId)) из шортката!"
            }
        } else {
            print("🔗 Apps already selected, using existing selection")
        }
        
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
        print("🧹 === НАЧАЛО ОЧИСТКИ ВЫБОРА ===")
        
        // Устанавливаем флаг для предотвращения рекурсии
        isUpdatingInstagramSelection = true
        defer { isUpdatingInstagramSelection = false }
        
        appSelection = FamilyActivitySelection()
        print("📱 App selection cleared")
        
        // Сбрасываем флаг Instagram без вызова didSet (избегаем рекурсии)
        isInstagramSelected = false
        print("✅ isInstagramSelected = false (без рекурсии)")
        
        print("🧹 === ЗАВЕРШЕНИЕ ОЧИСТКИ ВЫБОРА ===")
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
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @Sendable @escaping () async -> T) async -> T? {
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

    deinit {
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
        do { try await center.requestAuthorization(for: .individual) }
        catch { print("❌ FamilyControls auth failed: \(error)") }
    default: break
    }
}

@MainActor
private func requestNotificationPermissionIfNeeded() async {
    do { try await DIContainer.shared.makeNotificationService().requestPermission() }
    catch { print("❌ Notification permission failed: \(error)") }
}
