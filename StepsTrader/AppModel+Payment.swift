import Foundation

// MARK: - Payment & Entry Management
extension AppModel {
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
            addSpentSteps(cost, for: bundleId ?? "_unknown")
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
        dayPassGrants[bundleId] = Date.now
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
        let newSpent = self.spentStepsToday + consumeFromBase
        self.spentStepsToday = newSpent
        self.stepsBalance = max(0, todaysBaseEnergy - self.spentStepsToday)

        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            consumeBonusSteps(remainingCost)
        }

        let g = UserDefaults.stepsTrader()
        g.set(self.spentStepsToday, forKey: SharedKeys.spentStepsToday)
        g.set(self.stepsBalance, forKey: SharedKeys.stepsBalance)
        
        clearBonusBreakdown()
        
        writeWidgetSnapshot()
        
        #if DEBUG
        AppLogger.payment.debug("After: totalBalance=\(self.totalStepsBalance), stepsBalance=\(self.stepsBalance), bonusSteps=\(self.bonusSteps), spentStepsToday=\(self.spentStepsToday)")
        AppLogger.payment.debug("Balance persisted to UserDefaults (synchronized)")
        #endif
        return true
    }

    @MainActor
    func refund(cost: Int) {
        guard cost > 0 else { return }
        let refundToBase = min(cost, spentStepsToday)
        spentStepsToday = max(0, spentStepsToday - refundToBase)
        stepsBalance = max(0, baseEnergyToday - spentStepsToday)

        let g = UserDefaults.stepsTrader()
        g.set(self.spentStepsToday, forKey: SharedKeys.spentStepsToday)
        g.set(self.stepsBalance, forKey: SharedKeys.stepsBalance)

        writeWidgetSnapshot()
        AppLogger.payment.debug("Refunded \(cost) colors (spentStepsToday now \(self.spentStepsToday))")
    }

    // MARK: - Steps Balance Management
    func loadSpentStepsBalance() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: SharedKeys.dailyEnergyAnchor) as? Date ?? .distantPast
        let isSameDay = isSameCustomDay(anchor, Date.now)
        let rawUDSpent = g.integer(forKey: SharedKeys.spentStepsToday)
        
        AppLogger.energy.debug("📥 loadSpentStepsBalance: anchor=\(anchor), isSameDay=\(isSameDay), UD[spentStepsToday]=\(rawUDSpent), in-memory spentStepsToday=\(self.spentStepsToday)")
        
        if !isSameDay {
            AppLogger.energy.debug("📥 loadSpentStepsBalance: new day → resetting spent to 0")
            self.spentStepsToday = 0
            self.stepsBalance = 0
        } else {
            self.spentStepsToday = rawUDSpent
        }
        
        let todaysBaseEnergy = self.baseEnergyToday
        self.stepsBalance = max(0, todaysBaseEnergy - self.spentStepsToday)
        
        AppLogger.energy.debug("📥 loadSpentStepsBalance RESULT: spent=\(self.spentStepsToday), base=\(todaysBaseEnergy), balance=\(self.stepsBalance)")
        
        self.serverGrantedSteps = g.integer(forKey: "serverGrantedSteps_v1")
        
        clearBonusBreakdown()
    }

    @MainActor
    func clearBonusBreakdown() {
        self.bonusSteps = 0
        
        let g = UserDefaults.stepsTrader()
        g.set(0, forKey: SharedKeys.bonusSteps)
        g.removeObject(forKey: "debugStepsBonus_outerworld_v1")
        g.removeObject(forKey: "debugStepsBonus_debug_v1")
    }

    // MARK: - Spent Steps Tracking
    func addSpentSteps(_ cost: Int, for bundleId: String) {
        appStepsSpentToday[bundleId, default: 0] += cost
        appStepsSpentLifetime[bundleId, default: 0] += cost
        let key = Self.dayKey(for: Date.now)
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
        clearBonusBreakdown()
        
        // Force immediate persistence
        let g = UserDefaults.stepsTrader()
        g.set(self.serverGrantedSteps, forKey: "serverGrantedSteps_v1")
        
        // Force UI update
        objectWillChange.send()
    }
    
    // MARK: - Day Pass Management
    func hasDayPass(for bundleId: String?) -> Bool {
        guard let bundleId, let date = dayPassGrants[bundleId] else { return false }
        return isSameCustomDay(date, Date.now)
    }

}
