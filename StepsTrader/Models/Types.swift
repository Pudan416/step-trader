import Foundation
import Combine
import FamilyControls
import HealthKit

// MARK: - Service Protocols
// NOTE: Avoid exposing FamilyControls token types in shared protocol to prevent cross-target build issues.

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
    // Shield controls
    func enableShield()
    func disableShield()
    func allowOneSession() // uses current selection
    func reenableShield()  // uses current selection
}

// MARK: - Notification Service Protocol
protocol NotificationServiceProtocol {
    func requestPermission() async throws
    func sendTimeExpiredNotification()
    func sendTimeExpiredNotification(remainingMinutes: Int)
    func sendUnblockNotification(remainingMinutes: Int)
    func sendRemainingTimeNotification(remainingMinutes: Int)
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
    
    // Стоимость одного входа (шаги за вход)
    var entryCostSteps: Int {
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
        case .easy: return "100 шагов = 1 минута • вход: 100 шагов"
        case .medium: return "500 шагов = 1 минута • вход: 500 шагов"
        case .hard: return "1000 шагов = 1 минута • вход: 1000 шагов"
        }
    }
}

// Backward compatibility
typealias DifficultyLevel = Tariff