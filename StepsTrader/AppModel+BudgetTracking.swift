import Foundation
import AudioToolbox

// MARK: - Budget & Time Tracking Management
extension AppModel {
    /// v1 strategy: minute mode disabled in UI. Set to true to re-enable.
    static let minuteModeEnabled = false

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
        guard Self.minuteModeEnabled else { return false }
        return unlockSettings(for: bundleId).minuteTariffEnabled
    }

    func setMinuteTariffEnabled(_ enabled: Bool, for bundleId: String) {
        guard Self.minuteModeEnabled else { return }
        var settings = unlockSettings(for: bundleId)
        settings.minuteTariffEnabled = enabled
        appUnlockSettings[bundleId] = settings
        persistAppUnlockSettings()
        scheduleSupabaseTicketUpsert(bundleId: bundleId)
    }

    func minutesAvailable(for bundleId: String) -> Int {
        guard Self.minuteModeEnabled else { return 0 }
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
        // Clamp spent time to maximum available budget
        let maxSpentMinutes = budgetEngine.dailyBudgetMinutes
        spentMinutes = min(minutes, maxSpentMinutes)
        spentSteps = spentMinutes * Int(spentTariff.stepsPerMinute)
        saveSpentTime()
        syncBudgetProperties()  // Sync budget properties for UI updates
        AppLogger.energy.debug(
            "🕐 Updated spent time: \(self.spentMinutes) minutes (\(self.spentSteps) steps) (max: \(maxSpentMinutes))"
        )
    }

    func consumeMinutes(_ minutes: Int) {
        budgetEngine.consume(mins: minutes)

        // Set the tariff rate for minute spending
        spentTariff = budgetEngine.tariff

        // Update spent time with constraints
        updateSpentTime(minutes: spentMinutes + minutes)

        syncBudgetProperties()  // Sync budget properties for UI updates
        AppLogger.energy.debug("⏱️ Consumed \(minutes) minutes, remaining: \(self.remainingMinutes)")
    }
    
    // MARK: - Time Tracking
    func startTracking() {
        AppLogger.energy.debug("🎯 === START TRACKING BEGIN ===")

        // Recalculate budget with current tariff before starting tracking
        Task {
            await recalcSilently()
            await MainActor.run {
                AppLogger.energy.debug("💰 Budget recalculated: \(self.budgetEngine.remainingMinutes) minutes")

                guard self.budgetEngine.remainingMinutes > 0 else {
                    AppLogger.energy.debug("❌ No remaining time - aborting")
                    message = "No time left. Open Proof to earn exp."
                    return
                }

                continueStartTracking()
            }
        }
    }

    func continueStartTracking() {
        AppLogger.energy.debug("🎯 === START TRACKING CONTINUE ===")
        AppLogger.energy.debug("💰 Checking budget: \(self.budgetEngine.remainingMinutes) minutes")

        AppLogger.energy.debug(
            "📱 Checking selection: \(self.appSelection.applicationTokens.count) apps, \(self.appSelection.categoryTokens.count) categories"
        )
        guard !self.appSelection.applicationTokens.isEmpty || !self.appSelection.categoryTokens.isEmpty else {
            AppLogger.energy.debug("❌ No applications selected - aborting")
            message = "❌ Choose an app to track"
            return
        }

        AppLogger.energy.debug("✅ Checks passed, starting tracking")
        isTrackingTime = true
        startTime = Date()
        currentSessionElapsed = 0
        AppLogger.energy.debug("⏱️ Tracking flags set: isTrackingTime=true, startTime=\(Date())")

        let appCount = self.appSelection.applicationTokens.count
        AppLogger.energy.debug("🚀 Started tracking for \(appCount) selected applications")
        AppLogger.energy.debug("⏱️ Available time: \(self.budgetEngine.remainingMinutes) minutes")
        AppLogger.energy.debug("🎯 Using DeviceActivity for real-time usage monitoring")

        // Start DeviceActivity monitoring for real-time tracking
        if let familyService = familyControlsService as? FamilyControlsService {
            AppLogger.energy.debug("🔧 DEBUG: Starting monitoring with:")
            AppLogger.energy.debug("   - Selected apps: \(self.appSelection.applicationTokens.count)")
            AppLogger.energy.debug("   - Selected categories: \(self.appSelection.categoryTokens.count)")
            AppLogger.energy.debug("   - Budget minutes: \(self.budgetEngine.remainingMinutes)")

            // Start monitoring with timeout
            Task { [weak self] in
                AppLogger.energy.debug("🔄 Created task to start monitoring with a 10s timeout")
                await self?.withTimeout(seconds: 10) {
                    AppLogger.energy.debug("⏰ Calling startMonitoring in FamilyControlsService")
                    familyService.startMonitoring(
                        budgetMinutes: self?.budgetEngine.remainingMinutes ?? 0
                    )
                    AppLogger.energy.debug("✅ startMonitoring finished")
                }

                AppLogger.energy.debug("🔍 Running DeviceActivity diagnostics")
                // Run diagnostic after starting monitoring
                familyService.checkDeviceActivityStatus()
                AppLogger.energy.debug("✅ Diagnostics finished")
            }
        } else {
            AppLogger.energy.debug("❌ Failed to cast familyControlsService to FamilyControlsService")
        }

        // Check if DeviceActivity is running
        #if targetEnvironment(simulator)
            // Use timer as fallback in simulator
            AppLogger.energy.debug("⚠️ Using timer-based tracking (Simulator - DeviceActivity not available)")
            startTimerFallback()
        #else
            // On real device check for DeviceActivity
            if familyControlsService.isAuthorized {
                AppLogger.energy.debug("✅ Using DeviceActivity for real background tracking")
                AppLogger.energy.debug("✅ Real tracking enabled. Time counts in the background.")
            } else {
                AppLogger.energy.debug("⚠️ Using timer-based tracking (Family Controls not authorized)")
                startTimerFallback()
            }
        #endif
    }

    private func startTimerFallback() {
        // Timer fires every 60 seconds simulating 1 minute of usage (1:1 ratio)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulateAppUsage()
            }
        }

        AppLogger.energy.debug("⚠️ Demo mode: time decreases every real minute (in-app only)")
    }

    func stopTracking() {
        isTrackingTime = false
        isBlocked = false  // Remove block
        timer?.invalidate()
        timer = nil
        startTime = nil
        currentSessionElapsed = nil

        // Stop DeviceActivity monitoring
        if let familyService = familyControlsService as? FamilyControlsService {
            familyService.stopMonitoring()
        }

        AppLogger.energy.debug("🛑 Tracking stopped - DeviceActivity monitoring disabled")
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
        AppLogger.energy.debug("⏱️ DEMO: Simulating 1 minute of app usage")

        // Increment app usage time by 1 minute
        updateSpentTime(minutes: spentMinutes + 1)

        // Deduct from budget
        consumeMinutes(1)

        AppLogger.energy.debug("⏱️ Spent: \(self.spentMinutes) min, Remaining: \(self.remainingMinutes) min")

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
