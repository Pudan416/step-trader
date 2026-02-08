import Foundation
import Combine

@MainActor
final class UserEconomyStore: ObservableObject {
    // Dependencies
    private let budgetEngine: any BudgetEngineProtocol
    private let persistence = PersistenceManager.shared
    
    // Keys
    private let appStepsSpentByDayKey = "appStepsSpentByDay.json"
    private let appStepsSpentLifetimeKey = "appStepsSpentLifetime.json"
    private let minuteChargeLogsKey = "minuteChargeLogs.json"
    private let minuteTimeByDayKey = "minuteTimeByDay.json"
    
    // UserDefaults Keys (for migration)
    private let udAppStepsSpentByDayKey = "appStepsSpentByDay_v1"
    private let udAppStepsSpentLifetimeKey = "appStepsSpentLifetime_v1"
    private let udMinuteChargeLogsKey = "minuteChargeLogs_v1"
    private let udMinuteTimeByDayKey = "minuteTimeByDay_v1"
    
    // Published State
    @Published var entryCostSteps: Int = 5
    @Published var stepsBalance: Int = 0 {
        didSet { updateTotalStepsBalance() }
    }
    @Published var bonusSteps: Int = 0 {
        didSet { updateTotalStepsBalance() }
    }
    @Published var serverGrantedSteps: Int = 0
    @Published var totalStepsBalance: Int = 0
    
    @Published var spentSteps: Int = 0
    @Published var spentMinutes: Int = 0
    @Published var spentTariff: Tariff = .easy
    
    @Published var dailyTariffSelections: [String: Tariff] = [:]
    
    // PayGate
    @Published var showPayGate: Bool = false
    @Published var payGateTargetGroupId: String? = nil
    @Published var payGateSessions: [String: PayGateSession] = [:]
    @Published var currentPayGateSessionId: String? = nil
    
    // Stats
    @Published var minuteChargeLogs: [MinuteChargeLog] = []
    @Published var minuteTimeByDay: [String: [String: Int]] = [:]
    @Published var appStepsSpentToday: [String: Int] = [:]
    @Published var appStepsSpentByDay: [String: [String: Int]] = [:]
    @Published var appStepsSpentLifetime: [String: Int] = [:]
    @Published var dayPassGrants: [String: Date] = [:]
    
    init(budgetEngine: any BudgetEngineProtocol) {
        self.budgetEngine = budgetEngine
    }
    
    private func updateTotalStepsBalance() {
        totalStepsBalance = max(0, stepsBalance + bonusSteps)
    }
    
    // MARK: - Persistence & Loading
    func loadSpentStepsBalance() {
        let g = UserDefaults.stepsTrader()
        spentSteps = g.integer(forKey: "spentStepsToday")
        stepsBalance = g.integer(forKey: "stepsBalance")
        bonusSteps = g.integer(forKey: "debugStepsBonus_v1")
        
        // Check anchor
        if let anchor = g.object(forKey: "stepsBalanceAnchor") as? Date {
            if !Calendar.current.isDateInToday(anchor) {
                // New day - reset spent steps, keep balance
                spentSteps = 0
                g.set(0, forKey: "spentStepsToday")
                g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
            }
        } else {
            g.set(Calendar.current.startOfDay(for: Date()), forKey: "stepsBalanceAnchor")
        }
    }
    
    func loadAppStepsSpentToday() async {
        if let loaded: [String: [String: Int]] = await loadFromPersistenceOrDefaults(
            filename: appStepsSpentByDayKey,
            defaultsKey: udAppStepsSpentByDayKey
        ) {
            appStepsSpentByDay = loaded
        } else {
            appStepsSpentByDay = [:]
        }
        
        let dayKey = AppModel.dayKey(for: Date())
        appStepsSpentToday = appStepsSpentByDay[dayKey] ?? [:]
        
        if appStepsSpentLifetime.isEmpty {
            await loadAppStepsSpentLifetime()
        }
    }
    
    func loadAppStepsSpentLifetime() async {
        if let loaded: [String: Int] = await loadFromPersistenceOrDefaults(
            filename: appStepsSpentLifetimeKey,
            defaultsKey: udAppStepsSpentLifetimeKey
        ) {
            appStepsSpentLifetime = loaded
        } else {
            appStepsSpentLifetime = [:]
        }
    }
    
    func loadMinuteChargeLogs() async {
        if let loaded: [MinuteChargeLog] = await loadFromPersistenceOrDefaults(
            filename: minuteChargeLogsKey,
            defaultsKey: udMinuteChargeLogsKey
        ) {
            minuteChargeLogs = loaded
        } else {
            minuteChargeLogs = []
        }
        
        if let loadedTime: [String: [String: Int]] = await loadFromPersistenceOrDefaults(
            filename: minuteTimeByDayKey,
            defaultsKey: udMinuteTimeByDayKey
        ) {
            minuteTimeByDay = loadedTime
        } else {
            minuteTimeByDay = [:]
        }
    }
    
    func persistAppStepsSpentToday() {
        let dayKey = AppModel.dayKey(for: Date())
        appStepsSpentByDay[dayKey] = appStepsSpentToday
        persistAppStepsSpentByDay()
    }
    
    func persistAppStepsSpentByDay() {
        Task {
            try? await persistence.save(appStepsSpentByDay, to: appStepsSpentByDayKey)
        }
    }
    
    func persistAppStepsSpentLifetime() {
        Task {
            try? await persistence.save(appStepsSpentLifetime, to: appStepsSpentLifetimeKey)
        }
    }
    
    func persistMinuteChargeLogs() {
        Task {
            try? await persistence.save(minuteChargeLogs, to: minuteChargeLogsKey)
            try? await persistence.save(minuteTimeByDay, to: minuteTimeByDayKey)
        }
    }
    
    func clearMinuteChargeLogs() {
        minuteChargeLogs = []
        minuteTimeByDay = [:]
        persistMinuteChargeLogs()
    }
    
    // MARK: - Helper
    private func loadFromPersistenceOrDefaults<T: Decodable & Encodable>(
        filename: String,
        defaultsKey: String
    ) async -> T? {
        // 1. Try file
        if await persistence.exists(filename) {
            return try? await persistence.load(T.self, from: filename)
        }
        
        // 2. Try Defaults (Migration) - Check App Group first
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            // Migrate to file
            try? await persistence.save(decoded, to: filename)
            g.removeObject(forKey: defaultsKey)
            print("📦 Migrated \(defaultsKey) from AppGroup to \(filename)")
            return decoded
        }
        
        // 3. Try Standard Defaults (Migration fallback)
        let s = UserDefaults.standard
        if let data = s.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            // Migrate to file
            try? await persistence.save(decoded, to: filename)
            s.removeObject(forKey: defaultsKey)
            print("📦 Migrated \(defaultsKey) from Standard to \(filename)")
            return decoded
        }
        
        return nil
    }
    
    func loadDayPassGrants() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "appDayPassGrants_v1") else { return }
        if let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            dayPassGrants = decoded
            clearExpiredDayPasses()
        }
    }
    
    private func clearExpiredDayPasses() {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        
        var changed = false
        for (id, date) in dayPassGrants {
            if date < dayStart { // Expired yesterday
                dayPassGrants.removeValue(forKey: id)
                changed = true
            }
        }
        if changed {
            persistDayPassGrants()
        }
    }
    
    func persistDayPassGrants() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(dayPassGrants) {
            g.set(data, forKey: "appDayPassGrants_v1")
        }
    }
    
    // MARK: - Budget
    var dailyBudgetMinutes: Int { budgetEngine.dailyBudgetMinutes }
    var remainingMinutes: Int { budgetEngine.remainingMinutes }
    
    func setBudget(minutes: Int) {
        budgetEngine.setBudget(minutes: minutes)
    }
    
    func updateSpentTime(minutes: Int) {
        spentMinutes = minutes
        // Sync with budget engine if needed
    }
}
