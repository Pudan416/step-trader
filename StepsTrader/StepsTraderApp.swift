import SwiftUI
import HealthKit
import Combine
import FamilyControls
import UserNotifications
import AVFoundation
import DeviceActivity
import ManagedSettings
import Foundation


// MARK: - Notification Manager
final class NotificationManager: NotificationServiceProtocol {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        
        if granted {
            print("✅ Notification permission granted")
        } else {
            print("❌ Notification permission denied")
            throw NotificationError.permissionDenied
        }
    }
    
    func sendTimeExpiredNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Время истекло!"
        content.body = "Доступ к выбранным приложениям заблокирован. Сделайте больше шагов для получения времени."
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "timeExpired",
            content: content,
            trigger: nil // Немедленное уведомление
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🔔 Тест уведомления"
        content.body = "Это тестовое уведомление от Steps Trader"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "testNotification",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Notification Errors
enum NotificationError: Error, LocalizedError {
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Уведомления запрещены пользователем"
        }
    }
}

// MARK: - Dependency Injection Container
final class DIContainer {
    static let shared = DIContainer()
    
    private init() {}
    
    // MARK: - Service Factories
    func makeHealthKitService() -> any HealthKitServiceProtocol {
        HealthKitService()
    }
    
    @MainActor
    func makeFamilyControlsService() -> any FamilyControlsServiceProtocol {
        FamilyControlsService()
    }
    
    func makeNotificationService() -> any NotificationServiceProtocol {
        NotificationManager.shared
    }
    
    func makeBudgetEngine() -> any BudgetEngineProtocol {
        BudgetEngine()
    }
    
    // MARK: - App Model Factory
    @MainActor
    func makeAppModel() -> AppModel {
        AppModel(
            healthKitService: makeHealthKitService(),
            familyControlsService: makeFamilyControlsService(),
            notificationService: makeNotificationService(),
            budgetEngine: makeBudgetEngine()
        )
    }
}

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
        
        print("🎯 AppModel initialized with dependencies")
        
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
    }
    
    private func setupAppLifecycleObservers() {
        // Когда приложение уходит в фон
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }
        
        // Когда приложение возвращается на передний план
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillEnterForeground()
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
        
        guard isTrackingTime else { return }
        
        // Проверяем, сколько времени прошло в фоне
        if let backgroundTime = UserDefaults.standard.object(forKey: "backgroundTime") as? Date {
            let elapsedSeconds = Date().timeIntervalSince(backgroundTime)
            let elapsedMinutes = Int(elapsedSeconds / 60)
            
            if elapsedMinutes > 0 {
                print("⏰ App was in background for \(elapsedMinutes) minutes")
                
                // Симулируем использование приложения за время в фоне
                for _ in 0..<elapsedMinutes {
                    guard budgetEngine.remainingMinutes > 0 else {
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
                    budgetEngine.consume(mins: 1)
                }
                
                print("⏱️ Updated: spent \(spentMinutes) min, remaining \(budgetEngine.remainingMinutes) min")
            }
            
            UserDefaults.standard.removeObject(forKey: "backgroundTime")
        }
    }
    
    // Convenience computed properties for backward compatibility
    var budget: any BudgetEngineProtocol { budgetEngine }
    var family: any FamilyControlsServiceProtocol { familyControlsService }
    
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
        let userDefaults = UserDefaults(suiteName: "group.personal-project.StepsTrader")
        let savedSpentMinutes = userDefaults?.integer(forKey: "spentMinutes") ?? 0
        let savedDate = userDefaults?.object(forKey: "spentTimeDate") as? Date ?? Date()
        
        // Сбрасываем время если прошел день
        if !Calendar.current.isDate(savedDate, inSameDayAs: Date()) {
            spentMinutes = 0
            spentSteps = 0
            saveSpentTime()
            print("🔄 Reset spent time for new day")
                } else {
            spentMinutes = savedSpentMinutes
            spentSteps = spentMinutes * Int(budgetEngine.stepsPerMinute)
            print("📊 Loaded spent time: \(spentMinutes) minutes, \(spentSteps) steps")
        }
    }
    
    private func saveSpentTime() {
        let userDefaults = UserDefaults(suiteName: "group.personal-project.StepsTrader")
        userDefaults?.set(spentMinutes, forKey: "spentMinutes")
        userDefaults?.set(Date(), forKey: "spentTimeDate")
        print("💾 Saved spent time: \(spentMinutes) minutes")
    }
    
    func updateSpentTime(minutes: Int) {
        spentMinutes = minutes
        spentSteps = spentMinutes * Int(budgetEngine.stepsPerMinute)
        saveSpentTime()
        print("🕐 Updated spent time: \(spentMinutes) minutes (\(spentSteps) steps)")
    }
    
    // MARK: - App Selection Persistence
    
    private func saveAppSelection() {
        let userDefaults = UserDefaults(suiteName: "group.personal-project.StepsTrader")
        
        // Сохраняем ApplicationTokens
        if !appSelection.applicationTokens.isEmpty {
            do {
                let tokensData = try NSKeyedArchiver.archivedData(withRootObject: appSelection.applicationTokens, requiringSecureCoding: true)
                userDefaults?.set(tokensData, forKey: "persistentApplicationTokens")
                print("💾 Saved app selection: \(appSelection.applicationTokens.count) apps")
            } catch {
                print("❌ Failed to save app selection: \(error)")
            }
                } else {
            userDefaults?.removeObject(forKey: "persistentApplicationTokens")
        }
        
        // Сохраняем CategoryTokens
        if !appSelection.categoryTokens.isEmpty {
            do {
                let categoriesData = try NSKeyedArchiver.archivedData(withRootObject: appSelection.categoryTokens, requiringSecureCoding: true)
                userDefaults?.set(categoriesData, forKey: "persistentCategoryTokens")
                print("💾 Saved category selection: \(appSelection.categoryTokens.count) categories")
            } catch {
                print("❌ Failed to save category selection: \(error)")
            }
                                } else {
            userDefaults?.removeObject(forKey: "persistentCategoryTokens")
        }
        
        // Сохраняем дату сохранения
        userDefaults?.set(Date(), forKey: "appSelectionSavedDate")
    }
    
    private func loadAppSelection() {
        let userDefaults = UserDefaults(suiteName: "group.personal-project.StepsTrader")
        var hasSelection = false
        var newSelection = FamilyActivitySelection()
        
        // Восстанавливаем ApplicationTokens
        if let tokensData = userDefaults?.data(forKey: "persistentApplicationTokens") {
            do {
                if let applicationTokens = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(tokensData) as? Set<ApplicationToken> {
                    newSelection.applicationTokens = applicationTokens
                    hasSelection = true
                    print("📱 Restored app selection: \(applicationTokens.count) apps")
                }
            } catch {
                print("❌ Failed to restore app selection: \(error)")
            }
        }
        
        // Восстанавливаем CategoryTokens
        if let categoriesData = userDefaults?.data(forKey: "persistentCategoryTokens") {
            do {
                if let categoryTokens = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(categoriesData) as? Set<ActivityCategoryToken> {
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
            if let savedDate = userDefaults?.object(forKey: "appSelectionSavedDate") as? Date {
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
        let userDefaults = UserDefaults(suiteName: "group.personal-project.StepsTrader")
        print("💾 Shared UserDefaults:")
        print("   - Budget minutes: \(userDefaults?.object(forKey: "budgetMinutes") ?? "nil")")
        print("   - Spent minutes: \(userDefaults?.object(forKey: "spentMinutes") ?? "nil")")
        print("   - Monitoring start: \(userDefaults?.object(forKey: "monitoringStartTime") ?? "nil")")
        
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
        let userDefaults = UserDefaults(suiteName: "group.personal-project.StepsTrader")
        userDefaults?.removeObject(forKey: "spentMinutes")
        userDefaults?.removeObject(forKey: "spentTimeDate")
        userDefaults?.removeObject(forKey: "budgetMinutes")
        userDefaults?.removeObject(forKey: "monitoringStartTime")
        userDefaults?.removeObject(forKey: "selectedAppsCount")
        userDefaults?.removeObject(forKey: "selectedCategoriesCount")
        userDefaults?.removeObject(forKey: "selectedApplicationTokens")
        userDefaults?.removeObject(forKey: "persistentApplicationTokens")
        userDefaults?.removeObject(forKey: "persistentCategoryTokens")
        userDefaults?.removeObject(forKey: "appSelectionSavedDate")
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
            
            if stepsToday == 0 {
                print("⚠️ No steps available - budget is 0 minutes")
                #if targetEnvironment(simulator)
                message = "🎮 Демо-режим: \(Int(stepsToday)) шагов = \(budgetMinutes) мин"
                #else
                message = "📱 Нет данных о шагах. Пройдите несколько шагов и обновите."
                #endif
            } else {
                print("✅ Budget calculated: \(budgetMinutes) minutes from \(Int(stepsToday)) steps")
                message = "✅ Бюджет рассчитан: \(budgetMinutes) мин"
            }
            
            print("🎉 Bootstrap completed successfully!")
            
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
        message = "✅ Бюджет пересчитан: \(mins) минут (\(Int(stepsToday)) шагов)"
    }
    
    func recalcSilently() async {
        do {
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
            print("🔄 Silent budget recalculation: \(mins) minutes from \(Int(stepsToday)) steps")
        } catch {
            print("❌ Ошибка при автопересчете: \(error)")
        }
    }
    
    func toggleRealBlocking() {
        guard familyControlsService.isAuthorized else {
            message = "❌ Family Controls не авторизован"
            return
        }
        
        guard !appSelection.applicationTokens.isEmpty || !appSelection.categoryTokens.isEmpty else {
            message = "❌ Сначала выберите приложение для блокировки"
            return
        }
        
        if isTrackingTime {
            stopTracking()
            message = "🔓 Блокировка снята"
        } else {
            startTracking()
            let appCount = appSelection.applicationTokens.count
            message = "🛡️ Блокировка активна для приложения. Лимит: \(budgetEngine.remainingMinutes) минут"
        }
    }
    
    private func startTracking() {
        guard budgetEngine.remainingMinutes > 0 else {
            message = "Steps Trader: Нет доступного времени! Сделайте больше шагов."
            return
        }
        
        guard !appSelection.applicationTokens.isEmpty || !appSelection.categoryTokens.isEmpty else {
            message = "❌ Выберите приложение для отслеживания"
            return
        }
        
        isTrackingTime = true
        startTime = Date()
        currentSessionElapsed = 0
        
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
            
            familyService.startMonitoring(budgetMinutes: budgetEngine.remainingMinutes)
            
            // Run diagnostic after starting monitoring
            familyService.checkDeviceActivityStatus()
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
            message = "✅ Реальное отслеживание активировано. Время считается в фоне."
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
        
        message = "⚠️ Демо-режим: время списывается каждую реальную минуту (только в приложении)"
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
        budgetEngine.consume(mins: 1)
        
        print("⏱️ Spent: \(spentMinutes) min, Remaining: \(budgetEngine.remainingMinutes) min")
        
        if budgetEngine.remainingMinutes <= 0 {
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
}

@main
struct StepsTraderApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Block Screen
struct BlockScreen: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.red.opacity(0.1), .orange.opacity(0.3), .red.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Icon and title
                VStack(spacing: 16) {
                    Text("⏰")
                        .font(.system(size: 80))
                    
                    Text("Время истекло!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("Ваше время для развлечений закончилось")
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                
                // Stats
                VStack(spacing: 12) {
                    HStack {
                        Text("Потрачено времени:")
                        Spacer()
                        Text(formatTime(minutes: model.spentMinutes))
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Потрачено шагов:")
                        Spacer()
                        Text("\(model.spentSteps)")
                            .fontWeight(.semibold)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Шагов сегодня:")
                        Spacer()
                        Text("\(Int(model.stepsToday))")
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                
                // Action buttons
                VStack(spacing: 12) {
                    Text("Чтобы получить больше времени:")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("🚶‍♂️ Сделайте больше шагов")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("\(Int(model.budget.tariff.stepsPerMinute)) шагов = 1 минута развлечений")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Bottom buttons
                VStack(spacing: 12) {
                    Button("🔄 Обновить баланс") {
                        Task {
                            do {
                                try await model.recalc()
                                // Если появились новые минуты, снимаем блокировку
                                if model.budget.remainingMinutes > 0 {
                                    model.isBlocked = false
                                    model.message = "✅ Время восстановлено! Доступно: \(model.budget.remainingMinutes) мин"
                                } else {
                                    model.message = "❌ Недостаточно шагов для разблокировки"
                                }
                            } catch {
                                model.message = "❌ Ошибка обновления: \(error.localizedDescription)"
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("❌ Завершить сессию") {
                        model.stopTracking()
                        model.isBlocked = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.red)
                    
                    Button("🗑️ Сбросить всю статистику") {
                        model.resetStatistics()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.orange)
                }
            }
            .padding()
        }
    }
    
    private func formatTime(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        
        if hours > 0 {
            return "\(hours)ч \(remainingMinutes)мин"
        } else {
            return "\(remainingMinutes)мин"
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var model: AppModel
    
    init() {
        self._model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())
    }

    var body: some View {
        // Show block screen if blocked, otherwise show tab interface
        if model.isBlocked {
            BlockScreen(model: model)
        } else {
            TabView {
                StatusView(model: model)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Статус")
                    }
                
                SettingsView(model: model)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Настройки")
                    }
            }
            .task { await model.bootstrap() }
            .alert("Информация", isPresented: Binding(get: { model.message != nil }, set: { _ in model.message = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.message ?? "") }
        }
    }
}

// MARK: - StatusView
struct StatusView: View {
    @ObservedObject var model: AppModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Мини-статистика сверху
                    miniStatsView
                    
                    // Большое отображение времени в центре
                    bigTimeDisplayView
                    
                    // Прогресс-бар
                    progressBarView
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Mini Stats
    private var miniStatsView: some View {
        HStack(spacing: 16) {
            StatMiniCard(
                icon: "figure.walk",
                title: "Шаги сегодня",
                value: "\(Int(model.stepsToday))",
                color: .blue
            )
            
            StatMiniCard(
                icon: "clock",
                title: "Всего минут",
                value: "\(model.budget.dailyBudgetMinutes)",
                color: .green
            )
            
            StatMiniCard(
                icon: "timer",
                title: "Потрачено",
                value: formatTime(minutes: model.spentMinutes),
                color: .orange
            )
        }
    }
    
    // MARK: - Big Time Display
    private var bigTimeDisplayView: some View {
        VStack(spacing: 12) {
            if model.isBlocked {
                VStack(spacing: 8) {
                    Text("⏰")
                        .font(.system(size: 60))
                    
                    Text("Время прошло!")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Осталось")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("\(model.budget.remainingMinutes)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(timeColor)
                        .contentTransition(.numericText())
                    
                    Text(model.budget.remainingMinutes == 1 ? "минута" : "минут")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(timeBackgroundColor)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    // MARK: - Progress Bar
    private var progressBarView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Использовано времени")
                    .font(.headline)
                Spacer()
                Text("\(progressPercentage)%")
                    .font(.headline)
                    .foregroundColor(timeColor)
            }
            
            ProgressView(value: progressValue, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: timeColor))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
    
    // MARK: - Control Buttons
    private var controlButtonsView: some View {
        VStack(spacing: 12) {
            // Основная кнопка управления
            Button(model.isTrackingTime ? "🔓 Остановить отслеживание" : "🛡️ Начать отслеживание") {
                model.toggleRealBlocking()
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(model.isTrackingTime ? Color.red : Color.blue)
            .foregroundColor(.white)
            .font(.headline)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(!model.familyControlsService.isAuthorized || 
                     (!model.isTrackingTime && model.budget.remainingMinutes <= 0) ||
                     (model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty))
            
            // Предупреждение если нет времени
            if !model.isTrackingTime && model.budget.remainingMinutes <= 0 {
                Text("⚠️ Нет доступного времени! Сделайте больше шагов.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
            
            // Предупреждение если приложение не выбрано
            if model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty {
                Text("⚠️ Выберите приложение в настройках")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }
    
    // MARK: - Computed Properties
    private var timeColor: Color {
        let percentage = progressValue
        if percentage >= 0.9 {
            return .red
        } else if percentage >= 0.7 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var timeBackgroundColor: Color {
        if model.isBlocked {
            return .red.opacity(0.1)
        } else {
            return timeColor.opacity(0.1)
        }
    }
    
    private var progressValue: Double {
        guard model.budget.dailyBudgetMinutes > 0 else { return 0 }
        let used = model.budget.dailyBudgetMinutes - model.budget.remainingMinutes
        return Double(used) / Double(model.budget.dailyBudgetMinutes)
    }
    
    private var progressPercentage: Int {
        Int(progressValue * 100)
    }
    
    private func formatTime(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)м"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)ч \(remainingMinutes)м"
        }
    }
}

// MARK: - StatMiniCard Component
struct StatMiniCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showAppSelector = false
    
    var body: some View {
        NavigationView {
            Form {
                // 1. Секция тарифа (сначала)
                tariffSection
                
                // 2. Секция выбора приложения
                appSelectionSection
                
                // 3. Секция отслеживания (кнопка начать/остановить)
                trackingSection
                
                // 4. Секция управления
                managementSection
                
                // 5. Секция статуса системы
                systemStatusSection
            }
            .familyActivityPicker(isPresented: $showAppSelector, selection: $model.appSelection)
        }
    }
    
    // MARK: - App Selection Section
    private var appSelectionSection: some View {
        Section("Выбор приложения") {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundColor(.blue)
                    .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Приложение для отслеживания")
                            .font(.headline)
                        
                        if model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty {
                            Text("Не выбрано")
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("✅ Выбрано и сохранено")
                                    .font(.body)
                                    .foregroundColor(.green)
                                
                                Text("💾 Будет использоваться автоматически")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                Spacer()
            }
            
                VStack(spacing: 8) {
                    Button(model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty ? "📱 Выбрать приложение" : "🔄 Изменить приложение") {
                        showAppSelector = true
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    
                    // Кнопка очистки выбора (только если что-то выбрано)
                    if !model.appSelection.applicationTokens.isEmpty || !model.appSelection.categoryTokens.isEmpty {
                        Button("🗑️ Очистить выбор") {
                            model.appSelection = FamilyActivitySelection()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Tariff Section
    private var tariffSection: some View {
        Section("Тариф обмена") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Выберите сколько шагов нужно для получения 1 минуты времени:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(Tariff.allCases, id: \.self) { tariff in
                    TariffOptionView(
                        tariff: tariff,
                        isSelected: model.budget.tariff == tariff
                    ) {
                        selectTariff(tariff)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Tracking Section
    private var trackingSection: some View {
        Section("Отслеживание времени") {
            VStack(spacing: 16) {
                // Основная кнопка управления
                Button(model.isTrackingTime ? "🔓 Остановить отслеживание" : "🛡️ Начать отслеживание") {
                    model.toggleRealBlocking()
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(model.isTrackingTime ? Color.red : Color.blue)
                .foregroundColor(.white)
                .font(.headline)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(!model.familyControlsService.isAuthorized || 
                         (!model.isTrackingTime && model.budget.remainingMinutes <= 0) ||
                         (model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty))
                
                // Статус отслеживания
                if model.isTrackingTime {
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Отслеживание активно")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                // Предупреждения
                VStack(spacing: 8) {
                    if !model.isTrackingTime && model.budget.remainingMinutes <= 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Нет доступного времени! Сделайте больше шагов.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Сначала выберите приложение выше")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if !model.familyControlsService.isAuthorized {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Family Controls не авторизован")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Management Section
    private var managementSection: some View {
        Section("Управление") {
            VStack(spacing: 12) {
                Button("🔄 Пересчитать бюджет") {
                    Task {
                        await model.recalcSilently()
                        model.message = "✅ Бюджет пересчитан"
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                
                Button("🗑️ Сбросить статистику") {
                    model.resetStatistics()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
                
                Button("🔍 Диагностика") {
                    model.runDiagnostics()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .foregroundColor(.blue)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - System Status Section
    private var systemStatusSection: some View {
        Section("Статус системы") {
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    icon: "heart.fill",
                    title: "HealthKit",
                    status: .connected,
                    description: "Доступ к данным о шагах"
                )
                
                StatusRow(
                    icon: "shield.fill",
                    title: "Family Controls",
                    status: model.familyControlsService.isAuthorized ? .connected : .disconnected,
                    description: model.familyControlsService.isAuthorized ? "Блокировка приложений активна" : "Требуется авторизация"
                )
                
                StatusRow(
                    icon: "bell.fill",
                    title: "Уведомления",
                    status: .connected,
                    description: "Push-уведомления включены"
                )
                
                if !model.familyControlsService.isAuthorized {
                    Button("🔐 Запросить Family Controls") {
                        Task {
                            do {
                                try await model.familyControlsService.requestAuthorization()
                                model.message = "✅ Family Controls авторизация запрошена"
                            } catch {
                                model.message = "❌ Ошибка авторизации: \(error.localizedDescription)"
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.white)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Actions
    private func selectTariff(_ tariff: Tariff) {
        model.budget.updateTariff(tariff)
        
        // Пересчитываем бюджет с новым тарифом
        Task {
            await model.recalcSilently()
            await MainActor.run {
                model.message = "✅ Тариф изменен на \(tariff.displayName)"
            }
        }
    }
}

// MARK: - TariffOptionView Component
struct TariffOptionView: View {
    let tariff: Tariff
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Иконка тарифа
                Text(tariffIcon)
                    .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                    Text(tariff.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(tariff.description)
                    .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Индикатор выбора
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title2)
        }
        .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var tariffIcon: String {
        switch tariff {
        case .easy: return "💎"
        case .medium: return "🔥"
        case .hard: return "💪"
        }
    }
}

// MARK: - StatusRow Component
struct StatusRow: View {
    let icon: String
    let title: String
    let status: ConnectionStatus
    let description: String
    
    enum ConnectionStatus {
        case connected, disconnected, warning
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .disconnected: return .red
            case .warning: return .orange
            }
        }
        
        var icon: String {
            switch self {
            case .connected: return "checkmark.circle.fill"
            case .disconnected: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(status.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }
}