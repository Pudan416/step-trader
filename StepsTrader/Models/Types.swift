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
@MainActor
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
    var tariff: Tariff { get set }
    var stepsPerMinute: Double { get }
    var dailyBudgetMinutes: Int { get }
    var remainingMinutes: Int { get }
    
    func minutes(from steps: Double) -> Int
    func setBudget(minutes: Int)
    func consume(mins: Int)
    func resetIfNeeded()
    func updateTariff(_ newTariff: Tariff)
    
    // Backward compatibility
    var difficultyLevel: DifficultyLevel { get set }
}

enum Tariff: String, CaseIterable {
    case easy = "easy"     // 100 шагов = 1 мин
    case medium = "medium" // 500 шагов = 1 мин  
    case hard = "hard"     // 1000 шагов = 1 мин
    
    var stepsPerMinute: Double {
        switch self {
        case .easy: return 100
        case .medium: return 500
        case .hard: return 1000
        }
    }
    
    var displayName: String {
        switch self {
        case .easy: return "💎 EASY"
        case .medium: return "🔥 MEDIUM"
        case .hard: return "💪 HARD"
        }
    }
    
    var description: String {
        switch self {
        case .easy: return "100 шагов = 1 минута"
        case .medium: return "500 шагов = 1 минута"
        case .hard: return "1000 шагов = 1 минута"
        }
    }
}

// Backward compatibility
typealias DifficultyLevel = Tariff