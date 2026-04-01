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
    
    private var persistByDayTask: Task<Void, Never>?
    private var persistLifetimeTask: Task<Void, Never>?
    
    // UserDefaults Keys (for migration)
    private let udAppStepsSpentByDayKey = SharedKeys.appStepsSpentByDay
    private let udAppStepsSpentLifetimeKey = SharedKeys.appStepsSpentLifetime
    
    // Published State
    @Published var entryCostSteps: Int = Tariff.medium.entryCostSteps
    @Published var stepsBalance: Int = 0 {
        didSet {
            updateTotalStepsBalance()
            UserDefaults.stepsTrader().set(stepsBalance, forKey: SharedKeys.stepsBalance)
        }
    }
    @Published var bonusSteps: Int = 0 {
        didSet { updateTotalStepsBalance() }
    }
    @Published var serverGrantedSteps: Int = 0
    @Published var totalStepsBalance: Int = 0
    
    @Published var spentSteps: Int = 0 {
        didSet { UserDefaults.stepsTrader().set(spentSteps, forKey: SharedKeys.spentStepsToday) }
    }
    
    // PayGate
    @Published var showPayGate: Bool = false
    @Published var payGateTargetGroupId: String? = nil
    @Published var payGateSessions: [String: PayGateSession] = [:]
    @Published var currentPayGateSessionId: String? = nil
    
    // Stats
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
    
    
    func persistAppStepsSpentToday() {
        let dayKey = AppModel.dayKey(for: Date())
        appStepsSpentByDay[dayKey] = appStepsSpentToday
        persistAppStepsSpentByDay()
    }
    
    func persistAppStepsSpentByDay() {
        let snapshot = appStepsSpentByDay
        persistByDayTask?.cancel()
        persistByDayTask = Task {
            do {
                try await persistence.save(snapshot, to: appStepsSpentByDayKey)
            } catch {
                AppLogger.app.error("Failed to persist appStepsSpentByDay: \(error.localizedDescription)")
            }
        }
    }
    
    func persistAppStepsSpentLifetime() {
        let snapshot = appStepsSpentLifetime
        persistLifetimeTask?.cancel()
        persistLifetimeTask = Task {
            do {
                try await persistence.save(snapshot, to: appStepsSpentLifetimeKey)
            } catch {
                AppLogger.app.error("Failed to persist appStepsSpentLifetime: \(error.localizedDescription)")
            }
        }
    }
    
    
    // MARK: - Helper
    private func loadFromPersistenceOrDefaults<T: Decodable & Encodable>(
        filename: String,
        defaultsKey: String
    ) async -> T? {
        // 1. Try file
        if await persistence.exists(filename) {
            do {
                return try await persistence.load(T.self, from: filename)
            } catch {
                AppLogger.app.error("Failed to load \(filename) from persistence: \(error.localizedDescription)")
                return nil
            }
        }
        
        // 2. Try Defaults (Migration) - Check App Group first
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: defaultsKey) {
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                do {
                    try await persistence.save(decoded, to: filename)
                } catch {
                    AppLogger.app.error("Failed to migrate \(defaultsKey) to \(filename): \(error.localizedDescription)")
                }
                g.removeObject(forKey: defaultsKey)
                AppLogger.app.debug("📦 Migrated \(defaultsKey) from AppGroup to \(filename)")
                return decoded
            } catch {
                AppLogger.app.error("Failed to decode \(defaultsKey) from AppGroup defaults: \(error.localizedDescription)")
            }
        }
        
        // 3. Try Standard Defaults (Migration fallback)
        let s = UserDefaults.standard
        if let data = s.data(forKey: defaultsKey) {
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                do {
                    try await persistence.save(decoded, to: filename)
                } catch {
                    AppLogger.app.error("Failed to migrate \(defaultsKey) to \(filename): \(error.localizedDescription)")
                }
                s.removeObject(forKey: defaultsKey)
                AppLogger.app.debug("📦 Migrated \(defaultsKey) from Standard to \(filename)")
                return decoded
            } catch {
                AppLogger.app.error("Failed to decode \(defaultsKey) from Standard defaults: \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    func loadDayPassGrants() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: SharedKeys.appDayPassGrants) else { return }
        do {
            dayPassGrants = try JSONDecoder().decode([String: Date].self, from: data)
            clearExpiredDayPasses()
        } catch {
            AppLogger.app.error("Failed to decode dayPassGrants: \(error.localizedDescription)")
        }
    }
    
    private func clearExpiredDayPasses() {
        let now = Date()
        let g = UserDefaults.stepsTrader()
        let hour = (g.object(forKey: SharedKeys.dayEndHour) as? Int) ?? 0
        let minute = (g.object(forKey: SharedKeys.dayEndMinute) as? Int) ?? 0
        let dayStart = DayBoundary.currentDayStart(for: now, dayEndHour: hour, dayEndMinute: minute)
        
        var changed = false
        for (id, date) in dayPassGrants {
            if date < dayStart {
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
        do {
            let data = try JSONEncoder().encode(dayPassGrants)
            g.set(data, forKey: SharedKeys.appDayPassGrants)
        } catch {
            AppLogger.app.error("Failed to encode dayPassGrants: \(error.localizedDescription)")
        }
    }
    
}
