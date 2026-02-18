import Foundation
import SwiftUI
import Combine
import HealthKit
#if canImport(UIKit)
import UIKit
#endif
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
        Date().timeIntervalSince(createdAt) > 60 // Token valid for 1 minute
    }
}

// MARK: - Service Protocols
// NOTE: Avoid exposing FamilyControls token types in shared protocol to prevent cross-target build issues.

// MARK: - HealthKit Service Protocol
@preconcurrency
protocol HealthKitServiceProtocol {
    func fetchSleep(from: Date, to: Date) async throws -> Double
    @MainActor
    func requestAuthorization() async throws
    /// Returns the WRITE authorization status for steps. Note: this does NOT reflect
    /// read permission — HealthKit never reveals whether read access was granted.
    /// For read-only apps, `.sharingDenied` is expected and does not mean reads will fail.
    @MainActor
    func authorizationStatus() -> HKAuthorizationStatus
    /// Returns the WRITE authorization status for sleep (same caveat as above).
    @MainActor
    func sleepAuthorizationStatus() -> HKAuthorizationStatus
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
}

enum Tariff: String, CaseIterable, Codable {
    case hard = "hard"     // 1000 steps = 1 minute
    case medium = "medium" // 500 steps = 1 minute
    case easy = "easy"     // 100 steps = 1 minute
    case free = "free"     // 0 steps = 1 minute (free entry tracking only)

    /// Backward-compatible decoding: accept legacy "lite" raw value.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "lite" {
            self = .easy
        } else if let value = Tariff(rawValue: raw) {
            self = value
        } else {
            self = .easy
        }
    }
    
    var stepsPerMinute: Double {
        switch self {
        case .free: return 100 // avoid divide-by-zero; treat as easy for tracking
        case .easy: return 100
        case .medium: return 500
        case .hard: return 1000
        }
    }
    
    // Cost per entry (steps per entry)
    var entryCostSteps: Int {
        switch self {
        case .free: return 0
        case .easy: return 10
        case .medium: return 50
        case .hard: return 100
        }
    }
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
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

// MARK: - Gradient style
enum GradientStyle: String, CaseIterable {
    case radial
    case linear
    case radialReversed
    case linearReversed

    var displayName: String {
        switch self {
        case .radial: return "Radial"
        case .linear: return "Linear"
        case .radialReversed: return "Radial Reversed"
        case .linearReversed: return "Linear Reversed"
        }
    }
}

// MARK: - App theme
// "Dark theme feels like night and screens. Daylight theme feels like day and the world outside."
// Both communicate the same idea: The screen is not your life. This is just a place to notice.
enum AppTheme: String, CaseIterable {
    case system
    case daylight   // Daytime resistance — warm paper
    case night      // Night and screens
    
    var displayNameEn: String {
        switch self {
        case .system: return "System"
        case .daylight: return "Daylight"
        case .night: return "Night"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .daylight: return .light
        case .night: return .dark
        }
    }
    
    var isLightTheme: Bool {
        switch self {
        case .daylight: return true
        case .night: return false
        case .system:
#if canImport(UIKit)
            return UITraitCollection.current.userInterfaceStyle != .dark
#else
            return true
#endif
        }
    }
    
    // Dusty chalk pink — same across all themes
    var accentColor: Color {
        AppColors.brandAccent
    }
    
    var backgroundColor: Color {
        switch self {
        case .system:
#if canImport(UIKit)
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x22/255.0, green: 0x28/255.0, blue: 0x31/255.0, alpha: 1) // #222831
                    : UIColor(red: 0xF2/255.0, green: 0xF2/255.0, blue: 0xF2/255.0, alpha: 1) // #F2F2F2
            })
#else
            return Color(.systemBackground)
#endif
        case .daylight: return AppColors.Daylight.background
        case .night: return AppColors.Night.background
        }
    }
    
    var backgroundSecondary: Color {
        switch self {
        case .system: return Color(.secondarySystemBackground)
        case .daylight: return AppColors.Daylight.backgroundSecondary
        case .night: return AppColors.Night.backgroundSecondary
        }
    }
    
    var textPrimary: Color {
        switch self {
        case .system: return Color(.label)
        case .daylight: return AppColors.Daylight.textPrimary
        case .night: return AppColors.Night.textPrimary
        }
    }
    
    var textSecondary: Color {
        switch self {
        case .system: return Color(.secondaryLabel)
        case .daylight: return AppColors.Daylight.textSecondary
        case .night: return AppColors.Night.textSecondary
        }
    }
    
    var stroke: Color {
        switch self {
        case .system: return Color(.separator)
        case .daylight: return AppColors.Daylight.stroke
        case .night: return AppColors.Night.stroke
        }
    }
    
    var strokeOpacity: Double {
        0.15
    }
    
    var bodyColor: Color {
        switch self {
        case .system: return .green
        case .daylight: return AppColors.Daylight.activity
        case .night: return AppColors.Night.activity
        }
    }

    var mindColor: Color {
        switch self {
        case .system: return .blue
        case .daylight: return AppColors.Daylight.rest
        case .night: return AppColors.Night.rest
        }
    }

    var heartColor: Color {
        switch self {
        case .system: return .orange
        case .daylight: return AppColors.Daylight.joys
        case .night: return AppColors.Night.joys
        }
    }
    
    static var selectableThemes: [AppTheme] {
        [.system, .daylight, .night]
    }
    
    static func normalized(rawValue: String) -> AppTheme {
        switch rawValue {
        case "light": return .daylight
        case "dark": return .night
        case "minimal": return .system
        default: return AppTheme(rawValue: rawValue) ?? .system
        }
    }
}
