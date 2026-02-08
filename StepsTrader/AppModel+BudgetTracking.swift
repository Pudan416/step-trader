import Foundation
import Combine
import AudioToolbox

// MARK: - Budget & Time Tracking Management
extension AppModel {
    func updateDayEnd(hour: Int, minute: Int) {
        dayEndHour = max(0, min(23, hour))
        dayEndMinute = max(0, min(59, minute))
        budgetEngine.updateDayEnd(hour: hour, minute: minute)
        checkDayBoundary()
        scheduleDayBoundaryTimer()
    }
    // MARK: - Budget & Time Tracking Keys
    private var minuteTariffBundleKey: String { "minuteTariffBundleId_v1" }
    private var minuteTariffLastTickKey: String { "minuteTariffLastTick_v1" }
    private var minuteTariffRateKey: String { "minuteTariffRate_v1" }
    
    // Minute mode session summary (local notifications)
    private var minuteModeSessionBundleKey: String { "minuteModeSessionBundleId_v1" }
    private var minuteModeSessionStartMinuteCountKey: String { "minuteModeSessionStartMinuteCount_v1" }
    private var minuteModeSessionStartSpentStepsKey: String { "minuteModeSessionStartSpentStepsKey_v1" }
    private var minuteModeSessionStartDayKeyKey: String { "minuteModeSessionStartDayKey_v1" }
    
    // MARK: - Budget & Time Tracking Properties
    // Note: @Published properties (spentSteps, spentMinutes, spentTariff, isTrackingTime, etc.)
    // and stored properties (startTime, timer) remain in AppModel.swift
    // The extension provides methods to work with them
    
    // MARK: - Minute Tariff Functions
    func isMinuteTariffEnabled(for bundleId: String) -> Bool {
        unlockSettings(for: bundleId).minuteTariffEnabled
    }

    func setMinuteTariffEnabled(_ enabled: Bool, for bundleId: String) {
        var settings = unlockSettings(for: bundleId)
        settings.minuteTariffEnabled = enabled
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseTicketUpsert(bundleId: bundleId)
    }

    func minutesAvailable(for bundleId: String) -> Int {
        let costPerMinute = unlockSettings(for: bundleId).entryCostSteps
        guard costPerMinute > 0 else { return Int.max }
        return max(0, totalStepsBalance / costPerMinute)
    }
    
    // MARK: - Minute Charge Logs
    func loadMinuteChargeLogs() {
        Task {
            await userEconomyStore.loadMinuteChargeLogs()
        }
    }
    
    func refreshMinuteChargeLogs() {
        loadMinuteChargeLogs()
    }
    
    func clearMinuteChargeLogs() {
        userEconomyStore.clearMinuteChargeLogs()
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
    
    // MARK: - Daily Tariff Selections
    private func loadDailyTariffSelections() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: "dailyTariffSelectionsAnchor") as? Date ?? .distantPast
        if !isSameCustomDay(anchor, Date()) {
            dailyTariffSelections = [:]
            g.set(currentDayStart(for: Date()), forKey: "dailyTariffSelectionsAnchor")
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
        g.set(currentDayStart(for: Date()), forKey: "dailyTariffSelectionsAnchor")
    }
    
    // MARK: - Tariff Management
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
    
    func persistEntryCost(tariff: Tariff) {
        let g = UserDefaults.stepsTrader()
        g.set(tariff.rawValue, forKey: "entryCostTariff")
        entryCostSteps = tariff.entryCostSteps
    }
    
    func dayPassCost(for tariff: Tariff) -> Int {
        switch tariff {
        case .free: return 0
        case .easy: return 1000
        case .medium: return 5000
        case .hard: return 10000
        }
    }
    
    // MARK: - Budget & Spent Time Management
    private func syncEntryCostWithTariff() {
        if entryCostSteps <= 0 {
            entryCostSteps = 5
        }
    }

    func syncBudgetProperties() {
        // Sync budget properties from BudgetEngine to published properties for UI updates
        dailyBudgetMinutes = budgetEngine.dailyBudgetMinutes
        remainingMinutes = budgetEngine.remainingMinutes
    }
    
    func reloadBudgetFromStorage() {
        budgetEngine.reloadFromStorage()
        syncBudgetProperties()
    }
    
    func saveSpentTime() {
        let g = UserDefaults.stepsTrader()
        g.set(spentMinutes, forKey: "spentMinutes_v1")
        g.set(spentSteps, forKey: "spentSteps_v1")
        if let tariffData = try? JSONEncoder().encode(spentTariff.rawValue) {
            g.set(tariffData, forKey: "spentTariff_v1")
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
    
    // MARK: - Time Tracking
    func startTracking() {
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

    func continueStartTracking() {
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
    
    // MARK: - Minute Tariff Session Management
    private func startMinuteTariffSession(for bundleId: String, rate: Int) {
        let g = UserDefaults.stepsTrader()
        g.set(bundleId, forKey: minuteTariffBundleKey)
        g.set(rate, forKey: minuteTariffRateKey)
        g.set(Date(), forKey: minuteTariffLastTickKey)
        g.removeObject(forKey: accessBlockKey(for: bundleId))
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
    
    // MARK: - Timer-based tracking (fallback without DeviceActivity entitlement)
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

            notificationService.sendTimeExpiredNotification()
            sendReturnToAppNotification()
            AudioServicesPlaySystemSound(1005)
        }
    }
}
