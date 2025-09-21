import Foundation
import Combine
import FamilyControls
import HealthKit

// MARK: - Service Protocols

// MARK: - HealthKit Service Protocol
protocol HealthKitServiceProtocol {
    func requestAuthorization() async throws
    func fetchTodaySteps() async throws -> Double
}

// MARK: - Family Controls Service Protocol
protocol FamilyControlsServiceProtocol {
    var isAuthorized: Bool { get }
    var selection: FamilyActivitySelection { get set }
    func requestAuthorization() async throws
    func updateSelection(_ newSelection: FamilyActivitySelection)
}

// MARK: - Notification Service Protocol
protocol NotificationServiceProtocol {
    func requestPermission() async throws
    func sendTimeExpiredNotification()
    func sendTestNotification()
}

// MARK: - Budget Engine Protocol
protocol BudgetEngineProtocol: ObservableObject {
    var difficultyLevel: DifficultyLevel { get }
    var stepsPerMinute: Double { get }
    var dailyBudgetMinutes: Int { get }
    var remainingMinutes: Int { get }
    
    func minutes(from steps: Double) -> Int
    func setBudget(minutes: Int)
    func consume(mins: Int)
    func resetIfNeeded()
}

enum DifficultyLevel: String, CaseIterable {
    case easy = "EASY"
    case medium = "MEDIUM" 
    case hard = "HARD"
    case hardcore = "HARDCORE"
    
    var stepsPerMinute: Double {
        switch self {
        case .easy: return 500
        case .medium: return 1000
        case .hard: return 2000
        case .hardcore: return 5000
        }
    }
    
    var description: String {
        "\(rawValue): \(Int(stepsPerMinute)) шагов/мин"
    }
}