import Foundation
import Combine

final class BudgetEngine: ObservableObject, BudgetEngineProtocol {
    // Фиксированный тариф: 500 шагов = 1 минута
    let stepsPerMinute: Double = 500
    let difficultyLevel: DifficultyLevel = .easy
    
    @Published private(set) var todayAnchor: Date
    @Published private(set) var dailyBudgetMinutes: Int = 0
    @Published private(set) var remainingMinutes: Int = 0

    init() {
        let savedAnchor = UserDefaults.standard.object(forKey: "todayAnchor") as? Date ?? Calendar.current.startOfDay(for: Date())
        self.todayAnchor = savedAnchor
        
        self.dailyBudgetMinutes = UserDefaults.standard.integer(forKey: "dailyBudgetMinutes")
        self.remainingMinutes = UserDefaults.standard.integer(forKey: "remainingMinutes")
        
        // Проверяем, нужно ли сбросить на новый день
        if !Calendar.current.isDateInToday(savedAnchor) { 
            resetForToday() 
        }
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

    private func persist() {
        let d = UserDefaults.standard
        d.set(todayAnchor, forKey: "todayAnchor")
        d.set(dailyBudgetMinutes, forKey: "dailyBudgetMinutes")
        d.set(remainingMinutes, forKey: "remainingMinutes")
    }
}