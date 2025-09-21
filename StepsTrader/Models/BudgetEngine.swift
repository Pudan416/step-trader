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

    init() {
        // Загружаем сохраненный тариф или используем medium по умолчанию
        let savedTariffString = UserDefaults.standard.string(forKey: "selectedTariff") ?? Tariff.medium.rawValue
        self.tariff = Tariff(rawValue: savedTariffString) ?? .medium
        
        let savedAnchor = UserDefaults.standard.object(forKey: "todayAnchor") as? Date ?? Calendar.current.startOfDay(for: Date())
        self.todayAnchor = savedAnchor
        
        self.dailyBudgetMinutes = UserDefaults.standard.integer(forKey: "dailyBudgetMinutes")
        self.remainingMinutes = UserDefaults.standard.integer(forKey: "remainingMinutes")
        
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
        let d = UserDefaults.standard
        d.set(todayAnchor, forKey: "todayAnchor")
        d.set(dailyBudgetMinutes, forKey: "dailyBudgetMinutes")
        d.set(remainingMinutes, forKey: "remainingMinutes")
    }
}