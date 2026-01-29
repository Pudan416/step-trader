import Foundation
import SwiftUI
import Combine
import HealthKit
#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

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
@preconcurrency
protocol HealthKitServiceProtocol {
    func fetchTodaySleep() async throws -> Double
    func fetchSleep(from: Date, to: Date) async throws -> Double
    @MainActor
    func requestAuthorization() async throws
    @MainActor
    func authorizationStatus() -> HKAuthorizationStatus
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
    /// Updates DeviceActivity monitoring for minute-mode charging (if supported/authorized).
    func updateMinuteModeMonitoring()
    /// Updates shield configuration (shield is configured in DeviceActivityMonitorExtension).
    func updateShieldSchedule()
}

// MARK: - Notification Service Protocol
protocol NotificationServiceProtocol {
    func requestPermission() async throws
    func sendTimeExpiredNotification()
    func sendTimeExpiredNotification(remainingMinutes: Int)
    func sendUnblockNotification(remainingMinutes: Int)
    func sendRemainingTimeNotification(remainingMinutes: Int)
    func sendMinuteModeSummary(bundleId: String, minutesUsed: Int, stepsCharged: Int)
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
    func reloadFromStorage()
    
    // Backward compatibility
    var difficultyLevel: DifficultyLevel { get set }
}

enum Tariff: String, CaseIterable {
    case hard = "hard"     // 1000 steps = 1 minute
    case medium = "medium" // 500 steps = 1 minute
    case easy = "lite"     // 100 steps = 1 minute
    case free = "free"     // 0 steps = 1 minute (free entry tracking only)
    
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
        case .easy: return 10   // Level III
        case .medium: return 50 // Level II
        case .hard: return 100  // Level I
        }
    }
    
    var displayName: String {
        switch self {
        case .hard: return "I"
        case .medium: return "II"
        case .easy: return "III"
        case .free: return "IV"
        }
    }
    
    var description: String {
        switch self {
        case .free: return "0 steps"
        case .easy: return "10 steps"
        case .medium: return "50 steps"
        case .hard: return "100 steps"
        }
    }
}

// Backward compatibility
typealias DifficultyLevel = Tariff

// MARK: - FamilyControls placeholders / aliases
#if canImport(FamilyControls)
typealias FamilyActivitySelection = FamilyControls.FamilyActivitySelection
typealias ApplicationToken = ManagedSettings.ApplicationToken
typealias ActivityCategoryToken = ManagedSettings.ActivityCategoryToken
#else
struct FamilyActivitySelection {
    var applicationTokens: Set<ApplicationToken> = []
    var categoryTokens: Set<ActivityCategoryToken> = []
    
    init() {}
}

// Minimal stand-ins to keep compilation when Family Controls features are disabled.
final class ApplicationToken: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    override init() { super.init() }
    required init?(coder: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}
}

final class ActivityCategoryToken: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    override init() { super.init() }
    required init?(coder: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}
}
#endif

// MARK: - App theme
enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark
    
    var displayNameEn: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var displayNameRu: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var accentColor: Color {
        switch self {
        case .system: return Color.accentColor
        case .light: return Color.blue
        case .dark: return Color(red: 224/255, green: 130/255, blue: 217/255)
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .system, .light: return Color(.systemBackground)
        case .dark: return Color(.black)
        }
    }
}
