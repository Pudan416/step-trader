import Foundation
import Combine

final class BudgetEngine: ObservableObject, BudgetEngineProtocol {
    @Published var tariff: Tariff {
        didSet {
            UserDefaults.standard.set(tariff.rawValue, forKey: "selectedTariff")
            print("💰 Tariff updated to: \(tariff.displayName) (\(Int(tariff.stepsPerMinute)) steps/min)")
        }
    }
    
    var stepsPerMinute: Double { tariff.stepsPerMinute }
    
    // Backward compatibility
    var difficultyLevel: DifficultyLevel {
        get { tariff }
        set { tariff = newValue }
    }
    
    @Published private(set) var todayAnchor: Date
    @Published private(set) var dailyBudgetMinutes: Int = 0
    @Published private(set) var remainingMinutes: Int = 0
    @Published private(set) var dayEndHour: Int
    @Published private(set) var dayEndMinute: Int

    private var sharedDefaults: UserDefaults { UserDefaults.stepsTrader() }

    init() {
        // Load saved tariff or use medium as default
        let savedTariffString = UserDefaults.standard.string(forKey: "selectedTariff") ?? Tariff.medium.rawValue
        self.tariff = Tariff(rawValue: savedTariffString) ?? .medium
        
        // Read from App Group, fallback to standard keys for backward compatibility
        let g = UserDefaults.stepsTrader()
        let savedHour = (g.object(forKey: "dayEndHour_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndHour_v1") as? Int)
            ?? 0
        let savedMinute = (g.object(forKey: "dayEndMinute_v1") as? Int)
            ?? (UserDefaults.standard.object(forKey: "dayEndMinute_v1") as? Int)
            ?? 0
        let dayEndHourValue = max(0, min(23, savedHour))
        let dayEndMinuteValue = max(0, min(59, savedMinute))
        
        let savedAnchor = (g.object(forKey: "todayAnchor") as? Date)
            ?? (UserDefaults.standard.object(forKey: "todayAnchor") as? Date)
        let resolvedAnchor = savedAnchor
            ?? DayBoundary.currentDayStart(for: Date(), dayEndHour: dayEndHourValue, dayEndMinute: dayEndMinuteValue)
        
        let savedDaily = (g.object(forKey: "dailyBudgetMinutes") as? Int)
            ?? g.integer(forKey: "dailyBudgetMinutes")
        let savedRemaining = (g.object(forKey: "remainingMinutes") as? Int)
            ?? g.integer(forKey: "remainingMinutes")
        
        self.dayEndHour = dayEndHourValue
        self.dayEndMinute = dayEndMinuteValue
        self.dailyBudgetMinutes = savedDaily
        self.remainingMinutes = savedRemaining
        self.todayAnchor = resolvedAnchor
        
        print("💰 BudgetEngine initialized with tariff: \(tariff.displayName)")
    }

    func minutes(from steps: Double) -> Int { max(0, Int(steps / stepsPerMinute)) }

    func setBudget(minutes: Int) {
        dailyBudgetMinutes = minutes
        remainingMinutes = minutes
        persist()
    }

    func consume(mins: Int) {
        remainingMinutes = max(0, remainingMinutes - mins)
        persist()
    }

    func resetIfNeeded() {
        let currentAnchor = currentDayAnchor(for: Date())
        if currentAnchor != todayAnchor { resetForToday(currentAnchor) }
    }

    private func resetForToday(_ anchor: Date? = nil) {
        todayAnchor = anchor ?? currentDayAnchor(for: Date())
        dailyBudgetMinutes = 0
        remainingMinutes = 0
        persist()
    }

    func updateTariff(_ newTariff: Tariff) {
        print("💰 Updating tariff from \(tariff.displayName) to \(newTariff.displayName)")
        tariff = newTariff
    }
    
    func updateDayEnd(hour: Int, minute: Int) {
        dayEndHour = max(0, min(23, hour))
        dayEndMinute = max(0, min(59, minute))
        persistDayEnd()
        resetIfNeeded()
    }
    
    private func persist() {
        // Write to App Group and duplicate to standard for backward compatibility
        let g = sharedDefaults
        g.set(todayAnchor, forKey: "todayAnchor")
        g.set(dailyBudgetMinutes, forKey: "dailyBudgetMinutes")
        g.set(remainingMinutes, forKey: "remainingMinutes")
        g.set(dayEndHour, forKey: "dayEndHour_v1")
        g.set(dayEndMinute, forKey: "dayEndMinute_v1")
        
        let d = UserDefaults.standard
        d.set(todayAnchor, forKey: "todayAnchor")
        d.set(dailyBudgetMinutes, forKey: "dailyBudgetMinutes")
        d.set(remainingMinutes, forKey: "remainingMinutes")
        d.set(dayEndHour, forKey: "dayEndHour_v1")
        d.set(dayEndMinute, forKey: "dayEndMinute_v1")
    }

    // Force re-read values from App Group (for syncing with snippet/intent)
    func reloadFromStorage() {
        let g = UserDefaults.stepsTrader()
        if let anchor = g.object(forKey: "todayAnchor") as? Date {
            todayAnchor = anchor
        }
        dailyBudgetMinutes = g.integer(forKey: "dailyBudgetMinutes")
        remainingMinutes = g.integer(forKey: "remainingMinutes")
        let savedHour = g.object(forKey: "dayEndHour_v1") as? Int ?? 0
        let savedMinute = g.object(forKey: "dayEndMinute_v1") as? Int ?? 0
        dayEndHour = max(0, min(23, savedHour))
        dayEndMinute = max(0, min(59, savedMinute))
        print("🔄 BudgetEngine reloaded: daily=\(dailyBudgetMinutes), remaining=\(remainingMinutes)")
    }
    
    // MARK: - Day boundary helpers
    private func currentDayAnchor(for date: Date) -> Date {
        let cal = Calendar.current
        guard let cutoffToday = cal.date(
            bySettingHour: dayEndHour,
            minute: dayEndMinute,
            second: 0,
            of: date)
        else { return cal.startOfDay(for: date) }
        
        if date >= cutoffToday {
            return cutoffToday
        } else if let prevCutoff = cal.date(byAdding: .day, value: -1, to: cutoffToday) {
            return prevCutoff
        } else {
            return cal.startOfDay(for: date)
        }
    }
    
    private func isSamePeriod(anchor: Date, date: Date) -> Bool {
        currentDayAnchor(for: date) == currentDayAnchor(for: anchor)
    }
    
    private func persistDayEnd() {
        let g = sharedDefaults
        g.set(dayEndHour, forKey: "dayEndHour_v1")
        g.set(dayEndMinute, forKey: "dayEndMinute_v1")
        let d = UserDefaults.standard
        d.set(dayEndHour, forKey: "dayEndHour_v1")
        d.set(dayEndMinute, forKey: "dayEndMinute_v1")
    }
}
