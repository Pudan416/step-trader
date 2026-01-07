import Foundation
import SwiftUI
import Combine
import FamilyControls
import HealthKit

// MARK: - Handoff Token Model
struct HandoffToken: Codable {
    let targetBundleId: String
    let targetAppName: String
    let createdAt: Date
    let tokenId: String
    
    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 60 // Токен действителен 1 минуту
    }
}

// MARK: - Service Protocols
// NOTE: Avoid exposing FamilyControls token types in shared protocol to prevent cross-target build issues.

// MARK: - HealthKit Service Protocol
protocol HealthKitServiceProtocol {
    func requestAuthorization() async throws
    func fetchTodaySteps() async throws -> Double
    func fetchSteps(from: Date, to: Date) async throws -> Double
    func startObservingSteps(updateHandler: @escaping (Double) -> Void)
    func stopObservingSteps()
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
    func sendAccessWindowReminder(remainingSeconds: Int, bundleId: String)
    func scheduleAccessWindowStatus(remainingSeconds: Int, bundleId: String)
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
    func updateDayEnd(hour: Int, minute: Int)
    
    // Backward compatibility
    var difficultyLevel: DifficultyLevel { get set }
}

enum Tariff: String, CaseIterable {
    case free = "free"     // 0 steps = 1 minute (free entry tracking only)
    case easy = "lite"     // 100 steps = 1 minute
    case medium = "medium" // 500 steps = 1 minute
    case hard = "hard"     // 1000 steps = 1 minute
    
    var stepsPerMinute: Double {
        switch self {
        case .free: return 100 // avoid divide-by-zero; treat as easy for tracking
        case .easy: return 100
        case .medium: return 500
        case .hard: return 1000
        }
    }
    
    // Стоимость одного входа (шаги за вход)
    var entryCostSteps: Int {
        switch self {
        case .free: return 0
        case .easy: return 100
        case .medium: return 500
        case .hard: return 1000
        }
    }
    
    var displayName: String {
        switch self {
        case .free: return "🆓 FREE"
        case .easy: return "💡 LITE"
        case .medium: return "🔥 MEDIUM"
        case .hard: return "💪 HARD"
        }
    }
    
    var description: String {
        switch self {
        case .free: return "0 steps"
        case .easy: return "100 steps"
        case .medium: return "500 steps"
        case .hard: return "1000 steps"
        }
    }
}

// Backward compatibility
typealias DifficultyLevel = Tariff

// MARK: - App theme
enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
    case cosmic
    
    var displayNameEn: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .cosmic: return "Cosmic"
        }
    }
    
    var displayNameRu: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        case .cosmic: return "Космическая"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .cosmic: return .dark
        }
    }
}
