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

    private var sharedDefaults: UserDefaults { UserDefaults.stepsTrader() }

    init() {
        // Загружаем сохраненный тариф или используем medium по умолчанию
        let savedTariffString = UserDefaults.standard.string(forKey: "selectedTariff") ?? Tariff.medium.rawValue
        self.tariff = Tariff(rawValue: savedTariffString) ?? .medium
        
        // Читаем из App Group, fallback на стандартные ключи для обратной совместимости
        let g = UserDefaults.stepsTrader()
        let savedAnchor = (g.object(forKey: "todayAnchor") as? Date)
            ?? (UserDefaults.standard.object(forKey: "todayAnchor") as? Date)
            ?? Calendar.current.startOfDay(for: Date())
        self.todayAnchor = savedAnchor
        
        let savedDaily = (g.object(forKey: "dailyBudgetMinutes") as? Int)
        ?? g.integer(forKey: "dailyBudgetMinutes")
        let savedRemaining = (g.object(forKey: "remainingMinutes") as? Int)
        ?? g.integer(forKey: "remainingMinutes")
        self.dailyBudgetMinutes = savedDaily
        self.remainingMinutes = savedRemaining
        
        // Проверяем, нужно ли сбросить на новый день
        if !Calendar.current.isDateInToday(savedAnchor) { 
            resetForToday() 
        }
        
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
        if !Calendar.current.isDateInToday(todayAnchor) { resetForToday() }
    }

    private func resetForToday() {
        todayAnchor = Calendar.current.startOfDay(for: Date())
        dailyBudgetMinutes = 0
        remainingMinutes = 0
        persist()
    }

    func updateTariff(_ newTariff: Tariff) {
        print("💰 Updating tariff from \(tariff.displayName) to \(newTariff.displayName)")
        tariff = newTariff
    }
    
    private func persist() {
        // Пишем в App Group, а также дублируем в стандартные для обратной совместимости
        let g = sharedDefaults
        g.set(todayAnchor, forKey: "todayAnchor")
        g.set(dailyBudgetMinutes, forKey: "dailyBudgetMinutes")
        g.set(remainingMinutes, forKey: "remainingMinutes")
        
        let d = UserDefaults.standard
        d.set(todayAnchor, forKey: "todayAnchor")
        d.set(dailyBudgetMinutes, forKey: "dailyBudgetMinutes")
        d.set(remainingMinutes, forKey: "remainingMinutes")
    }

    // Принудительно перечитать значения из App Group (для синхронизации со сниппетом/интентом)
    func reloadFromStorage() {
        let g = UserDefaults.stepsTrader()
        if let anchor = g.object(forKey: "todayAnchor") as? Date {
            todayAnchor = anchor
        }
        dailyBudgetMinutes = g.integer(forKey: "dailyBudgetMinutes")
        remainingMinutes = g.integer(forKey: "remainingMinutes")
        print("🔄 BudgetEngine reloaded: daily=\(dailyBudgetMinutes), remaining=\(remainingMinutes)")
    }
}
