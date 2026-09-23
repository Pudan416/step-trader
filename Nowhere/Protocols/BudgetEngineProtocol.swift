import Foundation
import Combine

@MainActor
protocol BudgetEngineProtocol: ObservableObject {
    var tariff: Tariff { get set }
    var stepsPerMinute: Double { get }
    
    func minutes(from steps: Double) -> Int
    func setBudget(minutes: Int)
    func resetIfNeeded()
    func updateTariff(_ newTariff: Tariff)
    func updateDayEnd(hour: Int, minute: Int)
    func reloadFromStorage()
}
