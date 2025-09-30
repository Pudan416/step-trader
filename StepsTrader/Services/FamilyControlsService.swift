import FamilyControls
import Combine
import ManagedSettings
import DeviceActivity
import Foundation

@MainActor
final class FamilyControlsService: ObservableObject, FamilyControlsServiceProtocol {
    @Published var selection = FamilyActivitySelection()
    @Published var isAuthorized = false
    
    let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()
    
    init() {
        checkAuthorizationStatus()
        restorePersistentSelection()
        
        // Если статус не определен, автоматически запрашиваем авторизацию
        if AuthorizationCenter.shared.authorizationStatus == .notDetermined {
            Task {
                do {
                    try await requestAuthorization()
                    print("✅ Auto-authorization request completed")
                } catch {
                    print("⚠️ Auto-authorization failed: \(error)")
                }
            }
        }
    }
    
    func requestAuthorization() async throws {
        print("🔐 Steps Trader: Requesting Family Controls authorization...")
        print("📱 Current authorization status: \(AuthorizationCenter.shared.authorizationStatus)")
        
        #if targetEnvironment(simulator)
        print("❌ СИМУЛЯТОР ОБНАРУЖЕН! Family Controls НЕ РАБОТАЕТ в симуляторе!")
        print("📱 Запустите приложение на РЕАЛЬНОМ УСТРОЙСТВЕ для тестирования Family Controls")
        throw FamilyControlsError.simulatorNotSupported
        #endif
        
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined:
            print("🔐 Requesting authorization for first time...")
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            print("✅ Authorization request completed")
        case .denied:
            print("❌ Authorization was denied by user")
            throw FamilyControlsError.notAuthorized
        case .approved:
            print("✅ Already authorized")
            break
        @unknown default:
            print("⚠️ Unknown authorization status")
            break
        }
        
        await MainActor.run {
            checkAuthorizationStatus()
        }
    }
    
    func checkAuthorizationStatus() {
        let status = AuthorizationCenter.shared.authorizationStatus
        isAuthorized = status == .approved
        
        print("🔐 Steps Trader: Detailed Family Controls status:")
        print("   Raw status: \(status)")
        switch status {
        case .notDetermined:
            print("   ❓ Not determined - authorization not requested yet")
        case .denied:
            print("   ❌ Denied - user declined or restrictions in place")
        case .approved:
            print("   ✅ Approved - fully authorized")
        @unknown default:
            print("   ⚠️ Unknown status: \(status)")
        }
        print("   isAuthorized: \(isAuthorized)")
        
        #if targetEnvironment(simulator)
        print("   📱 RUNNING IN SIMULATOR - Family Controls will NOT work!")
        #else
        print("   📱 Running on real device - Family Controls should work")
        #endif
    }
    
    func startMonitoring(budgetMinutes: Int) {
        print("🔧 === НАЧАЛО START MONITORING ===")
        print("🔐 Авторизован: \(isAuthorized)")
        print("💰 Бюджет минут: \(budgetMinutes)")
        print("📱 Выбрано приложений: \(selection.applicationTokens.count)")
        print("📂 Выбрано категорий: \(selection.categoryTokens.count)")
        
        guard isAuthorized else {
            print("❌ Cannot start monitoring: not authorized")
            return
        }
        
        print("🚀 Starting Device Activity monitoring for \(budgetMinutes) minutes")
        print("📱 Selected applications: \(selection.applicationTokens.count)")
        print("📂 Selected categories: \(selection.categoryTokens.count)")
        
        // Проверяем что есть что мониторить
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            print("❌ Cannot start monitoring: no applications or categories selected")
            return
        }
        
        print("✅ Все проверки пройдены, запускаем асинхронный мониторинг")
        // Запускаем мониторинг в фоновом потоке чтобы не блокировать UI
        Task {
            print("🔄 Создана асинхронная задача для мониторинга")
            await startMonitoringAsync(budgetMinutes: budgetMinutes)
            print("✅ Асинхронный мониторинг завершен")
        }
        print("🔧 === ЗАВЕРШЕНИЕ START MONITORING ===")
    }
    
    private func startMonitoringAsync(budgetMinutes: Int) async {
        print("🔧 === НАЧАЛО START MONITORING ASYNC ===")
        
        // Сохраняем метаданные для диагностики
        let userDefaults = UserDefaults.stepsTrader()
        print("💾 Сохраняем метаданные в UserDefaults")
        userDefaults.set(selection.applicationTokens.count, forKey: "selectedAppsCount")
        userDefaults.set(selection.categoryTokens.count, forKey: "selectedCategoriesCount")
        userDefaults.set(budgetMinutes, forKey: "budgetMinutes")
        userDefaults.set(Date(), forKey: "monitoringStartTime")
        print("✅ Метаданные сохранены: \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, \(budgetMinutes) min")
        
        // Сохраняем ApplicationTokens для DeviceActivityMonitor
        if !selection.applicationTokens.isEmpty {
            do {
                let tokensData = try NSKeyedArchiver.archivedData(withRootObject: selection.applicationTokens, requiringSecureCoding: true)
                userDefaults.set(tokensData, forKey: "selectedApplicationTokens")
                print("💾 Saved ApplicationTokens for DeviceActivityMonitor")
            } catch {
                print("❌ Failed to save ApplicationTokens: \(error)")
            }
        }
        
        print("📝 Saved monitoring metadata: \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, budget: \(budgetMinutes) min, start time: \(Date())")
        
        // Токены передаются через DeviceActivityEvent
        print("💡 Tokens will be passed through DeviceActivityEvent")
        
        // Создаем расписание на оставшуюся часть дня (с текущего времени до конца дня)
        let now = Date()
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: now)
        let endComponents = DateComponents(hour: 23, minute: 59)
        
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        
        print("📅 Schedule: \(startComponents.hour ?? 0):\(startComponents.minute ?? 0) to 23:59")
        
        // Создаем событие с лимитом времени
        var event: DeviceActivityEvent
        
        if !selection.applicationTokens.isEmpty {
            // Мониторим конкретные приложения
            event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                threshold: DateComponents(minute: budgetMinutes)
            )
            print("📱 Monitoring specific applications: \(selection.applicationTokens.count)")
        } else if !selection.categoryTokens.isEmpty {
            // Мониторим категории приложений
            event = DeviceActivityEvent(
                categories: selection.categoryTokens,
                threshold: DateComponents(minute: budgetMinutes)
            )
            print("📂 Monitoring categories: \(selection.categoryTokens.count)")
        } else {
            print("❌ No applications or categories to monitor")
            return
        }
        
        print("⏱️ Event threshold: \(budgetMinutes) minutes")
        
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            DeviceActivityEvent.Name("dailyLimit"): event
        ]
        
        do {
            try center.startMonitoring(DeviceActivityName("daily"), during: schedule, events: events)
            print("✅ Device Activity monitoring started successfully")
            print("🔍 Monitor name: 'daily', Event name: 'dailyLimit'")
            
            // Дополнительная диагностическая информация
            print("🔍 DIAGNOSTIC INFO:")
            print("   - Budget minutes: \(budgetMinutes)")
            print("   - Applications count: \(selection.applicationTokens.count)")
            print("   - Categories count: \(selection.categoryTokens.count)")
            print("   - Schedule: \(startComponents.hour ?? 0):\(startComponents.minute ?? 0) - 23:59")
            print("   - Current time: \(Date())")
            
            #if targetEnvironment(simulator)
            print("⚠️ WARNING: Running in SIMULATOR - DeviceActivity will NOT work!")
            print("📱 Please test on a REAL DEVICE for DeviceActivity to function")
            #else
            print("📱 Running on real device - DeviceActivity should work")
            #endif
            
        } catch {
            print("❌ Failed to start monitoring: \(error)")
            print("   Error details: \(error.localizedDescription)")
            print("   Error type: \(type(of: error))")
        }
    }
    
    
    func stopMonitoring() {
        print("🛑 Stopping Device Activity monitoring")
        center.stopMonitoring([DeviceActivityName("daily")])
        
        // Снимаем все ограничения
        store.clearAllSettings()
    }
    
    func enableShield() {
        guard isAuthorized else { return }
        
        print("🛡️ Enabling shield for selected applications")
        store.shield.applications = selection.applicationTokens
    }
    
    func disableShield() {
        print("🔓 Disabling shield")
        store.clearAllSettings()
    }

    // Разрешить один сеанс для конкретного приложения (снять щит)
    func allowOneSession() {
        guard isAuthorized else { return }
        var apps = store.shield.applications ?? []
        for token in selection.applicationTokens { apps.remove(token) }
        store.shield.applications = apps
        print("🔓 Allow one session for current selection: \(selection.applicationTokens.count) apps")
    }
    
    // Повторно включить щит для приложения
    func reenableShield() {
        guard isAuthorized else { return }
        var apps = store.shield.applications ?? []
        for token in selection.applicationTokens { if !apps.contains(token) { apps.insert(token) } }
        store.shield.applications = apps
        print("🛡️ Re-enabled shield for current selection: \(selection.applicationTokens.count) apps")
    }
    
    func updateSelection(_ newSelection: FamilyActivitySelection) {
        // Этот метод теперь используется только для внешних вызовов
        // Основная логика перенесена в AppModel для избежания циклов
        DispatchQueue.main.async { [weak self] in
            self?.selection = newSelection
            self?.savePersistentSelection()
            print("📱 Service selection updated: \(newSelection.applicationTokens.count) apps, \(newSelection.categoryTokens.count) categories")
        }
    }
    
    func checkDeviceActivityStatus() {
        print("🔍 DEVICE ACTIVITY DIAGNOSTIC:")
        print("   - Family Controls authorized: \(isAuthorized)")
        print("   - Application tokens: \(selection.applicationTokens.count)")
        print("   - Category tokens: \(selection.categoryTokens.count)")
        
        #if targetEnvironment(simulator)
        print("   - ⚠️ RUNNING IN SIMULATOR - DeviceActivity WILL NOT WORK!")
        print("   - 📱 MUST TEST ON REAL DEVICE for DeviceActivity to function")
        #else
        print("   - ✅ Running on real device - DeviceActivity should work")
        #endif
        
        let userDefaults = UserDefaults.stepsTrader()
        let budgetMinutes = userDefaults.object(forKey: "budgetMinutes") as? Int ?? 0
        let startTime = userDefaults.object(forKey: "monitoringStartTime") as? Date
        
        print("   - Saved budget minutes: \(budgetMinutes)")
        print("   - Monitoring start time: \(startTime?.description ?? "none")")
        
        if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
            print("   - ✅ Has valid selection for monitoring")
        } else {
            print("   - ❌ NO SELECTION - Cannot monitor without apps or categories")
        }
    }

    // MARK: - Persistence
    private func restorePersistentSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        var newSelection = FamilyActivitySelection()
        var restored = false
        
        if let appsData = userDefaults.data(forKey: "persistentApplicationTokens"),
           let obj = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSSet.self, from: appsData),
           let apps = obj as? Set<ApplicationToken> {
            newSelection.applicationTokens = apps
            restored = true
        }
        if let catsData = userDefaults.data(forKey: "persistentCategoryTokens"),
           let obj = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSSet.self, from: catsData),
           let cats = obj as? Set<ActivityCategoryToken> {
            newSelection.categoryTokens = cats
            restored = true
        }
        if restored {
            self.selection = newSelection
            print("📱 Restored FamilyControlsService.selection: \(newSelection.applicationTokens.count) apps, \(newSelection.categoryTokens.count) categories")
        } else {
            print("ℹ️ No persisted selection to restore in FamilyControlsService")
        }
    }

    private func savePersistentSelection() {
        let userDefaults = UserDefaults.stepsTrader()
        if !selection.applicationTokens.isEmpty {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: selection.applicationTokens, requiringSecureCoding: true) {
                userDefaults.set(data, forKey: "persistentApplicationTokens")
            }
        }
        if !selection.categoryTokens.isEmpty {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: selection.categoryTokens, requiringSecureCoding: true) {
                userDefaults.set(data, forKey: "persistentCategoryTokens")
            }
        }
        userDefaults.set(Date(), forKey: "appSelectionSavedDate")
    }
}

enum FamilyControlsError: Error, LocalizedError {
    case notAuthorized
    case simulatorNotSupported
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Family Controls не авторизован. Разрешите доступ в настройках."
        case .simulatorNotSupported:
            return "Family Controls не работает в симуляторе. Запустите на реальном устройстве."
        }
    }
}
