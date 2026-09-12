import Foundation
import UserNotifications

enum SettingsPermissionStatus: Equatable {
    case connected
    case checkAccess
    case unavailable
    case allowed
    case notRequested
    case offInSystemSettings
    case actionNeeded

    var displayText: String {
        switch self {
        case .connected:
            String(localized: "Connected", comment: "Permission status")
        case .checkAccess:
            String(localized: "Check access", comment: "Permission status")
        case .unavailable:
            String(localized: "Unavailable", comment: "Permission unavailable status")
        case .allowed:
            String(localized: "Allowed", comment: "Notification permission status")
        case .notRequested:
            String(localized: "Not requested", comment: "Notification permission status")
        case .offInSystemSettings:
            String(localized: "Off in System Settings", comment: "Notification permission status")
        case .actionNeeded:
            String(localized: "Action needed", comment: "Permission status")
        }
    }
}

enum SettingsPermissionAction: Equatable {
    case checkAccess
    case requestPermission
    case openSystemSettings
}

enum SettingsPermissionKind: Equatable {
    case health
    case notifications
    case screenTime
}

enum SettingsPermissionFailureAction: Equatable {
    case tryAgain
    case openSettings
}

struct SettingsPermissionFailurePresentation: Equatable {
    let permission: SettingsPermissionKind
    let message: String
    let actions: [SettingsPermissionFailureAction]

    static let health = Self(
        permission: .health,
        message: String(
            localized: "We couldn't check Health access.",
            comment: "Health permission failure message"
        ),
        actions: [.tryAgain, .openSettings]
    )

    static let notifications = Self(
        permission: .notifications,
        message: String(
            localized: "We couldn't allow notifications.",
            comment: "Notification permission failure message"
        ),
        actions: [.tryAgain, .openSettings]
    )

    static let screenTime = Self(
        permission: .screenTime,
        message: String(
            localized: "We couldn't allow Screen Time access.",
            comment: "Screen Time permission failure message"
        ),
        actions: [.tryAgain, .openSettings]
    )
}

struct SettingsPermissionPresentation: Equatable {
    let status: SettingsPermissionStatus
    let action: SettingsPermissionAction?
    let contributesToWarning: Bool

    static func health(isAvailable: Bool, hasReturnedData: Bool) -> Self {
        guard isAvailable else {
            return .init(status: .unavailable, action: nil, contributesToWarning: false)
        }
        return hasReturnedData
            ? .init(status: .connected, action: .openSystemSettings, contributesToWarning: false)
            : .init(status: .checkAccess, action: .checkAccess, contributesToWarning: false)
    }

    static func remindersEnabled(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: SharedKeys.notifyOneMinBefore) as? Bool ?? true)
            || (defaults.object(forKey: SharedKeys.notifyWhenTimerOver) as? Bool ?? true)
            || (defaults.object(forKey: SharedKeys.notifyCanvasReminder) as? Bool ?? false)
            || (defaults.object(forKey: SharedKeys.notifyDayResetWarning) as? Bool ?? true)
    }

    static func notifications(status: UNAuthorizationStatus, remindersEnabled: Bool) -> Self {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .init(status: .allowed, action: nil, contributesToWarning: false)
        case .notDetermined:
            return .init(status: .notRequested, action: .requestPermission, contributesToWarning: remindersEnabled)
        case .denied:
            return .init(status: .offInSystemSettings, action: .openSystemSettings, contributesToWarning: remindersEnabled)
        @unknown default:
            return .init(status: .checkAccess, action: .openSystemSettings, contributesToWarning: false)
        }
    }

    static func screenTime(isAuthorized: Bool) -> Self {
        isAuthorized
            ? .init(status: .connected, action: nil, contributesToWarning: false)
            : .init(status: .actionNeeded, action: .requestPermission, contributesToWarning: true)
    }
}
