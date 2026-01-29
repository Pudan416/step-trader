import Foundation

// MARK: - Daily Energy Management
extension AppModel {
    // MARK: - Daily energy system keys
    private var dailyEnergyAnchorKey: String { "dailyEnergyAnchor_v1" }
    private var dailySleepHoursKey: String { "dailySleepHours_v1" }
    private var baseEnergyTodayKey: String { "baseEnergyToday_v1" }
    
    private func dailySelectionsKey(for category: EnergyCategory) -> String {
        "dailyEnergySelections_v1_\(category.rawValue)"
    }
    
    private func preferredOptionsKey(for category: EnergyCategory) -> String {
        "preferredEnergyOptions_v1_\(category.rawValue)"
    }
    // MARK: - Daily energy system
    func loadEnergyPreferences() {
        preferredMoveOptions = loadPreferredOptions(for: .move)
        preferredRebootOptions = loadPreferredOptions(for: .reboot)
        preferredJoyOptions = loadPreferredOptions(for: .joy)
    }

    func loadDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date ?? .distantPast
        if !isSameCustomDay(anchor, Date()) {
            resetDailyEnergyState()
            return
        }
        dailySleepHours = g.double(forKey: dailySleepHoursKey)
        // Migration: try to load old recovery/activity data
        let oldRecovery = loadStringArray(forKey: "dailyEnergySelections_v1_recovery")
        let oldActivity = loadStringArray(forKey: "dailyEnergySelections_v1_activity")
        let oldMove = loadStringArray(forKey: dailySelectionsKey(for: .move))
        let oldReboot = loadStringArray(forKey: dailySelectionsKey(for: .reboot))
        
        // Migrate: activity -> move, recovery -> reboot
        dailyMoveSelections = oldMove.isEmpty ? oldActivity : oldMove
        dailyRebootSelections = oldReboot.isEmpty ? oldRecovery : oldReboot
        dailyJoySelections = loadStringArray(forKey: dailySelectionsKey(for: .joy))
        
        // Migration: try to load old preferred options
        let oldPreferredRecovery = loadStringArray(forKey: "preferredEnergyOptions_v1_recovery")
        let oldPreferredActivity = loadStringArray(forKey: "preferredEnergyOptions_v1_activity")
        let oldPreferredMove = loadStringArray(forKey: preferredOptionsKey(for: .move))
        let oldPreferredReboot = loadStringArray(forKey: preferredOptionsKey(for: .reboot))
        
        preferredMoveOptions = oldPreferredMove.isEmpty ? oldPreferredActivity : oldPreferredMove
        preferredRebootOptions = oldPreferredReboot.isEmpty ? oldPreferredRecovery : oldPreferredReboot
        
        dailyMoveSelections = Array(dailyMoveSelections.filter { preferredMoveOptions.contains($0) }.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyRebootSelections = Array(dailyRebootSelections.filter { preferredRebootOptions.contains($0) }.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyJoySelections = Array(dailyJoySelections.filter { preferredJoyOptions.contains($0) }.prefix(EnergyDefaults.maxSelectionsPerCategory))
        baseEnergyToday = g.integer(forKey: baseEnergyTodayKey)
    }

    private func resetDailyEnergyState() {
        dailySleepHours = 0
        dailyMoveSelections = []
        dailyRebootSelections = []
        dailyJoySelections = []
        baseEnergyToday = 0
        if outerWorldBonusSteps != 0 {
            outerWorldBonusSteps = 0
            syncAndPersistBonusBreakdown()
        }
        persistDailyEnergyState()
        let g = UserDefaults.stepsTrader()
        g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
    }

    func resetDailyEnergyIfNeeded() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date ?? .distantPast
        if !isSameCustomDay(anchor, Date()) {
            resetDailyEnergyState()
        }
    }

    private func loadPreferredOptions(for category: EnergyCategory) -> [String] {
        let stored = loadStringArray(forKey: preferredOptionsKey(for: category))
        if !stored.isEmpty {
            return stored
        }
        let defaults = EnergyDefaults.options
            .filter { $0.category == category }
            .map(\.id)
        let fallback = Array(defaults.prefix(EnergyDefaults.maxSelectionsPerCategory))
        saveStringArray(fallback, forKey: preferredOptionsKey(for: category))
        return fallback
    }

    private func loadStringArray(forKey key: String) -> [String] {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveStringArray(_ value: [String], forKey key: String) {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(value) {
            g.set(data, forKey: key)
        }
    }

    func preferredOptions(for category: EnergyCategory) -> [EnergyOption] {
        let ids: [String]
        switch category {
        case .move: ids = preferredMoveOptions
        case .reboot: ids = preferredRebootOptions
        case .joy: ids = preferredJoyOptions
        }
        return EnergyDefaults.options.filter { $0.category == category && ids.contains($0.id) }
    }

    func availableOptions(for category: EnergyCategory) -> [EnergyOption] {
        EnergyDefaults.options.filter { $0.category == category }
    }

    func updatePreferredOptions(_ ids: [String], category: EnergyCategory) {
        let unique = Array(NSOrderedSet(array: ids)) as? [String] ?? ids
        let trimmed = Array(unique.prefix(EnergyDefaults.maxSelectionsPerCategory))
        switch category {
        case .move: preferredMoveOptions = trimmed
        case .reboot: preferredRebootOptions = trimmed
        case .joy: preferredJoyOptions = trimmed
        }
        let filteredDaily = dailySelections(for: category).filter { trimmed.contains($0) }
        setDailySelections(filteredDaily, category: category)
        saveStringArray(trimmed, forKey: preferredOptionsKey(for: category))
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }

    func togglePreferredOption(optionId: String, category: EnergyCategory) {
        var selections: [String]
        switch category {
        case .move: selections = preferredMoveOptions
        case .reboot: selections = preferredRebootOptions
        case .joy: selections = preferredJoyOptions
        }
        if let idx = selections.firstIndex(of: optionId) {
            selections.remove(at: idx)
        } else if selections.count < EnergyDefaults.maxSelectionsPerCategory {
            selections.append(optionId)
        }
        updatePreferredOptions(selections, category: category)
    }

    func isPreferredOptionSelected(_ optionId: String, category: EnergyCategory) -> Bool {
        switch category {
        case .move: return preferredMoveOptions.contains(optionId)
        case .reboot: return preferredRebootOptions.contains(optionId)
        case .joy: return preferredJoyOptions.contains(optionId)
        }
    }

    func toggleDailySelection(optionId: String, category: EnergyCategory) {
        var selections = dailySelections(for: category)
        if let idx = selections.firstIndex(of: optionId) {
            selections.remove(at: idx)
        } else if selections.count < EnergyDefaults.maxSelectionsPerCategory {
            selections.append(optionId)
        }
        setDailySelections(selections, category: category)
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }

    func isDailySelected(_ optionId: String, category: EnergyCategory) -> Bool {
        dailySelections(for: category).contains(optionId)
    }

    func setDailySleepHours(_ hours: Double) {
        dailySleepHours = min(max(0, hours), 24)
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }

    private func dailySelections(for category: EnergyCategory) -> [String] {
        switch category {
        case .move: return dailyMoveSelections
        case .reboot: return dailyRebootSelections
        case .joy: return dailyJoySelections
        }
    }

    private func setDailySelections(_ selections: [String], category: EnergyCategory) {
        switch category {
        case .move: dailyMoveSelections = selections
        case .reboot: dailyRebootSelections = selections
        case .joy: dailyJoySelections = selections
        }
    }

    func persistDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        g.set(dailySleepHours, forKey: dailySleepHoursKey)
        saveStringArray(dailyMoveSelections, forKey: dailySelectionsKey(for: .move))
        saveStringArray(dailyRebootSelections, forKey: dailySelectionsKey(for: .reboot))
        saveStringArray(dailyJoySelections, forKey: dailySelectionsKey(for: .joy))
        g.set(baseEnergyToday, forKey: baseEnergyTodayKey)
        if g.object(forKey: dailyEnergyAnchorKey) == nil {
            g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
        }
    }

    var sleepPointsToday: Int {
        pointsFromSleep(hours: dailySleepHours)
    }

    var stepsPointsToday: Int {
        pointsFromSteps(stepsToday)
    }

    var moveExtrasPoints: Int {
        pointsFromSelections(dailyMoveSelections.count)
    }
    
    var rebootExtrasPoints: Int {
        pointsFromSelections(dailyRebootSelections.count)
    }

    var joyPointsToday: Int {
        pointsFromSelections(dailyJoySelections.count)
    }

    var movePointsToday: Int {
        stepsPointsToday + moveExtrasPoints
    }
    
    var rebootPointsToday: Int {
        sleepPointsToday + rebootExtrasPoints
    }

    var joyCategoryPointsToday: Int {
        joyPointsToday
    }

    private var userSleepTarget: Double {
        let g = UserDefaults.stepsTrader()
        return g.object(forKey: "userSleepTarget") as? Double ?? EnergyDefaults.sleepTargetHours
    }
    
    private var userStepsTarget: Double {
        let g = UserDefaults.stepsTrader()
        return g.object(forKey: "userStepsTarget") as? Double ?? EnergyDefaults.stepsTarget
    }
    
    private func pointsFromSleep(hours: Double) -> Int {
        let target = userSleepTarget
        let capped = min(max(0, hours), target)
        let ratio = capped / target
        return Int(ratio * Double(EnergyDefaults.sleepMaxPoints))
    }

    private func pointsFromSteps(_ steps: Double) -> Int {
        let target = userStepsTarget
        let capped = min(max(0, steps), target)
        let ratio = capped / target
        return Int(ratio * Double(EnergyDefaults.stepsMaxPoints))
    }

    private func pointsFromSelections(_ count: Int) -> Int {
        min(count, EnergyDefaults.maxSelectionsPerCategory) * EnergyDefaults.selectionPoints
    }

    @MainActor
    func recalculateDailyEnergy() {
        let total = movePointsToday + rebootPointsToday + joyCategoryPointsToday
        
        print("⚡️ recalculateDailyEnergy: move=\(movePointsToday), reboot=\(rebootPointsToday), joy=\(joyCategoryPointsToday), total=\(total)")
        
        // Базовая энергия ограничена максимумом 100
        baseEnergyToday = min(EnergyDefaults.maxBaseEnergy, total)
        
        // Проверяем суммарный лимит: baseEnergyToday + bonusSteps не должно превышать 100
        // Если baseEnergyToday увеличился и сумма превышает лимит, уменьшаем bonusSteps
        let maxTotalEnergy = EnergyDefaults.maxBaseEnergy // 100
        let currentTotal = baseEnergyToday + bonusSteps
        if currentTotal > maxTotalEnergy {
            // Уменьшаем bonusSteps, чтобы сумма была <= 100
            let oldBonus = bonusSteps
            bonusSteps = max(0, maxTotalEnergy - baseEnergyToday)
            print("⚡️ Capped bonusSteps: \(oldBonus) → \(bonusSteps)")
            syncAndPersistBonusBreakdown() // Обновим сохранение
        }
        
        if spentStepsToday > baseEnergyToday {
            print("⚡️ Capping spentStepsToday from \(spentStepsToday) to \(baseEnergyToday)")
            spentStepsToday = baseEnergyToday
            let g = UserDefaults.stepsTrader()
            g.set(spentStepsToday, forKey: "spentStepsToday")
        }
        
        let oldBalance = stepsBalance
        stepsBalance = max(0, baseEnergyToday - spentStepsToday)
        print("⚡️ stepsBalance: \(oldBalance) → \(stepsBalance) (base=\(baseEnergyToday), spent=\(spentStepsToday))")
        
        let g = UserDefaults.stepsTrader()
        g.set(baseEnergyToday, forKey: baseEnergyTodayKey)
        g.set(stepsBalance, forKey: "stepsBalance")
        
        // Explicitly update totalStepsBalance after all changes
        updateTotalStepsBalance()
        print("⚡️ totalStepsBalance = \(totalStepsBalance)")
        
        // Force UI update
        objectWillChange.send()
    }
}
