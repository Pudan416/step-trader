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
            self.appSelection = self.familyControlsService.selection
            
            // Восстанавливаем сохраненное время использования
            self.loadSpentTime()
            print("🔄 Initial sync: \(self.appSelection.applicationTokens.count) apps")
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
            stepsToday = try await healthKitService.fetchTodaySteps()
            print("✅ Today's steps: \(Int(stepsToday))")
            
            print("💰 Calculating budget...")
            budgetEngine.resetIfNeeded()
            let budgetMinutes = budgetEngine.minutes(from: stepsToday)
            budgetEngine.setBudget(minutes: budgetMinutes)
            print("✅ Budget calculated: \(budgetMinutes) minutes")
            
            print("🎉 Bootstrap completed successfully!")
            
        } catch {
            print("❌ Bootstrap failed: \(error)")
            message = "Ошибка инициализации: \(error.localizedDescription)"
        }
    }
    
    func recalc() async throws {
        budgetEngine.resetIfNeeded()
        stepsToday = try await healthKitService.fetchTodaySteps()
        let mins = budgetEngine.minutes(from: stepsToday)
        budgetEngine.setBudget(minutes: mins)
        message = "✅ Бюджет пересчитан: \(mins) минут"
    }
    
    func recalcSilently() async {
        do {
            budgetEngine.resetIfNeeded()
            stepsToday = try await healthKitService.fetchTodaySteps()
            let mins = budgetEngine.minutes(from: stepsToday)
            budgetEngine.setBudget(minutes: mins)
            print("🔄 Silent budget recalculation: \(mins) minutes")
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
        
        // Запускаем таймер для отслеживания времени (fallback без DeviceActivity)
        print("⚠️ Using timer-based tracking (DeviceActivity entitlement not available)")
        
        // Таймер каждые 30 секунд симулирует 1 минуту использования
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulateAppUsage()
            }
        }
        
        message = "⚠️ Демо-режим: время списывается автоматически каждые 30 сек"
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
            notificationService.sendTimeExpiredNotification()
            sendReturnToAppNotification()
            AudioServicesPlaySystemSound(1005)
        }
    }
    
    private func enableAppBlocking() {
        guard familyControlsService.isAuthorized else {
            print("❌ Cannot enable blocking: Family Controls not authorized")
            return
        }
        
        // Используем ApplicationToken для блокировки конкретных приложений
        guard !appSelection.applicationTokens.isEmpty || !appSelection.categoryTokens.isEmpty else {
            print("❌ No applications selected for blocking")
            return
        }
        
        // Включаем блокировку через ManagedSettings
        if let familyService = familyControlsService as? FamilyControlsService {
            let store = familyService.store
            store.shield.applications = appSelection.applicationTokens
        }
        
        let appCount = appSelection.applicationTokens.count
        print("🛡️ Enabled blocking for \(appCount) selected applications")
        
        // Отправляем уведомление
        notificationService.sendTimeExpiredNotification()
        AudioServicesPlaySystemSound(1005) // Звук уведомления
    }
}

@main
struct StepsTraderApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - StatCard
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    init(title: String, value: String, icon: String, color: Color) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }
    
    init(title: String, value: Int, icon: String, color: Color) {
        self.init(title: title, value: "\(value)", icon: icon, color: color)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(icon)
                    .font(.title2)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
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
                    
                    Text("500 шагов = 1 минута развлечений")
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
    @State private var showAppSelector = false
    
    init() {
        self._model = StateObject(wrappedValue: DIContainer.shared.makeAppModel())
    }

    // MARK: - Header
    private var headerView: some View {
                    HStack(spacing: 8) {
                        Text("👟")
                            .font(.title)
                            .scaleEffect(1.2)
                            .rotationEffect(.degrees(model.isTrackingTime ? 15 : 0))
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: model.isTrackingTime)
                        
                        Text("Step Trader")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("⚡")
                            .font(.title)
                            .scaleEffect(1.2)
                            .opacity(model.isTrackingTime ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: model.isTrackingTime)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 15)
                    .padding(.bottom, 5)
    }
                    
    // MARK: - Stats Grid
    private var statsGridView: some View {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 15) {
                        StatCard(
                            title: "Шаги сегодня",
                            value: Int(model.stepsToday).formatted(),
                            icon: "👟",
                            color: .green
                        )
                        
                        StatCard(
                            title: "Потрачено времени",
                            value: formatTime(minutes: model.spentMinutes),
                            icon: "📱",
                            color: .orange
                        )
                        
                        StatCard(
                            title: "Бюджет минут",
                            value: model.budget.dailyBudgetMinutes.formatted(),
                            icon: "⏰",
                            color: .blue
                        )
                        
                        StatCard(
                title: "Остаток",
                value: formatTime(minutes: model.budget.remainingMinutes),
                            icon: "⏳",
                            color: model.budget.remainingMinutes > 0 ? .green : .red
                        )
                    }
                    .padding(.horizontal)
    }
                    
    // MARK: - Progress Bar
    private var progressBarView: some View {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Использование времени")
                                .font(.headline)
                            Spacer()
                Text("\(Int((Double(model.budget.dailyBudgetMinutes - model.budget.remainingMinutes) / Double(max(1, model.budget.dailyBudgetMinutes))) * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
            ProgressView(value: Double(max(0, model.budget.dailyBudgetMinutes - model.budget.remainingMinutes)), total: Double(max(1, model.budget.dailyBudgetMinutes)))
                .progressViewStyle(LinearProgressViewStyle(tint: model.budget.remainingMinutes > 0 ? .blue : .red))
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.red.opacity(0.3), lineWidth: 1)
                )
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .padding(.horizontal)
    }
                    
                    
    // MARK: - App Controls
    private var appControlsView: some View {
                    VStack(spacing: 12) {
            // Выбор приложения для блокировки
            VStack(spacing: 8) {
                Text("Приложение для блокировки:")
                                .font(.headline)
                
                if model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty {
                    Text("Приложение не выбрано")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("✅ Приложение выбрано")
                        .font(.body)
                        .foregroundStyle(.green)
                }
                
                Button("📱 Выбрать приложение") {
                                showAppSelector = true
                            }
                            .buttonStyle(.bordered)
                .controlSize(.regular)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .padding(.horizontal)
                    
            // Блокировка выбранного приложения
            Button(model.isTrackingTime ? "🔓 Снять блокировку" : "🛡️ Включить блокировку") {
                model.toggleRealBlocking()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.isTrackingTime ? .red : .blue)
            .disabled(!model.familyControlsService.isAuthorized || 
                     (model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty) || 
                     (!model.isTrackingTime && model.budget.remainingMinutes <= 0))
            
            // Предупреждение о недостатке минут
            if !model.isTrackingTime && model.budget.remainingMinutes <= 0 {
                Text("⚠️ Нет доступного времени! Сделайте больше шагов.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Tracking Status
    private var trackingStatusView: some View {
        Group {
                    if model.isTrackingTime {
                        VStack(spacing: 8) {
                            HStack {
                                Text("🔴")
                                Text("Отслеживание активно")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            
                            HStack {
                        if model.appSelection.applicationTokens.isEmpty && model.appSelection.categoryTokens.isEmpty {
                            Text("Приложение: не выбрано")
                        } else {
                            Text("Приложение: выбрано")
                                }
                                Spacer()
                                if let elapsed = model.currentSessionElapsed {
                                    Text("Сессия: \(elapsed) мин")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(.red.opacity(0.1)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.red.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    }
        }
    }
    
    // MARK: - Authorization Status
    private var authorizationStatusView: some View {
        Group {
            if !model.familyControlsService.isAuthorized {
                VStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text("⚠️ Family Controls не авторизован")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        
                        Text("⚠️ ДЕМО-РЕЖИМ: DeviceActivity недоступен")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("Время списывается автоматически каждые 30 сек")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        
                        #if targetEnvironment(simulator)
                        Text("📱 Family Controls НЕ работает в симуляторе!")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text("Запустите на реальном устройстве")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        #endif
                        
                        Button("🔔 Тест уведомления") {
                            NotificationManager.shared.sendTimeExpiredNotification()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("🔍 Диагностика DeviceActivity") {
                            if let familyService = model.familyControlsService as? FamilyControlsService {
                                familyService.checkDeviceActivityStatus()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("🔐 Запросить Family Controls") {
                            Task {
                                do {
                                    try await model.family.requestAuthorization()
                                    model.message = "✅ Family Controls авторизация запрошена"
                                } catch {
                                    model.message = "❌ Ошибка авторизации: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
            }
        }
    }
    
    
    // MARK: - Helper Functions
    private func formatTime(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }

    var body: some View {
        NavigationStack {
            // Show block screen if blocked, otherwise show main interface
            if model.isBlocked {
                BlockScreen(model: model)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        headerView
                    
                    statsGridView
                    
                    progressBarView
                    
                    trackingStatusView
                    
                    appControlsView
                    
                    authorizationStatusView
                    
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.bootstrap() }
            .alert("Информация", isPresented: Binding(get: { model.message != nil }, set: { _ in model.message = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.message ?? "") }
                .familyActivityPicker(isPresented: $showAppSelector, selection: $model.appSelection)
            }
        }
    }


}