import Foundation
import Combine

@MainActor
final class BudgetEngine: ObservableObject, BudgetEngineProtocol {
    @Published var tariff: Tariff {
        didSet {
            let g = UserDefaults.stepsTrader()
            g.set(tariff.rawValue, forKey: SharedKeys.selectedTariff)
            UserDefaults.standard.set(tariff.rawValue, forKey: SharedKeys.selectedTariff)
            AppLogger.energy.debug("💰 Tariff updated to: \(self.tariff.displayName) (\(Int(self.tariff.stepsPerMinute)) steps/min)")
        }
    }
    
    var stepsPerMinute: Double { tariff.stepsPerMinute }
    
    @Published private(set) var todayAnchor: Date
    @Published private(set) var dayEndHour: Int
    @Published private(set) var dayEndMinute: Int

    private var sharedDefaults: UserDefaults { UserDefaults.stepsTrader() }

    init() {
        let g = UserDefaults.stepsTrader()
        let savedTariffString = g.string(forKey: SharedKeys.selectedTariff)
            ?? UserDefaults.standard.string(forKey: SharedKeys.selectedTariff)
            ?? Tariff.medium.rawValue
        self.tariff = Tariff(rawValue: savedTariffString) ?? .medium
        
        let savedHour = (g.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? (UserDefaults.standard.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? 0
        let savedMinute = (g.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? (UserDefaults.standard.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? 0
        let dayEndHourValue = max(0, min(23, savedHour))
        let dayEndMinuteValue = max(0, min(59, savedMinute))
        
        let savedAnchor = (g.object(forKey: SharedKeys.todayAnchor) as? Date)
            ?? (UserDefaults.standard.object(forKey: SharedKeys.todayAnchor) as? Date)
        let resolvedAnchor = savedAnchor
            ?? DayBoundary.currentDayStart(for: Date(), dayEndHour: dayEndHourValue, dayEndMinute: dayEndMinuteValue)
        
        self.dayEndHour = dayEndHourValue
        self.dayEndMinute = dayEndMinuteValue
        self.todayAnchor = resolvedAnchor
        
        AppLogger.energy.debug("💰 BudgetEngine initialized with tariff: \(self.tariff.displayName)")
    }

    func minutes(from steps: Double) -> Int {
        guard stepsPerMinute > 0 else { return 1440 }
        return max(0, Int(steps / stepsPerMinute))
    }

    func setBudget(minutes: Int) {
        persist()
    }

    func resetIfNeeded() {
        let currentAnchor = currentDayAnchor(for: Date())
        if currentAnchor != todayAnchor { resetForToday(currentAnchor) }
    }

    private func resetForToday(_ anchor: Date? = nil) {
        todayAnchor = anchor ?? currentDayAnchor(for: Date())
        persist()
    }

    func updateTariff(_ newTariff: Tariff) {
        AppLogger.energy.debug("💰 Updating tariff from \(self.tariff.displayName) to \(newTariff.displayName)")
        tariff = newTariff
    }
    
    func updateDayEnd(hour: Int, minute: Int) {
        dayEndHour = max(0, min(23, hour))
        dayEndMinute = max(0, min(59, minute))
        persist()
        resetIfNeeded()
    }
    
    private func persist() {
        let g = sharedDefaults
        g.set(todayAnchor, forKey: SharedKeys.todayAnchor)
        g.set(dayEndHour, forKey: SharedKeys.dayEndHour)
        g.set(dayEndMinute, forKey: SharedKeys.dayEndMinute)
    }

    // Force re-read values from App Group (for syncing with snippet/intent)
    func reloadFromStorage() {
        let g = UserDefaults.stepsTrader()
        if let anchor = g.object(forKey: SharedKeys.todayAnchor) as? Date {
            todayAnchor = anchor
        }
        let savedHour = g.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let savedMinute = g.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0
        dayEndHour = max(0, min(23, savedHour))
        dayEndMinute = max(0, min(59, savedMinute))
        AppLogger.energy.debug("🔄 BudgetEngine reloaded: tariff=\(self.tariff.displayName), dayEnd=\(self.dayEndHour):\(self.dayEndMinute)")
    }
    
    // MARK: - Day boundary helpers
    private func currentDayAnchor(for date: Date) -> Date {
        DayBoundary.currentDayStart(for: date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }
}
