import Foundation

// MARK: - Payment & Entry Management
extension AppModel {
    // MARK: - Payment Checks
    func canPayForEntry(for bundleId: String? = nil, costOverride: Int? = nil) -> Bool {
        if hasDayPass(for: bundleId) { return true }
        let cost = costOverride ?? unlockSettings(for: bundleId).entryCostSteps
        return self.totalStepsBalance >= cost
    }

    func canPayForDayPass(for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        if hasDayPass(for: bundleId) { return true }
        let cost = unlockSettings(for: bundleId).dayPassCostSteps
        return self.totalStepsBalance >= cost
    }

    // MARK: - Payment Execution
    @MainActor
    @discardableResult
    func payForEntry(for bundleId: String? = nil, costOverride: Int? = nil) -> Bool {
        AppLogger.payment.debug("payForEntry called for bundleId: \(bundleId ?? "nil")")
        
        if hasDayPass(for: bundleId) {
            AppLogger.payment.debug("Day pass active, skipping payment")
            return true
        }
        
        let cost = costOverride ?? unlockSettings(for: bundleId).entryCostSteps
        #if DEBUG
        AppLogger.payment.debug("Entry cost: \(cost), current balance: \(self.totalStepsBalance)")
        #endif
        let success = pay(cost: cost)
        
        if success {
            if let bundleId {
                addSpentSteps(cost, for: bundleId)
            }
            #if DEBUG
            AppLogger.payment.debug("payForEntry successful, new balance: \(self.totalStepsBalance)")
            #else
            AppLogger.payment.info("payForEntry successful")
            #endif
        } else {
            AppLogger.payment.debug("payForEntry failed - not enough balance")
        }
        
        return success
    }
    
    @MainActor
    @discardableResult
    func payForDayPass(for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        if hasDayPass(for: bundleId) { return true }
        let cost = unlockSettings(for: bundleId).dayPassCostSteps
        
        #if DEBUG
        AppLogger.payment.debug("payForDayPass for \(bundleId), cost: \(cost)")
        #endif
        guard pay(cost: cost) else {
            AppLogger.payment.debug("payForDayPass failed - not enough balance")
            return false
        }
        
        addSpentSteps(cost, for: bundleId)
        dayPassGrants[bundleId] = Date()
        persistDayPassGrants()
        
        #if DEBUG
        AppLogger.payment.debug("payForDayPass successful, new balance: \(self.totalStepsBalance)")
        #else
        AppLogger.payment.info("payForDayPass successful")
        #endif
        
        return true
    }
    
    @MainActor
    func pay(cost: Int) -> Bool {
        #if DEBUG
        AppLogger.payment.debug("pay(\(cost)) called on main thread: \(Thread.isMainThread)")
        AppLogger.payment.debug("Before: totalBalance=\(self.totalStepsBalance), stepsBalance=\(self.stepsBalance), bonusSteps=\(self.bonusSteps), baseEnergyToday=\(self.baseEnergyToday), spentStepsToday=\(self.spentStepsToday)")
        #endif
        guard self.totalStepsBalance >= cost else {
            AppLogger.payment.debug("FAILED: Not enough balance")
            return false
        }
        
        // Deduct from base energy first, then from bonus
        let todaysBaseEnergy = self.baseEnergyToday
        let baseAvailable = self.stepsBalance
        let consumeFromBase = min(baseAvailable, cost)
        let newSpent = min(self.spentStepsToday + consumeFromBase, max(0, todaysBaseEnergy))
        self.spentStepsToday = newSpent
        self.stepsBalance = max(0, todaysBaseEnergy - self.spentStepsToday)

        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            consumeBonusSteps(remainingCost)
        }

        let g = UserDefaults.stepsTrader()
        g.set(self.stepsBalance, forKey: "stepsBalance")
        g.set(currentDayStart(for: Date()), forKey: "stepsBalanceAnchor")
        
        // Explicitly update totalStepsBalance
        updateTotalStepsBalance()
        
        // CRITICAL: Force sync bonus steps to UserDefaults to ensure persistence
        syncAndPersistBonusBreakdown()
        
        #if DEBUG
        AppLogger.payment.debug("After: totalBalance=\(self.totalStepsBalance), stepsBalance=\(self.stepsBalance), bonusSteps=\(self.bonusSteps), spentStepsToday=\(self.spentStepsToday)")
        AppLogger.payment.debug("Balance persisted to UserDefaults")
        #endif
        return true
    }

    // MARK: - Steps Balance Management
    func loadSpentStepsBalance() {
        let g = UserDefaults.stepsTrader()
        #if DEBUG
        AppLogger.payment.debug("Loading spent steps balance")
        #endif
        let anchor = g.object(forKey: "stepsBalanceAnchor") as? Date ?? .distantPast
        let isSameDay = isSameCustomDay(anchor, Date())
        
        if !isSameDay {
            #if DEBUG
            AppLogger.payment.debug("New day detected, resetting spentStepsToday to 0")
            #endif
            self.spentStepsToday = 0
            self.stepsBalance = 0
            g.set(0, forKey: "stepsBalance")
            g.set(currentDayStart(for: Date()), forKey: "stepsBalanceAnchor")
        } else {
            self.spentStepsToday = g.integer(forKey: SharedKeys.spentStepsToday)
        }
        
        let todaysBaseEnergy = self.baseEnergyToday
        if todaysBaseEnergy > 0, self.spentStepsToday > todaysBaseEnergy {
            self.spentStepsToday = todaysBaseEnergy
        }
        
        self.stepsBalance = g.integer(forKey: "stepsBalance")
        
        if self.stepsBalance == 0, todaysBaseEnergy > 0 {
            self.stepsBalance = max(0, todaysBaseEnergy - self.spentStepsToday)
        }
        
        self.serverGrantedSteps = g.integer(forKey: "serverGrantedSteps_v1")
        
        syncAndPersistBonusBreakdown()
        updateTotalStepsBalance()
    }

    @MainActor
    func syncAndPersistBonusBreakdown() {
        let cappedBonus = min(self.serverGrantedSteps, EnergyDefaults.maxBonusEnergy)
        let maxTotalEnergy = EnergyDefaults.maxBaseEnergy
        let availableForBonus = max(0, maxTotalEnergy - self.baseEnergyToday)
        self.bonusSteps = min(cappedBonus, availableForBonus)
        
        let g = UserDefaults.stepsTrader()
        g.set(self.bonusSteps, forKey: "debugStepsBonus_v1")
        g.removeObject(forKey: "debugStepsBonus_outerworld_v1")
        g.removeObject(forKey: "debugStepsBonus_debug_v1")
        
        updateTotalStepsBalance()
    }

    // MARK: - Entry Cost Management
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

    // MARK: - Spent Steps Tracking
    func addSpentSteps(_ cost: Int, for bundleId: String) {
        appStepsSpentToday[bundleId, default: 0] += cost
        appStepsSpentLifetime[bundleId, default: 0] += cost
        let key = Self.dayKey(for: Date())
        var perDay = appStepsSpentByDay[key] ?? [:]
        perDay[bundleId, default: 0] += cost
        appStepsSpentByDay[key] = perDay
        persistAppStepsSpentToday()
        persistAppStepsSpentByDay()
        persistAppStepsSpentLifetime()
        
        // Sync daily spent to Supabase
        let todaySpent = appStepsSpentByDay[key] ?? [:]
        let totalSpent = todaySpent.values.reduce(0, +)
        Task {
            await SupabaseSyncService.shared.syncDailySpent(dayKey: key, totalSpent: totalSpent, spentByApp: todaySpent)
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "experience_spent",
                properties: [
                    "bundle_id": bundleId,
                    "amount": String(cost),
                    "day_key": key,
                    "total_spent_today": String(totalSpent)
                ]
            )
        }
    }
    
    @MainActor
    func consumeBonusSteps(_ cost: Int) {
        guard cost > 0 else { return }
        
        let before = self.serverGrantedSteps
        self.serverGrantedSteps = max(0, self.serverGrantedSteps - min(self.serverGrantedSteps, cost))
        #if DEBUG
        AppLogger.payment.debug("consumeBonusSteps: \(cost), serverGrantedSteps: \(before) → \(self.serverGrantedSteps)")
        #endif
        syncAndPersistBonusBreakdown()
        
        // Force immediate persistence
        let g = UserDefaults.stepsTrader()
        g.set(self.serverGrantedSteps, forKey: "serverGrantedSteps_v1")
        
        // Force UI update
        objectWillChange.send()
    }
    
    // MARK: - Day Pass Management
    func hasDayPass(for bundleId: String?) -> Bool {
        guard let bundleId, let date = dayPassGrants[bundleId] else { return false }
        if isSameCustomDay(date, Date()) { return true }
        dayPassGrants.removeValue(forKey: bundleId)
        persistDayPassGrants()
        return false
    }
    
    func clearExpiredDayPasses() {
        let today = currentDayStart(for: Date())
        dayPassGrants = dayPassGrants.filter { _, value in
            isSameCustomDay(value, today)
        }
        persistDayPassGrants()
    }
}
