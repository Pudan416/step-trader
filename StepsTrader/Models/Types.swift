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
// "Dark theme feels like night and screens. Daylight theme feels like day and the world outside."
// Both communicate the same idea: The screen is not your life. This is just a place to notice.
enum AppTheme: String, CaseIterable {
    case system
    case daylight   // Daytime resistance — warm paper
    case night      // Night and screens
    case minimal    // Monochrome, max minimalism
    
    var displayNameEn: String {
        switch self {
        case .system: return "System"
        case .daylight: return "Daylight"
        case .night: return "Night"
        case .minimal: return "Minimal"
        }
    }
    
    var displayNameRu: String {
        switch self {
        case .system: return "Системная"
        case .daylight: return "Дневная"
        case .night: return "Ночная"
        case .minimal: return "Минимализм"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .daylight: return .light
        case .night: return .dark
        case .minimal: return .light
        }
    }
    
    var isLightTheme: Bool {
        switch self {
        case .daylight: return true
        case .night: return false
        case .minimal: return true
        case .system: return true
        }
    }
    
    // Dusty chalk pink — same across all themes
    var accentColor: Color {
        switch self {
        case .minimal: return AppColors.Minimal.mono
        default: return AppColors.brandPink
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .system: return Color(.systemBackground)
        case .daylight: return AppColors.Daylight.background
        case .night: return AppColors.Night.background
        case .minimal: return AppColors.Minimal.background
        }
    }
    
    var backgroundSecondary: Color {
        switch self {
        case .system: return Color(.secondarySystemBackground)
        case .daylight: return AppColors.Daylight.backgroundSecondary
        case .night: return AppColors.Night.backgroundSecondary
        case .minimal: return AppColors.Minimal.backgroundSecondary
        }
    }
    
    var textPrimary: Color {
        switch self {
        case .system: return Color(.label)
        case .daylight: return AppColors.Daylight.textPrimary
        case .night: return AppColors.Night.textPrimary
        case .minimal: return AppColors.Minimal.textPrimary
        }
    }
    
    var textSecondary: Color {
        switch self {
        case .system: return Color(.secondaryLabel)
        case .daylight: return AppColors.Daylight.textSecondary
        case .night: return AppColors.Night.textSecondary
        case .minimal: return AppColors.Minimal.textSecondary
        }
    }
    
    var stroke: Color {
        switch self {
        case .system: return Color(.separator)
        case .daylight: return AppColors.Daylight.stroke
        case .night: return AppColors.Night.stroke
        case .minimal: return AppColors.Minimal.stroke
        }
    }
    
    var strokeOpacity: Double {
        switch self {
        case .minimal: return 1.0
        default: return 0.15
        }
    }
    
    var activityColor: Color {
        switch self {
        case .system: return .green
        case .daylight: return AppColors.Daylight.activity
        case .night: return AppColors.Night.activity
        case .minimal: return AppColors.Minimal.mono
        }
    }
    
    var recoveryColor: Color {
        switch self {
        case .system: return .blue
        case .daylight: return AppColors.Daylight.recovery
        case .night: return AppColors.Night.recovery
        case .minimal: return AppColors.Minimal.mono
        }
    }
    
    var joysColor: Color {
        switch self {
        case .system: return .orange
        case .daylight: return AppColors.Daylight.joys
        case .night: return AppColors.Night.joys
        case .minimal: return AppColors.Minimal.mono
        }
    }
    
    static var selectableThemes: [AppTheme] {
        [.system, .daylight, .night, .minimal]
    }
    
    static func normalized(rawValue: String) -> AppTheme {
        switch rawValue {
        case "light": return .daylight
        case "dark": return .night
        default: return AppTheme(rawValue: rawValue) ?? .system
        }
    }
}
