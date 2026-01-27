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
    @discardableResult
    func payForEntry(for bundleId: String? = nil, costOverride: Int? = nil) -> Bool {
        if hasDayPass(for: bundleId) { return true }
        let cost = costOverride ?? unlockSettings(for: bundleId).entryCostSteps
        let success = pay(cost: cost)
        if success, let bundleId { addSpentSteps(cost, for: bundleId) }
        return success
    }
    
    @discardableResult
    func payForDayPass(for bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        if hasDayPass(for: bundleId) { return true }
        let cost = unlockSettings(for: bundleId).dayPassCostSteps
        guard pay(cost: cost) else { return false }
        addSpentSteps(cost, for: bundleId)
        dayPassGrants[bundleId] = Date()
        persistDayPassGrants()
        return true
    }
    
    func pay(cost: Int) -> Bool {
        guard totalStepsBalance >= cost else { return false }
        // Не позволяем тратить больше базовой энергии за день
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
        return true
    }

    // MARK: - Steps Balance Management
    func loadSpentStepsBalance() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: "stepsBalanceAnchor") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(anchor) {
            spentStepsToday = 0
            g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
        } else {
            spentStepsToday = g.integer(forKey: "spentStepsToday")
        }
        // Клэмп только если уже знаем базовую энергию (иначе при запуске с 0 мы затираем данные)
        let todaysBaseEnergy = baseEnergyToday
        if todaysBaseEnergy > 0, spentStepsToday > todaysBaseEnergy { spentStepsToday = todaysBaseEnergy }
        stepsBalance = g.integer(forKey: "stepsBalance")
        if stepsBalance == 0, todaysBaseEnergy > 0 {
            stepsBalance = max(0, todaysBaseEnergy - spentStepsToday)
        }
    }

    func syncAndPersistBonusBreakdown() {
        // Суммируем бонусную энергию
        let rawBonus = outerWorldBonusSteps + serverGrantedSteps
        
        // Ограничиваем бонусную энергию максимумом 50
        let cappedBonus = min(rawBonus, EnergyDefaults.maxBonusEnergy)
        
        // Проверяем суммарный лимит: baseEnergyToday + bonusSteps не должно превышать 100
        // Если превышает, уменьшаем bonusSteps
        let maxTotalEnergy = EnergyDefaults.maxBaseEnergy // 100
        let availableForBonus = max(0, maxTotalEnergy - baseEnergyToday)
        bonusSteps = min(cappedBonus, availableForBonus)
        
        let g = UserDefaults.stepsTrader()
        // Keep compatibility (extensions / older code) by writing Outer World bonus into legacy key.
        g.set(bonusSteps, forKey: "debugStepsBonus_v1")
        g.set(outerWorldBonusSteps, forKey: "debugStepsBonus_outerworld_v1")
        // Explicitly clear removed debug bucket if it exists.
        g.removeObject(forKey: "debugStepsBonus_debug_v1")
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
    }
    
    func consumeBonusSteps(_ cost: Int) {
        guard cost > 0 else { return }
        
        outerWorldBonusSteps = max(0, outerWorldBonusSteps - min(outerWorldBonusSteps, cost))
        
        syncAndPersistBonusBreakdown()
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
