import Foundation

// MARK: - Payment & Entry Management
extension AppModel {
    // MARK: - Payment Checks
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

    // MARK: - Payment Execution
    @MainActor
    @discardableResult
    func payForEntry(for bundleId: String? = nil, costOverride: Int? = nil) -> Bool {
        print("💳 payForEntry called for bundleId: \(bundleId ?? "nil")")
        
        if hasDayPass(for: bundleId) {
            print("💳 Day pass active, skipping payment")
            return true
        }
        
        let cost = costOverride ?? unlockSettings(for: bundleId).entryCostSteps
        print("💳 Entry cost: \(cost), current balance: \(totalStepsBalance)")
        
        let success = pay(cost: cost)
        
        if success {
            if let bundleId {
                addSpentSteps(cost, for: bundleId)
            }
            print("✅ payForEntry successful, new balance: \(totalStepsBalance)")
            
            // Force UI update
            objectWillChange.send()
        } else {
            print("❌ payForEntry failed - not enough balance")
        }
        
        return success
    }
    
    @MainActor
    @discardableResult
    func payForDayPass(for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        if hasDayPass(for: bundleId) { return true }
        let cost = unlockSettings(for: bundleId).dayPassCostSteps
        
        print("💳 payForDayPass for \(bundleId), cost: \(cost)")
        
        guard pay(cost: cost) else {
            print("❌ payForDayPass failed - not enough balance")
            return false
        }
        
        addSpentSteps(cost, for: bundleId)
        dayPassGrants[bundleId] = Date()
        persistDayPassGrants()
        
        print("✅ payForDayPass successful, new balance: \(totalStepsBalance)")
        
        // Force UI update
        objectWillChange.send()
        
        return true
    }
    
    @MainActor
    func pay(cost: Int) -> Bool {
        print("💳 pay(\(cost)) called on main thread: \(Thread.isMainThread)")
        print("💳 Before: totalBalance=\(totalStepsBalance), stepsBalance=\(stepsBalance), bonusSteps=\(bonusSteps), baseEnergyToday=\(baseEnergyToday), spentStepsToday=\(spentStepsToday)")
        
        guard totalStepsBalance >= cost else {
            print("💳 FAILED: Not enough balance (\(totalStepsBalance) < \(cost))")
            return false
        }
        
        // Deduct from base energy first, then from bonus
        let todaysBaseEnergy = baseEnergyToday
        let baseAvailable = stepsBalance
        let consumeFromBase = min(baseAvailable, cost)
        let newSpent = min(spentStepsToday + consumeFromBase, max(0, todaysBaseEnergy))
        spentStepsToday = newSpent
        stepsBalance = max(0, todaysBaseEnergy - spentStepsToday)

        let remainingCost = max(0, cost - consumeFromBase)
        if remainingCost > 0 {
            consumeBonusSteps(remainingCost)
        }

        let g = UserDefaults.stepsTrader()
        g.set(spentStepsToday, forKey: "spentStepsToday")
        g.set(stepsBalance, forKey: "stepsBalance")
        g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
        
        // Explicitly update totalStepsBalance
        updateTotalStepsBalance()
        
        // CRITICAL: Force sync bonus steps to UserDefaults to ensure persistence
        syncAndPersistBonusBreakdown()
        
        // Force UserDefaults to synchronize immediately
        g.synchronize()
        
        print("💳 After: totalBalance=\(totalStepsBalance), stepsBalance=\(stepsBalance), bonusSteps=\(bonusSteps), spentStepsToday=\(spentStepsToday)")
        print("💾 Balance persisted to UserDefaults: stepsBalance=\(g.integer(forKey: "stepsBalance")), bonusSteps=\(g.integer(forKey: "debugStepsBonus_v1"))")
        
        // Force UI update
        objectWillChange.send()
        
        return true
    }

    // MARK: - Steps Balance Management
    func loadSpentStepsBalance() {
        let g = UserDefaults.stepsTrader()
        
        print("💾 === LOADING SPENT STEPS BALANCE ===")
        
        let anchor = g.object(forKey: "stepsBalanceAnchor") as? Date ?? .distantPast
        let isSameDay = Calendar.current.isDateInToday(anchor)
        print("💾 Anchor date: \(anchor), isToday: \(isSameDay)")
        
        if !isSameDay {
            print("💾 New day detected, resetting spentStepsToday to 0")
            spentStepsToday = 0
            g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
        } else {
            spentStepsToday = g.integer(forKey: "spentStepsToday")
            print("💾 Loaded spentStepsToday from UserDefaults: \(spentStepsToday)")
        }
        
        // Клэмп только если уже знаем базовую энергию (иначе при запуске с 0 мы затираем данные)
        let todaysBaseEnergy = baseEnergyToday
        if todaysBaseEnergy > 0, spentStepsToday > todaysBaseEnergy {
            print("💾 Clamping spentStepsToday from \(spentStepsToday) to \(todaysBaseEnergy)")
            spentStepsToday = todaysBaseEnergy
        }
        
        stepsBalance = g.integer(forKey: "stepsBalance")
        print("💾 Loaded stepsBalance from UserDefaults: \(stepsBalance)")
        
        if stepsBalance == 0, todaysBaseEnergy > 0 {
            stepsBalance = max(0, todaysBaseEnergy - spentStepsToday)
            print("💾 Recalculated stepsBalance: \(stepsBalance) (baseEnergy \(todaysBaseEnergy) - spent \(spentStepsToday))")
        }
        
        serverGrantedSteps = g.integer(forKey: "serverGrantedSteps_v1")
        print("💾 Loaded serverGrantedSteps: \(serverGrantedSteps)")
        
        // Sync bonus breakdown which will calculate and set bonusSteps correctly
        syncAndPersistBonusBreakdown()
        
        // Update totalStepsBalance after loading
        updateTotalStepsBalance()
        
        print("💾 Final: spentStepsToday=\(spentStepsToday), stepsBalance=\(stepsBalance), bonusSteps=\(bonusSteps), totalBalance=\(totalStepsBalance)")
        print("💾 === END LOADING SPENT STEPS BALANCE ===")
    }

    @MainActor
    func syncAndPersistBonusBreakdown() {
        let cappedBonus = min(serverGrantedSteps, EnergyDefaults.maxBonusEnergy)
        let maxTotalEnergy = EnergyDefaults.maxBaseEnergy
        let availableForBonus = max(0, maxTotalEnergy - baseEnergyToday)
        bonusSteps = min(cappedBonus, availableForBonus)
        
        let g = UserDefaults.stepsTrader()
        g.set(bonusSteps, forKey: "debugStepsBonus_v1")
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
        SupabaseSyncService.shared.syncDailySpent(dayKey: key, totalSpent: totalSpent, spentByApp: todaySpent)
    }
    
    @MainActor
    func consumeBonusSteps(_ cost: Int) {
        guard cost > 0 else { return }
        
        let before = serverGrantedSteps
        serverGrantedSteps = max(0, serverGrantedSteps - min(serverGrantedSteps, cost))
        print("🔋 consumeBonusSteps: \(cost), serverGrantedSteps: \(before) → \(serverGrantedSteps)")
        
        syncAndPersistBonusBreakdown()
        
        // Force immediate persistence
        let g = UserDefaults.stepsTrader()
        g.set(serverGrantedSteps, forKey: "serverGrantedSteps_v1")
        g.synchronize()
        
        // Force UI update
        objectWillChange.send()
    }
    
    // MARK: - Day Pass Management
    func hasDayPass(for bundleId: String?) -> Bool {
        guard let bundleId, let date = dayPassGrants[bundleId] else { return false }
        if Calendar.current.isDateInToday(date) { return true }
        dayPassGrants.removeValue(forKey: bundleId)
        persistDayPassGrants()
        return false
    }
    
    func clearExpiredDayPasses() {
        let today = Calendar.current.startOfDay(for: Date())
        dayPassGrants = dayPassGrants.filter { _, value in
            Calendar.current.isDate(value, inSameDayAs: today)
        }
        persistDayPassGrants()
    }
}
